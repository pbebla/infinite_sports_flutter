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
// opens on News (a news push) or My Team (everything else), and
// [FantasyHubPage.focusPostId] scrolls the News feed to the tapped post. A
// tagged player's "View player" in News opens the SAME market sheet the
// Players tab opens, editing the same shared draft.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_player_sheet.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/team_name_dialog.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

export 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart'
    show FantasyHubTab;

class FantasyHubPage extends StatefulWidget {
  const FantasyHubPage({
    super.key,
    required this.sport,
    required this.season,
    this.initialTab = FantasyHubTab.myTeam,
    this.focusPostId,
  });

  final String sport;
  final String season;

  /// The tab the hub opens on (push taps: News for a news post, else My
  /// Team).
  final FantasyHubTab initialTab;

  /// A news post to scroll to + highlight once the News feed loads (a
  /// tapped news push); "This post was removed." when it's gone.
  final String? focusPostId;

  @override
  State<FantasyHubPage> createState() => _FantasyHubPageState();
}

class _FantasyHubPageState extends State<FantasyHubPage> {
  FantasyConfigState? _configState;
  List<FantasyPlayer>? _players;
  List<Gameweek> _gameweeks = const [];
  int? _gameweeksLockHour; // lockHour the gameweek stream was derived with

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

  /// The signed-in manager's finalized chips by gameweek
  /// (`History/<gw>/<uid>`, one small listener per schedule gameweek) — the
  /// chip row's real "1 left" / "Used" counts. Joins the reveal gate (no
  /// badge pops after the fade); it can only load once the schedule's
  /// gameweeks are known.
  Map<int, ChipHistoryEntry> _chipHistory = const {};
  bool _chipsLoaded = false;
  List<int>? _chipWeeks; // gameweek numbers the chip feed listens to

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

  StreamSubscription<FantasyConfigState?>? _configSub;
  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<List<Gameweek>>? _gameweeksSub;
  StreamSubscription<FantasyManager?>? _managerSub;
  StreamSubscription<FantasySquad?>? _squadSub;
  StreamSubscription<FantasySquadAlert?>? _alertSub;
  StreamSubscription<Map<int, ChipHistoryEntry>>? _chipSub;

  /// The push-tapped news post still to focus; cleared once the News tab
  /// has resolved it so a remounted tab (far tab swipes) never re-focuses.
  String? _pendingFocusPostId;

  // ── Market-sheet feeds for News "View player" ──────────────────────────
  // The same two feeds the Players tab hands its detail sheet (finalized
  // totals + the league's season stats), started LAZILY on the first View
  // player tap and kept live for the hub's life — a hub that never opens a
  // player from News never loads them. Not part of the reveal gate.
  Map<String, FantasyPlayerTotals>? _sheetTotals;
  Map<String, TournamentPlayer> _sheetStats = const {};
  final StreamController<Map<String, TournamentPlayer>> _sheetStatsFeed =
      StreamController<Map<String, TournamentPlayer>>.broadcast();
  StreamSubscription<Map<String, FantasyPlayerTotals>?>? _sheetTotalsSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _sheetRostersSub;
  final Completer<void> _sheetTotalsFirst = Completer<void>();
  bool _openingPlayer = false;

  bool get _ready =>
      _configState != null &&
      _players != null &&
      _managerLoaded &&
      _squadLoaded &&
      _alertLoaded &&
      _chipsLoaded;

  @override
  void initState() {
    super.initState();
    _pendingFocusPostId = widget.focusPostId;
    FantasyPrefs.hasSeenWalkthrough().then((seen) {
      if (mounted) setState(() => _walkthroughSeen = seen);
    });
    _configSub =
        FantasyService.watchConfig(widget.sport, widget.season).listen((s) {
      if (!mounted) return;
      setState(() {
        _configState = s;
        if (s != null) {
          if (_draft == null) {
            _draft = SquadDraftController(
                config: s.config, initial: _squadLoaded ? _squad : null);
          } else {
            _draft!.syncConfig(s.config);
          }
        }
      });
      _configForRules.add(s);
      if (s != null) _subscribeGameweeks(s);
    });
    _playersSub =
        FantasyService.watchPlayers(widget.sport, widget.season).listen((p) {
      if (mounted) setState(() => _players = p);
    });
    _managerSub = FantasyService.watchMyManager(widget.sport, widget.season)
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
    _squadSub = FantasyService.watchMySquadAuto(widget.sport, widget.season)
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
    _alertSub =
        FantasyService.watchMySquadAlertAuto(widget.sport, widget.season)
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
  }

  /// Gameweeks derive from the real schedule WITH the config's lock hour —
  /// resubscribe only when that hour actually changes (config tweaks that
  /// don't move deadlines shouldn't restart the stream).
  void _subscribeGameweeks(FantasyConfigState s) {
    if (_gameweeksLockHour == s.config.lockHour) return;
    _gameweeksLockHour = s.config.lockHour;
    _gameweeksSub?.cancel();
    _gameweeksSub = FantasyService.watchGameweeks(
            widget.sport, widget.season, s.config)
        .listen((gws) {
      if (!mounted) return;
      setState(() => _gameweeks = gws);
      _subscribeChips(gws);
    }, onError: (Object _) {
      // No schedule → no chip feed: never hold the hub on the skeleton.
      if (mounted) setState(() => _chipsLoaded = true);
    });
  }

