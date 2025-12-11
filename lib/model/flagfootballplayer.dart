import 'package:infinite_sports_flutter/model/player.dart';

class FlagFootballPlayer implements Player {
  @override
  String profileImagePath = "";

  @override
  String uid = "";

  @override
  String name = "";

  @override
  String number = "";

  int receptions = 0;
  int receptionMisses = 0;
  int receivingTouchdowns = 0;
  int rushingTouchdowns = 0;
  int qbCompletions = 0;
  int qbIncompletions = 0;
  int passingTouchdowns = 0;
  int passingInterceptions = 0;
  int interceptions = 0;
  int interceptionTouchdowns = 0;
  int flagPulls = 0;
  int passBreakups = 0;
  int sacks = 0;
  int pointAfterTouchdownMakes = 0;
  int pointAfterTouchdownMisses = 0;
  int twoPointConversions = 0;
  String teamPath = "";

  String catchRate = "";
  String qbCompletionRate = "";
  void getCompletionPercentage() {
    var percentageCheck = ((qbCompletions + 0.0) / (qbCompletions + qbIncompletions));

    if (percentageCheck.isNaN) {
      qbCompletionRate = "0%";
    } else {
      var percentage = (percentageCheck * 100.0).round();
      qbCompletionRate = "$percentage%";
    }
  }

  void getCatchRate() {
    var percentageCheck = ((receptions + 0.0) / (receptions + receptionMisses));

    if (percentageCheck.isNaN) {
      catchRate = "0%";
    } else {
      var percentage = (percentageCheck * 100.0).round();
      catchRate = "$percentage%";
    }
  }
}