import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

class TournamentMatch {
  final String id;
  final String stage;
  final String label;
  final String date;
  final String? time;
  final String? team1Id;
  final String? team2Id;
  final int team1Score;
  final int team2Score;
  final int status;
  final Map<String, dynamic>? team1Activity;
  final Map<String, dynamic>? team2Activity;
  final String? link;
  final String? matchLocation;
  final int bracketPosition;
  final int? team1Seed;
  final int? team2Seed;

  const TournamentMatch({
    required this.id,
    required this.stage,
    required this.label,
    required this.date,
    this.time,
    this.team1Id,
    this.team2Id,
    required this.team1Score,
    required this.team2Score,
    required this.status,
    this.team1Activity,
    this.team2Activity,
    this.link,
    this.matchLocation,
    required this.bracketPosition,
    this.team1Seed,
    this.team2Seed,
  });

  factory TournamentMatch.fromFirebase(String id, Map<dynamic, dynamic> data) {
    Map<String, dynamic>? parseActivity(dynamic raw) {
      if (raw == null) return null;
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    return TournamentMatch(
      id: id,
      stage: firstNonNull(data, ['Stage', 'stage'])?.toString() ?? 'Group Stage',
      label: firstNonNull(data, ['Label', 'label'])?.toString() ?? 'Group Stage',
      date: firstNonNull(data, ['Date', 'date'])?.toString() ?? '',
      time: firstNonNull(data, ['Time', 'time'])?.toString(),
      team1Id: firstNonNull(data, ['Team1Id', 'team1Id'])?.toString(),
      team2Id: firstNonNull(data, ['Team2Id', 'team2Id'])?.toString(),
      team1Score: parseInt(firstNonNull(data, ['Team1Score', 'team1Score'])),
      team2Score: parseInt(firstNonNull(data, ['Team2Score', 'team2Score'])),
      status: parseInt(firstNonNull(data, ['Status', 'status'])),
      team1Activity: parseActivity(firstNonNull(data, ['Team1Activity', 'team1Activity'])),
      team2Activity: parseActivity(firstNonNull(data, ['Team2Activity', 'team2Activity'])),
      link: firstNonNull(data, ['Link', 'link'])?.toString(),
      matchLocation: firstNonNull(data, ['MatchLocation', 'matchLocation'])?.toString(),
      bracketPosition: parseInt(firstNonNull(data, ['BracketPosition', 'bracketPosition'])),
      team1Seed: firstNonNull(data, ['Team1Seed', 'team1Seed']) != null
          ? parseInt(firstNonNull(data, ['Team1Seed', 'team1Seed']))
          : null,
      team2Seed: firstNonNull(data, ['Team2Seed', 'team2Seed']) != null
          ? parseInt(firstNonNull(data, ['Team2Seed', 'team2Seed']))
          : null,
    );
  }

  String get winnerTeamId {
    if (status != 2) return '';
    if (team1Score > team2Score) return team1Id ?? '';
    if (team2Score > team1Score) return team2Id ?? '';
    return '';
  }

  String get loserTeamId {
    if (status != 2) return '';
    if (team1Score > team2Score) return team2Id ?? '';
    if (team2Score > team1Score) return team1Id ?? '';
    return '';
  }
}
