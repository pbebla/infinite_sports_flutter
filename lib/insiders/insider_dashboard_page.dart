import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// The Insider-only 5th bottom-nav tab (Task F4) — private live dashboard
/// for an approved Insider: tier badge + progress, code + share, referral
/// history, per-sport breakdown, Infinite maintenance meter, and the two
/// leaderboard/profile opt-out toggles (spec §7).
///
/// `lib/misc/home_nav.dart` only ever puts this tab in front of the user
/// while `/Insiders/<uid>` streams Status=='active', but this page still
/// renders a defensive suspended/missing notice of its own — a suspension
/// landing WHILE the tab is open flips that source-of-truth stream live,
/// and this body should never show stale Insider data once that happens.
class InsiderDashboardPage extends StatefulWidget {
  const InsiderDashboardPage({
    super.key,
    this.insiderStream,
    this.referralsStream,
    this.setLeaderboardOptIn,
    this.setProfileBadgeOptIn,
    this.shareInvite,
  });

  /// Test seams — mirror the pattern in insiders_info_page.dart. Defaults
  /// to the real InsiderService calls for the signed-in uid.
  final Stream<Insider?>? insiderStream;
  final Stream<List<InsiderReferral>>? referralsStream;
  final Future<void> Function(bool value)? setLeaderboardOptIn;
  final Future<void> Function(bool value)? setProfileBadgeOptIn;

  /// Test seam replacing the real share-sheet call (SharePlus touches
  /// platform channels, which aren't available in widget tests).
  final void Function(String message)? shareInvite;

  @override
  State<InsiderDashboardPage> createState() => _InsiderDashboardPageState();
}

