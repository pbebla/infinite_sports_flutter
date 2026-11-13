import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/bps.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  test('bps raw score', () {
    // goal 12*2 + assist 9 + save 2*3 + yellow -4 = 35
    expect(
        bpsScore(const PlayerGameStats(goals: 2, assists: 1, saves: 3, yellows: 1, teamConceded: 1), cfg),
        35);
  });
  test('absent player has no bps', () {
    expect(bpsScore(const PlayerGameStats(goals: 2, present: false), cfg), 0);
  });
  test('a forfeited game puts 0 into BPS for BOTH sides (spec §8a) — so it '
      'awards no bonus', () {
    // Showing-up side at 0 conceded would otherwise carry the CS weight.
    const won = PlayerGameStats(goals: 1, forfeit: GameForfeit.won);
    const lost =
        PlayerGameStats(saves: 4, teamConceded: 5, forfeit: GameForfeit.lost);
    expect(bpsScore(won, cfg), 0);
    expect(bpsScore(lost, cfg), 0);
    expect(awardBonus({'w': bpsScore(won, cfg), 'l': bpsScore(lost, cfg)}),
        isEmpty);
  });
  test('top three get 3/2/1', () {
    final b = awardBonus({'a': 50, 'b': 40, 'c': 30, 'd': 20});
    expect(b, {'a': 3, 'b': 2, 'c': 1});
  });
  test('tie for first: both get 3, next gets 1', () {
    expect(awardBonus({'a': 50, 'b': 50, 'c': 30, 'd': 20}),
        {'a': 3, 'b': 3, 'c': 1});
  });
  test('tie for second: 3,2,2 and nobody gets 1', () {
    expect(awardBonus({'a': 50, 'b': 40, 'c': 40, 'd': 20}),
        {'a': 3, 'b': 2, 'c': 2});
  });
  test('triple tie for first: 3,3,3', () {
    expect(awardBonus({'a': 50, 'b': 50, 'c': 50, 'd': 20}),
        {'a': 3, 'b': 3, 'c': 3});
  });
  test('zero/negative bps earn nothing', () {
    expect(awardBonus({'a': 0, 'b': -5, 'c': 10}), {'c': 3});
  });
  test('fewer than three players', () {
    expect(awardBonus({'a': 10}), {'a': 3});
  });
}
