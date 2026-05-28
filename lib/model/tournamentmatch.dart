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
  final Map<String, dynamic>? team1Vote;
  final Map<String, dynamic>? team2Vote;
  final String? winnerGoesToMatchId;
  final String? winnerGoesToSlot;
  final String? link;
  final String? matchLocation;
  final int bracketPosition;
  final int? team1Seed;
  final int? team2Seed;
  final bool team1DirectBye;
  final bool team2DirectBye;
  final String? fromMatchId1;
  final String? fromMatchId2;

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
    this.team1Vote,
    this.team2Vote,
    this.winnerGoesToMatchId,
    this.winnerGoesToSlot,
    this.link,
    this.matchLocation,
    required this.bracketPosition,
    this.team1Seed,
    this.team2Seed,
    required this.team1DirectBye,
    required this.team2DirectBye,
    this.fromMatchId1,
    this.fromMatchId2,
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
      stage: data['Stage']?.toString() ?? data['stage']?.toString() ?? 'Group Stage',
      label: data['Label']?.toString() ?? data['label']?.toString() ?? 'Group Stage',
      date: data['Date']?.toString() ?? data['date']?.toString() ?? '',
      time: data['Time']?.toString() ?? data['time']?.toString(),
      team1Id: data['Team1Id']?.toString() ?? data['team1Id']?.toString(),
      team2Id: data['Team2Id']?.toString() ?? data['team2Id']?.toString(),
      team1Score: (data['Team1Score'] as num?)?.toInt() ?? (data['team1Score'] as num?)?.toInt() ?? 0,
      team2Score: (data['Team2Score'] as num?)?.toInt() ?? (data['team2Score'] as num?)?.toInt() ?? 0,
      status: (data['Status'] as num?)?.toInt() ?? (data['status'] as num?)?.toInt() ?? 0,
      team1Activity: parseActivity(data['Team1Activity'] ?? data['team1Activity']),
      team2Activity: parseActivity(data['Team2Activity'] ?? data['team2Activity']),
      team1Vote: parseActivity(data['Team1Vote'] ?? data['team1Vote']),
      team2Vote: parseActivity(data['Team2Vote'] ?? data['team2Vote']),
      winnerGoesToMatchId: data['WinnerGoesToMatchId']?.toString() ?? data['winnerGoesToMatchId']?.toString(),
      winnerGoesToSlot: data['WinnerGoesToSlot']?.toString() ?? data['winnerGoesToSlot']?.toString(),
      link: data['Link']?.toString() ?? data['link']?.toString(),
      matchLocation: data['MatchLocation']?.toString() ?? data['matchLocation']?.toString(),
      bracketPosition: (data['BracketPosition'] as num?)?.toInt() ?? (data['bracketPosition'] as num?)?.toInt() ?? 0,
      team1Seed: (data['Team1Seed'] as num?)?.toInt() ?? (data['team1Seed'] as num?)?.toInt(),
      team2Seed: (data['Team2Seed'] as num?)?.toInt() ?? (data['team2Seed'] as num?)?.toInt(),
      team1DirectBye: data['Team1DirectBye'] as bool? ?? data['team1DirectBye'] as bool? ?? false,
      team2DirectBye: data['Team2DirectBye'] as bool? ?? data['team2DirectBye'] as bool? ?? false,
      fromMatchId1: data['FromMatchId1']?.toString() ?? data['fromMatchId1']?.toString(),
      fromMatchId2: data['FromMatchId2']?.toString() ?? data['fromMatchId2']?.toString(),
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
