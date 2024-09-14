
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/game.dart';
import 'package:infinite_sports_flutter/model/soccergame.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

var infiniteSportsPrimaryColor = const Color.fromARGB(255, 208, 0, 0);

Map<String, Map<String, Map<String, FutsalPlayer>>> futsalLineups = {};
Map<String, Map<String, Map<String, BasketballPlayer>>> basketballLineups = {};
Map teamLogos = {};
FirebaseAuthService auth = FirebaseAuthService();
bool signedIn = false;
bool autoSignIn = false;
bool darkModeEnabled = false;

// Create storage
const secureStorage = FlutterSecureStorage();

// Read value
//String value = await storage.read(key: key);

ValueNotifier headerNotifier = ValueNotifier(["", ""]);

final List<String> months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
];

String convertDatabaseDateToFormatDate(String databaseDate) {
  int year = int.parse(databaseDate.substring(4));
  int day = int.parse(databaseDate.substring(2,4));
  int month = int.parse(databaseDate.substring(0,2));
  return DateFormat.yMMMMd('en_US').format(DateTime.utc(year, month=month, day=day));
}

String convertStringDateToDatabase(String date)
{
    var firstSplit = date.split(",".toString());
    var secondSplit = firstSplit[0].split(" ".toString());

    var year = firstSplit[1].replaceAll(" ", "");
    var month = secondSplit[0];
    var day = secondSplit[1];

    if (int.parse(day) < 10)
    {
        day = "0$day";
    }

    var numMonth = "${months.indexOf(month)+1}";

    if (int.parse(numMonth) < 10)
    {
        numMonth = "0$numMonth";
    }

    return numMonth + day + year;
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
    if (sport == "AFC San Jose") {
      sport = "AFC San Jose/Seasons";
    }
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    var event = await newClient.child("Date").once();
    var datesGotten = event.snapshot.value as Map<dynamic, dynamic>;

    var dates = List<String>.from(datesGotten.keys);

    return dates;
  }
  catch (e)
  {
    return [];
  }
}

Future<String> getCurrentDate(String sport, String season) async {
  var Sunday = DateTime.now();

  while (Sunday.weekday != DateTime.sunday)
  {
    Sunday = Sunday.add(const Duration(days: 1));
  }

  List<String> dates = await getDates(sport, season);

  var latestDate = dates.reduce((current, next) => current.compareTo(next)>0 ? current : next);
  if (convertDateToDatabase(Sunday).compareTo(latestDate) > 0) {
    return latestDate;
  }

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

Future<List<String>> getSoccerSeasons(sport) async {
  if (sport == "AFC San Jose") {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/");
    var event = await newClient.child("Seasons").once();
    var seasons = event.snapshot.value as Map<dynamic, dynamic>;
    return seasons.keys.toList().cast<String>();
  }
  return [];
}

Future<Map<String, SoccerPlayer>> getSoccerRoster(sport, season) async {
  Map<String, SoccerPlayer> roster = {};
  if (sport == "AFC San Jose") {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/Seasons/$season");
    var event = await newClient.child("Roster").once();
    var lineup = event.snapshot.value as Map;
    lineup.forEach((name, info) {
      SoccerPlayer temp = SoccerPlayer();
      temp.assists = info["Assists"] ?? 0;
      temp.goals = info["Goals"] ?? 0;
      temp.number = info["Number"].toString() ?? "";
      temp.saves = info["Saves"] ?? 0;
      temp.uid = info["UID"] ?? '0';
      temp.position = info["Position"] ?? "";
      temp.name = name;
      temp.red = info["Red"] ?? 0;
      temp.yellow = info["Yellow"] ?? 0;
      roster[name] = temp;
    });
  }
  return roster;
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
      temp2.uid = info["UID"] ?? '0';
      temp2.name = name;
      temp2.onePoint = info["OnePoint"] ?? 0;
      temp2.twoPoints = info["TwoPoints"] ?? 0;
      temp2.threePoints = info["ThreePoints"] ?? 0;
      temp2.total = info["Total"] ?? temp2.onePoint + (temp2.twoPoints*2) + (temp2.threePoints*3);
      temp2.misses = info["Misses"] ?? 0;
      temp2.rebounds = info["Rebounds"] ?? 0;
      temp2.getPercentage();
      temp[name] = temp2;

    });
    result[team] = temp;
  },);
  basketballLineups[season] = result;
}

