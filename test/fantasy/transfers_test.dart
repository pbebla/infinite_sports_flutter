import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/transfers.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  test('cost: within free allowance is zero', () {
    expect(transferCost(used: 2, free: 2, cfg: cfg), 0);
    expect(transferCost(used: 1, free: 2, cfg: cfg), 0);
  });
  test('cost: -4 per extra', () {
    expect(transferCost(used: 3, free: 2, cfg: cfg), 4);
    expect(transferCost(used: 5, free: 2, cfg: cfg), 12);
  });
  test('cost: wildcard/free hit weeks are free', () {
    expect(transferCost(used: 9, free: 2, cfg: cfg, unlimited: true), 0);
  });
  test('rollover banks unused up to 7', () {
    expect(rolloverFreeTransfers(free: 2, used: 0, cfg: cfg), 4);
    expect(rolloverFreeTransfers(free: 4, used: 1, cfg: cfg), 5);
    expect(rolloverFreeTransfers(free: 7, used: 0, cfg: cfg), 7);
  });
  test('rollover floors at the weekly grant even after overspend', () {
    expect(rolloverFreeTransfers(free: 2, used: 6, cfg: cfg), 2);
  });
  test('rollover on wildcard/free-hit week keeps the bank', () {
    expect(rolloverFreeTransfers(free: 5, used: 9, cfg: cfg, unlimited: true), 7);
  });
  // A manager's FIRST team is free to build, so it has no unused allowance to
  // bank (twin of functions/src/lib/fantasy/transfers.test.ts).
  test('rollover after a first week resets to the weekly grant — nothing banks',
      () {
    expect(
        rolloverFreeTransfers(free: 2, used: 0, cfg: cfg, firstWeek: true), 2);
    expect(
        rolloverFreeTransfers(free: 7, used: 0, cfg: cfg, firstWeek: true), 2);
  });
  test('rollover after a first week is the grant even on a wildcard/free-hit week',
      () {
    expect(
        rolloverFreeTransfers(
            free: 5, used: 9, cfg: cfg, unlimited: true, firstWeek: true),
        2);
  });
  test('rollover when not the first week is unchanged (bank, cap 7)', () {
    expect(
        rolloverFreeTransfers(free: 2, used: 0, cfg: cfg, firstWeek: false), 4);
    expect(
        rolloverFreeTransfers(free: 6, used: 0, cfg: cfg, firstWeek: false), 7);
  });
}
