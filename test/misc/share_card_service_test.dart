// The ONE share-card pipeline (share_card_service.dart) that the match,
// profile and Infinite Fantasy shares all run through: offscreen capture to a
// real PNG at the requested pixel ratio; the injected share seam receiving
// the PNG + caption + the TAPPED widget's rect (the iPad popover anchor —
// share_plus rejects an iPad share without one); a friendly SnackBar on
// failure; and the shared branded footer on both existing cards.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/widgets/share_card_footer.dart';
import 'package:infinite_sports_flutter/widgets/share_match_card.dart';
import 'package:infinite_sports_flutter/widgets/share_profile_card.dart';

import '../helpers/share_capture.dart';

void main() {
  const card = SizedBox(
    width: 120,
    height: 200,
    child: ColoredBox(color: Color(0xFF15171E)),
  );

  Future<void> pumpButton(
    WidgetTester tester, {
    required SharePng share,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: Builder(
            builder: (context) => IconButton(
              key: const ValueKey('share_button'),
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareCardImage(
                context,
                card,
                caption: 'Caption here',
                // Decoded first; the wait's timeout timer never outlives it.
                precache: const [AssetImage('assets/infinite_mark.png')],
                share: share,
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('captureCardToPng: a real PNG at the requested pixel ratio',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    Uint8ListBox? out;
    captureCardToPng(context, card, pixelRatio: 3)
        .then((bytes) => out = Uint8ListBox(bytes));
    await pumpUntil(tester, () => out != null);
    expect(out, isNotNull);
    expect(isPng(out!.bytes), isTrue);
    expect(pngSize(out!.bytes), const Size(360, 600));
    // The offscreen overlay entry is gone again.
    await tester.pump();
    expect(find.byWidget(card), findsNothing);
  });

  testWidgets(
      'shareCardImage hands the seam a PNG, the caption and the '
      "TAPPED button's rect (the iPad popover anchor)", (tester) async {
    final recorder = ShareRecorder();
    await pumpButton(tester, share: recorder.call);
    await tester.tap(find.byKey(const ValueKey('share_button')));
    await pumpUntil(tester, () => recorder.calls.isNotEmpty);

    final call = recorder.calls.single;
    expect(isPng(call.png), isTrue);
    expect(pngSize(call.png), const Size(360, 600));
    expect(call.caption, 'Caption here');
    expect(call.origin,
        tester.getRect(find.byKey(const ValueKey('share_button'))));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failing share shows the friendly SnackBar, never throws',
      (tester) async {
    await pumpButton(tester,
        share: (_, __, ___) async => throw StateError('no sheet'));
    await tester.tap(find.byKey(const ValueKey('share_button')));
    await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.text("Couldn't create the share card."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'never throws even when the tapped context is already gone (stale '
      'context: the origin / messenger lookups are inside the try)',
      (tester) async {
    BuildContext? stale;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          stale = context;
          return const SizedBox();
        }),
      ),
    ));
    await tester.pumpWidget(const SizedBox()); // the page is gone
    final recorder = ShareRecorder();

    await shareCardImage(stale!, card, caption: 'x', share: recorder.call);
    await shareMatchCard(
      stale!,
      match: const TournamentMatch(
        id: 'm', stage: 'Final', label: 'F', date: '08272026',
        team1Id: 'a', team2Id: 'b', team1Score: 0, team2Score: 0,
        status: 0, bracketPosition: 1,
      ),
      team1: null,
      team2: null,
      tournamentName: 'Cup',
      sport: 'Futsal',
    );

    expect(tester.takeException(), isNull);
    expect(recorder.calls, isEmpty);
  });

  testWidgets('shareOriginFor clips to the screen; nothing on screen = null',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Stack(
        children: [
          Positioned(
              left: 350,
              top: 10,
              width: 100,
              height: 40,
              child: SizedBox(key: ValueKey('half_off'))),
          Positioned(
              left: 500,
              top: 10,
              width: 100,
              height: 40,
              child: SizedBox(key: ValueKey('off'))),
        ],
      ),
    ));
    expect(
        shareOriginFor(tester.element(find.byKey(const ValueKey('half_off')))),
        const Rect.fromLTWH(350, 10, 50, 40));
    expect(shareOriginFor(tester.element(find.byKey(const ValueKey('off')))),
        isNull);
  });

  testWidgets('the match and profile cards both carry the ONE branded footer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              ShareMatchCard(
                match: const TournamentMatch(
                  id: 'm',
                  stage: 'Final',
                  label: 'F',
                  date: '08272026',
                  team1Id: 'a',
                  team2Id: 'b',
                  team1Score: 0,
                  team2Score: 0,
                  status: 0,
                  bracketPosition: 1,
                ),
                team1: null,
                team2: null,
                tournamentName: '',
                sport: 'Futsal',
              ),
              const ShareProfileCareerCard(
                name: 'Pat',
                photoUrl: '',
                headlineTotals: [],
              ),
            ],
          ),
        ),
      ),
    ));
    expect(find.byType(ShareCardFooter), findsNWidgets(2));
    expect(
        find.text('Follow Infinite Sports for live scores'), findsNWidgets(2));
  });
}

/// Box so the async capture result can be assigned from a callback.
class Uint8ListBox {
  Uint8ListBox(this.bytes);
  final Uint8List bytes;
}
