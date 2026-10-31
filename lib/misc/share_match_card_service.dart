import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';

/// Caption text shared alongside the image. Pure.
String buildShareText({
  required TournamentMatch match,
  required String team1Name,
  required String team2Name,
  required String tournamentName,
}) {
  final mid = tournamentName.isNotEmpty ? ' · $tournamentName' : '';
  final s = match.matchStatus;
  if (s.isFinished || s.isLive) {
    return '$team1Name ${match.team1Score}–${match.team2Score} $team2Name$mid'
        ' — follow live on Infinite Sports.';
  }
  return '$team1Name vs $team2Name$mid — follow live on Infinite Sports.';
}

/// Renders [ShareMatchCard] offscreen to a PNG and opens the system share sheet
/// (the shared pipeline in share_card_service.dart, anchored to [context] for
/// the iPad popover). Never throws; shows a SnackBar on failure.
Future<void> shareMatchCard(
  BuildContext context, {
  required TournamentMatch match,
  required TournamentTeam? team1,
  required TournamentTeam? team2,
  required String tournamentName,
  required String sport,
}) async {
  ScaffoldMessengerState? messenger;
  try {
    // Both context lookups sit INSIDE the try (a stale context asserts) and
    // run NOW, before any await — the "never throws" contract has no hole.
    messenger = ScaffoldMessenger.maybeOf(context);
    final origin = shareOriginFor(context);
    await Future.wait([
      precacheImage(const AssetImage('assets/goal.png'), context),
      precacheImage(const AssetImage('assets/assist.png'), context),
      precacheImage(const AssetImage('assets/dpl.png'), context),
      precacheImage(const AssetImage('assets/save.png'), context),
    ]);
    for (final url in [team1?.logoUrl, team2?.logoUrl]) {
      if (url != null && url.isNotEmpty && context.mounted) {
        try {
          await precacheImage(NetworkImage(url), context);
        } catch (_) {/* logo will fall back to shield */}
      }
    }
    if (!context.mounted) return;

    final bytes = await captureCardToPng(
      context,
      ShareMatchCard(
        match: match,
        team1: team1,
        team2: team2,
        tournamentName: tournamentName,
        sport: sport,
      ),
    );

    final text = buildShareText(
      match: match,
      team1Name: team1?.name ?? match.team1Id ?? 'TBD',
      team2Name: team2?.name ?? match.team2Id ?? 'TBD',
      tournamentName: tournamentName,
    );

    await sharePngWithSystemSheet(
      bytes,
      caption: text,
      fileName: 'match_card_${match.id}.png',
      origin: origin,
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't create the share card.")),
    );
  }
}
