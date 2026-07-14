import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/aroundyou.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/search_index.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';

/// Search across the app plus the hub of extra sections (Around You today;
/// future sections each add one card here).
class SearchHubPage extends StatefulWidget {
  const SearchHubPage({super.key});

  @override
  State<SearchHubPage> createState() => _SearchHubPageState();
}

class _SearchHubPageState extends State<SearchHubPage> {
  final TextEditingController _controller = TextEditingController();
  Future<SearchIndex>? _indexFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _indexFuture = _buildIndex();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      index.addEvents(await getEvents());
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
          return EventPage(index: result.eventIndex!);
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
      padding: const EdgeInsets.all(16),
      children: [
        Text('Explore', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
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
            return const Center(child: CircularProgressIndicator());
          }
          return _results(snapshot.data!);
        },
      ),
    );
  }
}
