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
}
