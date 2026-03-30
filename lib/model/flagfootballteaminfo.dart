import 'package:infinite_sports_flutter/model/teaminfo.dart';

class FlagFootballTeamInfo implements TeamInfo {
  @override
  int wins = 0;
  @override
  int losses = 0;

  int ties = 0;

  int pointsFor = 0;
  int pointsAgainst = 0;

  int get pointDifferential => pointsFor - pointsAgainst;
  String get pct => ((wins + (ties * 0.5)) / (wins + losses + ties)).toStringAsFixed(3);

  @override
  String imagePath = "";

}
