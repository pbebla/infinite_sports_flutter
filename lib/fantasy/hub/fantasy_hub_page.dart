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
// Paid access (spec 2026-11-01 §5): the own `Access/<uid>` stream joins the
// reveal gate (session-seeded, so a revisit is instant) and, in pass mode
// without an active pass, the My Team tab shows the season-pass pay card
// instead of the name step (or above a read-only court). Card payments open
// Stripe Checkout in the phone's browser; the stream flips the card the
// moment the server activates the pass — nothing polls.
//
// FPL selling (spec §4): the own `Baselines/<uid>` stream feeds the shared
// draft's money (SquadDraftController.setSaleContext) together with the live
// market prices and the gameweek being edited. It does NOT join the reveal
// gate — until it answers the draft simply isn't moneyReady.
//
// Transfers (plan 2026-11-03, spec §5): the own `TransferState/<uid>` stream
// feeds the same draft (SquadDraftController.setTransferContext) with the
// SAME edited gameweek the money uses, so the squad builder's transfers line
// and "Take a points hit?" count against the server's own baseline. Error ≠
// fact: until it answers, after it fails, or with nobody signed in (the
// signed-out feed's lone null means "no user", not "no node"), the draft's
// preview is "not ready" — never a free first team. It DOES join the reveal gate
// (no pop-in of the transfers line or the chips' first-team caption after the
// fade): its first answer or first error ends the wait, and signed out there
// is nothing to wait for.
//
// The locked week (live everywhere, Task 5): while My Team is locked
// ([lockedWeekNumber]) the hub listens to the locked week's five small
// streams (FantasyLockedWeekFeed: the live gameweek, the own Live/Squads/<uid>,
// the own PublishedPicks/<gw>/<uid> (the squad that was LOCKED: the court),
// the own History/<gw>/<uid>, the own Overall rank), resolves them with the
// Voided set into ONE LockedWeekModel (live_logic.dart) and hands it to the
// squad builder — the strip's live / Final / Voided line and every court
// chip's points. They join the FIRST reveal's gate (bounded at 2 s) so the
// first painted frame already carries live numbers; once revealed, a lock
// arriving mid-session never brings the skeleton back. Nothing is subscribed
// while editing is open or nobody is signed in.
//
// Player profiles (round 3, spec §4): EVERY player tap inside the hub — News
// "View player" and compact rows, the My Team court (chip sheet's "Player
// profile"; a locked court's chip tap), the Leaderboards tab's Team of the
// Week and manager squad viewer, and (via [FantasyHubPage.initialPlayerName])
// "Open in Fantasy" — goes through ONE opener, [_openPlayerProfile], which
// pushes the full-screen profile editing this hub's shared draft. The
// Players tab opens the same page itself, with the same draft.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart'
    show FantasyLiveState, LiveSquad;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/access_pay_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/collapsing_tab_shell.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/locked_week_feed.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/team_name_dialog.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.accessStates,
    this.saleBaselineStates,
    this.transferStateStates,
    this.signedInUid,
    this.priceHistoryStates,
    this.createCheckoutUrl,
    this.launchExternal,
    this.submitAccessClaim,
    this.displayName,
    this.liveStates,
    this.liveSquadStates,
    this.historyWeekFor,
    this.publishedPicksFor,
    this.overallStandingStates,
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

  // ── Paid-access seams (spec 2026-11-01) — null = the real wiring ───────

  /// Replaces `FantasyService.watchMyAccess`.
  final Stream<FantasyAccessState>? accessStates;

  /// Replaces `FantasyService.watchMySaleBaseline` (FPL selling).
  final Stream<SaleBaselineState>? saleBaselineStates;

  /// Replaces `FantasyService.watchMyTransferStateAuto` (the transfers line
  /// and points-hit confirm): null = the node is ABSENT (a first team).
  final Stream<TransferStateView?>? transferStateStates;

  /// Replaces the signed-in user's uid (null = signed out) — the gate the
  /// transfer feed is only subscribed behind.
  final String? Function()? signedInUid;

  /// Replaces `FantasyService.watchPriceHistory` (FPL selling: the market
  /// floor a new pick is charged at uses last week's prices).
  final Stream<Map<int, Map<String, int>>>? priceHistoryStates;

  /// Replaces `FantasyService.createCheckoutUrl` (the Checkout callable).
  final Future<Uri?> Function()? createCheckoutUrl;

  /// Replaces `launchUrl(uri, mode: LaunchMode.externalApplication)`.
  final Future<bool> Function(Uri uri)? launchExternal;

  /// Replaces `FantasyService.submitAccessClaim` ("I sent it").
  final Future<void> Function(
          FantasyAccessMethod method, double amountDollars, String note)?
      submitAccessClaim;

  /// Replaces the signed-in user's display name (the claim note's tail).
  final String Function()? displayName;

  // ── The locked week's feeds (live everywhere, Task 5) — null = the real ──

  /// Replaces `FantasyLiveFeed.watch` (the season's live gameweek).
  final Stream<FantasyLiveState>? liveStates;

  /// Replaces `FantasyService.watchLiveSquad` for the signed-in user.
  final Stream<LiveSquad?>? liveSquadStates;

  /// Replaces `FantasyService.watchHistoryWeek` (the settled week's squad).
  final Stream<HistoryWeek?> Function(int week)? historyWeekFor;

  /// Replaces `FantasyService.watchPublishedPicksWeek` (the squad that was
  /// locked — the live court).
  final Stream<FantasySquad?> Function(int week)? publishedPicksFor;

  /// Replaces `FantasyService.watchOverallStanding` (the official rank).
  final Stream<OverallStanding?>? overallStandingStates;

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
      if (!mounted) return;
      // The schedule / the lock override move the locked week (settled before
      // the repaint below, so the repaint already knows it).
      _syncLockedWeek(notify: false);
      setState(() {});
      _feedSaleContext(); // the schedule moves the week being edited
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

  /// The locked week's five small streams (live everywhere, Task 5): the live
  /// gameweek, the own live squad, the locked squad (PublishedPicks), the own
  /// settled History week and the own
  /// official Overall rank — subscribed ONLY while a week is locked
  /// ([lockedWeekNumber]), joined to the reveal gate (bounded at 2 s) so the
  /// first painted frame already carries live numbers. Never `Squads/<uid>`
  /// for points.
  late final FantasyLockedWeekFeed _locked = FantasyLockedWeekFeed(
    sport: widget.sport,
    season: widget.season,
    uid: _signedInUid,
    onChanged: () {
      if (mounted) setState(() {});
    },
    liveStates: widget.liveStates,
    liveSquadStates: widget.liveSquadStates,
    historyWeekFor: widget.historyWeekFor,
    publishedPicksFor: widget.publishedPicksFor,
    overallStates: widget.overallStandingStates,
  );

  /// Re-syncs the locked week when the clock crosses the next lock (or the
  /// end of the lock day, when editing reopens) even if no feed emits.
  Timer? _lockBoundary;

  /// The hub has been shown once: from then on a locked week starting
  /// mid-session (the lock arriving, the owner locking) never puts the
  /// skeleton back — its numbers land in place.
  bool _revealed = false;

  FantasyConfigState? get _configState => _schedule.config;
  List<Gameweek> get _gameweeks => _schedule.gameweeks ?? const [];
  Map<int, ChipHistoryEntry> get _chipHistory => _schedule.weekData ?? const {};
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

  /// The signed-in user's paid-access state (spec 2026-11-01 §4): none /
  /// pending / active / revoked, or degraded when the read failed before
  /// any value was known. Joins the reveal gate so the pay card never pops
  /// in (or away) after the fade; the service seeds a revisit.
  FantasyAccessState _access = FantasyAccessState.none;
  bool _accessLoaded = false;

  /// The signed-in user's sale baseline (FPL selling, `Baselines/<uid>`):
  /// null until the feed answers. NOT part of the reveal gate — the shared
  /// draft just isn't moneyReady until it lands.
  SaleBaselineState? _sale;

  /// The signed-in user's transfer state (`TransferState/<uid>`): null = the
  /// node is ABSENT, only meaningful once [_transferAnswered]. False before
  /// the first emission, after the feed failed and with nobody signed in —
  /// the draft's preview is then "not ready".
  TransferStateView? _transfer;
  bool _transferAnswered = false;

  /// Joins the reveal gate: true on the feed's first data OR first error (a
  /// failed feed never holds the screen), and at once when signed out.
  bool _transferLoaded = false;

  /// The season's price history (`PriceHistory/<gw>/<name>`, the prices
  /// DURING each locked week): the draft's market floor for a new pick
  /// reads `PriceHistory/<editingGw − 1>`, as the server's judge does.
  /// null until it answers (the floor is then today's price — never lower
  /// than the server's, so the room shown is never more than it allows).
  /// NOT part of the reveal gate.
  Map<int, Map<String, int>>? _priceHistory;

  /// Re-feeds the draft's sale context when the clock crosses the next
  /// lock: the week being edited moves on then even if no feed emits.
  Timer? _saleBoundary;

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

  /// And for the My Team pay card (paid access).
  final StreamController<FantasyAccessState> _accessForTabs =
      StreamController<FantasyAccessState>.broadcast();

  /// The header's ONE deadline tick (release report #8): the big countdown
  /// and the collapsed bar's slim line both read it — never a second timer.
  /// The tabs' primary scroll controller, also put above the Scaffold (the
  /// iOS status-bar tap's source): a scroll-to-top moves only the tab on
  /// screen, never every kept-alive tab (review 6, M-c).
  final ActiveTabScrollController _primaryScroll = ActiveTabScrollController();

  late final FantasyDeadlineClock _deadlineClock =
      FantasyDeadlineClock(nowUtc: widget.nowUtc);

  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<FantasyManager?>? _managerSub;
  StreamSubscription<FantasySquad?>? _squadSub;
  StreamSubscription<FantasySquadAlert?>? _alertSub;
  StreamSubscription<Set<int>>? _voidedSub;
  StreamSubscription<FantasyAccessState>? _accessSub;
  StreamSubscription<SaleBaselineState>? _saleSub;
  StreamSubscription<TransferStateView?>? _transferSub;

  /// Re-subscribes the transfer feed after a failure (the service's stream
  /// ends at its error, and the copy says "updating…" — so something must
  /// retry). One pending timer, replaced on each failure, cancelled by data
  /// and in dispose.
  Timer? _transferRetry;
  static const _transferRetryAfter = Duration(seconds: 30);
  StreamSubscription<Map<int, Map<String, int>>>? _priceHistorySub;

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
      _transferLoaded &&
      _chipsLoaded &&
      _voidedLoaded &&
      _accessLoaded &&
      // The locked week's streams (live arriving late is waited for, bounded
      // at 2 s) — only ever part of the FIRST reveal.
      (_revealed || _locked.ready);

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
      if (!mounted) return;
      setState(() => _players = p);
      _feedSaleContext(); // today's prices price the sales
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
    _subscribeSaleBaseline();
    _subscribeTransferState();
    _subscribePriceHistory();
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
    _subscribeAccess();
  }

  /// Listens to the own Access record (also the degraded face's "Try
  /// again": a re-subscribe). Error ≠ fact: a failed read keeps the last
  /// known record; with none known the card shows a retry line, never the
  /// pay methods as if unpaid — and the hub still reveals.
  void _subscribeAccess() {
    _accessSub?.cancel();
    void degrade(Object e) {
      debugPrint('FantasyHubPage: access feed failed: $e');
      if (!mounted) return;
      setState(() {
        if (_access.record == null) {
          _access = const FantasyAccessState(degraded: true);
        }
        _accessLoaded = true;
      });
      _accessForTabs.add(_access);
    }

    try {
      _accessSub = (widget.accessStates ??
              FantasyService.watchMyAccess(widget.sport, widget.season))
          .listen((a) {
        if (!mounted) return;
        setState(() {
          _access = a;
          _accessLoaded = true;
        });
        _accessForTabs.add(a);
      }, onError: degrade);
    } catch (e) {
      degrade(e);
    }
  }

  /// Listens to the own sale baseline (FPL selling). Error ≠ fact: a failed
  /// read keeps the last known state; with none known the draft gets a
  /// degraded state (never moneyReady). Never part of the reveal gate.
  void _subscribeSaleBaseline() {
    _saleSub?.cancel();
    void degrade(Object e) {
      debugPrint('FantasyHubPage: sale baseline feed failed: $e');
      if (!mounted) return;
      if (_sale?.loaded ?? false) return; // the last known state stays
      _sale = const SaleBaselineState(degraded: true);
      _feedSaleContext();
    }

    try {
      _saleSub = (widget.saleBaselineStates ??
              FantasyService.watchMySaleBaseline(widget.sport, widget.season))
          .listen((s) {
        if (!mounted) return;
        _sale = s;
        _feedSaleContext();
      }, onError: degrade);
    } catch (e) {
      degrade(e);
    }
  }

  /// The signed-in user's uid; null when signed out (or, in widget tests,
  /// with no Firebase app) — never throws.
  String? _signedInUid() {
    final seam = widget.signedInUid;
    if (seam != null) return seam();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Listens to the own transfer state (plan 2026-11-03). Error ≠ fact, the
  /// same one-shot subscription as the sale baseline (the service's stream
  /// ends after an error; there is no retry): data = answered; an error =
  /// NOT answered ("Transfer count updating…", never a first team). Nobody
  /// signed in = never subscribed: the real feed's lone null for a signed-out
  /// session is "no user", not "the node is absent". Joins the reveal gate
  /// ([_transferLoaded]): the first answer or error ends the wait, and with
  /// nobody signed in there is nothing to wait for. A failure re-subscribes
  /// after [_transferRetryAfter] (while mounted), and again after each
  /// further failure, until data arrives.
  void _subscribeTransferState() {
    _transferSub?.cancel();
    void failed(Object e) {
      debugPrint('FantasyHubPage: transfer state feed failed: $e');
      if (!mounted) return;
      setState(() {
        _transferAnswered = false;
        _transferLoaded = true;
      });
      _feedSaleContext();
      _transferRetry?.cancel();
      _transferRetry = Timer(_transferRetryAfter, () {
        _transferRetry = null;
        if (mounted) _subscribeTransferState();
      });
    }

    try {
      if (_signedInUid() == null) {
        _transferLoaded = true;
        return;
      }
      _transferSub = (widget.transferStateStates ??
              FantasyService.watchMyTransferStateAuto(
                  widget.sport, widget.season))
          .listen((view) {
        if (!mounted) return;
        _transferRetry?.cancel();
        _transferRetry = null;
        setState(() {
          _transfer = view;
          _transferAnswered = true;
          _transferLoaded = true;
        });
        _feedSaleContext();
      }, onError: failed);
    } catch (e) {
      failed(e);
    }
  }

  /// Listens to the season's price history (FPL selling: last week's
  /// prices set a new pick's market floor). Error ≠ fact: a failed read
  /// keeps the last known history; with none the floor stays today's price
  /// (the server's own fallback with no history). Never part of the reveal
  /// gate.
  void _subscribePriceHistory() {
    _priceHistorySub?.cancel();
    void failed(Object e) =>
        debugPrint('FantasyHubPage: price history feed failed: $e');
    try {
      _priceHistorySub = (widget.priceHistoryStates ??
              FantasyService.watchPriceHistory(widget.sport, widget.season))
          .listen((h) {
        if (!mounted) return;
        _priceHistory = h;
        _feedSaleContext();
      }, onError: failed);
    } catch (e) {
      failed(e);
    }
  }

  DateTime _nowUtc() => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  /// Points the locked-week feed at the week My Team is locked on right now
  /// ([lockedWeekNumber]; null while editing is open — and before the Config
  /// has answered, since its lock override decides) and schedules the next
  /// moment the clock moves it. Called on every schedule / config change and
  /// when that moment arrives. [notify] false inside a callback that
  /// repaints anyway.
  void _syncLockedWeek({bool notify = true}) {
    _lockBoundary?.cancel();
    _lockBoundary = null;
    final cfg = _configState;
    final gws = _schedule.gameweeks;
    final now = _nowUtc();
    _locked.setWeek(
      cfg == null
          ? null
          : lockedWeekNumber(
              lockOverride: cfg.lockOverride, gameweeks: gws, nowUtc: now),
      notify: notify,
    );
    final next = gws == null ? null : nextLockTransition(gws, now);
    if (next == null) return;
    var wait = next.difference(now);
    if (wait > const Duration(days: 1)) wait = const Duration(days: 1);
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _lockBoundary = Timer(wait, () {
      _lockBoundary = null;
      if (mounted) _syncLockedWeek();
    });
  }

  /// The locked week as My Team shows it (null while editing is open).
  LockedWeekModel? _lockedModel() {
    final week = _locked.week;
    if (week == null) return null;
    return resolveLockedWeek(
      week: week,
      uid: _signedInUid(),
      voidedWeeks: _voidedWeeks,
      sources: _locked.sources,
    );
  }

  /// Hands the shared draft its money context: the sale baseline, today's
  /// market prices (null until the market loads — the draft is never
  /// moneyReady before), last week's prices and the week being edited
  /// (saleEditingGameweek) — and, with that SAME week, its transfer context
  /// (the transfer state and whether it has answered). Called on every
  /// baseline / transfer state / players / price history / schedule / config
  /// change, and again at the next lock (the clock moves the edited week on
  /// by itself).
  void _feedSaleContext() {
    _saleBoundary?.cancel();
    _saleBoundary = null;
    final draft = _draft;
    if (draft == null || !mounted) return;
    final now = _nowUtc();
    final gws = _schedule.gameweeks;
    final players = _players;
    final editingGw = saleEditingGameweek(
      // A schedule that failed to load is unknown, never "GW1" (review 6,
      // I2): the draft's money then stays not-ready.
      gameweeks: _schedule.scheduleUnknown ? null : gws,
      lockOverride: _configState?.lockOverride ?? FantasyLockOverride.auto,
      baseline: _sale?.baseline,
      nowUtc: now,
    );
    draft.setSaleContext(
      sale: _sale,
      currentPrices: players == null
          ? null
          : {for (final p in players) p.name: p.priceTenths},
      lastWeekPrices: editingGw == null ? null : _priceHistory?[editingGw - 1],
      editingGw: editingGw,
    );
    draft.setTransferContext(
      state: _transfer,
      answered: _transferAnswered,
      editingGw: editingGw,
    );
    for (final g in gws ?? const <Gameweek>[]) {
      if (!now.isBefore(g.lockUtc)) continue;
      var wait = g.lockUtc.difference(now);
      if (wait > const Duration(days: 1)) wait = const Duration(days: 1);
      _saleBoundary = Timer(wait, _feedSaleContext);
      break;
    }
  }

  /// The pay card's side effects: the Checkout callable, the external
  /// browser, the claim write, the feed retry — seams first.
  FantasyAccessActions get _accessActions => FantasyAccessActions(
        createCheckoutUrl: widget.createCheckoutUrl ??
            () => FantasyService.createCheckoutUrl(widget.sport, widget.season),
        launch: widget.launchExternal ??
            (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
        submitClaim: widget.submitAccessClaim ??
            (method, amount, note) => FantasyService.submitAccessClaim(
                widget.sport, widget.season,
                method: method, amountDollars: amount, note: note),
        retryAccess: _subscribeAccess,
      );

  /// The claim note's tail (seam first; never throws in a widget test).
  String _displayName() {
    final seam = widget.displayName;
    if (seam != null) return seam();
    try {
      return FirebaseAuth.instance.currentUser?.displayName ?? '';
    } catch (_) {
      return '';
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
      // A new draft needs the money context (the baseline may have landed
      // first); a changed lock override moves the week being edited.
      _feedSaleContext();
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
    _accessSub?.cancel();
    _saleSub?.cancel();
    _transferSub?.cancel();
    _transferRetry?.cancel();
    _priceHistorySub?.cancel();
    _saleBoundary?.cancel();
    _lockBoundary?.cancel();
    _locked.dispose();
    _configForRules.close();
    _managerForTabs.close();
    _squadForTabs.close();
    _alertForTabs.close();
    _accessForTabs.close();
    _deadlineClock.dispose();
    _primaryScroll.dispose();
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
      _revealed = true;
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
        // A failed History read is UNKNOWN (null), never "nothing used": it
        // holds arming of Wildcard / Free Hit (a spent one would be voided
        // at the lock and every transfer charged).
        // A failed schedule read is unknown too: no weeks were listened to,
        // so the empty history says nothing (review 6, I2).
        chipHistory: _schedule.weekUnknown || _schedule.scheduleUnknown
            ? null
            : _chipHistory,
        scheduleUnknown: _schedule.scheduleUnknown,
        voidedWeeks: _voidedWeeks,
        lockedWeek: _lockedModel(),
        // The banner's live line: from the live feed the locked-week streams
        // already hold (the SAME first reveal — no extra stream, no late pop).
        liveLine: liveBannerLine(
            live: _locked.sources.live,
            uid: _signedInUid(),
            voidedWeeks: _voidedWeeks),
        access: _access,
        accessStates: _accessForTabs.stream,
        accessActions: _accessActions,
        displayName: _displayName(),
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
        deadlineClock: _deadlineClock,
        primaryScroll: _primaryScroll,
      );
    } else {
      body = const _HubSkeleton(key: ValueKey('skeleton'));
    }
    return PrimaryScrollController(
      controller: _primaryScroll,
      child: Scaffold(
        appBar: AppBar(title: const Text('Infinite Fantasy')),
        // Single fade reveal: skeleton until config+players+manager have ALL
        // arrived, then the whole hub fades in at once.
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: body,
        ),
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
    required this.lockedWeek,
    required this.liveLine,
    required this.access,
    required this.accessStates,
    required this.accessActions,
    required this.displayName,
    required this.draft,
    required this.saveTeamName,
    required this.saveSquad,
    required this.initialTab,
    required this.focusPostId,
    required this.onFocusHandled,
    required this.onOpenPlayer,
    required this.deadlineClock,
    required this.scheduleUnknown,
    required this.primaryScroll,
    this.newsStates,
    this.leaderboardsFeeds,
  });

  /// The hub's one deadline tick, shared by both header faces.
  final FantasyDeadlineClock deadlineClock;

  /// The schedule read failed ([gameweeks] is empty for that reason only):
  /// the deadline faces, My Team and the market say so instead of "Season
  /// complete" / "Locked" (review 6, I2).
  final bool scheduleUnknown;

  /// The tabs' primary scroll controller (see [ActiveTabScrollController]).
  final ActiveTabScrollController primaryScroll;

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

  /// The manager's finalized chips by gameweek — the chip row's counts;
  /// null = unknown (the History read failed).
  final Map<int, ChipHistoryEntry>? chipHistory;

  /// The season's owner-voided gameweeks — their chips are refunded.
  final Set<int> voidedWeeks;

  /// The locked week's live / settled view (live everywhere, Task 5): the
  /// strip and the chips' week lines; null while editing is open.
  final LockedWeekModel? lockedWeek;

  /// The banner's `GW{n} live · {W} pts · #{R}` line while his gameweek is
  /// being played ([liveBannerLine]); null = the plain banner.
  final String? liveLine;

  /// Paid access: the live own Access state + its re-listen-safe feed, the
  /// pay card's actions and the claim note's name (the config's `.access`
  /// block says whether the gate applies at all).
  final FantasyAccessState access;
  final Stream<FantasyAccessState> accessStates;
  final FantasyAccessActions accessActions;
  final String displayName;

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
    // Release report #8: the header shrinks to a slim pinned bar once the
    // active tab scrolls; the deadline stays on screen in both faces.
    return CollapsingTabShell(
      initialIndex: initialTab.index,
      primaryScrollController: primaryScroll,
      tabs: const ['My Team', 'Players', 'Leaderboards', 'News', 'Rules'],
      expandedHeader: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: FantasyBanner(
          subtitle: '$sport · Season $season',
          teamName: manager?.teamName,
          liveLine: liveLine,
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
            clock: deadlineClock,
            scheduleUnknown: scheduleUnknown,
          ),
        ),
      ),
      collapsedHeader: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Container(
          key: const ValueKey('fantasy_hub_slim_bar'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: FantasyBanner.cardDecoration(context, radius: 14),
          child: FantasyDeadlineSlimLine(
            gameweeks: gameweeks,
            lockOverride: configState.lockOverride,
            clock: deadlineClock,
            scheduleUnknown: scheduleUnknown,
          ),
        ),
      ),
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
          scheduleUnknown: scheduleUnknown,
          squadStates: squadStates,
          initialSquad: squad,
          onSaveSquad: saveSquad,
          draft: draft,
          alertStates: alertStates,
          initialAlert: alert,
          chipHistory: chipHistory,
          voidedWeeks: voidedWeeks,
          lockedWeek: lockedWeek,
          onOpenPlayer: onOpenPlayer,
          // Paid access (spec 2026-11-01 §5): the pay card in pass
          // mode until this fan's record is active.
          sport: sport,
          season: season,
          accessConfig: configState.access,
          accessStates: accessStates,
          initialAccess: access,
          accessActions: accessActions,
          displayName: displayName,
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
          scheduleUnknown: scheduleUnknown,
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
          viewerPublishedStates: leaderboardsFeeds?.viewerPublishedStates,
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
          scheduleUnknown: scheduleUnknown,
        ),
      ],
    );
  }
}
