import 'package:infinite_sports_flutter/model/player.dart';
import 'dart:core';

class BasketballPlayer implements Player {
  @override
  String name = "";

  @override
  String number = "";

  @override
  String profileImagePath = "";

  @override
  String uid = "";

  int onePoint = 0;
  int twoPoints = 0;
  int threePoints = 0;
  int rebounds = 0;
  int misses = 0;
  int total = 0;
  String teamPath = "";
  String shotPercentage = "";

  void getPercentage() {
    var totalShots = twoPoints + threePoints + misses + 0.0;
    var percentageCheck = (totalShots - misses) / totalShots;

    if (percentageCheck.isNaN) {
      shotPercentage = "0%";
    } else {
      var percentage = (percentageCheck * 100.0).round();
      shotPercentage = "$percentage%";
    }
  }

}