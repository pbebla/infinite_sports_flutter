import 'package:flutter/material.dart';

import 'package:infinite_sports_flutter/insiders/insider_tier_colors.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// The public Infinite Insiders leaderboard (Task F6, spec §8) — lives in
/// the Search hub (lib/search_hub_page.dart) alongside Around You, and is
/// also linked from the private Insider dashboard's "See full leaderboard"
/// button (lib/insiders/insider_dashboard_page.dart, Task F4).
///
/// LIVE: rides `InsiderService.watchAllInsiders` + `watchAllReferrals` so an
/// approval, a new counted referral, or a tier change appears here in real
/// time, no refresh. Opt-out is fully respected — [leaderboardRows] never
/// returns a row for an Insider with `PublicLeaderboardOptIn == false`.
class InsidersLeaderboardPage extends StatefulWidget {
  const InsidersLeaderboardPage({
    super.key,
    this.insidersStream,
    this.referralsStream,
    this.nowMs,
  });

  /// Test seams — mirror the pattern in insider_dashboard_page.dart. Default
  /// to the real InsiderService streams.
  final Stream<Map<String, Insider>>? insidersStream;
  final Stream<List<InsiderReferral>>? referralsStream;

  /// Fixed "now" for period-window math ([leaderboardRows]/[programStats]).
  /// Defaults to the real wall clock; tests pin this for determinism.
  final int? nowMs;

  @override
  State<InsidersLeaderboardPage> createState() =>
      _InsidersLeaderboardPageState();
}

class _InsidersLeaderboardPageState extends State<InsidersLeaderboardPage> {
  late final Stream<Map<String, Insider>> _insidersStream;
  late final Stream<List<InsiderReferral>> _referralsStream;

  LeaderboardPeriod _period = LeaderboardPeriod.allTime;
  String? _sportFilter; // null == "All sports"
  int? _tierFilter; // null == "All tiers"

  @override
  void initState() {
    super.initState();
    _insidersStream =
        widget.insidersStream ?? InsiderService.watchAllInsiders();
    _referralsStream =
        widget.referralsStream ?? InsiderService.watchAllReferrals();
  }

  int get _nowMs => widget.nowMs ?? DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insiders Leaderboard'),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: StreamBuilder<Map<String, Insider>>(
        stream: _insidersStream,
        builder: (context, insidersSnap) {
          final loadingInsiders =
              insidersSnap.connectionState == ConnectionState.waiting;
          final insiders = insidersSnap.data ?? const <String, Insider>{};
          return StreamBuilder<List<InsiderReferral>>(
            stream: _referralsStream,
            builder: (context, refSnap) {
              final loadingReferrals =
                  refSnap.connectionState == ConnectionState.waiting;
              final referrals = refSnap.data ?? const <InsiderReferral>[];

              if (loadingInsiders || loadingReferrals) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: SkeletonList(count: 6),
                );
              }

              final insiderList = insiders.values.toList();
              final stats = programStats(insiderList, referrals, _nowMs);
              final rows = leaderboardRows(
                insiders: insiderList,
                referrals: referrals,
                periodFilter: _period,
                sportFilter: _sportFilter,
                tierFilter: _tierFilter,
                nowMs: _nowMs,
              );
              final sportOptions = _sportOptions(referrals);

              return SafeArea(
                child: Column(
                  children: [
                    _statsHeader(context, stats),
                    _filters(context, sportOptions),
                    const Divider(height: 1),
                    Expanded(
                      child: rows.isEmpty
                          ? _emptyState(context)
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) =>
                                  _row(context, i + 1, rows[i]),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<String> _sportOptions(List<InsiderReferral> referrals) {
    final sports = referrals
        .where((r) => r.isCounted && r.sport.isNotEmpty)
        .map((r) => r.sport)
        .toSet()
        .toList()
      ..sort();
    return sports;
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.leaderboard_outlined,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No insiders yet',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _statsHeader(BuildContext context, ProgramStats stats) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
              child: _statTile(context, 'Insiders', '${stats.totalInsiders}')),
          const SizedBox(width: 10),
          Expanded(
              child: _statTile(
                  context, 'Referrals', '${stats.totalReferrals}')),
          const SizedBox(width: 10),
          Expanded(
              child: _statTile(context, 'This Month', '${stats.thisMonth}')),
        ],
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  static String _periodLabel(LeaderboardPeriod p) {
    switch (p) {
      case LeaderboardPeriod.allTime:
        return 'All-time';
      case LeaderboardPeriod.thisYear:
        return 'This year';
      case LeaderboardPeriod.thisMonth:
        return 'This month';
    }
  }

  Widget _filters(BuildContext context, List<String> sportOptions) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in LeaderboardPeriod.values)
                ChoiceChip(
                  key: ValueKey('insider_leaderboard_period_${period.name}'),
                  label: Text(_periodLabel(period)),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('insider_leaderboard_sport_chip_All'),
                label: const Text('All sports'),
                selected: _sportFilter == null,
                onSelected: (_) => setState(() => _sportFilter = null),
              ),
              for (final sport in sportOptions)
                ChoiceChip(
                  key: ValueKey('insider_leaderboard_sport_chip_$sport'),
                  label: Text(sport),
                  selected: _sportFilter == sport,
                  onSelected: (_) => setState(() => _sportFilter = sport),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Tier: ',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              DropdownButton<int?>(
                key: const ValueKey('insider_leaderboard_tier_dropdown'),
                value: _tierFilter,
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('All')),
                  for (var t = 1; t <= 5; t++)
                    DropdownMenuItem<int?>(
                        value: t, child: Text(tierName(t))),
                ],
                onChanged: (value) => setState(() => _tierFilter = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int rank, LeaderboardRow row) {
    final scheme = Theme.of(context).colorScheme;
    final medal = rankMedalColor(rank);
    final tierLabel = row.tier == 0 ? 'Insider' : tierName(row.tier);
    final tierColor = insiderTierColor(row.tier);
    final sportEntries = row.perSport.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final sportsLine =
        sportEntries.map((e) => '${e.key} ${e.value}').join(' · ');

    return Card(
      key: ValueKey('insider_leaderboard_row_${row.uid}'),
      elevation: medal != null ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: medal != null
            ? BorderSide(color: medal, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: medal != null
                  ? Icon(Icons.emoji_events,
                      color: medal,
                      key: ValueKey('insider_leaderboard_medal_$rank'))
                  : Text('$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 10),
            Icon(Icons.diamond, size: 16, color: tierColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name.isEmpty ? 'Unnamed Insider' : row.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tierLabel,
                        style:
                            TextStyle(fontSize: 11, color: scheme.onSurface)),
                  ),
                  if (sportsLine.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(sportsLine,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${row.referralCount}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}
