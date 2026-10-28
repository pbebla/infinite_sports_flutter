import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/aroundyou.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/insiders/insiders_leaderboard_page.dart';
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/misc/search_index.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Search across the app plus the hub of extra sections (Around You,
/// Infinite Insiders, Infinite Fantasy today; future sections each add one
/// card here).
class SearchHubPage extends StatefulWidget {
  const SearchHubPage({
    super.key,
    this.insidersLeaderboardPageBuilder,
    this.fantasyGateOverride,
    this.fantasyHubPageBuilder,
  });

  /// Test seam replacing the real `Navigator.push(... InsidersLeaderboardPage
  /// ...)` the "Infinite Insiders" card makes (Task F6) — the real page
  /// reaches for InsiderService's live Firebase streams in its own default
  /// wiring, which isn't available in widget tests. Mirrors
  /// insiders_info_page.dart's `dashboardPageBuilder` seam.
  final Widget Function()? insidersLeaderboardPageBuilder;

  /// Test seam replacing the live Fantasy gate (current league's
  /// `Fantasy/<sport>/<season>/Config` existence): emits (sport, season)
  /// while fantasy is open, null while it isn't.
  final Stream<(String, String)?>? fantasyGateOverride;

  /// Test seam replacing the real `Navigator.push(... FantasyHubPage ...)`.
  final Widget Function(String sport, String season)? fantasyHubPageBuilder;

  @override
  State<SearchHubPage> createState() => _SearchHubPageState();
}

class _SearchHubPageState extends State<SearchHubPage> {
  final TextEditingController _controller = TextEditingController();
  Future<SearchIndex>? _indexFuture;
  String _query = '';

  /// (sport, season) while the current league has a Fantasy Config node —
  /// the card appears/disappears live with it (same stream gate as the
  /// league page's Fantasy tab).
  (String, String)? _fantasy;
  StreamSubscription<Object?>? _fantasySub;

  @override
  void initState() {
    super.initState();
    _indexFuture = _buildIndex();
    _subscribeFantasyGate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fantasySub?.cancel();
    super.dispose();
  }

  void _subscribeFantasyGate() {
    final override = widget.fantasyGateOverride;
    if (override != null) {
      _fantasySub = override.listen((v) {
        if (mounted) setState(() => _fantasy = v);
      });
      return;
    }
    _watchCurrentLeagueFantasy();
  }

  Future<void> _watchCurrentLeagueFantasy() async {
    // Current league pointer — the same utility.dart source main.dart and
    // frontpage.dart resolve the live league from.
    final sport = await getCurrentSport();
    final season = await getCurrentSeason(sport);
    if (!mounted) return;
    _fantasySub =
        FantasyService.watchConfig(sport, season).listen((state) {
      if (mounted) {
        setState(() => _fantasy = state != null ? (sport, season) : null);
      }
    }, onError: (Object _) {
      // Offline/unreachable: the card simply stays hidden.
      if (mounted) setState(() => _fantasy = null);
    });
  }

  void _openFantasy(String sport, String season) {
    final builder = widget.fantasyHubPageBuilder ??
        (String s, String n) => FantasyHubPage(sport: s, season: n);
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => builder(sport, season)));
  }

  Future<SearchIndex> _buildIndex() async {
    final index = SearchIndex();
    try {
      await getAllTeamLogo();
      index.addTeamsAndLeagues(teamLogos);
    } catch (_) {}
    try {
      index.addTournaments(await TournamentService.getAllTournaments());
    } catch (_) {}
    try {
      // Merged V2 + legacy list so search opens the same full event page as
      // the calendar and Around You (never a stripped-down mirror row).
      index.addEvents(await getAllEvents());
    } catch (_) {}
    try {
      index.addUsers(await getAllUsers());
    } catch (_) {}
    return index;
  }

  void _open(SearchResult result) {
    switch (result.type) {
      case SearchResultType.team:
      case SearchResultType.league:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return ShowLeaguePage(sport: result.sport!, season: result.season!);
        }));
      case SearchResultType.tournament:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return TournamentDetailPage(
              tournamentId: result.tournamentId!, tournamentName: result.title);
        }));
      case SearchResultType.player:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return PlayerPage(uid: result.uid!);
        }));
      case SearchResultType.event:
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return result.eventId != null
              ? EventPage(v2Id: result.eventId)
              : EventPage(index: result.eventIndex!);
        }));
    }
  }

  static const Map<SearchResultType, String> _sectionTitles = {
    SearchResultType.team: 'Teams',
    SearchResultType.league: 'Leagues',
    SearchResultType.tournament: 'Tournaments',
    SearchResultType.player: 'Players',
    SearchResultType.event: 'Events',
  };

  static const Map<SearchResultType, IconData> _fallbackIcons = {
    SearchResultType.team: Icons.shield_outlined,
    SearchResultType.league: Icons.format_list_numbered,
    SearchResultType.tournament: Icons.emoji_events_outlined,
    SearchResultType.player: Icons.person_outline,
    SearchResultType.event: Icons.event,
  };

  Widget _resultTile(SearchResult result) {
    return ListTile(
      leading: (result.imageUrl ?? '').isNotEmpty
          ? CircleAvatar(
              backgroundColor: Colors.transparent,
              foregroundImage: NetworkImage(result.imageUrl!),
              onForegroundImageError: (_, __) {},
              child: Icon(_fallbackIcons[result.type]),
            )
          : CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(_fallbackIcons[result.type]),
            ),
      title: Text(result.title),
      subtitle: result.subtitle.isEmpty ? null : Text(result.subtitle),
      onTap: () => _open(result),
    );
  }

  Widget _hub() {
    return ListView(
      // Bottom inset clears the bottom of the screen (PR #12 review).
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text('Explore', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Infinite Fantasy entry (P3a feedback): present exactly while the
        // current league's Fantasy Config node exists — the same dark
        // gradient + gold logo language as the league page's entry card.
        if (_fantasy != null) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    FantasyBanner.gradientTop,
                    FantasyBanner.gradientBottom,
                  ],
                ),
              ),
              child: ListTile(
                key: const ValueKey('search_hub_fantasy_card'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Image.asset(
                  'assets/fantasy/fantasy_logo.png',
                  width: 44,
                  height: 36,
                  fit: BoxFit.contain,
                ),
                title: const Text(
                  'Infinite Fantasy',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Pick your seven — ${_fantasy!.$1} Season ${_fantasy!.$2} '
                  'is live',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: Colors.white70),
                onTap: () => _openFantasy(_fantasy!.$1, _fantasy!.$2),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const ImageIcon(AssetImage('assets/aroundyou.png'), size: 32),
            title: const Text('Around You'),
            subtitle: const Text('Businesses and events near you'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return const AroundYou();
              }));
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Icon(Icons.diamond,
                size: 32, color: Theme.of(context).colorScheme.primary),
            title: const Text('Infinite Insiders'),
            // B8: the leaderboard page shows its dormant coming-soon state,
            // so the card says so instead of promising rankings.
            subtitle: const Text('Referral program — coming soon'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final builder = widget.insidersLeaderboardPageBuilder ??
                  () => const InsidersLeaderboardPage();
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => builder()));
            },
          ),
        ),
      ],
    );
  }

  Widget _results(SearchIndex index) {
    final hits = index.query(_query);
    if (hits.isEmpty) {
      return const Center(child: Text('No results'));
    }
    final children = <Widget>[];
    SearchResultType? lastType;
    for (final hit in hits) {
      if (hit.type != lastType) {
        lastType = hit.type;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(_sectionTitles[hit.type]!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ));
      }
      children.add(_resultTile(hit));
    }
    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search teams, players, events...',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() { _query = value; }),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() { _query = ''; });
              },
            ),
        ],
      ),
      body: FutureBuilder(
        future: _indexFuture,
        builder: (context, snapshot) {
          if (_query.trim().isEmpty) {
            return _hub();
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Skeleton sweep (F3 Fix 2): matches the search results list.
            return const SkeletonList();
          }
          return _results(snapshot.data!);
        },
      ),
    );
  }
}
