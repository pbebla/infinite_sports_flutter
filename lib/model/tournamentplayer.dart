import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

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

  /// Returns the integer stat value for a given stat name.
  /// Recognized names: 'goals', 'assists', 'saves', 'dpl',
  /// 'cleanSheets', 'yellowCards', 'redCards', 'goalsAndAssists'.
  /// Returns 0 for unrecognized names.
  int statByName(String stat) {
    switch (stat) {
      case 'goals':
        return goals;
      case 'assists':
        return assists;
      case 'saves':
        return saves;
      case 'dpl':
        return dpl;
      case 'cleanSheets':
        return cleanSheets;
      case 'yellowCards':
        return yellowCards;
      case 'redCards':
        return redCards;
      case 'goalsAndAssists':
        return goalsAndAssists;
      default:
        return 0;
    }
  }

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
      uid: firstNonNull(data, ['UID', 'uid'])?.toString(),
      number: firstNonNull(data, ['Number', 'number'])?.toString(),
      position: firstNonNull(data, ['Position', 'position'])?.toString(),
      photoUrl: firstNonNull(data, ['PhotoUrl', 'photoUrl'])?.toString(),
      goals: parseInt(firstNonNull(data, ['Goals', 'goals'])),
      assists: parseInt(firstNonNull(data, ['Assists', 'assists'])),
      saves: parseInt(firstNonNull(data, ['Saves', 'saves'])),
      dpl: parseInt(firstNonNull(data, ['DPL', 'dpl'])),
      cleanSheets: parseInt(firstNonNull(data, ['CleanSheets', 'cleanSheets'])),
      yellowCards: parseInt(firstNonNull(data, ['YellowCards', 'yellowCards'])),
      redCards: parseInt(firstNonNull(data, ['RedCards', 'redCards'])),
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
