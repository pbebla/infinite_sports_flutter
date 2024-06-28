import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';

Map<String, Map<String, Map<String, FutsalPlayer>>> futsalLineups = {};
Map<String, Map<String, Map<String, BasketballPlayer>>> basketballLineups = {};
Map teamLogos = {};

ValueNotifier headerNotifier = ValueNotifier(["", ""]);

Future<void> getAllTeamLogo() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var event = await newClient.child("Logo Urls").once();
  teamLogos = event.snapshot.value as Map;
}

String convertDateToDatabase(DateTime date) {
  String formattedDate = "";

  if (date.month < 10)
  {
      formattedDate = "0${date.month.toString()}";
  }
  else
  {
      formattedDate = date.month.toString();
  }

  if (date.day < 10)
  {
      formattedDate = "${formattedDate}0${date.day.toString()}";
  }
  else
  {
      formattedDate = formattedDate + (date.day.toString());
  }

  return formattedDate + (date.year.toString());
}

Future<String> getCurrentSport() async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var season = await newClient.child("Current League").get();
    return season.value.toString();
  }
  catch (e)
  {
      return e.toString();
  }
}

Future<String> getCurrentSeason(currentSport) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var seasonNum = await newClient.child(currentSport + " Season").get();
    return seasonNum.value.toString();
  }
  catch (e)
  {
      return e.toString();
  }
}

Future<bool> isSeasonFinished(sport, season) async {
  try
  {
      DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
      var seasonFinished = await newClient.child("Finished").get();
      return seasonFinished.value as bool;
  }
  catch (e)
  {
      return true;
  }
}

Future<List<String>> getDates(String sport, String season) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    var event = await newClient.child("Date").once();
    var datesGotten = event.snapshot.value as Map<dynamic, dynamic>;

    var dates = List<String>.from(datesGotten.keys);

    return dates;
  }
  on Exception catch (_, e)
  {
    throw e;
  }
}

Future<String> getCurrentDate(String sport, String season) async {
  var Sunday = DateTime.now();

  while (Sunday.weekday != DateTime.sunday)
  {
      Sunday = Sunday.add(const Duration(days: 1));
  }

  List<String> dates = await getDates(sport, season);
  while (!dates.contains(convertDateToDatabase(Sunday)))
  {
      Sunday = Sunday.add(const Duration(days: 7));
  }
  return convertDateToDatabase(Sunday);
}

Future<String> getMinSeason(sport) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport");
    var seasonNum = await newClient.child("Init Season").get();
    return seasonNum.value.toString();
  }
  catch (e)
  {
      return e.toString();
  }
}

Future<void> getAllFutsalLineUps(String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Futsal/$season");
  var event = await newClient.child("Line Ups").once();
  var lineups = event.snapshot.value as Map;
  Map<String, Map<String, FutsalPlayer>> result = {};
  lineups.forEach((team, lineup) {
    Map<String, FutsalPlayer> temp = {};
    (lineup as Map).forEach((name, info) {
      FutsalPlayer temp2 = FutsalPlayer();
      temp2.assists = info["Assists"] ?? 0;
      temp2.goals = info["Goals"] ?? 0;
      temp2.number = info["number"] ?? '0';
      temp2.saves = info["Saves"] ?? 0;
      temp2.uid = info["UID"] ?? '0';
      temp2.name = name;
      temp[name] = temp2;
    });
    result[team] = temp;
  },);

  futsalLineups[season] = result;
}

Future<void> getAllBasketballLineUps(String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Basketball/$season");
  var event = await newClient.child("Line Ups").once();
  var lineups = event.snapshot.value as Map;
  Map<String, Map<String, BasketballPlayer>> result = {};
  lineups.forEach((team, lineup) {
    Map<String, BasketballPlayer> temp = {};
    (lineup as Map).forEach((name, info) {
      BasketballPlayer temp2 = BasketballPlayer();
      temp2.number = info["number"] ?? 0;
      temp2.uid = info["UID"] ?? 0;
      temp2.name = name;
      temp2.onePoint = info["OnePoint"] ?? 0;
      temp2.twoPoints = info["TwoPoints"] ?? 0;
      temp2.threePoints = info["ThreePoints"] ?? 0;
      temp2.total = info["Total"] ?? 0;
      temp2.misses = info["Misses"] ?? 0;
      temp2.rebounds = info["Rebounds"] ?? 0;
      temp2.getPercentage();
      temp[name] = temp2;

    });
    result[team] = temp;
  },);
  basketballLineups[season] = result;

  //futsalLineups[season] = lineups;
}