int compareValues(dynamic value1, dynamic value2, bool ascending) =>
  ascending ? value1.compareTo(value2) : value2.compareTo(value1);

Future<List<Game>> getGames(sport, season, date, times) async {
  List<Game> allGames = <Game>[];
  if (date == "") {
    return [];
  }
  List<Game> games = <Game>[];

  if (sport == "Futsal")
  {
    var all = await getAllFutsalGames(sport, season);
    games = List<Game>.from(all[date] as List<Game>);
  }
  else if (sport == "AFC San Jose")
  {
    var all = await getAllSoccerGames(sport, season);
    games = List<Game>.from(all[date] as List<Game>);
  }
  else
  {
    var all = await getAllBasketballGames(sport, season);
    games = List<Game>.from(all[date] as List<Game>);
  }

  int i = 0;
  for (var game in games)
  {
      await fillInNull(game, sport, season);
      if (sport != "AFC San Jose") {
        game.Time = (await getSeasonStartTime(times, sport, season)) + i;
      }
      
      switch (game.status)
      {
          case 0:
              game.stringStatus = "Upcoming";
              game.statusColor = Colors.grey;
              break;
          case 1:
              game.stringStatus = "Live";
              game.statusColor = Colors.red;
              break;
          case 2:
              game.stringStatus = "Final";
              game.statusColor = Colors.green;
              break;
      }

      game.UrlPath = "https://infinite-sports-app.firebaseio.com/$sport/$season/Date/$date";
      game.GameNum = i;

      game.SetUpVote();
      game.GetLineUpImages();
      allGames.add(game);
      i++;
  }
  return allGames;
}

Future<Map<String, List<SoccerGame>>> getAllSoccerGames(sport, season) async {
  try
  {
    DatabaseReference newClient;
    if (sport == "AFC San Jose") {
      newClient = FirebaseDatabase.instance.ref("/$sport/Seasons/$season");
    } else {
      newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    }
    var games = await newClient.child("Date").get();
    dynamic data = games.value;
    var result = <String, List<SoccerGame>>{};
    data.forEach((key, value) {
      var list = <SoccerGame>[];
      for (var val in value) {
        var game = SoccerGame();
        if (val.containsKey("team1vote")) {
          game.team1vote = val["team1vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2vote")) {
          game.team2vote = val["team2vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team1activity")) {
          game.team1activity = val["team1activity"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2activity")) {
          game.team2activity = val["team2activity"] as Map<dynamic, dynamic>;
        }
        game.team1 = val["team1"];
        game.team2 = val["team2"];
        game.team1score = (val["team1score"] ?? val["team1Score"]).toString();
        game.team2score = (val["team2score"] ?? val["team2Score"]).toString();
        game.date = val["Date"] ?? val["date"];
        game.startTime = val["startTime"] ?? "";
        game.location = val["location"] ?? "";
        game.type = val["type"] ?? "";
        game.status = val["status"];
        if(val.containsKey("link")) {
          game.link = val["link"];
        }
        list.add(game);
      }
      result[key] = list;
    });
    return result;
  }
  catch (e)
  {
      return {};
  }
}

Future<Map<String, List<FutsalGame>>> getAllFutsalGames(sport, season) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    var games = await newClient.child("Date").get();
    dynamic data = games.value;
    var result = <String, List<FutsalGame>>{};
    data.forEach((key, value) {
      var list = <FutsalGame>[];
      for (var val in value) {
        var game = FutsalGame();
        if (val.containsKey("team1vote")) {
          game.team1vote = val["team1vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2vote")) {
          game.team2vote = val["team2vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team1activity")) {
          game.team1activity = val["team1activity"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2activity")) {
          game.team2activity = val["team2activity"] as Map<dynamic, dynamic>;
        }
        game.team1 = val["team1"];
        game.team2 = val["team2"];
        game.team1score = (val["team1score"] ?? val["team1Score"]).toString();
        game.team2score = (val["team2score"] ?? val["team2Score"]).toString();
        game.date = val["Date"] ?? val["date"];
        game.status = val["status"];
        if(val.containsKey("link")) {
          game.link = val["link"];
        }
        list.add(game);
      }
      result[key] = list;
    });
    return result;
  }
  catch (e)
  {
      return {};
  }
}

