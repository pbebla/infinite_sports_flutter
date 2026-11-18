// Release report #10: on the Team of the Week pitch the name boxes of one
// row crowded into the photos of the row below at phone width. Every court
// (Team of the Week mini chips, the squad builder's full chips) must keep
// each row's whole chip — photo, two-line name box, points/price — clear of
// the next row, in light and dark, at 360 px (and a narrower 320 px phone).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

void main() {
  const gk = 'Anthony Memon Longname';
  const defs = ['Demsin Bet varda', 'Pedro Siva Longname'];
  const atts = ['Eli Derazizyan Long', 'Bruno Siva Longname'];

  test('courtHeightFor: grows the pitch only as far as the rows need', () {
    // Plenty of room: the natural aspect height stands.
    expect(
        courtHeightFor(
            width: 400,
            aspect: 0.8,
            rowFractions: const [0, 0.5, 1],
            chipHeight: 100),
        500);
    // Tight: (H - chip) * 0.5 must clear chip + gap.
    expect(
        courtHeightFor(
            width: 200,
            aspect: 0.8,
            rowFractions: const [0, 0.5, 1],
            chipHeight: 100,
            gap: 6),
        closeTo(100 + 106 / 0.5, 1e-9));
  });

  test('appCourtLayout: rows stand on the grass, grown to fit inside it', () {
    final flat = starterOffsets(FantasyConfig.futsalDefault());
    for (final chipH in [100.0, 160.0]) {
      final chips = List.filled(5, Size(96, chipH));
      final out = appCourtLayout(width: 336, chips: chips, flat: flat);
      final top = out.height * (pitchAssetTopY + pitchAssetRimTop);
      final bottom = out.height * pitchAssetBottomY;
      expect(out.height, greaterThanOrEqualTo(336 / pitchAssetAspect));
      // Keeper at the far edge, attackers at the near edge, DEF midway.
      expect(out.origins[0].dy, closeTo(top + kCourtGrassMargin, 1e-9));
      expect(out.origins[3].dy + chipH,
          closeTo(bottom - kCourtGrassMargin, 1e-9));
      final gapAbove = out.origins[1].dy - (out.origins[0].dy + chipH);
      final gapBelow = out.origins[3].dy - (out.origins[1].dy + chipH);
      expect(gapAbove, closeTo(gapBelow, 1e-9));
      expect(gapAbove, greaterThanOrEqualTo(kCourtRowGap - 1e-9));
      // Inside the touchlines at each chip's top edge.
      for (var i = 0; i < 5; i++) {
        final o = out.origins[i];
        final half = 336 * pitchAssetHalfAt(o.dy / out.height);
        expect(o.dx, greaterThanOrEqualTo(168 - half));
        expect(o.dx + 96, lessThanOrEqualTo(168 + half));
      }
    }
    // A bounded parent caps the height.
    expect(
        appCourtLayout(
                width: 336,
                chips: List.filled(5, const Size(96, 160)),
                flat: flat,
                maxHeight: 300)
            .height,
        300);
  });

  for (final brightness in Brightness.values) {
    for (final width in [360.0, 320.0]) {
      for (final (label, chipWidth, avatar, pad) in [
        ('Team of the Week', 78.0, 44.0, 26.0), // 12 page + 14 card padding
        ('squad builder', 96.0, 58.0, 12.0),
      ]) {
        testWidgets('$label at ${width.toInt()} px ($brightness): rows never '
            'overlap', (tester) async {
          tester.view.physicalSize = Size(width, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final team = dreamTeamsFromNode({
            '12': {
              'Players': [
                {'name': gk, 'position': 'GK', 'points': -2},
                for (final n in defs)
                  {'name': n, 'position': 'DEF', 'points': 16},
                for (final n in atts)
                  {'name': n, 'position': 'ATT', 'points': 11},
              ],
            },
          })[12]!;
          final cfg = FantasyConfig.futsalDefault();
          final court = dreamTeamCourt(cfg, team);
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: FantasyCourtView(
                    config: cfg,
                    slots: court.slots,
                    slotPicks: court.slotPicks,
                    showPrices: false,
                    chipWidth: chipWidth,
                    chipAvatarSize: avatar,
                    weekPointsFor: (n) => '${court.pointsByName[n]} pts',
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          Rect chip(String n) =>
              tester.getRect(find.byKey(ValueKey('squad_chip_$n')));
          for (final d in defs) {
            expect(chip(gk).bottom, lessThanOrEqualTo(chip(d).top),
                reason: 'GK name box runs into $d');
            for (final a in atts) {
              expect(chip(d).bottom, lessThanOrEqualTo(chip(a).top),
                  reason: '$d name box runs into $a');
            }
          }
          // The estimate the court sizes itself by covers the real chip.
          expect(
              fantasyChipHeightEstimate(avatar, TextScaler.noScaling),
              greaterThanOrEqualTo(chip(gk).height));
        });
      }
    }
  }
}
