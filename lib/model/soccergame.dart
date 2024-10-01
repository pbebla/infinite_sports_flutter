import 'dart:ui';

import 'package:infinite_sports_flutter/model/game.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';

class SoccerGame implements Game {
  @override
  late int GameNum;

  @override
  late Color ProgressColor1;

  @override
  late Color ProgressColor2;

  @override
  late int Time;

  String startTime = "";

  String location = "";
  String type = "";

  @override
  String UrlPath = "";

  @override
  String date = "";

  @override
  double finalvote1 = 0.0;

  @override
  double finalvote2 = 0.0;

  @override
  String stringStatus = "";

  @override
  String link = "";

  @override
  String percvote1 = "";

  @override
  String percvote2 = "";

  @override
  late bool signedIn;

  @override
  late int status;

  @override
  late Color statusColor;

  @override
  String team1 = "";

  @override
  String team1SourcePath = "";

  @override
  Map<dynamic, dynamic> team1activity = {};

  @override
  String team1score = "";

  @override
  Map<dynamic, dynamic> team1vote = {};

  @override
  String team2 = "";

  @override
  String team2SourcePath = "";

  @override
  Map<dynamic, dynamic> team2activity = {};

  @override
  String team2score = "";

  @override
  Map<dynamic, dynamic> team2vote = {};

  @override
  int vote1 = 0;

  @override
  int vote2 = 0;

  @override
  late bool voted;

  Map<String, SoccerPlayer> team1lineup = {};

  Map<String, SoccerPlayer> team2lineup = {};

  @override
  void getLineUpImages() async {
  }

  @override
  void setUpVote()
{
    //signedIn = Utility.LoggedInUser != null;
    signedIn = false;
    if (team1vote.isNotEmpty)
    {
        vote1 = team1vote.values.reduce((value, element) => value + element);
    }
    else
    {
        vote1 = 0;
    }

    if (team2vote.isNotEmpty)
    {
        vote2 = team2vote.values.reduce((value, element) => value + element);
    }
    else
    {
        vote2 = 0;
    }

    if (team1vote.isNotEmpty && team2vote.isNotEmpty && signedIn)
    {
        //voted = !((new List<string>(team1vote.Keys).Contains(Utility.LoggedInUser.User.Uid)) || (new List<string>(team2vote.Keys).Contains(Utility.LoggedInUser.User.Uid)));
    }
    else if (team1vote.isNotEmpty && signedIn)
    {
        //voted = !(new List<string>(team1vote.Keys).Contains(Utility.LoggedInUser.User.Uid));
    }
    else if (team2vote.isNotEmpty && signedIn)
    {
        //voted = !(new List<string>(team2vote.Keys).Contains(Utility.LoggedInUser.User.Uid));
    }
    else
    {
        voted = true;
    }

    signedIn = signedIn && voted;

    if ((vote1 + vote2) != 0)
    {
        finalvote1 = ((vote1 + vote2) - vote2) / ((vote1 + vote2));
        finalvote2 = 1 - finalvote1;

        percvote1 = "${(finalvote1 * 100).round()}%";
        percvote2 = "${(finalvote2 * 100).round()}%";
    }
    else
    {
        finalvote1 = 1.0;
        finalvote2 = 1.0;

        percvote1 = "0%";
        percvote2 = "0%";
    }

    ProgressColor1 = const Color(0xFFD80000);
    ProgressColor2 = const Color(0xFFD80000);
}
  
}

