import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/pricing.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();

  test('opening prices: percentile within position maps to range', () {
    final prices = openingPrices({
      'best': 100.0, 'mid': 50.0, 'low': 0.0,
    }, cfg);
    expect(prices['best'], cfg.priceMaxTenths);
    expect(prices['low'], cfg.priceMinTenths);
    expect(prices['mid'], 95); // midpoint of 40..150 snapped to step 5
  });
  test('opening price snaps to 0.5M steps', () {
    final prices = openingPrices({'a': 61.0, 'b': 0.0, 'c': 100.0}, cfg);
    expect(prices['a']! % cfg.priceStepTenths, 0);
  });
  test('rookies (no history) get the rookie price', () {
    expect(openingPrices({}, cfg), isEmpty);
    expect(cfg.rookiePriceTenths, 60);
  });
  test('single-player position gets midpoint', () {
    expect(openingPrices({'only': 42.0}, cfg)['only'], 95);
  });
  test('reprice: beat the position mean by the gap → +1 step', () {
    // mean of {10, 2, 0} = 4; gap 4 → rise at >= 8, fall at <= 0
    final deltas = repriceDeltas({'hot': 10, 'ok': 2, 'cold': 0}, cfg);
    expect(deltas['hot'], cfg.priceStepTenths);
    expect(deltas['ok'], 0);
    expect(deltas['cold'], -cfg.priceStepTenths);
  });
  test('reprice clamps at floor and ceiling', () {
    expect(applyDelta(150, 5, cfg), 150);
    expect(applyDelta(40, -5, cfg), 40);
    expect(applyDelta(70, 5, cfg), 75);
  });
  test('empty week → no movement', () {
    expect(repriceDeltas({}, cfg), isEmpty);
  });
}
