
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/flagfootballgame.dart';
import 'package:infinite_sports_flutter/model/flagfootballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/game.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/model/soccergame.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
import 'package:intl/intl.dart';
import 'dart:async';


var infiniteSportsPrimaryColor = const Color.fromARGB(255, 208, 0, 0);
// Dark mode swaps red accents for gold (owner's black & gold dark theme).
// Light mode keeps the brand red everywhere.
var infiniteSportsGoldColor = const Color(0xFFE3B84C);

/// Brand accent for the current brightness: red in light, gold in dark.
/// Prefer Theme.of(context).colorScheme.primary (already brightness-aware);
/// use this only where no ColorScheme is in play.
Color brandAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? infiniteSportsGoldColor
        : infiniteSportsPrimaryColor;

/// Header bar background: brand red in light mode, near-black surface in
/// dark mode (black & gold treatment).
Color appBarBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainer
        : infiniteSportsPrimaryColor;

/// Foreground (title/icons) that pairs with [appBarBackground]:
/// white on red in light mode, gold on black in dark mode.
Color appBarForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? infiniteSportsGoldColor
        : Colors.white;

/// Text/icon color for content sitting on a brand-accent fill (buttons,
/// banners): white on red in light mode, near-black on gold in dark mode.
Color onBrandAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1A1206)
        : Colors.white;

Map<String, Map<String, Map<String, FutsalPlayer>>> futsalLineups = {};
Map<String, Map<String, Map<String, BasketballPlayer>>> basketballLineups = {};
Map<String, Map<String, Map<String, FlagFootballPlayer>>> flagFootballLineups = {};
Map teamLogos = {};
FirebaseAuthService auth = FirebaseAuthService();
bool signedIn = false;
bool darkModeEnabled = false;
BuildContext? mainContext;
BuildContext? mainScaffoldContext;

/// True for the duration of an in-flight signup flow (email, Google, or
/// Apple) — from the moment the account is created/signed-in until the
/// flow's own final step (About You, then favorites) finishes. While true,
/// `MyHomePage._setupNotificationPrefs` (lib/main.dart) skips its one-time
/// "complete your profile" gate entirely: that gate reads `Users/<uid>` the
/// instant `authStateChanges()` flips to signed-in, which can race the
/// signup flow's own writes to that same node (the flow hasn't written
/// `ProfileCompleted`/`Phone Number` yet), causing the gate to push its own
/// stale duplicate About You page on top of the flow's (auth-wall F2 fix).
/// Returning users never set this flag, so the gate always runs normally
/// for them.
bool onboardingFlowActive = false;

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

/// Fetches the list of seasons / tournaments a user has played in.
/// Reads from /Users/{uid}/Played. Returns an empty list on error or
/// malformed data. Each entry is {'season': String, 'sport': String,
/// 'team': String}.
Future<List<Map<String, String>>> getUserPlayedHistory(String uid) async {
  try {
    final ref = FirebaseDatabase.instance.ref('/Users/$uid/Played');
    final snap = await ref.get();
    if (snap.value == null) return [];
    if (snap.value is! Map) return [];
    final data = snap.value as Map;
    final result = <Map<String, String>>[];
    data.forEach((k, v) {
      if (v is Map) {
        result.add({
          'season': k.toString(),
          'sport': v['Sport']?.toString() ?? v['sport']?.toString() ?? '',
          'team': v['Team']?.toString() ?? v['team']?.toString() ?? '',
        });
      }
    });
    return result;
  } catch (e) {
    debugPrint('getUserPlayedHistory error: $e');
    return [];
  }
}

/// Parses a Firebase MMDDYYYY string into a DateTime. Returns null
/// when the input is not 8 digits or any segment is non-numeric.
DateTime? parseDatabaseDate(String databaseDate) {
  if (databaseDate.length != 8) return null;
  final m = int.tryParse(databaseDate.substring(0, 2));
  final d = int.tryParse(databaseDate.substring(2, 4));
  final y = int.tryParse(databaseDate.substring(4, 8));
  if (m == null || d == null || y == null) return null;
  return DateTime.utc(y, m, d);
}

