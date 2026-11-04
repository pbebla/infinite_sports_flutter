// The ONE point-count formatter (lib/misc/points_text.dart) and fantasy's
// tenths variant (fantasy_format.pointsTenthsText): the unit agrees with the
// count — exactly ±1 is singular, 0 and decimals are plural.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart'
    show pointsTenthsText;
import 'package:infinite_sports_flutter/misc/points_text.dart';

void main() {
  test('whole points: 1 / -1 singular, 0 and the rest plural', () {
    expect(pointsText(1), '1 pt');
    expect(pointsText(-1), '-1 pt');
    expect(pointsText(0), '0 pts');
    expect(pointsText(2), '2 pts');
    expect(pointsText(-4), '-4 pts');
    expect(pointsText(34), '34 pts');
  });

  test('the unit alone, and spelled out', () {
    expect(pointsUnit(1), 'pt');
    expect(pointsUnit(1.0), 'pt');
    expect(pointsUnit(2.5), 'pts');
    expect(pointsUnit(0), 'pts');
    expect(pointsText(1, long: true), '1 point');
    expect(pointsText(4, long: true), '4 points');
    expect(pointsText(0, long: true), '0 points');
  });

  test('tenths: whole numbers lose the decimal; halves stay plural', () {
    expect(pointsTenthsText(10), '1 pt');
    expect(pointsTenthsText(-10), '-1 pt');
    expect(pointsTenthsText(0), '0 pts');
    expect(pointsTenthsText(80), '8 pts');
    expect(pointsTenthsText(25), '2.5 pts');
    expect(pointsTenthsText(-5), '-0.5 pts');
    expect(pointsTenthsText(15), '1.5 pts');
  });
}
