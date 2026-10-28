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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/team_name_dialog.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

class FantasyHubPage extends StatefulWidget {
  const FantasyHubPage({
    super.key,
    required this.sport,
    required this.season,
  });

  final String sport;
  final String season;

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

  StreamSubscription<FantasyConfigState?>? _configSub;
  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<List<Gameweek>>? _gameweeksSub;
  StreamSubscription<FantasyManager?>? _managerSub;
  StreamSubscription<FantasySquad?>? _squadSub;

  bool get _ready =>
      _configState != null &&
      _players != null &&
      _managerLoaded &&
      _squadLoaded;

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _gameweeks = gws);
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _playersSub?.cancel();
    _gameweeksSub?.cancel();
    _managerSub?.cancel();
    _squadSub?.cancel();
    _configForRules.close();
    _managerForTabs.close();
    _squadForTabs.close();
    _draft?.dispose();
    super.dispose();
  }

  void _finishWalkthrough() {
    FantasyPrefs.markWalkthroughSeen();
    setState(() => _walkthroughSeen = true);
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
        draft: _draft!,
        saveTeamName: (name) =>
            FantasyService.saveTeamName(widget.sport, widget.season, name),
        saveSquad: (squad) =>
            FantasyService.saveMySquadAuto(widget.sport, widget.season, squad),
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
    required this.draft,
    required this.saveTeamName,
    required this.saveSquad,
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

  /// The hub-owned shared draft both the court and the market edit (P3c).
  final SquadDraftController draft;
  final Future<void> Function(String name) saveTeamName;
  final Future<void> Function(FantasySquad squad) saveSquad;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
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
                // Published league news (P3d; the composer/AI pipeline is
                // P4/P5).
                FantasyNewsTab(sport: sport, season: season),
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

