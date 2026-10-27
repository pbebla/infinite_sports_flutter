import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

void main() {
  test('futsal defaults match the locked spec table', () {
    final c = FantasyConfig.futsalDefault();
    expect(c.scoring[FantasyPosition.gk]!.goal, 10);
    expect(c.scoring[FantasyPosition.def]!.goal, 6);
    expect(c.scoring[FantasyPosition.att]!.goal, 4);
    expect(c.scoring[FantasyPosition.gk]!.assist, 5);
    expect(c.scoring[FantasyPosition.def]!.cleanSheet, 5);
    expect(c.scoring[FantasyPosition.att]!.cleanSheet, 2);
    expect(c.scoring[FantasyPosition.gk]!.per2Saves, 1);
    expect(c.scoring[FantasyPosition.att]!.per2Conceded, 0);
    expect(c.scoring[FantasyPosition.def]!.dplThreshold, 5);
    expect(c.scoring[FantasyPosition.att]!.dplThreshold, 7);
    expect(c.budgetTenths, 500);
    expect(c.priceMinTenths, 40);
    expect(c.priceMaxTenths, 150);
    expect(c.priceStepTenths, 5);
    expect(c.freeTransfersPerWeek, 2);
    expect(c.maxBankedTransfers, 7);
    expect(c.extraTransferCost, 4);
    expect(c.lockHour, 15);
    expect(c.benchFactorPercent, 50);
    expect(c.captainMultiplier, 2);
    expect(c.tripleCaptainMultiplier, 3);
    expect(c.rookiePriceTenths, 60);
  });
  test('round-trips through RTDB-safe map', () {
    final c = FantasyConfig.futsalDefault();
    final back = FantasyConfig.fromMap(c.toMap());
    expect(back.toMap(), c.toMap());
  });
  test('fromMap tolerates missing keys with defaults', () {
    final c = FantasyConfig.fromMap({'budgetTenths': 400});
    expect(c.budgetTenths, 400);
    expect(c.scoring[FantasyPosition.gk]!.goal, 10);
  });
  test('position parsing', () {
    expect(FantasyPosition.parse('GK'), FantasyPosition.gk);
    expect(FantasyPosition.parse('DEF'), FantasyPosition.def);
    expect(FantasyPosition.parse('ATT'), FantasyPosition.att);
    expect(() => FantasyPosition.parse('MID'), throwsArgumentError);
  });
}