Future<Map<String, List<BasketballGame>>> getAllBasketballGames(sport, season) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    var games = await newClient.child("Date").get();
    dynamic data = games.value;
    var result = <String, List<BasketballGame>>{};
    data.forEach((key, value) {
      var list = <BasketballGame>[];
      for (var val in value) {
        var game = BasketballGame();
        if (val.containsKey("team1vote")) {
          game.team1vote = val["team1vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2vote")) {
          game.team2vote = val["team2vote"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team1activity")) {
          game.team1activity = val["team1activity"] as Map<dynamic, dynamic>;
        }
        if (val.containsKey("team2activity")) {
          game.team2activity = val["team2activity"] as Map<dynamic, dynamic>;
        }
        game.team1 = val["team1"];
        game.team2 = val["team2"];
        game.team1score = val["team1score"].toString();
        game.team2score = val["team2score"].toString();
        game.date = val["Date"];
        game.status = val["status"] ?? 0;
        if(val.containsKey("link")) {
          game.link = val["link"];
        }
        list.add(game);
      }
      result[key] = list;
    });
    return result;
  }
  catch (e)
  {
      return {};
  }
}

Future<void> fillInNull(game, sport, season) async {
  if (game is SoccerGame) {
    if (game.team1SourcePath == "")
      {
          await getAllTeamLogo();

          if (game.team1 == "AFC San Jose") {
            game.team1lineup = await getSoccerRoster(sport, season);
            game.team1SourcePath = teamLogos[game.team1];
          }
          if (game.team2 == "AFC San Jose") {
            game.team2lineup = await getSoccerRoster(sport, season);
            game.team2SourcePath = teamLogos[game.team2];
          }
      }

  }
  if (game is FutsalGame) {
    try
    {
      game.team1lineup = await getFutsalLineUp(season, game.team1);
      game.team2lineup = await getFutsalLineUp(season, game.team2);

      if (game.team1SourcePath == "")
      {
          await getAllTeamLogo();
          var futsal = teamLogos["Futsal"];
          var logos = futsal[season];

          if (logos.containsKey(game.team1)) {
            game.team1SourcePath = logos[game.team1];
          }
          if (logos.containsKey(game.team2)) {
            game.team2SourcePath = logos[game.team2];
          }
      }

    }
    catch (e)
    {
        var message = e.toString();
    }
  }
  if (game is BasketballGame) {
    try
    {
        game.team1lineup = await getBasketballLineUp(season, game.team1);
        game.team2lineup = await getBasketballLineUp(season, game.team2);

        if (game.team1SourcePath == "")
        {
            await getAllTeamLogo();
            var basketball = teamLogos["Basketball"];
            var logos = basketball[season];

            game.team1SourcePath = logos[game.team1] ?? "";
            game.team2SourcePath = logos[game.team2] ?? "";
        }
    }
    catch (e)
    {
        var message = e.toString();
    }
  }
}

Future<int> getSeasonStartTime(times, sport, season) async {
  if (times.containsKey(sport))
  {
      if (times[sport]!.containsKey(season))
      {
          return times[sport]![season]!;
      }
  }

  try
  {
      DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
      var event = await newClient.child("Start Time").once();
      late int seasonStart;
      if (event.snapshot.value != null) {
        seasonStart = event.snapshot.value as int;
      } else {
        seasonStart = 0;
      }

      if (!times.containsKey(sport))
      {
          var dictionary = <String, int>{};
          dictionary[season] = seasonStart;
          times[sport] = dictionary;
      }
      else
      {
          times[sport]![season] = seasonStart;
      }

      return seasonStart;
  }
  catch (e)
  {
      return 5;
  }
}

Future<Map<String, FutsalPlayer>> getFutsalLineUp(season, team) async {
  await getAllFutsalLineUps(season);
  Map<String, FutsalPlayer> lineup = futsalLineups[season]?[team] ?? {};
  return lineup;
}

Future<Map<String, BasketballPlayer>> getBasketballLineUp(season, team) async {
  await getAllBasketballLineUps(season);
  Map<String, BasketballPlayer> lineup = basketballLineups[season]?[team] ?? {};
  return lineup;
}

