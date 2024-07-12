// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/teaminfo.dart';

class BasketballTeamInfo implements TeamInfo {
  double ppg = 0;
  double pcpg = 0;
  double pd = 0;
  int gp = 0;

  @override
  int losses = 0;

  String pct = "";

  @override
  int wins = 0;

  @override
  String imagePath = "";
}
