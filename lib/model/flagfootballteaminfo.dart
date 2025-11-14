import 'package:infinite_sports_flutter/model/teaminfo.dart';

class FlagFootballTeamInfo implements TeamInfo {
  @override
  int wins = 0;
  @override
  int losses = 0;

  int pointsFor = 0;
  int pointsAgainst = 0;

  int get pointDifferential => pointsFor - pointsAgainst;

  @override
  String imagePath = "";

}
