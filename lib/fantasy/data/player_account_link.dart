// Fantasy player ↔ league account link (round 3, spec §4 "Name → account"):
// a runtime join, no uid is stored on fantasy Players. Rosters come from
// `LeagueService.watchRosters` — `{team name: [TournamentPlayer]}` (League
// teams are keyed by NAME; the adapter already turns an unlinked '0'/empty
// UID into null, but the join defends against the raw values too).
//
// The match is on team AND name: the same name can exist on two teams and
// must never cross-link. An ambiguous match yields null — the profile then
// hides "See full profile" rather than guess. Pure; unit-tested in
// test/fantasy/player_account_link_test.dart.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// A real linked uid, trimmed; null for null / empty / the legacy '0'.
String? _linkedUid(String? raw) {
  final uid = raw?.trim() ?? '';
  return (uid.isEmpty || uid == '0') ? null : uid;
}

/// The distinct linked uids of the roster rows on [team] named [name].
Set<String> _uidsOn(
    String team, String name, Map<String, List<TournamentPlayer>> rosters) {
  final uids = <String>{};
  rosters.forEach((rosterTeam, players) {
    if (rosterTeam.trim() != team) return;
    for (final r in players) {
      if (r.name.trim() != name) continue;
      final uid = _linkedUid(r.uid);
      if (uid != null) uids.add(uid);
    }
  });
  return uids;
}

/// [p]'s linked account uid: the roster entry with the same team AND name.
/// null when there is none, the entry is unlinked ('0' / empty), or the
/// matching rows disagree about the uid.
String? uidForFantasyPlayer(
    FantasyPlayer p, Map<String, List<TournamentPlayer>> rostersByTeam) {
  final uids = _uidsOn(p.teamName.trim(), p.name.trim(), rostersByTeam);
  return uids.length == 1 ? uids.first : null;
}

/// The fantasy player behind account [uid]: the one market player whose
/// team + name resolve to that uid. null when [uid] is unlinked, matches no
/// player, or matches more than one (a team change, duplicated entries).
FantasyPlayer? fantasyPlayerForUid(
  String uid,
  List<FantasyPlayer> players,
  Map<String, List<TournamentPlayer>> rostersByTeam,
) {
  final wanted = _linkedUid(uid);
  if (wanted == null) return null;
  FantasyPlayer? match;
  for (final p in players) {
    if (uidForFantasyPlayer(p, rostersByTeam) != wanted) continue;
    if (match != null) return null; // ambiguous: don't guess
    match = p;
  }
  return match;
}
