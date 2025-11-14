import 'package:infinite_sports_flutter/model/teaminfo.dart';

class FlagFootballTeamInfo extends TeamInfo {
  @override
  String name = "";
  @override
  int wins = 0;
  @override
  int losses = 0;

  int pointsFor = 0;
  int pointsAgainst = 0;

  int get pointDifferential => pointsFor - pointsAgainst;

  FlagFootballTeamInfo();
}
