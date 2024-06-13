
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_application/model/game.dart';

class BasketballGame implements Game
{
  @override
  late int GameNum;

  @override
  late Color ProgressColor1;

  @override
  late Color ProgressColor2;

  @override
  late int Time;

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
  Map<String, List<Map<String, String>>> team1activity = {};

  @override
  String team1score = "";

  @override
  Map<dynamic, dynamic> team1vote = {};

  @override
  String team2 = "";

  @override
  String team2SourcePath = "";

  @override
  Map<String, List<Map<String, String>>> team2activity = {};

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

  //late Map<String, BasketballPlayer> team1lineup;
  //late Map<String, BasketballPlayer> team2lineup;

  @override
  void GetLineUpImages() async {
  }

  @override
  void SetUpVote() {
    // TODO: implement SetUpVote
  }
  
}
/*
public async void GetLineUpImages()
{
    if(team1lineup == null || team2lineup == null)
    {
        return;
    }

    foreach (var player in team1lineup)
    {
        player.Value.GetPercentage();

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
        player.Value.GetPercentage();

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

    if (team1vote != null)
    {
        vote1 = team1vote.Count;
    }
    else
    {
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
*/
