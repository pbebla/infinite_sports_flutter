// The Team of the Week SHARE IMAGE's pitch layout (owner 2026-11-17: "the
// defenders are too inside ... forwards just tiny bit come down" — on the
// shared story an attacker's photo covered the defender above him). The story
// court is capped by the 9:16 canvas, so it gets its own starter layout:
// defenders out toward the touchlines, attackers lower, every photo and name
// box clear of every other chip and on the drawn grass (never on the gold rim
// or off the pitch). The in-app courts (My Team, the squad builder, the
// in-app Dream Team card) keep their layout exactly — "dont touch the app
// part just the part where its created to share".
//
// Visual review: run with
//   --dart-define=TOTW_PNG=<path/to/file.png>
// to write the story (real Roboto) through the real share pipeline.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

import '../helpers/real_fonts.dart';
import '../helpers/share_capture.dart';

const String kPngPath = String.fromEnvironment('TOTW_PNG');

/// GK, DEF, DEF, ATT, ATT — made-up names.
FantasyDreamTeam dreamTeam(List<String> names, {bool live = false}) {
  const positions = ['GK', 'DEF', 'DEF', 'ATT', 'ATT'];
  final team = dreamTeamsFromNode({
    '8': {
      'Players': [
        for (var i = 0; i < 5; i++)
          {'name': names[i], 'position': positions[i], 'points': 10 + i},
      ],
    },
  })[8]!;
  return FantasyDreamTeam(players: team.players, live: live);
}

/// A long two-word defender over an attacker, and a short defender over a
/// two-line attacker (the owner's case: the attacker's photo under the
/// defender's points).
const mixedNames = [
  'Kit Moreno',
  'Alexandros Papadopoulos',
  'Yara Haddad',
  'Alex Rivera',
  'Annabel Vasconcelos',
];

/// Every nameplate two lines (the tallest chips).
const longNames = [
  'Maximiliano Featherstonehaugh',
  'Alexandros Papadopoulos',
  'Bartholomew Smythe-Jones',
  'Annabel Vasconcelos',
  'Constantine Oyelaran-Whitfield',
];

/// The gold rim's thickness at the far end, measured off the artwork (the
/// grass starts ~1.1% of the frame below [pitchAssetTopY]).
const double kRim = 0.011;

/// The visible parts of a chip: the photo (with its armband ring) and the
/// name box. The chip's own box also spans the empty corners beside the
/// photo, which draw nothing.
({Rect photo, Rect plate}) chipParts(WidgetTester tester, String name) {
  final chip = find.byKey(ValueKey('squad_chip_$name'));
  final avatar =
      find.descendant(of: chip, matching: find.byType(FantasyAvatar));
  final ring =
      find.ancestor(of: avatar, matching: find.byType(Container)).first;
  final plate = find
      .ancestor(
          of: find.descendant(of: chip, matching: find.text(name)),
          matching: find.byType(Container))
      .first;
  return (photo: tester.getRect(ring), plate: tester.getRect(plate));
}