  /// (Re)subscribes the chip-usage feed when the schedule's gameweek list
  /// changes — the same numbers keep the running listeners (and the badges)
  /// untouched, so a config/schedule re-emit never flickers them.
  void _subscribeChips(List<Gameweek> gws) {
    final weeks = [for (final g in gws) g.number];
    final known = _chipWeeks;
    if (known != null &&
        known.length == weeks.length &&
        Iterable<int>.generate(weeks.length)
            .every((i) => known[i] == weeks[i])) {
      return;
    }
    _chipWeeks = weeks;
    _chipSub?.cancel();
    _chipSub = FantasyService.watchMyChipHistoryAuto(
            widget.sport, widget.season, weeks)
        .listen((history) {
      if (!mounted) return;
      setState(() {
        _chipHistory = history;
        _chipsLoaded = true;
      });
    }, onError: (Object _) {
      // A failed History read just means no usage shown ("1 left").
      if (mounted) setState(() => _chipsLoaded = true);
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _playersSub?.cancel();
    _gameweeksSub?.cancel();
    _managerSub?.cancel();
    _squadSub?.cancel();
    _alertSub?.cancel();
    _chipSub?.cancel();
    _sheetTotalsSub?.cancel();
    _sheetRostersSub?.cancel();
    _configForRules.close();
    _managerForTabs.close();
    _squadForTabs.close();
    _alertForTabs.close();
    _sheetStatsFeed.close();
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

  /// Starts the market-sheet feeds once (see the field comment).
  void _startSheetFeeds() {
    if (_sheetTotalsSub != null) return;
    void firstTotals() {
      if (!_sheetTotalsFirst.isCompleted) _sheetTotalsFirst.complete();
    }

    _sheetTotalsSub =
        FantasyService.watchPlayerTotals(widget.sport, widget.season).listen(
      (totals) {
        _sheetTotals = totals;
        firstTotals();
      },
      // A failed totals read just hides the sheet's totals line.
      onError: (Object _) => firstTotals(),
    );
    _sheetRostersSub =
        LeagueService.watchRosters(widget.sport, widget.season).listen(
      (rosters) {
        final byName = <String, TournamentPlayer>{
          for (final players in rosters.values)
            for (final p in players) p.name: p,
        };
        _sheetStats = byName;
        if (!_sheetStatsFeed.isClosed) _sheetStatsFeed.add(byName);
      },
      // No league stats → the sheet's tiles stay dashes.
      onError: (Object _) {},
    );
  }

  /// News "View player": the Players tab's market sheet for [name], or a
  /// SnackBar when the player has left the market since the post was
  /// written.
  Future<void> _openPlayerFromNews(String name) async {
    if (_openingPlayer) return;
    FantasyPlayer? player;
    for (final p in _players ?? const <FantasyPlayer>[]) {
      if (p.name == name) {
        player = p;
        break;
      }
    }
    final draft = _draft;
    final configState = _configState;
    if (player == null || draft == null || configState == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("That player isn't in the market anymore.")));
      return;
    }
    _openingPlayer = true;
    try {
      _startSheetFeeds();
      // Totals are one small, session-cached node: wait briefly so the
      // sheet opens WITH its points line (the sheet takes them as a value);
      // league stats stream into the open sheet on their own.
      await _sheetTotalsFirst.future
          .timeout(const Duration(milliseconds: 1500), onTimeout: () {});
      if (!mounted) return;
      await showMarketPlayerSheet(
        context,
        player: player,
        draft: draft,
        editable: squadEditable(
          lockOverride: configState.lockOverride,
          gameweeks: _gameweeks,
          nowUtc: DateTime.now().toUtc(),
        ),
        totals: _sheetTotals?[player.name],
        totalsAvailable: _sheetTotals != null,
        initialStats: _sheetStats,
        statsStates: _sheetStatsFeed.stream,
      );
    } finally {
      _openingPlayer = false;
    }
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
        draft: _draft!,
        saveTeamName: (name) =>
            FantasyService.saveTeamName(widget.sport, widget.season, name),
        saveSquad: (squad) =>
            FantasyService.saveMySquadAuto(widget.sport, widget.season, squad),
        initialTab: widget.initialTab,
        focusPostId: _pendingFocusPostId,
        onFocusHandled: _onFocusHandled,
        onOpenPlayer: _openPlayerFromNews,
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
    required this.draft,
    required this.saveTeamName,
    required this.saveSquad,
    required this.initialTab,
    required this.focusPostId,
    required this.onFocusHandled,
    required this.onOpenPlayer,
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

  /// The hub-owned shared draft both the court and the market edit (P3c).
  final SquadDraftController draft;
  final Future<void> Function(String name) saveTeamName;
  final Future<void> Function(FantasySquad squad) saveSquad;

  /// The tab DefaultTabController starts on (read once, at first build).
  final FantasyHubTab initialTab;

  /// Push-tapped news post for the News tab to focus (null once handled).
  final String? focusPostId;
  final VoidCallback onFocusHandled;

  /// News "View player" → the market sheet.
  final void Function(String name) onOpenPlayer;

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
                ),
                // Published league news (P3d) with tagged-player cards and
                // push-tap focus (News desk 2.0).
                FantasyNewsTab(
                  sport: sport,
                  season: season,
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

