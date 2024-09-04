import 'package:infinite_sports_flutter/model/player.dart';

class SoccerPlayer implements Player {
  @override
  String profileImagePath = "";

  @override
  String uid = "";

  @override
  String name = "";

  @override
  String number = "";

  int assists = 0;
  int goals = 0;
  int red = 0;
  int yellow = 0;
  int saves = 0;
  
  String position = "";
  
  String teamPath = "";
  
}