/*namespace InfiniteSportsApp
{
    public class FutsalGame : Game
    {
        public string date { get; set; }

        public string team1 { get; set; }

        public string team2 { get; set; }

        public string team1score { get; set; }

        public string team2score { get; set; }

        public int status { get; set; }

        public string stringStatus { get; set; }

        public Color statusColor { get; set; }

        public ImageSource team1Source { get; set; }

        public ImageSource team2Source { get; set; }

        public Dictionary<string, List<Dictionary<string, string>>> team1activity { get; set; }

        public Dictionary<string, List<Dictionary<string, string>>> team2activity { get; set; }

        public Dictionary<string, FutsalPlayer> team1lineup { get; set; }

        public Dictionary<string, FutsalPlayer> team2lineup { get; set; }

        public Dictionary<string, object> team1vote { get; set; }
        public Dictionary<string, object> team2vote { get; set; }

        public bool signedIn { get; set; }

        public int vote1 { get; set; }
        public int vote2 { get; set; }
        public bool voted { get; set; }
        public double finalvote1 { get; set; }
        public double finalvote2 { get; set; }
        public string percvote1 { get; set; }
        public string percvote2 { get; set; }

        public Color ProgressColor1 { get; set; }
        public Color ProgressColor2 { get; set; }

        public string UrlPath { get; set; }
        public int GameNum { set; get; }
        public int Time { get; set; }
        public string link { get; set; }

        public async void GetLineUpImages()
        {
            if (team1lineup == null || team2lineup == null)
            {
                return;
            }

            foreach (var player in team1lineup)
            {
                if (player.Value.UID != null)
                {
                    try
                    {
                        if (player.Value.ProfileImage == null)
                        {
                            player.Value.ProfileImage = ImageSource.FromUri(new Uri(await ProfileHelper.GetProfileURL(player.Value.UID)));
                        }
                    }
                    catch
                    {
                        player.Value.ProfileImage = "PortraitPlaceholder.png";
                    }
                }
                else
                {
                    player.Value.ProfileImage = "PortraitPlaceholder.png";
                }

            }

            foreach (var player in team2lineup)
            {
                if (player.Value.UID != null)
                {
                    try
                    {
                        if (player.Value.ProfileImage == null)
                        {
                            player.Value.ProfileImage = ImageSource.FromUri(new Uri(await ProfileHelper.GetProfileURL(player.Value.UID)));
                        }
                    }
                    catch
                    {
                        player.Value.ProfileImage = "PortraitPlaceholder.png";
                    }
                }
                else
                {
                    player.Value.ProfileImage = "PortraitPlaceholder.png";
                }

            }
        }

        public void SetUpVote()
        {
            signedIn = Utility.LoggedInUser != null;

            if (team1vote != null){
                vote1 = team1vote.Count;
            }
            else{
                vote1 = 0;
            }

            if (team2vote != null)
            {
                vote2 = team2vote.Count;
            }
            else
            {
                vote2 = 0;
            }

            if (team1vote != null && team2vote != null && signedIn)
            {
                voted = !((new List<string>(team1vote.Keys).Contains(Utility.LoggedInUser.User.Uid)) || (new List<string>(team2vote.Keys).Contains(Utility.LoggedInUser.User.Uid)));
            }
            else if (team1vote != null && signedIn)
            {
                voted = !(new List<string>(team1vote.Keys).Contains(Utility.LoggedInUser.User.Uid));
            }
            else if (team2vote != null && signedIn)
            {
                voted = !(new List<string>(team2vote.Keys).Contains(Utility.LoggedInUser.User.Uid));
            }
            else
            {
                voted = true;
            }

            signedIn = signedIn && voted;

            if ((vote1 + vote2) != 0)
            {
                finalvote1 = ((vote1 + vote2) - vote2) / ((double)(vote1 + vote2));
                finalvote2 = 1 - finalvote1;

                percvote1 = (Math.Round(finalvote1, 2) * 100) + "%";
                percvote2 = (Math.Round(finalvote2, 2) * 100) + "%";
            }
            else
            {
                finalvote1 = 1;
                finalvote2 = 1;

                percvote1 = "0%";
                percvote2 = "0%";
            }
            ProgressColor1 = Color.FromHex("#D80000");
            ProgressColor2 = Color.FromHex("#D80000"); 
        }
    }
}*/
