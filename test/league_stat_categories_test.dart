// Guard for the "stat screen hardcoded to futsal" bug class (owner report,
// PR #11): a basketball league team's Stats tab rendered "No stats recorded
// yet" while its players had 100+ points, because the tab carried its own
// futsal-only category list. Every league stat surface now reads these
// per-sport categories from one place.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_stat_categories.dart';

void main() {
  String labelsOf(String sport) =>
      leagueStatCategories(sport).map((c) => c['label']).join(', ');

  test('each sport gets its own categories', () {
    expect(labelsOf('Basketball'), contains('Rebounds'));
    expect(labelsOf('Basketball'), isNot(contains('Clean Sheets')));
    expect(labelsOf('Flag Football'), contains('Touchdowns'));
    expect(labelsOf('Futsal'), contains('Top Scorer'));
  });

  test('unknown sports fall back to the futsal set', () {
    expect(leagueStatCategories('Soccer'), leagueStatCategories('Futsal'));
    expect(leagueStatCategories('Cricket'), leagueStatCategories('Futsal'));
  });

  test('categories resolve real values on adapted basketball players', () {
    // Shape mirrors /Basketball/<season>/Line Ups/<team>/<player>.
    final p = leaguePlayerFromLineup(
      sport: 'Basketball',
      name: 'Alderin Babayan',
      teamName: 'Ishtar',
      raw: const {
        'OnePoint': 8, 'TwoPoints': 14, 'ThreePoints': 27,
        'Rebounds': 41, 'Misses': 62, 'Total': 117, 'number': '11',
      },
    );
    final hits = leagueStatCategories('Basketball')
        .where((c) => p.statByName(c['stat']!) > 0)
        .map((c) => c['label'])
        .toList();
    expect(hits, contains('Points'));
    expect(hits, contains('Rebounds'));
    expect(p.statByName('points'), 117);

    // The old futsal-only list found nothing on the same player — that is
    // exactly what produced the blank tab.
    final futsalHits = leagueStatCategories('Futsal')
        .where((c) => p.statByName(c['stat']!) > 0)
        .toList();
    expect(futsalHits, isEmpty);
  });
}
