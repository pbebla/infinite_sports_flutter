import 'package:infinite_sports_flutter/model/playerstats.dart';

class BasketballPlayerStats extends PlayerStats {
  int ones;
  int twos;
  int threes;
  late int total;
  int fouls;
  int rebounds;
  BasketballPlayerStats(name, number, uid, this.ones, this.twos, this.threes, this.fouls, this.rebounds) {
    total = ones + (twos*2) + (threes*3);
    super.name = name;
    super.number = number;
    super.uid = uid;
  }
}