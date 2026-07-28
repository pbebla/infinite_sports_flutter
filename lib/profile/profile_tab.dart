import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/insiders/insider_tier_colors.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

/// The "Profile" tab of the tabbed player profile.
///
/// Renders in order:
/// 1. **"Player Info"** card — biographical fields.
/// 2. **Infinite Insider box** (Task F7) — ONLY when this profile's
///    `/Insiders/<uid>` is `Status == active` AND `ProfileBadgeOptIn == true`
///    (spec §7 privacy paragraph). Works identically whether [uid] is the
///    signed-in user's own profile or a visited profile (openPlayerProfile).
/// 3. **"Current Team"** card — sport icon, team name, position, jersey #.
/// 4. **Current-season stats** card — stat grid for the active stint.
/// 5. [TrophyCabinet].
///
/// Parameters:
/// - [uid] — the profile being viewed (own or visited); drives the Insider
///   box's live `/Insiders/<uid>` read.
/// - [information] — raw `Users/{uid}/Information` Firebase map.
/// - [awards] — pre-loaded award list.
/// - [current] — active / most-recent [ParticipationStint]; null if none.
/// - [currentTeamNumber] — jersey number for the current stint (if available).
/// - [currentStatsLabel] — display label for the current-season stats card
///   (e.g. "Futsal League Season 13" or "Summer Cup 2026").
/// - [currentStats] — stat items for the current-season card.
/// - [insiderStream] — test seam replacing the live `/Insiders/<uid>` stream
///   (mirrors the seam pattern in insider_dashboard_page.dart); defaults to
///   `InsiderService.watchMyInsider(uid)`.
/// - [careerLoading] — the profile's slow career load (phase 2) is still in
///   flight: the career-dependent sections render skeletons instead of
///   claiming "not on a roster".
class ProfileTab extends StatelessWidget {
  final String uid;
  final Map<dynamic, dynamic> information;
  final List<Award> awards;
  final bool careerLoading;
  final ParticipationStint? current;
  final String? currentTeamNumber;
  final String? currentStatsLabel;
  final List<({String label, String value})> currentStats;
  final Stream<Insider?>? insiderStream;

  const ProfileTab({
    super.key,
    required this.uid,
    required this.information,
    required this.awards,
    this.careerLoading = false,
    this.current,
    this.currentTeamNumber,
    this.currentStatsLabel,
    this.currentStats = const [],
    this.insiderStream,
  });

  // Known fields shown in this exact order when present and non-empty.
  static const List<({String key, String label})> _knownFields = [
    (key: 'Height', label: 'Height'),
    (key: 'Weight', label: 'Weight'),
    (key: 'Age', label: 'Age'),
    (key: 'Foot', label: 'Preferred Foot'),
    (key: 'PreferredFoot', label: 'Preferred Foot'),
    (key: 'Hand', label: 'Preferred Hand'),
    (key: 'PreferredHand', label: 'Preferred Hand'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_hasAnyInfo()) _infoCard(context),
        _insiderBox(context),
        _currentTeamCard(context),
        if (!careerLoading &&
            current != null &&
            currentStatsLabel != null &&
            currentStats.isNotEmpty)
          _currentSeasonStatsCard(context),
        TrophyCabinet(awards: awards),
      ],
    );
  }

  bool _hasAnyInfo() {
    if (information.isEmpty) return false;
    return _resolvedRows().isNotEmpty;
  }

  /// Build the ordered list of (label, value) pairs to display.
  List<({String label, String value})> _resolvedRows() {
    final rows = <({String label, String value})>[];
    final usedKeys = <String>{};
    // Deduplicate known labels (Foot / PreferredFoot both map to the same
    // display row — show the first one that has a value).
    final shownLabels = <String>{};

    for (final field in _knownFields) {
      if (shownLabels.contains(field.label)) continue;
      final raw = information[field.key];
      final value = _stringify(raw);
      if (value.isNotEmpty) {
        rows.add((label: field.label, value: value));
        shownLabels.add(field.label);
      }
      usedKeys.add(field.key);
    }

    // Remaining keys: exclude *Position variants and already-used keys.
    for (final entry in information.entries) {
      final key = entry.key.toString();
      if (usedKeys.contains(key)) continue;
      if (key.endsWith('Position')) continue;
      final value = _stringify(entry.value);
      if (value.isEmpty) continue;
      rows.add((label: _humanize(key), value: value));
    }

    return rows;
  }

  static String _stringify(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    return s == 'null' || s == '0' ? '' : s;
  }

  /// Insert spaces before capital letters: `JerseySize` → `Jersey Size`.
  static String _humanize(String key) {
    return key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(0)}',
    ).trim();
  }

  Widget _infoCard(BuildContext context) {
    final rows = _resolvedRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Player Info',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 10),
            ...rows.map((r) => _InfoRow(label: r.label, value: r.value)),
          ],
        ),
      ),
    );
  }

  /// The public "Infinite Insider" box (Task F7, spec §7 privacy paragraph)
  /// — LIVE via `/Insiders/<uid>`, so an owner suspending this Insider (or
  /// the Insider flipping their profile-badge opt-out) removes this box
  /// immediately, no refresh. Renders nothing at all (not even a loading
  /// placeholder) for every other case: no application ever submitted,
  /// pending, suspended, declined, or opted out — a bare uid with no
  /// Insider history should look exactly like a non-Insider profile.
  Widget _insiderBox(BuildContext context) {
    if (uid.trim().isEmpty) return const SizedBox.shrink();
    final stream = insiderStream ?? InsiderService.watchMyInsider(uid);
    return StreamBuilder<Insider?>(
      stream: stream,
      builder: (context, snapshot) {
        final insider = snapshot.data;
        if (insider == null || !insider.isActive || !insider.profileBadgeOptIn) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final tierColor = insiderTierColor(insider.tier);
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.diamond, size: 20, color: tierColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Infinite Insider',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: ${profileStatusLabel(insider.tier)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Referrals: ${insider.totalReferred}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _currentTeamCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // PR #10: only an ongoing (unfinished) competition earns
              // "Current Team" — a stint from a finished season/tournament
              // is shown as the player's last team instead.
              (careerLoading || current == null || current!.isActive)
                  ? 'Current Team'
                  : 'Last Team',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 10),
            if (careerLoading)
              // Career load still in flight — a skeleton row in place of the
              // team identity so the card never flashes "not on a roster".
              const Row(
                children: [
                  SkeletonBox(width: 28, height: 28, radius: 14),
                  SizedBox(width: 12),
                  Expanded(
                    child: SkeletonBox(width: double.infinity, height: 16),
                  ),
                ],
              )
            else if (current == null)
              Text(
                'Not currently on a roster.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    _sportIcon(current!.sport),
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current!.team,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (current!.position.isNotEmpty ||
                            (currentTeamNumber?.isNotEmpty ?? false))
                          Wrap(
                            spacing: 8,
                            children: [
                              if (current!.position.isNotEmpty)
                                Text(
                                  current!.position,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                              if (currentTeamNumber?.isNotEmpty ?? false)
                                Text(
                                  '#$currentTeamNumber',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _currentSeasonStatsCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentStatsLabel!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: currentStats
                  .map((s) => _StatCell(label: s.label, value: s.value))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _sportIcon(String sport) {
    switch (sport) {
      case 'Basketball':
        return Icons.sports_basketball;
      case 'Flag Football':
        return Icons.sports_football;
      case 'Tournament':
        return Icons.emoji_events;
      default:
        // Futsal, AFC San Jose, Soccer — all soccer ball
        return Icons.sports_soccer;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.6),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