Future<void> getAllTeamLogo() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var event = await newClient.child("Logo Urls").once();
  teamLogos = event.snapshot.value as Map;

  newClient = FirebaseDatabase.instance.ref("AFC San Jose");
  event = await newClient.child("Logo URL").once();
  teamLogos["AFC San Jose"] = event.snapshot.value as String;
}

Future<Game> getGame(widget, sport, season, date, times, num) async {
  try {
    var games = await getGames(sport, season, date, times);
    return games[num];
  }
  catch (e)
  {
    rethrow;
  }
}

/// Converts fully qualified YouTube Url to video id.
///
/// If videoId is passed as url then no conversion is done.
String? convertUrlToId(String url, {bool trimWhitespaces = true}) {
  if (!url.contains("http") && (url.length == 11)) return url;
  if (trimWhitespaces) url = url.trim();

  for (var exp in [
    RegExp(
        r"^https:\/\/(?:www\.|m\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https:\/\/(?:music\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https:\/\/(?:www\.|m\.)?youtube\.com\/shorts\/([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https:\/\/(?:www\.|m\.)?youtube(?:-nocookie)?\.com\/embed\/([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(r"^https:\/\/youtu\.be\/([_\-a-zA-Z0-9]{11}).*$")
  ]) {
    Match? match = exp.firstMatch(url);
    if (match != null && match.groupCount >= 1) return match.group(1);
  }

  return null;
}

Future<int> getSignUpStatus() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Sign Ups/");

  try
  {
    var event = await newClient.child("Sign Up Status").once();
    var status = event.snapshot.value as int;
    return status;
  }
  catch (e)
  {
    return 0;
  }
}

Future<String> getSignUpDue() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Sign Ups/");

  try
  {
    var event = await newClient.child("Due").once();
    var status = event.snapshot.value as String;
    return status;
  }
  catch (e)
  {
    return "";
  }
}

Future<String> getSignUpInformation() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Sign Ups/");

  try
  {
    var event = await newClient.child("Information").once();
    var status = event.snapshot.value as String;
    return status;
  }
  catch (e)
  {
    return "";
  }
}

Future<UserInformation?> getInformation() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  try
  {
    var event = await newClient.child("Users/${auth.credential!.user!.uid}/Information/").once();
    var info = event.snapshot.value as Map<dynamic, dynamic>;
    var result = UserInformation();
    result.age = info["Age"] ?? info["age"];
    result.height = info["Height"] ?? info["height"];
    result.basketballPosition = info["BasketballPosition"] ?? info["basketballPosition"] ?? "";
    result.futsalPosition = info["FutsalPosition"] ?? info["futsalPosition"] ?? "";
    return result;
  }
  catch (e)
  {
      return null;
  }
}

Future<void> addUpdateInfo(UserInformation information, String phone) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("Users/${auth.credential!.user!.uid}");
  try
  {
    var client = newClient.child("/Information/");
    await client.set(information);
    var phoneClient = newClient.child("/Phone Number/");
    await phoneClient.set(phone);
  }
  catch (e)
  {

  }
}

Future<void> signUpToPlay(String league, String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("Sign Ups/$league/$season/NotPaid/${auth.credential!.user!.uid}");

  try
  {
    await newClient.set(auth.credential!.user!.displayName);
  }
  catch (e)
  {

  }
}

Future<void> setImage(User user, FileImage fileImage) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  Reference storage = FirebaseStorage.instance.ref();
  try
  {
    var storageUser = storage.child("Users").child(user.uid).child("profileimage.jpg");
    await storageUser.putFile(fileImage.file);
    var url = await storageUser.getDownloadURL();

    await user.updatePhotoURL(url);

  }
  catch (e)
  {
    var mess = e.toString();
  }
}

Future<void> createDatabaseLocation(User user, FileImage? fileImage, String phoneNumber) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  if (fileImage != null) {
    await setImage(user, fileImage);
  }

  var firstClient = newClient.child("Users/${user.uid}/First Name");

  await firstClient.set(user.displayName!.split(' ')[0]);

  var lastClient = newClient.child("Users/${user.uid}/Last Name");

  await lastClient.set(user.displayName!.split(' ')[1]);

  var numberClient = newClient.child("Users/${user.uid}/Phone Number");

  await numberClient.set(phoneNumber);

  var dateClient = newClient.child("Users/${user.uid}/Date Joined");

  await dateClient.set(DateTime.now().toString());
}