void main() {
  Future<void> pumpStory(
    WidgetTester tester,
    Widget story, {
    double textScale = 1.0,
    String? fontFamily,
  }) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: fontFamily),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: story),
      ),
    ));
    await tester.pump();
  }

  /// Every way a chip breaks the image: a visible part (photo or name box)
  /// touching another chip's (a 2 px gap is required), or leaving the drawn
  /// grass (onto the gold rim or off the pitch).
  List<String> layoutProblems(WidgetTester tester, List<String> names) {
    final court = tester.getRect(find.image(const AssetImage(kNeonPitchAsset)));
    final grassTop = court.top + court.height * (pitchAssetTopY + kRim);
    final grassBottom = court.top + court.height * pitchAssetBottomY;
    double halfAt(double y) {
      final f = (y - court.top) / court.height;
      final t = ((f - pitchAssetTopY) / (pitchAssetBottomY - pitchAssetTopY))
          .clamp(0.0, 1.0);
      return court.width *
          (pitchAssetHalfTop + (pitchAssetHalfBottom - pitchAssetHalfTop) * t);
    }

    String px(double v) => v.toStringAsFixed(1);
    final problems = <String>[];
    final parts = {for (final n in names) n: chipParts(tester, n)};
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final a = parts[names[i]]!;
        final b = parts[names[j]]!;
        for (final (la, ra) in [('photo', a.photo), ('name box', a.plate)]) {
          for (final (lb, rb) in [('photo', b.photo), ('name box', b.plate)]) {
            if (ra.inflate(1).overlaps(rb.inflate(1))) {
              problems.add("${names[i]}'s $la touches ${names[j]}'s $lb");
            }
          }
        }
      }
    }
    for (final n in names) {
      final p = parts[n]!;
      for (final (label, r) in [('photo', p.photo), ('name box', p.plate)]) {
        if (r.top < grassTop - 0.01) {
          problems.add("$n's $label sits on the far rim "
              '(top ${px(r.top)} < grass ${px(grassTop)})');
        }
        if (r.bottom > grassBottom + 0.01) {
          problems.add("$n's $label hangs off the near edge "
              '(bottom ${px(r.bottom)} > grass ${px(grassBottom)})');
        }
        // The pitch narrows toward the far end: the part's top edge is its
        // tightest row.
        final half = halfAt(r.top);
        if (r.left < court.center.dx - half - 0.01) {
          problems.add("$n's $label hangs off the left touchline");
        }
        if (r.right > court.center.dx + half + 0.01) {
          problems.add("$n's $label hangs off the right touchline");
        }
      }
    }
    return problems;
  }

  // Real Roboto metrics (the test font draws every glyph as a full square,
  // which wraps the story's title onto two lines and shrinks the pitch — a
  // canvas no phone ever renders). Text scale is pinned by the story frame,
  // so 1.3 must give the same picture as 1.0.
  group('Team of the Week share image: every chip clear and on the grass', () {
    for (final (label, names) in [
      ('mixed names', mixedNames),
      ('all two-line names', longNames),
    ]) {
      for (final live in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets('$label, ${live ? 'live tag' : 'official'}, text x$scale',
              (tester) async {
            final ok = await tester.runAsync(loadRealFont);
            if (ok != true) {
              markTestSkipped('Flutter SDK material_fonts not found');
              return;
            }
            await pumpStory(
              tester,
              TeamOfWeekStoryCard(
                week: 8,
                seasonLabel: 'Futsal Season 16',
                team: dreamTeam(names, live: live),
                config: FantasyConfig.futsalDefault(),
              ),
              textScale: scale,
              fontFamily: kRealFont,
            );
            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byType(FantasyStoryFrame)),
                const Size(kStoryWidth, kStoryHeight));
            expect(
                tester
                    .widget<FantasyCourtView>(find.byType(FantasyCourtView))
                    .starterLayout,
                StarterLayout.story);
            for (final n in names) {
              expect(find.byKey(ValueKey('squad_chip_$n')), findsOneWidget);
              // The parts measured are the 48 px photo in its ring and the
              // 84 px name box.
              final p = chipParts(tester, n);
              expect(p.photo.width, closeTo(57, 0.01));
              expect(p.photo.height, closeTo(57, 0.01));
              expect(p.plate.width, closeTo(84, 0.01));
            }
            expect(layoutProblems(tester, names), isEmpty);
          });
        }
      }
    }
  });

  // The in-app courts never change: chip boxes (relative to the pitch) are
  // pinned to the values the default layout produced before the share
  // image got its own layout.
  group('in-app courts keep their layout exactly (the default layout)', () {
    const squadNames = [
      'Kit Moreno',
      'Alexandros Papadopoulos',
      'Yara Haddad',
      'Alex Rivera',
      'Annabel Vasconcelos',
      'Bench Defender',
      'Bench Attacker',
    ];

    Future<Map<String, Rect>> pumpCourt(
      WidgetTester tester, {
      required double width,
      required double chipWidth,
      required double avatar,
      required bool bench,
      double textScale = 1.0,
    }) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final cfg = FantasyConfig.futsalDefault();
      final slots = buildSlots(cfg);
      final picks = <SquadPick?>[
        for (var i = 0; i < slots.length; i++)
          (bench || !slots[i].bench)
              ? SquadPick(
                  playerId: squadNames[i],
                  position: slots[i].position,
                  priceTenths: 55,
                  bench: slots[i].bench,
                )
              : null,
      ];
      final shown = [
        for (var i = 0; i < slots.length; i++)
          if (bench || !slots[i].bench) i,
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FantasyCourtView(
                config: cfg,
                slots: [for (final i in shown) slots[i]],
                slotPicks: [for (final i in shown) picks[i]],
                showPrices: bench,
                chipWidth: chipWidth,
                chipAvatarSize: avatar,
                weekPointsFor: bench ? null : (n) => '12 pts',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final court =
          tester.getRect(find.image(const AssetImage(kNeonPitchAsset)));
      return {
        'court': Offset.zero & court.size,
        for (final i in shown)
          squadNames[i]: tester
              .getRect(find.byKey(ValueKey('squad_chip_${squadNames[i]}')))
              .shift(-court.topLeft),
      };
    }

    // Recorded from the default layout before the share layout existed
    // (left, top, right, bottom relative to the pitch; 'court' = its size).
    const dreamTeam360 = {
      'court': [0.0, 0.0, 336.0, 408.1875],
      'Kit Moreno': [129.0, 0.6561, 207.0, 120.0561],
      'Alexandros Papadopoulos': [78.9067, 144.3938, 156.9067, 263.7938],
      'Yara Haddad': [179.0933, 144.3938, 257.0933, 263.7938],
      'Alex Rivera': [64.2893, 288.1314, 142.2893, 407.5314],
      'Annabel Vasconcelos': [193.7107, 288.1314, 271.7107, 407.5314],
    };
    const dreamTeam320Large = {
      'court': [0.0, 0.0, 296.0, 429.7219],
      'Kit Moreno': [109.0, 0.6712, 187.0, 134.9881],
      'Alexandros Papadopoulos': [66.6731, 147.7025, 144.6731, 282.0195],
      'Yara Haddad': [151.3269, 147.7025, 229.3269, 282.0195],
      'Alex Rivera': [54.3219, 294.7338, 132.3219, 429.0508],
      'Annabel Vasconcelos': [163.6781, 294.7338, 241.6781, 429.0508],
    };
    const squadBuilder360 = {
      'court': [0.0, 0.0, 336.0, 419.4909],
      'Kit Moreno': [120.0, 0.6477, 216.0, 135.0477],
      'Alexandros Papadopoulos': [73.4016, 142.5455, 169.4016, 276.9455],
      'Yara Haddad': [166.5984, 142.5455, 262.5984, 276.9455],
      'Alex Rivera': [59.8040, 284.4432, 155.8040, 418.8432],
      'Annabel Vasconcelos': [180.1960, 284.4432, 276.1960, 418.8432],
      'Bench Defender': [53.0, 464.4909, 149.0, 598.8909],
      'Bench Attacker': [187.0, 464.4909, 283.0, 598.8909],
    };

    for (final (label, width, chipWidth, avatar, bench, scale, expected) in [
      ('Dream Team card, 360 px', 360.0, 78.0, 44.0, false, 1.0, dreamTeam360),
      (
        'Dream Team card, 320 px, large text',
        320.0,
        78.0,
        44.0,
        false,
        1.3,
        dreamTeam320Large
      ),
      (
        'My Team / squad builder, 360 px',
        360.0,
        96.0,
        58.0,
        true,
        1.0,
        squadBuilder360
      ),
    ]) {
      testWidgets(label, (tester) async {
        final rects = await pumpCourt(tester,
            width: width,
            chipWidth: chipWidth,
            avatar: avatar,
            bench: bench,
            textScale: scale);
        expect(rects.keys.toSet(), expected.keys.toSet());
        for (final MapEntry(key: name, value: want) in expected.entries) {
          final got = rects[name]!;
          for (final (i, side) in [
            (0, got.left),
            (1, got.top),
            (2, got.right),
            (3, got.bottom),
          ]) {
            expect(side, closeTo(want[i], 0.001),
                reason:
                    '$name moved (${['left', 'top', 'right', 'bottom'][i]})');
          }
        }
      });
    }

    testWidgets('the in-app Dream Team card uses the default layout',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      DreamTeamCard.sessionWeek = null;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DreamTeamCard(
              teams: {8: dreamTeam(mixedNames)},
              config: FantasyConfig.futsalDefault(),
              players: const [],
              seasonLabel: 'Futsal Season 16',
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(
          tester
              .widget<FantasyCourtView>(find.byType(FantasyCourtView))
              .starterLayout,
          StarterLayout.app);
    });

    test('the default starter rows are still the app ones', () {
      final offsets = starterOffsets(FantasyConfig.futsalDefault());
      const want = [
        (x: 0.5, y: -0.06),
        (x: 0.26, y: 0.5),
        (x: 0.74, y: 0.5),
        (x: 0.24, y: 1.06),
        (x: 0.76, y: 1.06),
      ];
      expect(offsets.length, want.length);
      for (var i = 0; i < want.length; i++) {
        expect(offsets[i].x, closeTo(want[i].x, 1e-9));
        expect(offsets[i].y, closeTo(want[i].y, 1e-9));
      }
    });
  });

  group('storyStarterOffsets', () {
    test(
        'futsal 1-2-2: keeper central, defenders wide and above the '
        'attackers, attackers inside them', () {
      final story = storyStarterOffsets(FantasyConfig.futsalDefault());
      final app = starterOffsets(FantasyConfig.futsalDefault());
      expect(story.length, 5);
      final (gk, defL, defR, attL, attR) =
          (story[0], story[1], story[2], story[3], story[4]);
      expect(gk.x, 0.5);
      expect(gk.y, lessThan(defL.y));
      expect(defL.y, lessThan(attL.y));
      // Out toward the touchlines: wider than the app's defenders and the
      // attackers below them.
      expect(defL.x, lessThan(app[1].x));
      expect(defL.x, lessThan(attL.x));
      expect(defL.x + defR.x, closeTo(1, 1e-9));
      expect(attL.x + attR.x, closeTo(1, 1e-9));
      expect(defL.y, defR.y);
      expect(attL.y, attR.y);
      // On the frame (the court clamps rows to it).
      for (final o in story) {
        final mapped = pitchAssetPerspective(o);
        expect(mapped.y, inInclusiveRange(0, 1));
      }
    });

    test('any other shape keeps the app rows', () {
      final cfg =
          FantasyConfig.fromMap(const {'startersDef': 3, 'startersAtt': 1});
      expect((cfg.startersGk, cfg.startersDef, cfg.startersAtt), (1, 3, 1));
      expect(storyStarterOffsets(cfg), starterOffsets(cfg));
    });
  });

  group('visual review (only with --dart-define=TOTW_PNG)', () {
    testWidgets('writes the story PNG through the real share pipeline',
        (tester) async {
      if (kPngPath.isEmpty) {
        markTestSkipped('set TOTW_PNG to write the preview');
        return;
      }
      final fonts = await tester.runAsync(
          () async => await loadRealFont() && await loadMaterialIconsFont());
      if (fonts != true) {
        markTestSkipped('Flutter SDK material_fonts not found');
        return;
      }
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: kRealFont),
        home: const Scaffold(body: SizedBox.expand()),
      ));
      final shares = ShareRecorder();
      final context = tester.element(find.byType(SizedBox).last);
      shareFantasyStory(
        context,
        TeamOfWeekStoryCard(
          week: 8,
          seasonLabel: 'Futsal Season 16',
          team: dreamTeam(mixedNames),
          config: FantasyConfig.futsalDefault(),
        ),
        caption: 'preview',
        share: shares.call,
      );
      await pumpUntil(tester, () => shares.calls.isNotEmpty);
      final png = shares.calls.single.png;
      expect(pngSize(png), const Size(1080, 1920));
      await tester
          .runAsync(() => File(kPngPath).writeAsBytes(png, flush: true));
    });
  });
}
