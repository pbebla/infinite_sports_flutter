import 'package:infinite_sports_flutter/model/player.dart';
import 'dart:core';
import 'dart:ui';

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
  String shotPercentage = "N/A";

  void getPercentage() {
    total = onePoint + twoPoints + threePoints;
    var totalShots = twoPoints + threePoints + misses + 0.0;
    var percentage = (((totalShots - misses) / totalShots) * 100.0).round();

    if (percentage.isNaN)
    {
        shotPercentage = "N/A";
    }
    else
    {
        shotPercentage = "$percentage%";
    }
  }

}