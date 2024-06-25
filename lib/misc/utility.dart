import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';

String tableSport = "";
String tableSeason = "";
Map<String, Map<String, Map<String, FutsalPlayer>>> futsalLineups = {};
Map<String, Map<String, Map<String, BasketballPlayer>>> basketballLineups = {};
Map teamLogos = {};

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
      temp2.assists = info["Assists"];
      temp2.goals = info["Goals"];
      temp2.number = info["number"];
      temp2.uid = info["UID"];
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
      temp2.number = info["number"];
      temp2.uid = info["UID"];
      temp2.name = name;
      temp2.onePoint = info["OnePoint"];
      temp2.twoPoints = info["TwoPoints"];
      temp2.threePoints = info["ThreePoints"];
      temp2.total = info["Total"];
      temp2.misses = info["Misses"];
      temp2.rebounds = info["Rebounds"];
      temp2.shotPercentage = ((temp2.twoPoints + temp2.threePoints) / (temp2.twoPoints + temp2.threePoints + temp2.misses)).toStringAsFixed(2);
      temp[name] = temp2;

    });
    result[team] = temp;
  },);
  basketballLineups[season] = result;

  //futsalLineups[season] = lineups;
}