// The Infinite Fantasy Hub (P3a Task 2) — banner, deadline chip, and the five
// tabs: My Team · Players · Leaderboards · News · Rules (spec §10). My Team /
// Players / Leaderboards / News are tasteful placeholders until P3b–P3d; the
// Rules tab renders live from the streamed config (Task 3).
//
// House rules honored here: streams only; SINGLE fade reveal once
// config+players+manager first arrive (no piecemeal pops — a skeleton holds
// the layout until all three streams have emitted); light+dark via colorScheme with
// the fantasy banner staying a dark gradient in both themes; scrollables
// clear the floating glass navbar (base + MediaQuery.paddingOf(context)
// .bottom).
//
// Push taps (automation spec 2026-10-28 §4.2): [FantasyHubPage.initialTab]
// opens on News (a news push), Leaderboards on Overall (a badge push, spec
// 2026-10-30 §4) or My Team (everything else), and
// [FantasyHubPage.focusPostId] scrolls the News feed to the tapped post.
//
// Player profiles (round 3, spec §4): EVERY player tap inside the hub — News
// "View player" and compact rows, the My Team court (chip sheet's "Player
// profile"; a locked court's chip tap), the Leaderboards tab's Team of the
// Week and manager squad viewer, and (via [FantasyHubPage.initialPlayerName])
// "Open in Fantasy" — goes through ONE opener, [_openPlayerProfile], which
// pushes the full-screen profile editing this hub's shared draft. The
// Players tab opens the same page itself, with the same draft.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/team_name_dialog.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

export 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart'
    show FantasyHubTab;

/// The page route that opens the hub for a [FantasyHubRoute] — shared by the
/// push-tap router (News/My Team landings) and "Open in Fantasy" (Players tab
/// + a player's profile), so the route → page mapping lives in one place.
MaterialPageRoute<void> fantasyHubPageRoute(FantasyHubRoute route) =>
    MaterialPageRoute<void>(
      builder: (_) => FantasyHubPage(
        sport: route.sport,
        season: route.season,
        initialTab: route.initialTab,
        focusPostId: route.focusPostId,
        initialPlayerName: route.initialPlayerName,
      ),
    );