class _InsiderDashboardPageState extends State<InsiderDashboardPage> {
  late final Stream<Insider?> _insiderStream;
  late final Stream<List<InsiderReferral>> _referralsStream;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // `??` short-circuits: when a test supplies both streams, FirebaseAuth
    // is never touched (mirrors insiders_info_page.dart's own seam).
    _insiderStream = widget.insiderStream ?? InsiderService.watchMyInsider(_uid);
    _referralsStream =
        widget.referralsStream ?? InsiderService.watchMyReferrals(_uid);
  }

  Future<void> _onLeaderboardOptInChanged(bool value) async {
    final write = widget.setLeaderboardOptIn ??
        (v) => InsiderService.setLeaderboardOptIn(uid: _uid, value: v);
    await write(value);
  }

  Future<void> _onProfileBadgeOptInChanged(bool value) async {
    final write = widget.setProfileBadgeOptIn ??
        (v) => InsiderService.setProfileBadgeOptIn(uid: _uid, value: v);
    await write(value);
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  void _share(String code) {
    final message = inviteMessage(code);
    final override = widget.shareInvite;
    if (override != null) {
      override(message);
    } else {
      SharePlus.instance.share(ShareParams(text: message));
    }
  }

  void _showLeaderboardComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Leaderboard coming in the next update')),
    );
    // TODO(F6): push the real public leaderboard hub page here once built.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insider Dashboard'),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: StreamBuilder<Insider?>(
        stream: _insiderStream,
        builder: (context, insiderSnap) {
          if (insiderSnap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonList(count: 6),
            );
          }
          final insider = insiderSnap.data;
          if (insider == null || !insider.isActive) {
            return _suspendedOrMissingNotice(context, insider);
          }
          return StreamBuilder<List<InsiderReferral>>(
            stream: _referralsStream,
            builder: (context, refSnap) {
              final loadingReferrals =
                  refSnap.connectionState == ConnectionState.waiting;
              final referrals = refSnap.data ?? const <InsiderReferral>[];
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, insider),
                      const SizedBox(height: 20),
                      _codeCard(context, insider),
                      const SizedBox(height: 20),
                      _referralsSection(context, referrals, loadingReferrals),
                      if (!loadingReferrals && referrals.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _perSportSection(context, referrals),
                      ],
                      if (insider.tier == 5) ...[
                        const SizedBox(height: 16),
                        _infiniteMeter(context, insider),
                      ],
                      const SizedBox(height: 20),
                      _settingsSection(context, insider),
                      const SizedBox(height: 20),
                      _leaderboardButton(context),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _suspendedOrMissingNotice(BuildContext context, Insider? insider) {
    final scheme = Theme.of(context).colorScheme;
    final suspended = insider?.isSuspended == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pause_circle_outline, color: scheme.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  suspended
                      ? 'Your Insider account is currently suspended.'
                      : 'Your Insider dashboard is not available right now.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (suspended) ...[
                  const SizedBox(height: 8),
                  Text('Contact us for details.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Insider insider) {
    final scheme = Theme.of(context).colorScheme;
    final label = insider.tier == 0 ? 'Insider' : tierName(insider.tier);
    final pct = tierDiscountPct(insider.tier);
    final progress = tierProgress(insider.currentStanding);
    final label2 = progressLabel(insider.currentStanding);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.diamond, color: infiniteSportsGoldColor, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    insider.tier == 0 ? label : '$label — $pct% off',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: infiniteSportsGoldColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(infiniteSportsGoldColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(label2, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _statBox(context, 'Total Referred',
                      insider.totalReferred.toString()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statBox(context, 'Current Standing',
                      insider.currentStanding.toString()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _codeCard(BuildContext context, Insider insider) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your code',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(
              insider.code,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('insider_dashboard_copy_button'),
                    onPressed: () => _copyCode(insider.code),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('insider_dashboard_share_button'),
                    onPressed: () => _share(insider.code),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _referralsSection(
      BuildContext context, List<InsiderReferral> referrals, bool loading) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your referrals',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (loading)
              const SkeletonLines(count: 3)
            else if (referrals.isEmpty)
              Text('No referrals yet — share your code to get started!',
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (var i = 0; i < referrals.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _referralRow(context, referrals[i]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _referralRow(BuildContext context, InsiderReferral r) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = r.countedAt > 0
        ? DateFormat.yMMMd()
            .format(DateTime.fromMillisecondsSinceEpoch(r.countedAt))
        : '';
    Widget trailing;
    if (r.isVoided) {
      trailing = Text('Voided',
          style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600));
    } else if (r.verified) {
      trailing = const Text('✓ Verified',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600));
    } else {
      trailing =
          Text('Counted', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.referredName.isEmpty ? 'Unnamed player' : r.referredName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: r.isVoided ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [r.sport, dateStr].where((s) => s.isNotEmpty).join(' · '),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (r.manual)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Manual',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _perSportSection(BuildContext context, List<InsiderReferral> referrals) {
    final counts = perSportCounts(referrals);
    if (counts.isEmpty) return const SizedBox.shrink();
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in entries)
          Chip(
            label: Text('${e.key} ${e.value}'),
            backgroundColor: scheme.surfaceContainerHigh,
          ),
      ],
    );
  }

  Widget _infiniteMeter(BuildContext context, Insider insider) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.all_inclusive, color: infiniteSportsGoldColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Infinite maintenance: '
              '${infiniteMaintenanceLabel(insider.currentYearCount)}',
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSection(BuildContext context, Insider insider) {
    return Card(
      elevation: 1,
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('insider_leaderboard_switch'),
            title: const Text('Show me on the public leaderboard'),
            value: insider.publicLeaderboardOptIn,
            onChanged: (v) => _onLeaderboardOptInChanged(v),
          ),
          SwitchListTile(
            key: const ValueKey('insider_profile_badge_switch'),
            title: const Text('Show Insider badge on my profile'),
            value: insider.profileBadgeOptIn,
            onChanged: (v) => _onProfileBadgeOptInChanged(v),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: const ValueKey('insider_dashboard_leaderboard_button'),
        onPressed: _showLeaderboardComingSoon,
        child: const Text('See full leaderboard'),
      ),
    );
  }
}
