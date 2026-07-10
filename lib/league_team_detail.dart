import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_form.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
import 'package:infinite_sports_flutter/widgets/form_chips.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:intl/intl.dart';

/// League team detail (League Experience P2): live record header + follow
/// bell (bell UI + FollowStore persistence only — league pushes arrive
/// with the P3 watcher), form chips, results/fixtures that open the league
/// match page, and the squad with player-profile taps.
class LeagueTeamDetailPage extends StatefulWidget {
  final String sport;
  final String season;
  final String teamName;

  const LeagueTeamDetailPage({
    super.key,
    this.sport = 'Futsal',
    required this.season,
    required this.teamName,
  });

  @override
  State<LeagueTeamDetailPage> createState() => _LeagueTeamDetailPageState();
}

class _LeagueTeamDetailPageState extends State<LeagueTeamDetailPage> {
  // null = that stream's first snapshot hasn't arrived → section skeleton.
  List<TournamentMatch>? _matches;
  List<TournamentTeam>? _standings;
  Map<String, List<TournamentPlayer>>? _rosters;
  Map<String, String> _logos = {};
  int _startHour = 0;
  StreamSubscription<List<TournamentMatch>>? _gamesSub;
  StreamSubscription<List<TournamentTeam>>? _standingsSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rostersSub;

  @override
  void initState() {
    super.initState();
    // First paint speed (P2.1): subscribe immediately with default seeds
    // (startHour 0, no logos); each seed re-applies when it arrives.
    _subscribeGames();
    _subscribeStandings();
    _rostersSub =
        LeagueService.watchRosters(widget.sport, widget.season).listen((r) {
      if (mounted) setState(() => _rosters = r);
    });
    LeagueService.getStartHour(widget.sport, widget.season).then((h) {
      if (!mounted || h == _startHour) return;
      _startHour = h;
      _subscribeGames();
    });
    LeagueService.leagueLogoUrls(widget.sport, widget.season).then((logos) {
      if (!mounted || logos.isEmpty) return;
      setState(() => _logos = logos);
      _subscribeStandings();
    });
  }

  void _subscribeGames() {
    _gamesSub?.cancel();
    _gamesSub = LeagueService
        .watchGames(widget.sport, widget.season, startHour: _startHour)
        .listen((m) {
      if (mounted) setState(() => _matches = m);
    });
  }

  void _subscribeStandings() {
    _standingsSub?.cancel();
    _standingsSub = LeagueService
        .watchStandings(widget.sport, widget.season, _logos)
        .listen((s) {
      if (mounted) setState(() => _standings = s);
    });
  }

  @override
  void dispose() {
    _gamesSub?.cancel();
    _standingsSub?.cancel();
    _rostersSub?.cancel();
    super.dispose();
  }

  /// Live record straight from the standings stream; stub until it lands.
  TournamentTeam get _team => (_standings ?? const <TournamentTeam>[]).firstWhere(
        (t) => t.id == widget.teamName,
        orElse: () =>
            leagueTeamStub(widget.teamName, _logos[widget.teamName]),
      );

  void _openMatch(TournamentMatch m) {
    final ref = parseLeagueGameId(m.id);
    if (ref == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeagueMatchDetailPage(
          sport: widget.sport,
          season: widget.season,
          dateKey: ref.dateKey,
          gameIndex: ref.index,
          initialMatch: m,
        ),
      ),
    );
  }

  String _shortDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    final matches = _matches ?? const <TournamentMatch>[];
    final myMatches = teamLeagueMatches(widget.teamName, matches);
    final form = teamLeagueForm(widget.teamName, matches);
    final roster = _rosters?[widget.teamName] ?? <TournamentPlayer>[];

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            actions: [
              FollowBell(
                topic: leagueTeamTopic(
                    widget.sport, widget.season, widget.teamName),
                label: widget.teamName,
                kind: 'team',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(context, team, form),
            ),
          ),
        ],
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _sectionHeader(context, 'RESULTS & FIXTURES'),
            // Skeleton rows until each section's stream lands (P2.1 audit).
            if (_matches == null)
              const SkeletonMatchList(count: 3)
            else if (myMatches.isEmpty)
              _emptyNote(context, 'No games scheduled yet'),
            ...myMatches.map((m) => _matchRow(context, m)),
            _sectionHeader(context, 'SQUAD'),
            if (_rosters == null)
              const SkeletonMatchList(count: 3)
            else if (roster.isEmpty)
              _emptyNote(context, 'No roster yet'),
            ...roster.map((p) => _playerRow(context, p)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, TournamentTeam team, List<String> form) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 8, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TeamLogo(url: team.logoUrl, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (_standings == null)
                      // Record skeleton until the standings stream lands.
                      const SkeletonBox(width: 170, height: 12)
                    else
                      Text(
                        'W${team.wins} D${team.draws} L${team.losses} · ${team.points} pts · Season ${widget.season}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    if (form.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FormChips(form: form),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _emptyNote(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _matchRow(BuildContext context, TournamentMatch m) {
    final isFinished = m.matchStatus.isFinished;
    final isLive = m.matchStatus.isLive;

    Widget leading;
    if (isFinished && m.stage.toLowerCase() != 'friendly') {
      leading =
          FormChips(form: [teamResultLetter(widget.teamName, m)], size: 24);
    } else if (isLive) {
      leading = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9),
        ),
      );
    } else {
      leading = Icon(
        Icons.schedule,
        size: 20,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      );
    }

    final trailing = (isFinished || isLive)
        ? Text(
            '${m.team1Score} - ${m.team2Score}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          )
        : Text(
            m.time ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          );

    final subtitleBits = [
      _shortDate(m.date),
      if (m.label != 'League') m.label, // Friendly / Semifinal / ...
    ];

    return ListTile(
      dense: true,
      leading: SizedBox(width: 40, child: Center(child: leading)),
      title: Text(
        '${m.team1Id} vs ${m.team2Id}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle:
          Text(subtitleBits.join(' · '), style: const TextStyle(fontSize: 11)),
      trailing: trailing,
      onTap: () => _openMatch(m),
    );
  }

  Widget _playerRow(BuildContext context, TournamentPlayer p) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 40,
        child: Center(
          child: Text(
            p.number ?? '–',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
      title: Text(
        p.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'G ${p.goals} · A ${p.assists} · SV ${p.saves}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
      ),
      onTap: () => openPlayerProfileById(context, uid: p.uid, name: p.name),
    );
  }
}