class FantasyHubPage extends StatefulWidget {
  const FantasyHubPage({
    super.key,
    required this.sport,
    required this.season,
    this.initialTab = FantasyHubTab.myTeam,
    this.focusPostId,
    this.initialPlayerName,
    this.configStates,
    this.playersStates,
    this.managerStates,
    this.squadStates,
    this.alertStates,
    this.gameweekStates,
    this.chipHistoryFor,
    this.voidedWeeksStates,
    this.newsStates,
    this.leaderboardsFeeds,
    this.profileOpener,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// The tab the hub opens on (push taps: News for a news post, else My
  /// Team; "Open in Fantasy": Players).
  final FantasyHubTab initialTab;

  /// A news post to scroll to + highlight once the News feed loads (a
  /// tapped news push); "This post was removed." when it's gone.
  final String? focusPostId;

  /// "Open in Fantasy": a market player whose profile the hub pushes once it
  /// is ready (after the first-open walkthrough, if one is showing) — once
  /// per hub, with the hub's shared draft. A name that has left the market
  /// says so in a SnackBar instead.
  final String? initialPlayerName;

  // ── Test seams — null = the real FantasyService feeds ──────────────────
  final Stream<FantasyConfigState?>? configStates;
  final Stream<List<FantasyPlayer>>? playersStates;
  final Stream<FantasyManager?>? managerStates;
  final Stream<FantasySquad?>? squadStates;
  final Stream<FantasySquadAlert?>? alertStates;

  /// Replaces the config-derived schedule gameweeks.
  final Stream<List<Gameweek>>? gameweekStates;

  /// The manager's chip history for the schedule's gameweek numbers.
  final Stream<Map<int, ChipHistoryEntry>> Function(List<int> weeks)?
      chipHistoryFor;

  /// The season's owner-voided gameweeks (`FantasyService.watchVoidedWeeks`).
  final Stream<Set<int>>? voidedWeeksStates;

  /// Forwarded to the News tab.
  final Stream<List<FantasyNewsPost>>? newsStates;

  /// Forwarded to the Leaderboards tab (its feeds + the squad viewer's).
  final FantasyLeaderboardsFeeds? leaderboardsFeeds;

  /// Replaces [openFantasyPlayerProfile] (records the call in tests).
  final FantasyProfileOpener? profileOpener;

  /// Clock seam for the schedule feed's "weeks up to the current gameweek"
  /// chip-history trim (null = real UTC now).
  final DateTime Function()? nowUtc;

  @override
  State<FantasyHubPage> createState() => _FantasyHubPageState();
}

class _FantasyHubPageState extends State<FantasyHubPage> {
  /// Config → schedule gameweeks → the signed-in manager's finalized chips
  /// by gameweek (`History/<gw>/<uid>`, one small listener per schedule
  /// gameweek) — the shared wiring (fantasy_schedule_feed.dart): lock-hour
  /// resubscribe, a removed Config clears the schedule, errors logged with
  /// the last good value kept. The chips are the chip row's real "1 left" /
  /// "Used" counts and join the reveal gate (no badge pops after the fade);
  /// they load once the schedule's gameweeks are known, and the same week
  /// numbers keep the running listeners (no flicker on a re-emit). Only weeks
  /// up to the current gameweek are listened to (a future week can't have
  /// History), and the service seeds a revisit from its session cache.
  late final FantasyScheduleFeed<Map<int, ChipHistoryEntry>> _schedule =
      FantasyScheduleFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyHubPage',
    onChanged: () {
      if (mounted) setState(() {});
    },
    onConfig: _onConfig,
    configStates: widget.configStates,
    gameweekStates: widget.gameweekStates,
    weekFeed: (weeks) =>
        widget.chipHistoryFor?.call(weeks) ??
        FantasyService.watchMyChipHistoryAuto(
            widget.sport, widget.season, weeks),
    weekLabel: 'chip history feed',
    nowUtc: widget.nowUtc,
  );

  FantasyConfigState? get _configState => _schedule.config;
  List<Gameweek> get _gameweeks => _schedule.gameweeks ?? const [];
  Map<int, ChipHistoryEntry> get _chipHistory =>
      _schedule.weekData ?? const {};
  bool get _chipsLoaded => _schedule.weekLoaded;

  List<FantasyPlayer>? _players;

  /// The signed-in user's Managers entry (spec §10b): null until named.
  /// [_managerLoaded] joins the single-reveal gate so the banner never pops
  /// a team name in after the hub has already faded in.
  FantasyManager? _manager;
  bool _managerLoaded = false;

  /// The signed-in user's squad (P3b): null until their first save.
  /// [_squadLoaded] joins the reveal gate so the court never pops from
  /// empty to filled after the fade.
  FantasySquad? _squad;
  bool _squadLoaded = false;

  /// The signed-in user's squad alert (spec §3 holder protection): non-null
  /// while a position change has left their formation illegal. Joins the
  /// reveal gate so the banner never pops in after the fade.
  FantasySquadAlert? _alert;
  bool _alertLoaded = false;

  /// The season's owner-voided gameweeks (`Voided/<gw>`, what the server's
  /// chip refund reads — Opus audit item 4): a chip played in one is
  /// refunded on the chip row at once. Joins the reveal gate so a refund
  /// never flips "Used" → "1 left" after the fade; a failing feed loads as
  /// "none voided" (the History mirror still refunds).
  Set<int> _voidedWeeks = const {};
  bool _voidedLoaded = false;

  /// First-open walkthrough (spec §10a): null while the prefs flag loads,
  /// false = show the intro, true = straight to the hub.
  bool? _walkthroughSeen;

  /// The ONE shared squad draft (P3c): created on the first config emit,
  /// fed by this page's squad subscription (dirty drafts never overwritten),
  /// edited by BOTH the My Team court and the Players market. It lives here
  /// so an unsaved draft survives tab swipes; saving stays on My Team.
  SquadDraftController? _draft;

  /// Re-listenable config feed for the Rules tab, fed from this page's own
  /// subscription. A raw watchConfig() stream is single-subscription, and a
  /// TabBarView unmounts/remounts its tabs on far swipes — a remounted
  /// StreamBuilder re-listening to the same instance would throw. The
  /// broadcast controller makes re-listening safe without a second RTDB
  /// listener.
  final StreamController<FantasyConfigState?> _configForRules =
      StreamController<FantasyConfigState?>.broadcast();

  /// Same re-listen-safe pattern for the My Team tab's manager stream.
  final StreamController<FantasyManager?> _managerForTabs =
      StreamController<FantasyManager?>.broadcast();

  /// And for the squad builder's squad stream (P3b).
  final StreamController<FantasySquad?> _squadForTabs =
      StreamController<FantasySquad?>.broadcast();

  /// And for the My Team alert banner (spec §3).
  final StreamController<FantasySquadAlert?> _alertForTabs =
      StreamController<FantasySquadAlert?>.broadcast();

  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<FantasyManager?>? _managerSub;
  StreamSubscription<FantasySquad?>? _squadSub;
  StreamSubscription<FantasySquadAlert?>? _alertSub;
  StreamSubscription<Set<int>>? _voidedSub;

  /// The push-tapped news post still to focus; cleared once the News tab
  /// has resolved it so a remounted tab (far tab swipes) never re-focuses.
  String? _pendingFocusPostId;

  /// "Open in Fantasy": the player whose profile still has to open. Cleared
  /// the moment the hub body is first built (so live re-emits, rebuilds and
  /// returning from the profile never reopen it).
  String? _pendingPlayerName;

  /// Guards a double tap from stacking two profiles.
  bool _openingPlayer = false;

  bool get _ready =>
      _configState != null &&
      _players != null &&
      _managerLoaded &&
      _squadLoaded &&
      _alertLoaded &&
      _chipsLoaded &&
      _voidedLoaded;

  @override
  void initState() {
    super.initState();
    _pendingFocusPostId = widget.focusPostId;
    _pendingPlayerName = widget.initialPlayerName;
    // Only a badge push opens the hub straight onto Leaderboards: show
    // Overall, where the manager's own row and its badge count are.
    if (widget.initialTab == FantasyHubTab.leaderboards) {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.overall;
    }
    FantasyPrefs.hasSeenWalkthrough().then((seen) {
      if (mounted) setState(() => _walkthroughSeen = seen);
    });
    _schedule.start();
    _playersSub = (widget.playersStates ??
            FantasyService.watchPlayers(widget.sport, widget.season))
        .listen((p) {
      if (mounted) setState(() => _players = p);
    });
    _managerSub = (widget.managerStates ??
            FantasyService.watchMyManager(widget.sport, widget.season))
        .listen((m) {
      if (!mounted) return;
      setState(() {
        _manager = m;
        _managerLoaded = true;
      });
      _managerForTabs.add(m);
    }, onError: (Object _) {
      // A permissions/auth hiccup must never hold the whole hub on the
      // skeleton — the tab just shows the name prompt until a re-emit.
      if (mounted) setState(() => _managerLoaded = true);
    });
    _squadSub = (widget.squadStates ??
            FantasyService.watchMySquadAuto(widget.sport, widget.season))
        .listen((s) {
      if (!mounted) return;
      setState(() {
        _squad = s;
        _squadLoaded = true;
      });
      // The shared draft follows the saved squad while clean; a dirty draft
      // (unsaved edits from either tab) always wins until saved.
      _draft?.adoptFromStream(s);
      _squadForTabs.add(s);
    }, onError: (Object _) {
      // Same escape hatch: a squad-read hiccup renders an empty court, not
      // an eternal skeleton.
      if (mounted) setState(() => _squadLoaded = true);
    });
    _alertSub = (widget.alertStates ??
            FantasyService.watchMySquadAlertAuto(widget.sport, widget.season))
        .listen((a) {
      if (!mounted) return;
      setState(() {
        _alert = a;
        _alertLoaded = true;
      });
      _alertForTabs.add(a);
    }, onError: (Object _) {
      // A denied/failed alert read (e.g. rules not deployed yet) just means
      // no banner — never an eternal skeleton.
      if (mounted) setState(() => _alertLoaded = true);
    });
    try {
      _voidedSub = (widget.voidedWeeksStates ??
              FantasyService.watchVoidedWeeks(widget.sport, widget.season))
          .listen((weeks) {
        if (!mounted) return;
        setState(() {
          _voidedWeeks = weeks;
          _voidedLoaded = true;
        });
      }, onError: (Object e) {
        debugPrint('FantasyHubPage: voided weeks feed failed: $e');
        // The last good set stays; none = nothing voided.
        if (mounted) setState(() => _voidedLoaded = true);
      });
    } catch (e) {
      debugPrint('FantasyHubPage: voided weeks feed failed: $e');
      _voidedLoaded = true;
    }
  }

  /// Every real Config emission: the ONE shared draft is created on the
  /// first config (seeded with the saved squad once it is known) and follows
  /// later config changes; the Rules tab's re-listenable feed gets it too.
  void _onConfig(FantasyConfigState? s) {
    if (s != null) {
      if (_draft == null) {
        _draft = SquadDraftController(
            config: s.config, initial: _squadLoaded ? _squad : null);
      } else {
        _draft!.syncConfig(s.config);
      }
    }
    _configForRules.add(s);
  }

  @override
  void dispose() {
    _schedule.dispose();
    _playersSub?.cancel();
    _managerSub?.cancel();
    _squadSub?.cancel();
    _alertSub?.cancel();
    _voidedSub?.cancel();
    _configForRules.close();
    _managerForTabs.close();
    _squadForTabs.close();
    _alertForTabs.close();
    _draft?.dispose();
    super.dispose();
  }

  void _finishWalkthrough() {
    FantasyPrefs.markWalkthroughSeen();
    setState(() => _walkthroughSeen = true);
  }

  void _onFocusHandled() {
    if (!mounted || _pendingFocusPostId == null) return;
    setState(() => _pendingFocusPostId = null);
  }

  /// The ONE way a player tap inside the hub opens his fantasy profile —
  /// News "View player" / rows, My Team court chips, the Leaderboards tab's
  /// Team of the Week and squad viewer, and "Open in Fantasy". The profile
  /// edits this hub's shared draft (Add / Remove; saving stays on My Team).
  /// A player who has left the market since the post / squad was written gets
  /// a SnackBar instead of an empty page.
  Future<void> _openPlayerProfile(String name) async {
    if (_openingPlayer || !mounted) return;
    final draft = _draft;
    final inMarket = (_players ?? const <FantasyPlayer>[]).any(
      (p) => p.name == name,
    );
    if (!inMarket || draft == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("That player isn't in the market anymore.")));
      return;
    }
    _openingPlayer = true;
    try {
      await (widget.profileOpener ?? openFantasyPlayerProfile)(
        context,
        sport: widget.sport,
        season: widget.season,
        playerName: name,
        draft: draft,
      );
    } finally {
      _openingPlayer = false;
    }
  }

  /// "Open in Fantasy": once the hub body is first shown, pushes the named
  /// player's profile on top (back lands on the hub). One-shot — see
  /// [_pendingPlayerName].
  void _openPendingPlayer() {
    final name = _pendingPlayerName;
    if (name == null) return;
    _pendingPlayerName = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPlayerProfile(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The walkthrough needs no network: it shows immediately on first open
    // (config numbers fall back to the launch defaults until the stream
    // lands) and never again after Skip/finish.
    final Widget body;
    if (_walkthroughSeen == false) {
      body = FantasyWalkthrough(
        key: const ValueKey('walkthrough'),
        config: _configState?.config ?? FantasyConfig.futsalDefault(),
        onDone: _finishWalkthrough,
      );
    } else if (_ready && _walkthroughSeen != null) {
      _openPendingPlayer();
      body = _HubBody(
        key: const ValueKey('hub'),
        sport: widget.sport,
        season: widget.season,
        configState: _configState!,
        configStates: _configForRules.stream,
        gameweeks: _gameweeks,
        players: _players!,
        manager: _manager,
        managerStates: _managerForTabs.stream,
        squad: _squad,
        squadStates: _squadForTabs.stream,
        alert: _alert,
        alertStates: _alertForTabs.stream,
        chipHistory: _chipHistory,
        voidedWeeks: _voidedWeeks,
        draft: _draft!,
        saveTeamName: (name) =>
            FantasyService.saveTeamName(widget.sport, widget.season, name),
        saveSquad: (squad) =>
            FantasyService.saveMySquadAuto(widget.sport, widget.season, squad),
        initialTab: widget.initialTab,
        focusPostId: _pendingFocusPostId,
        onFocusHandled: _onFocusHandled,
        onOpenPlayer: _openPlayerProfile,
        newsStates: widget.newsStates,
        leaderboardsFeeds: widget.leaderboardsFeeds,
      );
    } else {
      body = const _HubSkeleton(key: ValueKey('skeleton'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Infinite Fantasy')),
      // Single fade reveal: skeleton until config+players+manager have ALL
      // arrived, then the whole hub fades in at once.
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: body,
      ),
    );
  }
}

class _HubSkeleton extends StatelessWidget {
  const _HubSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: double.infinity, height: 120, radius: 20),
            SizedBox(height: 16),
            SkeletonLines(count: 2),
            SizedBox(height: 16),
            SkeletonList(count: 6),
          ],
        ),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody({
    super.key,
    required this.sport,
    required this.season,
    required this.configState,
    required this.configStates,
    required this.gameweeks,
    required this.players,
    required this.manager,
    required this.managerStates,
    required this.squad,
    required this.squadStates,
    required this.alert,
    required this.alertStates,
    required this.chipHistory,
    required this.voidedWeeks,
    required this.draft,
    required this.saveTeamName,
    required this.saveSquad,
    required this.initialTab,
    required this.focusPostId,
    required this.onFocusHandled,
    required this.onOpenPlayer,
    this.newsStates,
    this.leaderboardsFeeds,
  });

  final String sport;
  final String season;
  final FantasyConfigState configState;
  final Stream<FantasyConfigState?> configStates;
  final List<Gameweek> gameweeks;
  final List<FantasyPlayer> players;
  final FantasyManager? manager;
  final Stream<FantasyManager?> managerStates;
  final FantasySquad? squad;
  final Stream<FantasySquad?> squadStates;

  /// The live squad alert (spec §3) + its re-listen-safe feed.
  final FantasySquadAlert? alert;
  final Stream<FantasySquadAlert?> alertStates;

  /// The manager's finalized chips by gameweek — the chip row's counts.
  final Map<int, ChipHistoryEntry> chipHistory;

  /// The season's owner-voided gameweeks — their chips are refunded.
  final Set<int> voidedWeeks;

  /// The hub-owned shared draft both the court and the market edit (P3c).
  final SquadDraftController draft;
  final Future<void> Function(String name) saveTeamName;
  final Future<void> Function(FantasySquad squad) saveSquad;

  /// The tab DefaultTabController starts on (read once, at first build).
  final FantasyHubTab initialTab;

  /// Push-tapped news post for the News tab to focus (null once handled).
  final String? focusPostId;
  final VoidCallback onFocusHandled;

  /// Every player tap in the tabs → the hub's one profile opener.
  final void Function(String name) onOpenPlayer;

  /// Test seam forwarded to the News tab (null = the real feed).
  final Stream<List<FantasyNewsPost>>? newsStates;

  /// Test seams forwarded to the Leaderboards tab (null = the real feeds).
  final FantasyLeaderboardsFeeds? leaderboardsFeeds;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab.index,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FantasyBanner(
              subtitle: '$sport · Season $season',
              teamName: manager?.teamName,
              onEditTeamName: manager == null
                  ? null
                  : () => showTeamNameDialog(
                        context,
                        initialName: manager!.teamName,
                        onSave: saveTeamName,
                      ),
              // FPL-style live countdown (P3b Task 4): ticking D/H/M/S boxes
              // while the gameweek is open under the auto lock; the override
              // and locked states keep their chips.
              bottom: FantasyDeadlineCountdown(
                gameweeks: gameweeks,
                lockOverride: configState.lockOverride,
              ),
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'My Team'),
              Tab(text: 'Players'),
              Tab(text: 'Leaderboards'),
              Tab(text: 'News'),
              Tab(text: 'Rules'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Name prompt / moderation gate / court squad builder — all
                // stream-driven (spec §10b, P3b).
                FantasyMyTeamTab(
                  managerStates: managerStates,
                  initialManager: manager,
                  onSaveName: saveTeamName,
                  configState: configState,
                  players: players,
                  gameweeks: gameweeks,
                  squadStates: squadStates,
                  initialSquad: squad,
                  onSaveSquad: saveSquad,
                  draft: draft,
                  alertStates: alertStates,
                  initialAlert: alert,
                  chipHistory: chipHistory,
                  voidedWeeks: voidedWeeks,
                  onOpenPlayer: onOpenPlayer,
                ),
                // The market (P3c) — edits the SAME shared draft as above;
                // saving stays on My Team.
                FantasyPlayersTab(
                  sport: sport,
                  season: season,
                  players: players,
                  draft: draft,
                  lockOverride: configState.lockOverride,
                  gameweeks: gameweeks,
                ),
                // Overall/gameweek standings, mini-leagues and the manager
                // squad viewer (P3d, spec §9/§10).
                FantasyLeaderboardsTab(
                  sport: sport,
                  season: season,
                  configState: configState,
                  players: players,
                  gameweeks: gameweeks,
                  squadStates: squadStates,
                  initialSquad: squad,
                  leaderboardsStates: leaderboardsFeeds?.leaderboardsStates,
                  managersStates: leaderboardsFeeds?.managersStates,
                  miniLeaguesStates: leaderboardsFeeds?.miniLeaguesStates,
                  dreamTeamsStates: leaderboardsFeeds?.dreamTeamsStates,
                  loadProfiles: leaderboardsFeeds?.loadProfiles,
                  selfUidOverride: leaderboardsFeeds?.selfUidOverride,
                  viewerPublishedStates:
                      leaderboardsFeeds?.viewerPublishedStates,
                  viewerHistoryStates: leaderboardsFeeds?.viewerHistoryStates,
                  shareImage: leaderboardsFeeds?.shareImage,
                  badgesStates: leaderboardsFeeds?.badgesStates,
                  onOpenPlayer: onOpenPlayer,
                ),
                // Published league news (P3d) with tagged-player cards and
                // push-tap focus (News desk 2.0).
                FantasyNewsTab(
                  sport: sport,
                  season: season,
                  newsStates: newsStates,
                  focusPostId: focusPostId,
                  onFocusHandled: onFocusHandled,
                  onOpenPlayer: onOpenPlayer,
                ),
                // Rendered ENTIRELY from the live config (spec §10a): a
                // tuned value re-renders this page by itself.
                FantasyRulesTab(
                  configStates: configStates,
                  initialState: configState,
                  gameweeks: gameweeks,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

