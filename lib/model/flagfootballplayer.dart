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
  int receivingTouchdowns = 0;
  int receiverMiss = 0;
  int passingTouchdowns = 0;
  int qbCompletions = 0;
  int qbIncomplete = 0;
  int interceptions = 0;
  int flagPulls = 0;
  int passBreakups = 0;
  int sacks = 0;
  String teamPath = "";

  double get catchRate => receptions + receiverMiss == 0 ? 0.0 : (receptions / (receptions + receiverMiss)) * 100;
  double get qbCompletionRate => qbCompletions + qbIncomplete == 0 ? 0.0 : (qbCompletions / (qbCompletions + qbIncomplete)) * 100;
}