/// "08272026" -> "Thursday, August 27". Falls back to the raw string.
String formatDayHeading(String mmddyyyy) {
  final dt = parseDatabaseDate(mmddyyyy);
  if (dt == null) return mmddyyyy;
  return DateFormat('EEEE, MMMM d').format(dt);
}

String convertDatabaseDateToFormatDate(String databaseDate) {
  final dt = parseDatabaseDate(databaseDate);
  if (dt == null) return databaseDate;
  return DateFormat.yMMMMd('en_US').format(dt);
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

Future<String> getAFCCurrentSeason() async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/AFC San Jose/");
    var seasonNum = await newClient.child("Current Season").get();
    return seasonNum.value.toString();
  }
  catch (e)
  {
    return e.toString();
  }
}

Future<bool> isAFCSeasonFinished(season) async {
  try
  {

    DatabaseReference newClient = FirebaseDatabase.instance.ref("/AFC San Jose/Seasons/$season");
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
  var now = DateTime.now();

  List<String> dates = await getDates(sport, season);
  dates.sort((a, b) => DateTime.parse(a.substring(4)+a.substring(0,2)+a.substring(2,4)).compareTo(DateTime.parse(b.substring(4)+b.substring(0,2)+b.substring(2,4))));
  int i = 0;
  while (i < dates.length) {
    var converted = DateTime.parse(dates[i].substring(4)+dates[i].substring(0,2)+dates[i].substring(2,4));
    if (DateUtils.isSameDay(now, converted)) {
      return dates[i];
    } else if (now.compareTo(converted) == 1){
      i+=1;
    } else {
      return dates[i];
    }
  }
  return dates[dates.length-1];
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
    if (event.snapshot.value == null) return [];
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
      temp.number = info["Number"]?.toString() ?? '';
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

Future<void> getAllFlagFootballLineUps(String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("/Flag Football/$season");
  var event = await newClient.child("Line Ups").once();
  var lineups = event.snapshot.value as Map;
  Map<String, Map<String, FlagFootballPlayer>> result = {};
  lineups.forEach((team, lineup) {
    Map<String, FlagFootballPlayer> temp = {};
    (lineup as Map).forEach((name, info) {
      FlagFootballPlayer temp2 = FlagFootballPlayer();
      temp2.name = name;
      temp2.number = info["number"]?.toString() ?? '0';
      temp2.uid = info["UID"] ?? '0';
      // P4 FF stat-key fix: the Manager writes SHORT keys (REC, RECTD,
      // QBComp, ...). Read those first; fall back to the legacy long
      // names so pre-Manager seasons still render.
      temp2.receptions = info["REC"] ?? info["Receptions"] ?? 0;
      temp2.receivingTouchdowns =
          info["RECTD"] ?? info["Receiving Touchdowns"] ?? 0;
      temp2.receptionMisses = info["RECMiss"] ?? info["Receiver Miss"] ?? 0;
      temp2.passingTouchdowns =
          info["PassTD"] ?? info["Passing Touchdowns"] ?? 0;
      temp2.qbCompletions = info["QBComp"] ?? info["QB Completions"] ?? 0;
      temp2.qbIncompletions = info["QBInc"] ?? info["QB Incomplete"] ?? 0;
      temp2.interceptions = info["INT"] ?? info["Interceptions"] ?? 0;
      temp2.flagPulls = info["FP"] ?? info["Flag Pulls"] ?? 0;
      temp2.passBreakups = info["PBU"] ?? info["Pass Breakups"] ?? 0;
      temp2.sacks = info["Sack"] ?? info["Sacks"] ?? 0;
      // Never parsed before P4 (model fields existed all along):
      temp2.passingInterceptions = info["PassINT"] ?? 0;
      temp2.rushingTouchdowns = info["RushTD"] ?? 0;
      temp2.interceptionTouchdowns = info["INTTD"] ?? 0;
      temp2.pointAfterTouchdownMakes = info["PAT1"] ?? 0;
      temp2.pointAfterTouchdownMisses = info["PAT1Miss"] ?? 0;
      temp2.twoPointConversions = info["TwoPT"] ?? 0;
      temp2.getCompletionPercentage();
      temp2.getCatchRate();
      temp[name] = temp2;
    });
    result[team] = temp;
  },);

  flagFootballLineups[season] = result;
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
      temp2.number = (info["number"] ?? '0').toString();
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
  else if (sport == "Flag Football")
  {
    var all = await getAllFlagFootballGames(sport, season);
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

    game.databaseReference = FirebaseDatabase.instance
      .ref(sport)
      .child(season)
      .child("Date")
      .child(date);

    game.GameNum = i;

    game.setUpVote();
    //game.getLineUpImages();
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
        game.storedTime = (val["Time"] ?? "").toString();
        game.stage = (val["Stage"] ?? "").toString();
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
        game.storedTime = (val["Time"] ?? "").toString();
        game.stage = (val["Stage"] ?? "").toString();
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

Future<Map<String, List<FlagFootballGame>>> getAllFlagFootballGames(sport, season) async {
  try
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
    var games = await newClient.child("Date").get();
    dynamic data = games.value;
    var result = <String, List<FlagFootballGame>>{};
    data.forEach((key, value) {
      var list = <FlagFootballGame>[];
      for (var val in value) {
        var game = FlagFootballGame();
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
        game.storedTime = (val["Time"] ?? "").toString();
        game.stage = (val["Stage"] ?? "").toString();
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
  if (game is FlagFootballGame) {
    try
    {
      game.team1lineup = await getFlagFootballLineUp(season, game.team1);
      game.team2lineup = await getFlagFootballLineUp(season, game.team2);

      if (game.team1SourcePath == "")
      {
        await getAllTeamLogo();
        var flagFootball = teamLogos["Flag Football"];
        var logos = flagFootball[season];

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

Future<Map<String, FlagFootballPlayer>> getFlagFootballLineUp(season, team) async {
  await getAllFlagFootballLineUps(season);
  Map<String, FlagFootballPlayer> lineup = flagFootballLineups[season]?[team] ?? {};
  return lineup;
}

Future<Map<String, BasketballPlayer>> getBasketballLineUp(season, team) async {
  await getAllBasketballLineUps(season);
  Map<String, BasketballPlayer> lineup = basketballLineups[season]?[team] ?? {};
  return lineup;
}

Future<void> getAllTeamLogo() async
{
  if (teamLogos.isNotEmpty) return;

  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  var event = await newClient.child("Logo Urls").once();
  final raw = event.snapshot.value;
  if (raw is Map) teamLogos = raw;

  newClient = FirebaseDatabase.instance.ref("AFC San Jose");
  var afcEvent = await newClient.child("Logo URL").once();
  final afcLogo = afcEvent.snapshot.value;
  if (afcLogo != null) teamLogos["AFC San Jose"] = afcLogo.toString();
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
        r"^https?:\/\/(?:www\.|m\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https?:\/\/(?:music\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https?:\/\/(?:www\.|m\.)?youtube\.com\/shorts\/([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(
        r"^https?:\/\/(?:www\.|m\.)?youtube(?:-nocookie)?\.com\/embed\/([_\-a-zA-Z0-9]{11}).*$"),
    RegExp(r"^https?:\/\/youtu\.be\/([_\-a-zA-Z0-9]{11}).*$")
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
    var event = await newClient.child("Users/${FirebaseAuth.instance.currentUser!.uid}/Information/").once();
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
  DatabaseReference newClient = FirebaseDatabase.instance.ref("Users/${FirebaseAuth.instance.currentUser!.uid}");
  try
  {
    var client = newClient.child("/Information/");
    Map<String, dynamic> infoList = {
      "Age" : information.age,
      "Height": information.height,
      "FutsalPosition" : information.futsalPosition,
      "BasketballPosition": information.basketballPosition
    };
    await client.set(infoList);
    var phoneClient = newClient.child("/Phone Number/");
    await phoneClient.set(phone);
  }
  catch (e)
  {

  }
}

Future<void> signUpToPlay(String league, String season) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref("Sign Ups/$league/$season/NotPaid/${FirebaseAuth.instance.currentUser!.uid}");

  try
  {
    await newClient.set(FirebaseAuth.instance.currentUser!.displayName);
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
    var imageCLient = newClient.child("Users/${user.uid}/ProfileUrl");
    await imageCLient.set(url);

  }
  catch (e)
  {
    var mess = e.toString();
  }
}

Future<void> removeImage(User user) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  Reference storage = FirebaseStorage.instance.ref();
  try
  {
    var storageUser = storage.child("Users").child(user.uid).child("profileimage.jpg");
    await storageUser.delete();
    var imageCLient = newClient.child("Users/${user.uid}/ProfileUrl");
    await imageCLient.remove();
    await user.updatePhotoURL(null);

  }
  catch (e)
  {
    var mess = e.toString();
  }
}

Future<void> createDatabaseLocation(User user, FileImage? fileImage, String phoneNumber, String firstName, String lastName) async
{
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  if (fileImage != null) {
    await setImage(user, fileImage);
  }

  var firstClient = newClient.child("Users/${user.uid}/First Name");

  await firstClient.set(firstName);

  var lastClient = newClient.child("Users/${user.uid}/Last Name");

  await lastClient.set(lastName);

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
  var client = newClient.child("Sign Ups/$league/$season/Comments/${FirebaseAuth.instance.currentUser!.displayName!}");

  try
  {
    await client.set("${FirebaseAuth.instance.currentUser!.uid}:$comment");
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
    var event = await newClient.child("Users/${FirebaseAuth.instance.currentUser!.uid}/Phone Number/").once();
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
    for (var value in list) {
      Business business = Business();
      business.description = value["Description"] ?? "";
      business.logoUrl = value["LogoUrl"] ?? "";
      business.name = value["Name"] ?? "";
      business.url = value["Url"];
      business.phone = value["Phone"] ?? "";
      business.lat = value["Lat"] ?? double.nan;
      business.long = value["Long"] ?? double.nan;
      if (business.logoUrl != null) {
        business.logo = Image.network(business.logoUrl!, errorBuilder:(context, error, stackTrace) => SizedBox(width: 0, height: 0));
      }
      businesses.add(business);
    }
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
    for (var value in list) {
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
      if ((value as Map).containsKey("Attendees")) {
        event.attendees = {};
        value["Attendees"].forEach((uid, value) {
          event.attendees![uid] = value.toString();
        });
      }
      event.format();
      events.add(event);
    }
    return events.toList();
  } catch (e) {
    return events.toList();
  }
}

Future<Event> getEvent(index) async {
  List<Event> events = await getEvents();
  return events[index];
}

Future<Map<String, MyUser>> getAllUsers() async {
  DatabaseReference newClient = FirebaseDatabase.instance.ref();
  Map<String, MyUser> users = {};
  try
  {
    var event = await newClient.child("Users").once();
    var list = event.snapshot.value as Map;
    list.forEach((uid, info) {
      if(info.containsKey("ProfileUrl")) {
        users[uid] = MyUser(info["First Name"] ?? "", info["Last Name"] ?? "", info["Date Joined"] ?? "", uid, info["ProfileUrl"]);
      } else {
        users[uid] = MyUser(info["First Name"] ?? "", info["Last Name"] ?? "", info["Date Joined"] ?? "", uid);
      }
    });
    return users;
  }
  catch (e)
  {
    return users;
  }
}
