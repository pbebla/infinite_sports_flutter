import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

/// The "Share match" icon in the league and tournament match pages' app bars.
///
/// One widget for both pages so the iPad share popover anchors to THIS icon:
/// this widget's own [BuildContext] (not the page's) is what [shareMatchCard]
/// measures for `sharePositionOrigin` (a StatelessWidget's context resolves to
/// the first render object beneath it, here the IconButton's), and share_plus
/// REJECTS an iPad share without a non-empty origin. [share] replaces the
/// system sheet (tests).
class MatchShareButton extends StatelessWidget {
  const MatchShareButton({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.tournamentName,
    required this.sport,
    this.share,
  });

  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final String tournamentName;
  final String sport;
  final SharePng? share;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.ios_share),
      tooltip: 'Share match',
      onPressed: () => shareMatchCard(
        context,
        match: match,
        team1: team1,
        team2: team2,
        tournamentName: tournamentName,
        sport: sport,
        share: share,
      ),
    );
  }
}
