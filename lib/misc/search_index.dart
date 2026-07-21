import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';

enum SearchResultType { team, league, tournament, player, event }

class SearchResult {
  const SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.sport,
    this.season,
    this.tournamentId,
    this.uid,
    this.eventIndex,
    this.eventId,
  });

  final SearchResultType type;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? sport;
  final String? season;
  final String? tournamentId;
  final String? uid;
  final int? eventIndex;

  /// EventsV2 id; set for V2 events (eventIndex is then null).
  final String? eventId;
}

/// Client-side search over data the app already loads: the team-logos map,
/// tournaments, registered users, and events. Rebuilt each time the search
/// page opens — no persistence, no backend.
class SearchIndex {
  final List<SearchResult> _entries = [];

  /// teamLogos shape: {sport: {season: {teamName: url}}} — except the
  /// "AFC San Jose" key, whose value is a plain URL string (skipped here,
  /// AFC has its own seasons UI).
  void addTeamsAndLeagues(Map logos) {
    logos.forEach((sportKey, seasonsVal) {
      if (seasonsVal is! Map) return;
      final sport = sportKey.toString();
      final seasonEntries = seasonsVal.entries.toList()
        ..sort((a, b) => (int.tryParse(b.key.toString()) ?? 0)
            .compareTo(int.tryParse(a.key.toString()) ?? 0));
      final seenTeams = <String>{};
      for (final se in seasonEntries) {
        final season = se.key.toString();
        final teams = se.value;
        if (teams is! Map) continue;
        _entries.add(SearchResult(
          type: SearchResultType.league,
          title: '$sport Season $season',
          subtitle: 'League',
          sport: sport,
          season: season,
        ));
        teams.forEach((teamKey, url) {
          final team = teamKey.toString();
          if (!seenTeams.add(team.toLowerCase())) return;
          _entries.add(SearchResult(
            type: SearchResultType.team,
            title: team,
            subtitle: '$sport · Season $season',
            imageUrl: url?.toString(),
            sport: sport,
            season: season,
          ));
        });
      }
    });
  }

  void addTournaments(List<Tournament> tournaments) {
    for (final t in tournaments) {
      _entries.add(SearchResult(
        type: SearchResultType.tournament,
        title: t.name,
        subtitle: '${t.sport} · ${t.edition}'.trim(),
        imageUrl: t.logoUrl,
        tournamentId: t.id,
      ));
    }
  }

  void addUsers(Map<String, MyUser> users) {
    users.forEach((uid, user) {
      final name = '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim();
      if (name.isEmpty) return;
      _entries.add(SearchResult(
        type: SearchResultType.player,
        title: name,
        subtitle: 'Player',
        imageUrl: user.profileURL,
        uid: uid,
      ));
    });
  }

  /// [events] must be the MERGED list (getAllEvents): V2 events carry their
  /// id, unmirrored legacy events carry their true list index — so a search
  /// hit opens the exact same page the event's own section opens.
  void addEvents(List<Event> events) {
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if ((e.title ?? '').isEmpty) continue;
      _entries.add(SearchResult(
        type: SearchResultType.event,
        title: e.title!,
        subtitle: [e.eventDate, e.location]
            .where((s) => (s ?? '').isNotEmpty)
            .join(' · '),
        imageUrl: e.imageUrl,
        eventId: e.id,
        eventIndex: e.id != null ? null : (e.legacyIndex ?? i),
      ));
    }
  }

  List<SearchResult> query(String q, {int limitPerType = 6}) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final byType = <SearchResultType, List<SearchResult>>{};
    for (final entry in _entries) {
      if (!entry.title.toLowerCase().contains(needle)) continue;
      final bucket = byType.putIfAbsent(entry.type, () => []);
      if (bucket.length < limitPerType) bucket.add(entry);
    }
    return [
      for (final type in SearchResultType.values) ...?byType[type],
    ];
  }
}
