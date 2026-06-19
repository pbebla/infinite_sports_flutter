import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:intl/intl.dart';

class KnockoutTab extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final String? tournamentId;
  final Map<String, List<TournamentPlayer>> rosters;
  final String sport;

  const KnockoutTab({
    super.key,
    required this.matches,
    required this.teams,
    this.tournamentId,
    this.rosters = const {},
    this.sport = '',
  });

  @override
  State<KnockoutTab> createState() => _KnockoutTabState();
}

class _KnockoutTabState extends State<KnockoutTab> {
  String? _selectedRound;
  @override
  void initState() {
    super.initState();
    // Pre-select the first knockout round
    final knockoutMatches = widget.matches
        .where((m) => TournamentStage.fromString(m.stage).isKnockout)
        .toList();
    if (knockoutMatches.isNotEmpty) {
      final roundsSet = <String>{};
      for (final m in knockoutMatches) {
        roundsSet.add(TournamentStage.fromString(m.stage).label);
      }
      final rounds = _roundOrder.where((r) => roundsSet.contains(r)).toList();
      if (rounds.isNotEmpty) _selectedRound = rounds.first;
    }
  }

  /// Ordered list of knockout-round display labels, sorted by stage progression.
  static final List<String> _roundOrder = (TournamentStage.values
          .where((s) => s.isKnockout)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      .map((s) => s.label)
      .toList();

  String _formatMatchDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final knockoutMatches = widget.matches
        .where((m) => TournamentStage.fromString(m.stage).isKnockout)
        .toList();

    if (knockoutMatches.isEmpty) {
      return const Center(child: Text('Knockout stage not yet available'));
    }

    // Build ordered unique rounds
    final roundsSet = <String>{};
    for (final m in knockoutMatches) {
      roundsSet.add(TournamentStage.fromString(m.stage).label);
    }
    final rounds = _roundOrder.where((r) => roundsSet.contains(r)).toList();

    // Group by normalised round
    final Map<String, List<TournamentMatch>> byRound = {};
    for (final m in knockoutMatches) {
      final nr = TournamentStage.fromString(m.stage).label;
      byRound.putIfAbsent(nr, () => []).add(m);
    }
    for (final r in byRound.keys) {
      byRound[r]!
          .sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));
    }

    // Eliminated teams across all knockout matches
    final eliminated = <String>{};
    for (final m in knockoutMatches) {
      if (m.matchStatus.isFinished) {
        final loser = m.loserTeamId;
        if (loser.isNotEmpty) eliminated.add(loser);
      }
    }

    // Find third-place match
    final thirdPlaceMatches = knockoutMatches
        .where((m) =>
            TournamentStage.fromString(m.stage) == TournamentStage.thirdPlace)
        .toList();
    final thirdPlaceMatch =
        thirdPlaceMatches.isNotEmpty ? thirdPlaceMatches.first : null;

    return Column(
      children: [
        // Round selector chips
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rounds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final round = rounds[index];
              final selected = round == _selectedRound;
              return ChoiceChip(
                label: Text(round),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _selectedRound = round),
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            },
          ),
        ),
        // Content area — Final round gets hero layout, others get card columns
        Expanded(
          child: Builder(builder: (context) {
            final selectedRound = _selectedRound;
            if (selectedRound == null) return const SizedBox.shrink();

            final isFinalSelected =
                selectedRound == TournamentStage.finalStage.label;

            if (isFinalSelected) {
              // Find the final match (bracketPosition 0 or first)
              final finalMatches = byRound[selectedRound] ?? [];
              final finalMatch =
                  finalMatches.isNotEmpty ? finalMatches.first : null;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (finalMatch != null)
                      _buildFinalHero(context, finalMatch),
                    _buildBronzeCard(context, thirdPlaceMatch),
                  ],
                ),
              );
            }

            // Non-final rounds: FotMob-style bracket view with connector lines
            // Find the next round after the selected one.
            final selIdx = rounds.indexOf(selectedRound);
            final nextRound =
                (selIdx >= 0 && selIdx + 1 < rounds.length)
                    ? rounds[selIdx + 1]
                    : null;
            return _buildBracketView(
              context,
              selectedRound,
              nextRound,
              byRound,
              eliminated,
            );
          }),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bracket view — selected round (left column) + next round faded (right)
  // with FotMob-style "]" connector lines between feeders and successor cards.
  // ---------------------------------------------------------------------------

  /// Fixed-slot constants.  slotH must be consistent with _KnockoutMatchCard's
  /// compact height; gap is the vertical whitespace between slots.
  static const double _slotH = 96.0;
  static const double _slotGap = 18.0;
  static const double _leftColW = 230.0;
  static const double _rightColW = 200.0;
  static const double _colGapX = 44.0;

  Widget _buildBracketView(
    BuildContext context,
    String selectedRound,
    String? nextRound,
    Map<String, List<TournamentMatch>> byRound,
    Set<String> eliminated,
  ) {
    final leftMatches = List<TournamentMatch>.from(byRound[selectedRound] ?? [])
      ..sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));

    final rightMatches = nextRound != null
        ? (List<TournamentMatch>.from(byRound[nextRound] ?? [])
          ..sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition)))
        : <TournamentMatch>[];

    final leftCount = leftMatches.length;
    final totalH = leftCount * (_slotH + _slotGap);
    final totalW = _leftColW +
        (rightMatches.isNotEmpty ? _colGapX + _rightColW : 0.0) +
        16.0; // right padding

    final dividerColor = Theme.of(context).dividerColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalW,
          height: totalH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Connector lines (behind the cards) ────────────────────────
              if (rightMatches.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BracketConnectorPainter(
                      leftCount: leftCount,
                      rightCount: rightMatches.length,
                      slotH: _slotH,
                      slotGap: _slotGap,
                      leftColW: _leftColW,
                      colGapX: _colGapX,
                      dividerColor: dividerColor,
                    ),
                  ),
                ),
              // ── Left column cards ──────────────────────────────────────────
              for (int i = 0; i < leftCount; i++)
                Positioned(
                  top: i * (_slotH + _slotGap),
                  left: 0,
                  width: _leftColW,
                  height: _slotH,
                  child: _KnockoutMatchCard(
                    match: leftMatches[i],
                    teams: widget.teams,
                    eliminated: eliminated,
                    tournamentId: widget.tournamentId,
                    rosters: widget.rosters,
                    sport: widget.sport,
                    formatDate: _formatMatchDate,
                    compact: true,
                  ),
                ),
              // ── Right column cards (faded, next round) ─────────────────────
              ..._buildRightCards(
                context: context,
                rightMatches: rightMatches,
                leftCount: leftCount,
                eliminated: eliminated,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the right-column (next-round, faded) Positioned widgets for the
  /// bracket Stack.  Extracted so we can compute each card's top Y with normal
  /// Dart control flow rather than a list-spread IIFE.
  List<Widget> _buildRightCards({
    required BuildContext context,
    required List<TournamentMatch> rightMatches,
    required int leftCount,
    required Set<String> eliminated,
  }) {
    final result = <Widget>[];
    for (int k = 0; k < rightMatches.length; k++) {
      final feederA = 2 * k;
      final feederB = 2 * k + 1;

      final double? centerA = feederA < leftCount
          ? feederA * (_slotH + _slotGap) + _slotH / 2
          : null;
      final double? centerB = feederB < leftCount
          ? feederB * (_slotH + _slotGap) + _slotH / 2
          : null;

      final double rightTopY;
      if (centerA != null && centerB != null) {
        rightTopY = (centerA + centerB) / 2 - _slotH / 2;
      } else if (centerA != null) {
        rightTopY = centerA - _slotH / 2;
      } else {
        // No feeder cards visible — fall back to natural k-th slot position.
        rightTopY = k * (_slotH + _slotGap);
      }

      result.add(Positioned(
        top: rightTopY,
        left: _leftColW + _colGapX,
        width: _rightColW,
        height: _slotH,
        child: Opacity(
          opacity: 0.55,
          child: _KnockoutMatchCard(
            match: rightMatches[k],
            teams: widget.teams,
            eliminated: eliminated,
            tournamentId: widget.tournamentId,
            rosters: widget.rosters,
            sport: widget.sport,
            formatDate: _formatMatchDate,
            compact: true,
          ),
        ),
      ));
    }
    return result;
  }

  Widget _buildFinalHero(BuildContext context, TournamentMatch match) {
    final team1 =
        match.team1Id != null ? widget.teams[match.team1Id] : null;
    final team2 =
        match.team2Id != null ? widget.teams[match.team2Id] : null;
    final isFinished = match.matchStatus.isFinished;
    final isLive = match.matchStatus.isLive;
    final winnerId = isFinished ? match.winnerTeamId : '';
    final winnerTeam = winnerId.isNotEmpty ? widget.teams[winnerId] : null;

    // Champion tint gradient
    List<Color> gradientColors;
    if (isFinished) {
      final homeColor = winnerTeam?.homeColor;
      if (homeColor != null) {
        gradientColors = [
          homeColor,
          Color.lerp(homeColor, Colors.black, 0.35)!,
        ];
      } else {
        // Fallback gold
        gradientColors = const [Color(0xFFFFB300), Color(0xFFE65100)];
      }
    } else {
      // Default blue
      gradientColors = const [Color(0xFF5B9BFF), Color(0xFF2D5BA8)];
    }

    final team1IsWinner = winnerId.isNotEmpty && winnerId == match.team1Id;
    final team2IsWinner = winnerId.isNotEmpty && winnerId == match.team2Id;

    final canTap = match.team1Id != null &&
        match.team2Id != null &&
        widget.tournamentId != null;

    Widget hero = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Teams row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Team 1
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(url: team1?.logoUrl, size: 40),
                    const SizedBox(height: 6),
                    Text(
                      team1?.name ?? (match.team1Seed != null
                          ? 'Seed #${match.team1Seed}'
                          : 'TBD'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: team1IsWinner
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontStyle: team1 == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Score + Trophy
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    // Trophy
                    Image.asset(
                      'assets/trophy.png',
                      height: 44,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.emoji_events,
                        size: 44,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isFinished || isLive)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${match.team1Score}',
                            style: TextStyle(
                              color: team1IsWinner
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 26,
                              fontWeight: team1IsWinner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '–',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          Text(
                            '${match.team2Score}',
                            style: TextStyle(
                              color: team2IsWinner
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 26,
                              fontWeight: team2IsWinner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        match.time ?? '–',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    if (isLive)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Team 2
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(url: team2?.logoUrl, size: 40),
                    const SizedBox(height: 6),
                    Text(
                      team2?.name ?? (match.team2Seed != null
                          ? 'Seed #${match.team2Seed}'
                          : 'TBD'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: team2IsWinner
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontStyle: team2 == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Venue + date
          if (match.locationInfo?.venue != null || match.date.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              [
                if (match.locationInfo?.venue != null)
                  match.locationInfo!.venue,
                if (match.date.isNotEmpty) _formatMatchDate(match.date),
                if (match.time != null) match.time!,
              ].join(' · '),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );

    if (canTap) {
      hero = InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TournamentMatchDetailPage(
              match: match,
              teams: widget.teams,
              rosters: widget.rosters,
              tournamentId: widget.tournamentId!,
              sport: widget.sport,
            ),
          ),
        ),
        child: hero,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: hero,
    );
  }

  Widget _buildBronzeCard(
      BuildContext context, TournamentMatch? thirdPlaceMatch) {
    if (thirdPlaceMatch == null) return const SizedBox.shrink();

    return _KnockoutMatchCard(
      match: thirdPlaceMatch,
      teams: widget.teams,
      eliminated: const {},
      tournamentId: widget.tournamentId,
      rosters: widget.rosters,
      sport: widget.sport,
      formatDate: _formatMatchDate,
      headerLabel: '🥉 Third place',
    );
  }

}

// ---------------------------------------------------------------------------
// Bracket connector painter — draws FotMob "]" lines between left and right
// ---------------------------------------------------------------------------

class _BracketConnectorPainter extends CustomPainter {
  final int leftCount;
  final int rightCount;
  final double slotH;
  final double slotGap;
  final double leftColW;
  final double colGapX;
  final Color dividerColor;

  const _BracketConnectorPainter({
    required this.leftCount,
    required this.rightCount,
    required this.slotH,
    required this.slotGap,
    required this.leftColW,
    required this.colGapX,
    required this.dividerColor,
  });

  double _leftCenterY(int i) => i * (slotH + slotGap) + slotH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dividerColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final midX = leftColW + colGapX / 2;
    final rightEdgeX = leftColW + colGapX;

    for (int k = 0; k < rightCount; k++) {
      final feederA = 2 * k;
      final feederB = 2 * k + 1;

      // We need at least one feeder to draw anything meaningful.
      if (feederA >= leftCount) continue;

      final centerA = _leftCenterY(feederA);
      final double centerB =
          feederB < leftCount ? _leftCenterY(feederB) : centerA;

      final rightCenterY = (centerA + centerB) / 2;

      final path = Path();

      if (feederB < leftCount) {
        // Both feeders exist — draw the classic "]" bracket:
        //  · horizontal stub from right edge of feeder A card → midX
        //  · horizontal stub from right edge of feeder B card → midX
        //  · vertical bar along midX connecting A and B
        //  · horizontal line from midX → right edge, at right card center Y
        path
          ..moveTo(leftColW, centerA)
          ..lineTo(midX, centerA)
          ..moveTo(leftColW, centerB)
          ..lineTo(midX, centerB)
          ..moveTo(midX, centerA)
          ..lineTo(midX, centerB)
          ..moveTo(midX, rightCenterY)
          ..lineTo(rightEdgeX, rightCenterY);
      } else {
        // Only one feeder — simple horizontal stub
        path
          ..moveTo(leftColW, centerA)
          ..lineTo(rightEdgeX, centerA);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BracketConnectorPainter old) =>
      old.leftCount != leftCount ||
      old.rightCount != rightCount ||
      old.slotH != slotH ||
      old.slotGap != slotGap ||
      old.leftColW != leftColW ||
      old.colGapX != colGapX ||
      old.dividerColor != dividerColor;
}

// ---------------------------------------------------------------------------
// Boxed match card widget
// ---------------------------------------------------------------------------

class _KnockoutMatchCard extends StatelessWidget {
  final TournamentMatch match;
  final Map<String, TournamentTeam> teams;
  final Set<String> eliminated;
  final String? tournamentId;
  final Map<String, List<TournamentPlayer>> rosters;
  final String sport;
  final String Function(String) formatDate;
  final String? headerLabel;
  /// When true, uses compact paddings so the card fits within the fixed bracket
  /// slot height (~96 px) without overflow.
  final bool compact;

  const _KnockoutMatchCard({
    required this.match,
    required this.teams,
    required this.eliminated,
    required this.tournamentId,
    required this.rosters,
    required this.sport,
    required this.formatDate,
    this.headerLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final team1 = match.team1Id != null ? teams[match.team1Id] : null;
    final team2 = match.team2Id != null ? teams[match.team2Id] : null;
    final isLive = match.matchStatus.isLive;
    final isFinished = match.matchStatus.isFinished;
    final winner = isFinished ? match.winnerTeamId : '';

    final team1IsWinner = winner.isNotEmpty && winner == match.team1Id;
    final team2IsWinner = winner.isNotEmpty && winner == match.team2Id;

    final team1Eliminated = match.team1Id != null &&
        eliminated.contains(match.team1Id) &&
        !team1IsWinner;
    final team2Eliminated = match.team2Id != null &&
        eliminated.contains(match.team2Id) &&
        !team2IsWinner;

    // Only allow tap when both teams are real
    final canTap = match.team1Id != null &&
        match.team1Id!.isNotEmpty &&
        match.team2Id != null &&
        match.team2Id!.isNotEmpty &&
        tournamentId != null;

    // Compact mode uses tighter padding to fit within the 96-px bracket slot.
    final hPad = compact ? 8.0 : 10.0;
    final vPadHeader = compact ? 4.0 : 6.0;

    Widget card = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: optional label / venue + time/date
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPadHeader),
              child: Row(
                children: [
                  if (headerLabel != null) ...[
                    Text(
                      headerLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ] else if (match.locationInfo?.venue != null)
                    Expanded(
                      child: Text(
                        match.locationInfo!.venue,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  if (headerLabel != null) const Spacer(),
                  Text(
                    _timeLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                thickness: 0.5,
                color: Theme.of(context).dividerColor),
            // Team 1 row
            _teamRow(
              context: context,
              team: team1,
              teamId: match.team1Id,
              seed: match.team1Seed,
              score: match.team1Score,
              isEliminated: team1Eliminated,
              isWinner: team1IsWinner,
              showScore: isFinished || isLive,
              compact: compact,
            ),
            Divider(
                height: 1,
                thickness: 0.5,
                color: Theme.of(context).dividerColor),
            // Team 2 row
            _teamRow(
              context: context,
              team: team2,
              teamId: match.team2Id,
              seed: match.team2Seed,
              score: match.team2Score,
              isEliminated: team2Eliminated,
              isWinner: team2IsWinner,
              showScore: isFinished || isLive,
              compact: compact,
            ),
            // LIVE strip
            if (isLive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: Colors.red,
                child: const Center(
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (canTap) {
      card = InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TournamentMatchDetailPage(
              match: match,
              teams: teams,
              rosters: rosters,
              tournamentId: tournamentId!,
              sport: sport,
            ),
          ),
        ),
        child: card,
      );
    }

    // In compact/bracket mode the card is already positioned by the Stack;
    // no outer bottom padding is needed (it would cause overflow).
    if (compact) return card;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
  }

  String _timeLabel() {
    final parts = <String>[];
    if (match.date.isNotEmpty) parts.add(formatDate(match.date));
    if (match.time != null && match.time!.isNotEmpty) parts.add(match.time!);
    return parts.join(' · ');
  }

  Widget _teamRow({
    required BuildContext context,
    required TournamentTeam? team,
    required String? teamId,
    required int? seed,
    required int score,
    required bool isEliminated,
    required bool isWinner,
    required bool showScore,
    bool compact = false,
  }) {
    String displayName;
    if (team != null) {
      displayName = team.name;
    } else if (seed != null) {
      displayName = 'Seed #$seed';
    } else if (teamId != null && teamId.isNotEmpty) {
      displayName = teamId;
    } else {
      displayName = 'TBD';
    }

    final rowHPad = compact ? 8.0 : 10.0;
    final rowVPad = compact ? 5.0 : 8.0;
    final logoSize = compact ? 20.0 : 24.0;
    final fontSize = compact ? 12.0 : 13.0;
    final scoreFontSize = compact ? 13.0 : 15.0;

    Widget logoWidget = TeamLogo(url: team?.logoUrl, size: logoSize);
    if (isEliminated) {
      logoWidget = Opacity(opacity: 0.5, child: logoWidget);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: rowHPad, vertical: rowVPad),
      child: Row(
        children: [
          logoWidget,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight:
                    isWinner ? FontWeight.bold : FontWeight.normal,
                fontStyle: (team == null && seed != null)
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: isEliminated
                    ? Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4)
                    : team == null
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5)
                        : null,
                decoration: isEliminated
                    ? TextDecoration.lineThrough
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showScore)
            Text(
              '$score',
              style: TextStyle(
                fontSize: scoreFontSize,
                fontWeight:
                    isWinner ? FontWeight.bold : FontWeight.normal,
                color: isEliminated
                    ? Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
