
import 'package:infinite_sports_flutter/model/playerstats.dart';

class FlagFootballPlayerStats extends PlayerStats {
  int receptions;
  int receivingTouchdowns;
  int receiverMiss;
  int passingTouchdowns;
  int qbCompletions;
  int qbIncomplete;
  int interceptions;
  int flagPulls;
  int passBreakups;
  int sacks;

  double get catchRate => receptions + receiverMiss == 0 ? 0.0 : (receptions / (receptions + receiverMiss)) * 100;
  double get qbCompletionRate => qbCompletions + qbIncomplete == 0 ? 0.0 : (qbCompletions / (qbCompletions + qbIncomplete)) * 100;

  FlagFootballPlayerStats(
      String name,
      String number,
      String uid,
      this.receptions,
      this.receivingTouchdowns,
      this.receiverMiss,
      this.passingTouchdowns,
      this.qbCompletions,
      this.qbIncomplete,
      this.interceptions,
      this.flagPulls,
      this.passBreakups,
      this.sacks,
      ) {
    super.name = name;
    super.number = number;
    super.uid = uid;
  }
}