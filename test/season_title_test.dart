import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/season_title.dart';

/// Release report #6: the Table / Leaderboard subtitles read "15 Table".
void main() {
  test('a bare season number gets the "Season" word', () {
    expect(seasonTitle('15'), 'Season 15');
    expect(seasonTitle(' 7 '), 'Season 7');
  });

  test('a season that is already words is left alone (AFC San Jose)', () {
    expect(seasonTitle('Season 15'), 'Season 15');
    expect(seasonTitle('season 3'), 'season 3');
    expect(seasonTitle('Spring 2025'), 'Spring 2025');
    expect(seasonTitle('2024-2025'), '2024-2025');
  });

  test('empty stays empty', () {
    expect(seasonTitle(''), '');
  });
}
