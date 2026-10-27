import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  // unsorted on purpose; typical futsal Sundays
  final dates = ['07122026', '06282026', '07052026'];

  test('derives ordered gameweeks, one per match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws.map((g) => g.number), [1, 2, 3]);
    expect(gws.map((g) => g.date), ['06282026', '07052026', '07122026']);
  });
  test('lock = 3PM league time on the match day (PDT in July)', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].lockUtc, DateTime.utc(2026, 6, 28, 22, 0));
  });
  test('status transitions', () {
    final gws = deriveGameweeks(dates, cfg);
    final gw2 = gws[1]; // Jul 5
    expect(gw2.statusAt(DateTime.utc(2026, 7, 3, 12)), GameweekStatus.open);
    expect(gw2.statusAt(DateTime.utc(2026, 7, 5, 23)), GameweekStatus.locked);
    expect(gw2.statusAt(DateTime.utc(2026, 6, 20)), GameweekStatus.upcoming);
  });
  test('gw1 opens immediately; later gws open after the previous match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].opensUtc, isNull);
    // gw2 opens Jun 29 00:00 league time = 07:00 UTC (PDT)
    expect(gws[1].opensUtc, DateTime.utc(2026, 6, 29, 7, 0));
  });
  test('current gameweek at a moment', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(currentGameweek(gws, DateTime.utc(2026, 7, 3))!.number, 2);
    expect(currentGameweek(gws, DateTime.utc(2026, 8, 1)), isNull);
  });
}
