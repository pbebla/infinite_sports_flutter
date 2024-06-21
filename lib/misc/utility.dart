import 'package:firebase_database/firebase_database.dart';

String tableSport = "";
String tableSeason = "";

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