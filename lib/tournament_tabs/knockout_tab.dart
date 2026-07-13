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
  late ScrollController _hCtrl;

  /// Ordered knockout-round labels sorted by stage progression (no Third Place
  /// in the main bracket columns).
  static final List<String> _roundOrder = (TournamentStage.values
          .where((s) => s.isKnockout && s != TournamentStage.thirdPlace)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      .map((s) => s.label)
      .toList();

  // Layout constants
  static const double _slotH = 96.0;
  static const double _slotGap = 18.0;
  static const double _colW = 210.0;
  // Change 2: wider final column (300 → 360)
  static const double _finalColW = 360.0;
  static const double _colGapX = 44.0;
  static const double _outerPad = 16.0;

  // Fixed height for the final hero card
  static const double _heroH = 150.0;
  // Estimated bronze card height (two team rows + small header)
  static const double _bronzeH = 90.0;
  // Gap between hero and bronze
  static const double _heroBronzeGap = 12.0;

  @override
  void initState() {
    super.initState();
    _hCtrl = ScrollController();
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  String _formatMatchDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('MMM d').format(dt);
  }

  // ---------------------------------------------------------------------------
  // Pre-compute x-offsets per round (index into bracketRounds list)
  // ---------------------------------------------------------------------------

  double _xOf(int roundIdx, List<String> bracketRounds) {
    double x = _outerPad;
    for (int r = 0; r < roundIdx; r++) {
      final isFinal = bracketRounds[r] == TournamentStage.finalStage.label;
      x += (isFinal ? _finalColW : _colW) + _colGapX;
    }
    return x;
  }

  // ---------------------------------------------------------------------------
  // Pre-compute center Y positions per round (carries forward from round 0)
  // ---------------------------------------------------------------------------

  /// Returns a list of center-Y lists: centersPerRound[r][k] = center Y of
  /// card k in round r, relative to the top of the bracket content.
  List<List<double>> _computeCenters(
      List<String> bracketRounds, Map<String, List<TournamentMatch>> byRound) {
    final result = <List<double>>[];
    for (int r = 0; r < bracketRounds.length; r++) {
      final matches = byRound[bracketRounds[r]] ?? [];
      final count = matches.length;
      if (r == 0) {
        // First round: evenly spaced
        final centers = List.generate(
            count, (i) => i * (_slotH + _slotGap) + _slotH / 2);
        result.add(centers);
      } else {
        final prevCenters = result[r - 1];
        final centers = <double>[];
        for (int k = 0; k < count; k++) {
          final feederA = 2 * k;
          final feederB = 2 * k + 1;
          final double cA = feederA < prevCenters.length
              ? prevCenters[feederA]
              : (prevCenters.isNotEmpty
                  ? prevCenters.last
                  : k * (_slotH + _slotGap) + _slotH / 2);
          final double cB = feederB < prevCenters.length
              ? prevCenters[feederB]
              : cA;
          centers.add((cA + cB) / 2);
        }
        result.add(centers);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Scroll to a round's x-offset
  // ---------------------------------------------------------------------------

  void _scrollToRound(int roundIdx, List<String> bracketRounds) {
    final target = _xOf(roundIdx, bracketRounds);
    if (_hCtrl.hasClients) {
      _hCtrl.animateTo(
        target.clamp(0.0, _hCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Change 3: faint grey backdrop in light mode
    final isLight = Theme.of(context).brightness == Brightness.light;
    final backdropColor = isLight
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : Colors.transparent;

    final knockoutMatches = widget.matches
        .where((m) => TournamentStage.fromString(m.stage).isKnockout)
        .toList();

    if (knockoutMatches.isEmpty) {
      return const Center(child: Text('Knockout stage not yet available'));
    }

    // Build ordered unique bracket rounds (no Third Place)
    final roundsSet = <String>{};
    for (final m in knockoutMatches) {
      final stage = TournamentStage.fromString(m.stage);
      if (stage != TournamentStage.thirdPlace) {
        roundsSet.add(stage.label);
      }
    }
    final bracketRounds =
        _roundOrder.where((r) => roundsSet.contains(r)).toList();

    // Group by normalised round label (all knockout including third place)
    final Map<String, List<TournamentMatch>> byRound = {};
    for (final m in knockoutMatches) {
      final nr = TournamentStage.fromString(m.stage).label;
      byRound.putIfAbsent(nr, () => []).add(m);
    }
    for (final r in byRound.keys) {
      byRound[r]!
          .sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));
    }

    // Eliminated teams
    final eliminated = <String>{};
    for (final m in knockoutMatches) {
      if (m.matchStatus.isFinished) {
        final loser = m.loserTeamId;
        if (loser.isNotEmpty) eliminated.add(loser);
      }
    }

    // Third place match
    final thirdPlaceMatches = knockoutMatches
        .where((m) =>
            TournamentStage.fromString(m.stage) == TournamentStage.thirdPlace)
        .toList();
    final thirdPlaceMatch =
        thirdPlaceMatches.isNotEmpty ? thirdPlaceMatches.first : null;

    if (bracketRounds.isEmpty) {
      return const Center(child: Text('Knockout stage not yet available'));
    }

    // Pre-compute centers
    final centersPerRound = _computeCenters(bracketRounds, byRound);

    // Base height = height of the first (tallest) round column
    final firstCount = (byRound[bracketRounds.first] ?? []).length;
    final baseH = firstCount * (_slotH + _slotGap);

    // Change 1: ensure the Stack is tall enough for the hero + bronze sitting
    // below it in the Final column (both live inside the Stack now).
    final finalRoundIdx = bracketRounds.length - 1;
    final isFinalPresent =
        bracketRounds[finalRoundIdx] == TournamentStage.finalStage.label;
    double totalH = baseH;
    if (isFinalPresent && centersPerRound[finalRoundIdx].isNotEmpty) {
      final finalCenterY = centersPerRound[finalRoundIdx][0];
      final heroTop = finalCenterY - _heroH / 2;
      final bottomEdge = heroTop +
          _heroH +
          _heroBronzeGap +
          (thirdPlaceMatch != null ? _bronzeH : 0) +
          16; // bottom padding inside Stack
      if (bottomEdge > totalH) totalH = bottomEdge;
    }

    // Total width — last column uses finalColW only if it's actually the Final stage
    final lastRoundIdx = bracketRounds.length - 1;
    final lastColW = bracketRounds[lastRoundIdx] == TournamentStage.finalStage.label
        ? _finalColW
        : _colW;
    final totalW = _xOf(lastRoundIdx, bracketRounds) + lastColW + _outerPad;

    // Chip labels — all including Third Place if present
    final allRoundChipLabels = <String>[
      ...bracketRounds,
      if (thirdPlaceMatch != null) TournamentStage.thirdPlace.label,
    ];

    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      color: backdropColor,
      child: Column(
        children: [
          // ── Round chips (quick-jumps) ──────────────────────────────────────
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: allRoundChipLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final label = allRoundChipLabels[index];
                // Change 1: Third Place chip now scrolls to the Final column
                // (bronze lives beneath the hero at the Final x-offset)
                final isThirdPlace = label == TournamentStage.thirdPlace.label;
                return ChoiceChip(
                  label: Text(label),
                  selected: false,
                  showCheckmark: false,
                  onSelected: (_) {
                    if (isThirdPlace) {
                      // Scroll to the Final round x so hero + bronze are in view
                      _scrollToRound(finalRoundIdx, bracketRounds);
                    } else {
                      final roundIdx = bracketRounds.indexOf(label);
                      if (roundIdx >= 0) _scrollToRound(roundIdx, bracketRounds);
                    }
                  },
                );
              },
            ),
          ),

          // ── Continuous bracket ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              // Outer vertical scroll. Bottom inset keeps the last bracket
              // row reachable above the floating glass nav bar.
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hCtrl,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: SizedBox(
                    width: totalW,
                    height: totalH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ── Connectors (behind cards) ──────────────────
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MultiBracketConnectorPainter(
                              bracketRounds: bracketRounds,
                              centersPerRound: centersPerRound,
                              byRound: byRound,
                              slotH: _slotH,
                              colW: _colW,
                              finalColW: _finalColW,
                              colGapX: _colGapX,
                              outerPad: _outerPad,
                              dividerColor: dividerColor,
                            ),
                          ),
                        ),
                        // ── Cards per round ────────────────────────────
                        for (int r = 0; r < bracketRounds.length; r++) ...[
                          ..._buildRoundCards(
                            context: context,
                            roundIdx: r,
                            bracketRounds: bracketRounds,
                            byRound: byRound,
                            centersPerRound: centersPerRound,
                            eliminated: eliminated,
                            allMatches: knockoutMatches,
                            thirdPlaceMatch: thirdPlaceMatch,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build all positioned cards for one round
  // ---------------------------------------------------------------------------

  List<Widget> _buildRoundCards({
    required BuildContext context,
    required int roundIdx,
    required List<String> bracketRounds,
    required Map<String, List<TournamentMatch>> byRound,
    required List<List<double>> centersPerRound,
    required Set<String> eliminated,
    required List<TournamentMatch> allMatches,
    TournamentMatch? thirdPlaceMatch,
  }) {
    final roundLabel = bracketRounds[roundIdx];
    final matches = byRound[roundLabel] ?? [];
    // Only use the hero layout for the actual "Final" stage, not just any last round.
    final isFinalRound = roundLabel == TournamentStage.finalStage.label;
    final colW = isFinalRound ? _finalColW : _colW;
    final leftX = _xOf(roundIdx, bracketRounds);
    final centers = centersPerRound[roundIdx];

    final result = <Widget>[];
    for (int k = 0; k < matches.length; k++) {
      final m = matches[k];
      final centerY = k < centers.length
          ? centers[k]
          : k * (_slotH + _slotGap) + _slotH / 2;

      if (isFinalRound) {
        // Change 1: Final column = hero (fixed 150 h) + bronze beneath it,
        // all in a single Positioned Column so bronze scrolls with the hero.
        final heroTop = centerY - _heroH / 2;
        result.add(Positioned(
          top: heroTop,
          left: leftX,
          width: colW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Hero at fixed height
              SizedBox(
                height: _heroH,
                child: _buildFinalHero(context, m),
              ),
              // Bronze card beneath the hero (only when present)
              if (thirdPlaceMatch != null) ...[
                const SizedBox(height: _heroBronzeGap),
                _buildBronzeCard(context, thirdPlaceMatch, colW),
              ],
            ],
          ),
        ));
      } else {
        final topY = centerY - _slotH / 2;
        result.add(Positioned(
          top: topY,
          left: leftX,
          width: colW,
          height: _slotH,
          child: _KnockoutMatchCard(
            match: m,
            teams: widget.teams,
            eliminated: eliminated,
            tournamentId: widget.tournamentId,
            rosters: widget.rosters,
            sport: widget.sport,
            formatDate: _formatMatchDate,
            compact: true,
            allMatches: allMatches,
          ),
        ));
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Final hero
  // ---------------------------------------------------------------------------

  Widget _buildFinalHero(BuildContext context, TournamentMatch match) {
    final team1 =
        match.team1Id != null ? widget.teams[match.team1Id] : null;
    final team2 =
        match.team2Id != null ? widget.teams[match.team2Id] : null;
    final isFinished = match.matchStatus.isFinished;
    final isLive = match.matchStatus.isLive;
    final winnerId = isFinished ? match.winnerTeamId : '';
    final winnerTeam = winnerId.isNotEmpty ? widget.teams[winnerId] : null;

    List<Color> gradientColors;
    if (isFinished) {
      final homeColor = winnerTeam?.homeColor;
      if (homeColor != null) {
        gradientColors = [
          homeColor,
          Color.lerp(homeColor, Colors.black, 0.35)!,
        ];
      } else {
        gradientColors = const [Color(0xFFFFB300), Color(0xFFE65100)];
      }
    } else {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(url: team1?.logoUrl, size: 36),
                    const SizedBox(height: 5),
                    Text(
                      team1?.name ?? (match.team1Seed != null
                          ? 'Seed #${match.team1Seed}'
                          : 'TBD'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/trophy.png',
                      height: 36,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.emoji_events,
                        size: 36,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(height: 6),
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
                              fontSize: 24,
                              fontWeight: team1IsWinner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              '–',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          Text(
                            '${match.team2Score}',
                            style: TextStyle(
                              color: team2IsWinner
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 24,
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
                          fontSize: 13,
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
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(url: team2?.logoUrl, size: 36),
                    const SizedBox(height: 5),
                    Text(
                      team2?.name ?? (match.team2Seed != null
                          ? 'Seed #${match.team2Seed}'
                          : 'TBD'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
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
          if (!isFinished &&
              (match.locationInfo?.venue != null ||
                  match.date.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (match.locationInfo?.venue != null)
                  match.locationInfo!.venue,
                if (match.date.isNotEmpty) _formatMatchDate(match.date),
                if (match.time != null) match.time!,
              ].join(' · '),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
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

    // Fill the fixed hero height
    return SizedBox(
      height: _heroH,
      child: hero,
    );
  }

  // ---------------------------------------------------------------------------
  // Bronze card — smaller, muted, sits beneath the Final hero
  // ---------------------------------------------------------------------------

  Widget _buildBronzeCard(
      BuildContext context, TournamentMatch? thirdPlaceMatch, double parentWidth) {
    if (thirdPlaceMatch == null) return const SizedBox.shrink();

    // Narrower than the hero and centered within the final column width
    final bronzeWidth = parentWidth - 48;
    return Center(
      child: SizedBox(
        width: bronzeWidth,
        child: _KnockoutMatchCard(
          match: thirdPlaceMatch,
          teams: widget.teams,
          eliminated: const {},
          tournamentId: widget.tournamentId,
          rosters: widget.rosters,
          sport: widget.sport,
          formatDate: _formatMatchDate,
          headerLabel: '🥉 Third place',
          allMatches: widget.matches,
          compact: true,
          isBronze: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-round bracket connector painter
// Draws "]" connectors for every adjacent round pair r → r+1.
// ---------------------------------------------------------------------------

class _MultiBracketConnectorPainter extends CustomPainter {
  final List<String> bracketRounds;
  final List<List<double>> centersPerRound;
  final Map<String, List<TournamentMatch>> byRound;
  final double slotH;
  final double colW;
  final double finalColW;
  final double colGapX;
  final double outerPad;
  final Color dividerColor;

  const _MultiBracketConnectorPainter({
    required this.bracketRounds,
    required this.centersPerRound,
    required this.byRound,
    required this.slotH,
    required this.colW,
    required this.finalColW,
    required this.colGapX,
    required this.outerPad,
    required this.dividerColor,
  });

  double _xOf(int roundIdx) {
    double x = outerPad;
    for (int r = 0; r < roundIdx; r++) {
      // Use the wider final column only for the actual Final stage, not just the last position.
      final isFinalStage =
          bracketRounds[r] == TournamentStage.finalStage.label;
      x += (isFinalStage ? finalColW : colW) + colGapX;
    }
    return x;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dividerColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < bracketRounds.length - 1; r++) {
      final leftCenters = centersPerRound[r];
      final rightCenters = centersPerRound[r + 1];
      final rightCount = rightCenters.length;

      final leftColActualW = bracketRounds[r] == TournamentStage.finalStage.label
          ? finalColW
          : colW;
      final leftRightEdgeX = _xOf(r) + leftColActualW; // right edge of left col
      final rightLeftEdgeX = _xOf(r + 1);               // left edge of right col
      final midX = (leftRightEdgeX + rightLeftEdgeX) / 2;

      for (int k = 0; k < rightCount; k++) {
        final feederA = 2 * k;
        final feederB = 2 * k + 1;

        if (feederA >= leftCenters.length) continue;

        final centerA = leftCenters[feederA];
        final double centerB = feederB < leftCenters.length
            ? leftCenters[feederB]
            : centerA;
        final rightCenterY = rightCenters[k];

        final path = Path();
        if (feederB < leftCenters.length) {
          // Classic "]" bracket
          path
            ..moveTo(leftRightEdgeX, centerA)
            ..lineTo(midX, centerA)
            ..moveTo(leftRightEdgeX, centerB)
            ..lineTo(midX, centerB)
            ..moveTo(midX, centerA)
            ..lineTo(midX, centerB)
            ..moveTo(midX, rightCenterY)
            ..lineTo(rightLeftEdgeX, rightCenterY);
        } else {
          // Single feeder — straight horizontal stub
          path
            ..moveTo(leftRightEdgeX, centerA)
            ..lineTo(rightLeftEdgeX, centerA);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MultiBracketConnectorPainter old) =>
      old.bracketRounds != bracketRounds ||
      old.centersPerRound != centersPerRound ||
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
  final List<TournamentMatch> allMatches;

  /// When true, uses compact paddings so the card fits within the fixed bracket
  /// slot height (~96 px) without overflow.
  final bool compact;

  /// When true, applies muted styling appropriate for the 3rd-place bronze card.
  final bool isBronze;

  const _KnockoutMatchCard({
    required this.match,
    required this.teams,
    required this.eliminated,
    required this.tournamentId,
    required this.rosters,
    required this.sport,
    required this.formatDate,
    required this.allMatches,
    this.headerLabel,
    this.compact = false,
    this.isBronze = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

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

    final hPad = compact ? 8.0 : 10.0;
    final vPadHeader = compact ? 4.0 : 6.0;

    // Change 3: light-mode card background matches Teams tab (Card = surface/white)
    // + faint border to stand off the grey backdrop. Dark mode unchanged.
    final cardColor = isLight
        ? cs.surface
        : const Color(0xFF24262B);
    final cardBorder = isLight
        ? Border.all(color: cs.onSurface.withValues(alpha: 0.08))
        : null;
    // Bronze: slightly dimmer surface in light, same dark fill in dark
    final effectiveCardColor = isBronze && isLight
        ? cs.surfaceContainerHighest
        : cardColor;

    Widget card = Container(
      decoration: BoxDecoration(
        color: effectiveCardColor,
        borderRadius: BorderRadius.circular(12),
        border: cardBorder,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.06),
            blurRadius: isLight ? 4 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header row — only for upcoming matches. Live shows the LIVE
            // strip + live score, finished shows the final score, so the
            // kickoff date/time header is redundant (and would overflow the
            // fixed bracket slot when stacked with the LIVE strip).
            if (!isFinished && !isLive)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: hPad, vertical: vPadHeader),
                child: Row(
                  children: [
                    if (headerLabel != null) ...[
                      Text(
                        headerLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          // Change 4: secondary label is muted
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ] else if (match.locationInfo?.venue != null)
                      Expanded(
                        child: Text(
                          match.locationInfo!.venue,
                          style: TextStyle(
                            fontSize: 11,
                            // Change 4: venue is secondary/muted
                            color: cs.onSurface.withValues(alpha: 0.55),
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
                        // Change 4: date/time is secondary/muted
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            // Team 1 row (no internal divider — FotMob style)
            _teamRow(
              context: context,
              team: team1,
              teamId: match.team1Id,
              seed: match.team1Seed,
              source: match.team1Source,
              score: match.team1Score,
              isEliminated: team1Eliminated,
              isWinner: team1IsWinner,
              showScore: isFinished || isLive,
              compact: compact,
            ),
            // Team 2 row
            _teamRow(
              context: context,
              team: team2,
              teamId: match.team2Id,
              seed: match.team2Seed,
              source: match.team2Source,
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
    required String? source,
    required int score,
    required bool isEliminated,
    required bool isWinner,
    required bool showScore,
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    // Determine display name and whether this is a placeholder slot
    String displayName;
    bool isPlaceholder = false;
    if (team != null) {
      displayName = team.name;
    } else if (seed != null) {
      displayName = 'Seed #$seed';
    } else if (teamId != null && teamId.isNotEmpty) {
      displayName = teamId;
    } else if (source != null && source.isNotEmpty) {
      // Show feeder placeholder
      displayName = formatFeederSource(source, allMatches);
      isPlaceholder = true;
    } else {
      displayName = 'TBD';
    }

    final rowHPad = compact ? 8.0 : 10.0;
    final rowVPad = compact ? 5.0 : 8.0;
    final logoSize = compact ? 20.0 : 24.0;
    final fontSize = compact ? 12.0 : 13.0;
    final scoreFontSize = compact ? 13.0 : 15.0;

    // Logo or placeholder shield icon
    Widget logoWidget;
    if (isPlaceholder) {
      logoWidget = Icon(
        Icons.shield_outlined,
        size: logoSize,
        color: cs.onSurface.withValues(alpha: 0.35),
      );
    } else {
      logoWidget = TeamLogo(url: team?.logoUrl, size: logoSize);
    }
    if (isEliminated) {
      logoWidget = Opacity(opacity: 0.5, child: logoWidget);
    }

    // Change 4: team name uses full-strength onSurface (w600) for real teams.
    // Placeholder / TBD / eliminated retain muted treatment.
    Color? nameColor;
    if (isEliminated) {
      nameColor = cs.onSurface.withValues(alpha: 0.4);
    } else if (isPlaceholder) {
      nameColor = cs.onSurface.withValues(alpha: 0.55);
    } else if (team == null && seed == null) {
      // Pure TBD
      nameColor = cs.onSurface.withValues(alpha: 0.5);
    }
    // else null → inherits default (full onSurface)

    FontWeight nameWeight;
    if (isWinner) {
      nameWeight = FontWeight.bold;
    } else if (!isPlaceholder && team != null) {
      // Real named team: w600 for contrast even when not winner
      nameWeight = FontWeight.w600;
    } else {
      nameWeight = FontWeight.normal;
    }

    // Score text: full onSurface for active teams, muted for eliminated
    Color? scoreColor;
    if (isEliminated) {
      scoreColor = cs.onSurface.withValues(alpha: 0.4);
    }
    // else null → full onSurface

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
                fontWeight: nameWeight,
                fontStyle: isPlaceholder || (team == null && seed != null)
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: nameColor,
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
                fontWeight: isWinner ? FontWeight.bold : FontWeight.w600,
                color: scoreColor,
              ),
            ),
        ],
      ),
    );
  }
}
