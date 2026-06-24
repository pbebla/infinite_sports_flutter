import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Renders [ShareMatchCard] offscreen to a PNG and opens the system share sheet.
/// Never throws; shows a SnackBar on failure.
Future<void> shareMatchCard(
  BuildContext context, {
  required TournamentMatch match,
  required TournamentTeam? team1,
  required TournamentTeam? team2,
  required String tournamentName,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
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

    final bytes = await _capture(
      context,
      ShareMatchCard(
        match: match,
        team1: team1,
        team2: team2,
        tournamentName: tournamentName,
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/match_card_${match.id}.png');
    await file.writeAsBytes(bytes);

    final text = buildShareText(
      match: match,
      team1Name: team1?.name ?? match.team1Id ?? 'TBD',
      team2Name: team2?.name ?? match.team2Id ?? 'TBD',
      tournamentName: tournamentName,
    );

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't create the share card.")),
    );
  }
}

Future<Uint8List> _capture(BuildContext context, Widget card) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(key: key, child: card),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
