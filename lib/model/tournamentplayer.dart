class TournamentPlayer {
  final String name;
  final String teamId;
  final String teamName;
  final String? uid;
  final String? number;
  final String? position;
  final String? photoUrl;
  final int goals;
  final int assists;
  final int saves;
  final int dpl;
  final int cleanSheets;
  final int yellowCards;
  final int redCards;

  const TournamentPlayer({
    required this.name,
    required this.teamId,
    required this.teamName,
    this.uid,
    this.number,
    this.position,
    this.photoUrl,
    required this.goals,
    required this.assists,
    required this.saves,
    required this.dpl,
    required this.cleanSheets,
    required this.yellowCards,
    required this.redCards,
  });

  int get goalsAndAssists => goals + assists;

  factory TournamentPlayer.fromFirebase(
    String name,
    String teamId,
    String teamName,
    Map<dynamic, dynamic> data,
  ) {
    return TournamentPlayer(
      name: name,
      teamId: teamId,
      teamName: teamName,
      uid: data['UID']?.toString() ?? data['uid']?.toString(),
      number: data['Number']?.toString() ?? data['number']?.toString(),
      position: data['Position']?.toString() ?? data['position']?.toString(),
      photoUrl: data['PhotoUrl']?.toString() ?? data['photoUrl']?.toString(),
      goals: (data['Goals'] as num?)?.toInt() ?? (data['goals'] as num?)?.toInt() ?? 0,
      assists: (data['Assists'] as num?)?.toInt() ?? (data['assists'] as num?)?.toInt() ?? 0,
      saves: (data['Saves'] as num?)?.toInt() ?? (data['saves'] as num?)?.toInt() ?? 0,
      dpl: (data['DPL'] as num?)?.toInt() ?? (data['dpl'] as num?)?.toInt() ?? 0,
      cleanSheets: (data['CleanSheets'] as num?)?.toInt() ??
          (data['cleanSheets'] as num?)?.toInt() ??
          0,
      yellowCards: (data['YellowCards'] as num?)?.toInt() ??
          (data['yellowCards'] as num?)?.toInt() ??
          0,
      redCards: (data['RedCards'] as num?)?.toInt() ??
          (data['redCards'] as num?)?.toInt() ??
          0,
    );
  }

  TournamentPlayer copyWith({String? photoUrl}) {
    return TournamentPlayer(
      name: name,
      teamId: teamId,
      teamName: teamName,
      uid: uid,
      number: number,
      position: position,
      photoUrl: photoUrl ?? this.photoUrl,
      goals: goals,
      assists: assists,
      saves: saves,
      dpl: dpl,
      cleanSheets: cleanSheets,
      yellowCards: yellowCards,
      redCards: redCards,
    );
  }
}
