import 'package:infinite_sports_flutter/model/playerstats.dart';

class FutsalPlayerStats extends PlayerStats {
  int goals;
  int assists;
  FutsalPlayerStats(name, number, uid, this.goals, this.assists) {
    super.name = name;
    super.number = number;
    super.uid = uid;
  }
}