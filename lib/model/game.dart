// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';

abstract class Game
{
  String date = "";
  String team1 = "";
  String team2 = "";
  String team1score = "";
  String team2score = "";
  String link = "";
  int status = 0;
  String stringStatus = "";
  late Color statusColor;
  String team1SourcePath = "";
  String team2SourcePath = "";
  Map<dynamic, dynamic> team1activity = {};
  Map<dynamic, dynamic> team2activity = {};
  Map<dynamic, dynamic> team1vote = {};
  Map<dynamic, dynamic> team2vote = {};
  late bool signedIn;
  int vote1 = 0;
  int vote2 = 0;
  bool voted = false;
  double finalvote1 = 0.0;
  double finalvote2 = 0.0;
  String percvote1 = "";
  String percvote2 = "";
  late Color ProgressColor1;
  late Color ProgressColor2;
  String UrlPath = "";
  late int GameNum;
  late int Time;
  void setUpVote();
  void getLineUpImages();
}
