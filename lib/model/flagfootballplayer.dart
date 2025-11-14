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

  double get catchRate => receptions + receptionMisses == 0 ? 0.0 : (receptions / (receptions + receptionMisses)) * 100;
  double get qbCompletionRate => qbCompletions + qbIncompletions == 0 ? 0.0 : (qbCompletions / (qbCompletions + qbIncompletions)) * 100;
}