Future<void> uploadToken(User user, String token) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  try
  {
      var dateClient = newClient.child("Users/${user.uid}/Token");

      await dateClient.set(token);
  }
  catch (e) {

  }
}

Future<void> addComment(String league, String season, String comment) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var client = newClient.child("Sign Ups/$league/$season/Comments/${auth.credential!.user!.displayName!}");

  try
  {
      await client.set("${auth.credential!.user!.uid}:$comment");
  }
  catch (e)
  {

  }
}

Future<bool> isSignedUp(User user, String league, String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var client = newClient.child("Sign Ups/$league/$season/NotPaid/");
  var client2 = newClient.child("Sign Ups/$league/$season/Paid/");

  try
  {
    var event = await client.once();
    var listNP = event.snapshot.value as Map;
    event = await client2.once();
    var listP = event.snapshot.value ?? {};

    return ((listP as Map).containsKey(user.uid) || listNP.containsKey(user.uid));
  }
  catch (e) 
  {
    return false;
  }
}

Future<String?> getPhone() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("");
  try
  {
    var event = await newClient.child("Users/${auth.credential!.user!.uid}/Phone Number/").once();
    var info = event.snapshot.value.toString();

      return info;
  }
  catch (e)
  {
      return null;
  }
}

Future<String> getSignUpRules() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Sign Ups/");

  try
  {
    var event = await newClient.child("Rules").once();
    var status = event.snapshot.value as String;
    return status;
  }
  catch (e)
  {
    return "";
  }
}

Future<String> getSignUpWaiver() async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Sign Ups/");

  try
  {
    var event = await newClient.child("Waiver").once();
    var status = event.snapshot.value as String;
    return status;
  }
  catch (e)
  {
    return "";
  }
}

Future<String> getSeason(league) async {
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  try
  {
      var event = await newClient.child(league + " Season").once();
      var seasonNum = event.snapshot.value.toString();
      return seasonNum;
  }
  catch (e)
  {
    return "";
  }
}

Future<Map<dynamic, dynamic>> getOtherSignups() async {
  try {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var event = await newClient.child("Sign Ups").once();
    var status = event.snapshot.value as Map<dynamic, dynamic>;
  return status;
  } catch (e) {
    return {};
  }
}

Future<List<Business>> getBusinesses() async {
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var businesses = List<Business>.empty(growable: true);
  try {
    var event = await newClient.child("Map").once();
    var list = event.snapshot.value as List;
    list.forEach((value) {
      Business business = Business();
      business.description = value["Description"] ?? "";
      business.logoUrl = value["LogoUrl"] ?? "";
      business.name = value["Name"] ?? "";
      business.url = value["Url"];
      business.phone = value["Phone"] ?? "";
      business.lat = value["Lat"] ?? double.nan;
      business.long = value["Long"] ?? double.nan;
      if (business.logoUrl != null) {
        business.logo = Image.network(business.logoUrl!);
      }
      businesses.add(business);
    });
    return businesses;
  } catch (e) {
    return businesses;
  }
}

Future<List<Event>> getEvents() async {
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var events = List<Event>.empty(growable: true);
  try {
    var snapshot = await newClient.child("Events").once();
    var list = snapshot.snapshot.value as List;
    list.forEach((value) {
      Event event = Event();
      event.address = value["Address"] ?? "";
      event.date = value["Date"] ?? "";
      event.endTime = value["EndTime"] ?? "";
      event.eventDate = value["EventDate"] ?? "";
      event.imageUrl = value["ImageUrl"] ?? "";
      event.info = value["Info"] ?? "";
      event.location = value["Location"] ?? "";
      event.startTime = value["StartTime"] ?? "";
      event.endTime = value["EndTime"] ?? "";
      event.title = value["Title"] ?? "";
      event.format();
      events.add(event);
    });
    return events.reversed.toList();
  } catch (e) {
    return events.reversed.toList();
  }
}