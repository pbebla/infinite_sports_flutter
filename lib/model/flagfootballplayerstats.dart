
import 'package:infinite_sports_flutter/model/playerstats.dart';

class FlagFootballPlayerStats extends PlayerStats {
  int receptions;
  int receptionMisses;
  int receivingTouchdowns;
  int rushingTouchdowns;
  int qbCompletions;
  int qbIncompletions;
  int passingTouchdowns;
  int passingInterceptions;
  int interceptions;
  int interceptionTouchdowns;
  int flagPulls;
  int passBreakups;
  int sacks;
  int pointAfterTouchdownMakes;
  int pointAfterTouchdownMisses;
  int twoPointConversions;

  FlagFootballPlayerStats(
      String name,
      String number,
      String uid,
      this.receptions,
      this.receptionMisses,
      this.receivingTouchdowns,
      this.rushingTouchdowns,
      this.qbCompletions,
      this.qbIncompletions,
      this.passingTouchdowns,
      this.passingInterceptions,
      this.interceptions,
      this.interceptionTouchdowns,
      this.flagPulls,
      this.passBreakups,
      this.sacks,
      this.pointAfterTouchdownMakes,
      this.pointAfterTouchdownMisses,
      this.twoPointConversions
      ) {
    super.name = name;
    super.number = number;
    super.uid = uid;
  }
}