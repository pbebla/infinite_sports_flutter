// Owner 2026-11-17 (My Team on a Pixel 7): "players positions are so far out
// they are out of the soccer field". The in-app court put the keeper's photo
// on the gold rim above the far goal and hung the attackers' name boxes off
// the near edge of the artwork. Every in-app chip — photo AND name box — must
// lie on the drawn grass (inside the far / near edges and the touchlines at
// its row), and no two starters may overlap (release report #10), at 360 px
// and wider, text scale 1.0 and 1.3, two-line names everywhere.
//
// Visual review: run with
//   --dart-define=COURT_PNG=<path/to/file.png>
// to write the in-app court (real Roboto, dark theme, 411 px wide) to a PNG.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

import '../helpers/real_fonts.dart';

const String kCourtPngPath = String.fromEnvironment('COURT_PNG');

/// GK, DEF, DEF, ATT, ATT starters then the bench — made-up names, every
/// one long enough to wrap onto two lines.
const starters = [
  'Maximiliano Featherstonehaugh',
  'Alexandros Papadopoulos',
  'Bartholomew Smythe-Jones',
  'Annabel Vasconcelos',
  'Constantine Oyelaran-Whitfield',
];
const bench = ['Theodora Castellanos', 'Leopold Abernathy-Quinn'];

/// The gold rim's thickness at the far end (the grass starts ~1.1% of the
/// frame below [pitchAssetTopY]) — the share-layout test's measurement.
const double kRim = 0.011;

Widget court(FantasyConfig cfg) {
  final slots = buildSlots(cfg);
  final names = [...starters, ...bench];
  final picks = [
    for (var i = 0; i < slots.length; i++)
      SquadPick(
        playerId: names[i],
        position: slots[i].position,
        priceTenths: 150,
        bench: slots[i].bench,
      ),
  ];
  return FantasyCourtView(
    config: cfg,
    slots: slots,
    slotPicks: picks,
    // The tallest nameplate: captain (price · ×2 can wrap) + a points line.
    captainId: starters[3],
    viceId: starters[4],
    weekPointsFor: (_) => '12 pts · live',
    onSlotTap: (_) {},
  );
}

Future<void> pumpCourt(
  WidgetTester tester, {
  required double width,
  required double textScale,
  Brightness brightness = Brightness.dark,
  double height = 1600,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
        useMaterial3: true, brightness: brightness, fontFamily: kRealFont),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: court(FantasyConfig.futsalDefault()),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Everything wrong with the court's starters: a chip off the grass, or two
/// chips touching.
List<String> courtProblems(WidgetTester tester) {
  final pitch = tester.getRect(find.image(const AssetImage(kNeonPitchAsset)));
  final grassTop = pitch.top + pitch.height * (pitchAssetTopY + kRim);
  final grassBottom = pitch.top + pitch.height * pitchAssetBottomY;
  double halfAt(double y) {
    final f = (y - pitch.top) / pitch.height;
    final t = ((f - pitchAssetTopY) / (pitchAssetBottomY - pitchAssetTopY))
        .clamp(0.0, 1.0);
    return pitch.width *
        (pitchAssetHalfTop + (pitchAssetHalfBottom - pitchAssetHalfTop) * t);
  }

  String px(double v) => v.toStringAsFixed(1);
  final problems = <String>[];
  final rects = {
    for (final n in starters)
      n: tester.getRect(find.byKey(ValueKey('squad_chip_$n'))),
  };
  for (final n in starters) {
    final r = rects[n]!;
    if (r.top < grassTop - 0.01) {
      problems.add('$n sits on the far rim '
          '(top ${px(r.top)} < grass ${px(grassTop)})');
    }
    if (r.bottom > grassBottom + 0.01) {
      problems.add('$n hangs off the near edge '
          '(bottom ${px(r.bottom)} > grass ${px(grassBottom)})');
    }
    for (final y in [r.top, r.bottom]) {
      final half = halfAt(y);
      if (r.left < pitch.center.dx - half - 0.01) {
        problems.add('$n crosses the left touchline at y ${px(y)}');
      }
      if (r.right > pitch.center.dx + half + 0.01) {
        problems.add('$n crosses the right touchline at y ${px(y)}');
      }
    }
  }
  for (var i = 0; i < starters.length; i++) {
    for (var j = i + 1; j < starters.length; j++) {
      if (rects[starters[i]]!.overlaps(rects[starters[j]]!)) {
        problems.add('${starters[i]} overlaps ${starters[j]}');
      }
    }
  }
  return problems;
}

void main() {
  group('in-app court: every chip on the grass, none overlapping', () {
    for (final width in [360.0, 393.0, 412.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final brightness in Brightness.values) {
          testWidgets('${width.toInt()} px, text ×$scale, ${brightness.name}',
              (tester) async {
            final ok = await tester.runAsync(loadRealFont);
            if (ok != true) {
              markTestSkipped('Flutter SDK material_fonts not found');
              return;
            }
            await pumpCourt(tester,
                width: width, textScale: scale, brightness: brightness);
            expect(tester.takeException(), isNull);
            expect(courtProblems(tester), isEmpty);
            // Still tappable, every starter.
            for (final n in starters) {
              expect(
                  tester
                      .getRect(find.byKey(ValueKey('squad_chip_$n')))
                      .center
                      .dx,
                  inExclusiveRange(0, width));
            }
          });
        }
      }
    }
  });

  testWidgets('a chip tap still reaches its slot', (tester) async {
    final ok = await tester.runAsync(loadRealFont);
    if (ok != true) {
      markTestSkipped('Flutter SDK material_fonts not found');
      return;
    }
    final cfg = FantasyConfig.futsalDefault();
    final slots = buildSlots(cfg);
    final names = [...starters, ...bench];
    final tapped = <int>[];
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: kRealFont),
      home: Scaffold(
        body: SingleChildScrollView(
          child: FantasyCourtView(
            config: cfg,
            slots: slots,
            slotPicks: [
              for (var i = 0; i < slots.length; i++)
                SquadPick(
                    playerId: names[i],
                    position: slots[i].position,
                    priceTenths: 50,
                    bench: slots[i].bench),
            ],
            onSlotTap: tapped.add,
          ),
        ),
      ),
    ));
    for (var i = 0; i < names.length; i++) {
      await tester.tap(find.byKey(ValueKey('squad_chip_${names[i]}')));
    }
    expect(tapped, [for (var i = 0; i < names.length; i++) i]);
  });

  group('visual review (only with --dart-define=COURT_PNG)', () {
    testWidgets('writes the in-app court PNG', (tester) async {
      if (kCourtPngPath.isEmpty) {
        markTestSkipped('set COURT_PNG to write the preview');
        return;
      }
      final fonts = await tester.runAsync(
          () async => await loadRealFont() && await loadMaterialIconsFont());
      if (fonts != true) {
        markTestSkipped('Flutter SDK material_fonts not found');
        return;
      }
      const size = Size(411, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: kRealFont),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: court(FantasyConfig.futsalDefault()),
              ),
            ),
          ),
        ),
      ));
      final context = tester.element(find.byType(FantasyCourtView));
      await tester.runAsync(() =>
          precacheImage(const AssetImage(kNeonPitchAsset), context));
      await tester.pump();
      await tester.pump();
      final png = await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return bytes!.buffer.asUint8List();
      });
      await tester.runAsync(
          () => File(kCourtPngPath).writeAsBytes(png!, flush: true));
    });
  });
}
