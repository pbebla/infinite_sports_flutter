import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Message that launched the app from a terminated state; routed by
/// MyHomePage once the first frame (and mainContext) exists.
RemoteMessage? pendingLaunchMessage;

/// Opens the match page for a Watcher notification payload
/// `{type, tournamentId, matchId}`. Silently no-ops on bad payloads —
/// a tap must never crash the app. Shows an immediate loading overlay so the
/// tap always gives instant feedback while the match data downloads.
Future<void> openMatchFromNotification(Map<String, dynamic> data) async {
  // Campaign / event payloads (P4). A campaign that names an event, or an
  // event reminder, deep-links to the event; a plain campaign just opened
  // the app (no navigation target).
  final type = data['type']?.toString() ?? '';
  if (type == 'event' || type == 'campaign') {
    final eventId = data['eventId']?.toString() ?? '';
    final ctx = mainContext;
    if (eventId.isNotEmpty && ctx != null) {
      Navigator.of(ctx, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => EventPage(v2Id: eventId)),
      );
    }
    return;
  }

  // League watcher payloads (P3) carry sport/season/dateKey/gameIndex —
  // route straight to the league match page (it self-streams + has its
  // own skeleton, so no preloading dialog is needed).
  final sport = data['sport']?.toString() ?? '';
  if (sport.isNotEmpty) {
    final season = data['season']?.toString() ?? '';
    final dateKey = data['dateKey']?.toString() ?? '';
    final gameIndex = int.tryParse(data['gameIndex']?.toString() ?? '');
    final leagueCtx = mainContext;
    if (season.isEmpty || dateKey.isEmpty || gameIndex == null ||
        leagueCtx == null) {
      return; // bad payload: a tap must never crash the app
    }
    Navigator.of(leagueCtx, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => LeagueMatchDetailPage(
        sport: sport,
        season: season,
        dateKey: dateKey,
        gameIndex: gameIndex,
      ),
    ));
    return;
  }

  final tid = data['tournamentId']?.toString() ?? '';
  final mid = data['matchId']?.toString() ?? '';
  if (tid.isEmpty || mid.isEmpty) return;
  final ctx = mainContext;
  if (ctx == null) return;
  final navigator = Navigator.of(ctx, rootNavigator: true);
  var loadingShown = true;
  showDialog(
    context: ctx,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogCtx) => PopScope(
      canPop: false,
      child: Material(
        color: Theme.of(dialogCtx).colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: const [
              SizedBox(height: 16),
              SkeletonMatchList(count: 3),
            ],
          ),
        ),
      ),
    ),
  );
  void dismissLoading() {
    if (loadingShown) {
      loadingShown = false;
      navigator.pop();
    }
  }

  try {
    // One whole-node read — the header get here used to overlap its own
    // Teams/Table/Matches child gets, the exact race firebase-ios-sdk
    // mishandles (see TournamentService.getTournamentBundle). Avatar
    // enrichment still rides behind the single fetch.
    final bundle = await TournamentService.getTournamentBundle(tid);
    final tournament = bundle.tournament;
    final teams = bundle.teams;
    final matches = bundle.matches;
    final rosters = await TournamentService.enrichRosterPhotos(
        TournamentService.parseRosters(bundle.rostersNode, teams));
    TournamentMatch? match;
    for (final m in matches) {
      if (m.id == mid) {
        match = m;
        break;
      }
    }
    if (match == null) {
      dismissLoading();
      return;
    }
    dismissLoading();
    navigator.push(MaterialPageRoute(
      builder: (_) => TournamentMatchDetailPage(
        match: match!,
        teams: teams,
        rosters: rosters,
        tournamentId: tid,
        sport: tournament?.sport ?? 'Soccer',
      ),
    ));
  } catch (e) {
    dismissLoading();
    debugPrint('openMatchFromNotification failed: $e');
  }
}

/// For local-notification taps where the payload is the JSON-encoded
/// `message.data` (see main.dart onMessage handler).
Future<void> openMatchFromPayloadString(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    await openMatchFromNotification(data);
  } catch (e) {
    debugPrint('openMatchFromPayloadString failed: $e');
  }
}
