import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:infinite_sports_flutter/misc/home_nav.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/search_hub_page.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';

/// The public Infinite Insiders leaderboard spot (Task F6) — lives in the
/// Search hub (lib/search_hub_page.dart) alongside Around You, and is also
/// linked from the private Insider dashboard's "See full leaderboard"
/// button (lib/insiders/insider_dashboard_page.dart, Task F4).
///
/// DB lockdown B6: the program is DORMANT (its data was wiped 2026-07-31)
/// and the old whole-`/Insiders` + `/Referrals` reads — which exposed every
/// applicant's email — are denied under the default-deny rules. Until the
/// Insiders rebuild ships its own public mirror, this page shows a friendly
/// "coming soon" state and performs NO program-wide read at all. The only
/// Firebase read left is the viewer's OWN `/Insiders/<uid>` node (owner-
/// readable by rule), which drives the bottom nav's Insider tab exactly
/// like MyHomePage's own check (lib/main.dart, Task F8).
class InsidersLeaderboardPage extends StatefulWidget {
  const InsidersLeaderboardPage({
    super.key,
    this.myInsiderStream,
    this.viewerUid,
    this.switchHomeTabOverride,
    this.searchHubPageBuilder,
  });

  /// Test seam replacing the live `/Insiders/<viewer uid>` stream that
  /// decides whether the bottom nav shows the Insider tab (mirrors the
  /// `insiderStream` seam on ProfileTab / InsidersInfoPage).
  final Stream<Insider?>? myInsiderStream;

  /// Test seam for the signed-in viewer's own uid — production reads
  /// FirebaseAuth.instance.currentUser. Used only for the bottom nav's tab
  /// set (Task F8).
  final String? viewerUid;

  /// Test seam replacing the real [switchHomeTab] call (Task F8) the bottom
  /// nav's items make — the real call pops to the root route and switches
  /// MyHomePage's tab, which needs a multi-route Navigator + main.dart's
  /// listener wired up, neither available in a plain widget test.
  final void Function(BuildContext context, HomeTab tab)? switchHomeTabOverride;

  /// Test seam replacing the real `Navigator.push(... SearchHubPage ...)`
  /// the bottom nav's search button makes (Task F8).
  final Widget Function()? searchHubPageBuilder;

  @override
  State<InsidersLeaderboardPage> createState() =>
      _InsidersLeaderboardPageState();
}

class _InsidersLeaderboardPageState extends State<InsidersLeaderboardPage> {
  late final Stream<Insider?> _myInsiderStream;

  @override
  void initState() {
    super.initState();
    final uid = _viewerUid;
    _myInsiderStream = widget.myInsiderStream ??
        (uid.isEmpty
            ? Stream<Insider?>.value(null)
            : InsiderService.watchMyInsider(uid));
  }

  // Best-effort (utility.dart convention): this page is reachable by ANY
  // signed-in fan, so a widget test may never touch FirebaseAuth at all —
  // reading it defensively means a missing `viewerUid` test seam degrades
  // to "not an active Insider" instead of throwing `[core/no-app]`.
  String get _viewerUid {
    if (widget.viewerUid != null) return widget.viewerUid!;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Insider?>(
      stream: _myInsiderStream,
      builder: (context, insiderSnap) {
        // Task F8: the bottom nav's tab set must match the viewer's own
        // MyHomePage exactly — same live Status=='active' check
        // _MyHomePageState (lib/main.dart) uses.
        final isActiveInsider = insiderSnap.data?.isActive == true;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Insiders Leaderboard'),
            backgroundColor: TournamentColors.headerBackground(context),
            foregroundColor: TournamentColors.headerForeground(context),
          ),
          bottomNavigationBar: _bottomNav(context, isActiveInsider),
          body: SafeArea(child: _comingSoon(context)),
        );
      },
    );
  }

  /// Friendly dormant state — theme-safe: every color comes from the
  /// active ColorScheme, so it reads correctly in light AND dark mode.
  Widget _comingSoon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('insider_leaderboard_coming_soon'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.diamond,
                  size: 48, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Text('Leaderboard coming soon',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'The Infinite Insiders referral program is getting a fresh '
              'start. Check back soon to see the top referrers here!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// The same glass bottom nav MyHomePage renders (Task F8) — lets someone
  /// on this pushed route jump straight to Matches/Leagues/Tournaments/
  /// Calendar(/Insider) instead of backing out first. `selectedIndex: -1`
  /// deliberately matches nothing: this page isn't one of MyHomePage's tabs,
  /// so no item should render as "current".
  Widget _bottomNav(BuildContext context, bool isActiveInsider) {
    final tabs = navItemsFor(isActiveInsider);
    return GlassNavBar(
      destinations: [for (final tab in tabs) destinationFor(tab)],
      selectedIndex: -1,
      onDestinationSelected: (i) => _onNavTap(tabs[i]),
      onSearchTap: _openSearchHub,
    );
  }

  void _onNavTap(HomeTab tab) {
    final override = widget.switchHomeTabOverride;
    if (override != null) {
      override(context, tab);
    } else {
      switchHomeTab(context, tab);
    }
  }

  void _openSearchHub() {
    final builder = widget.searchHubPageBuilder ?? () => const SearchHubPage();
    Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
  }
}
