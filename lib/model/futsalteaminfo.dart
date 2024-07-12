// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/teaminfo.dart';

class FutsalTeamInfo implements TeamInfo {
  int draws = 0;
  int gc = 0;
  int gd = 0;
  int gp = 0;
  int gs = 0;

  @override
  int losses = 0;

  int points = 0;

  @override
  int wins = 0;

  @override
  String imagePath = "";
}
