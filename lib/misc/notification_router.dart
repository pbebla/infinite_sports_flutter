import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';

/// Message that launched the app from a terminated state; routed by
/// MyHomePage once the first frame (and mainContext) exists.
RemoteMessage? pendingLaunchMessage;

/// Opens the match page for a Watcher notification payload
/// `{type, tournamentId, matchId}`. Silently no-ops on bad payloads —
/// a tap must never crash the app.
Future<void> openMatchFromNotification(Map<String, dynamic> data) async {
  final tid = data['tournamentId']?.toString() ?? '';
  final mid = data['matchId']?.toString() ?? '';
  if (tid.isEmpty || mid.isEmpty) return;
  try {
    final results = await Future.wait([
      TournamentService.getTournamentHeader(tid),
      TournamentService.getTeams(tid),
      TournamentService.getMatches(tid),
    ]);
    final tournament = results[0] as Tournament?;
    final teams = results[1] as Map<String, TournamentTeam>;
    final matches = results[2] as List<TournamentMatch>;
    TournamentMatch? match;
    for (final m in matches) {
      if (m.id == mid) {
        match = m;
        break;
      }
    }
    if (match == null) return;
    final rosters = await TournamentService.getRosters(tid, teams);
    final ctx = mainContext;
    if (ctx == null) return;
    Navigator.of(ctx, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => TournamentMatchDetailPage(
        match: match!,
        teams: teams,
        rosters: rosters,
        tournamentId: tid,
        sport: tournament?.sport ?? 'Soccer',
      ),
    ));
  } catch (e) {
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
