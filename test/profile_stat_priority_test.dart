import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';

void main() {
  test('positionGroup classifies keepers/defenders/etc', () {
    expect(positionGroup('Futsal', 'GK'), 'GK');
    expect(positionGroup('Futsal', 'Goalkeeper'), 'GK');
    expect(positionGroup('Futsal', 'DEF'), 'DEF');
    expect(positionGroup('Futsal', 'Forward'), 'ATT');
    expect(positionGroup('Basketball', 'Guard'), 'GUARD');
    expect(positionGroup('Flag Football', 'QB'), 'QB');
    expect(positionGroup('Futsal', ''), 'ATT'); // default outfield
  });

  test('profileStatPriority orders by sport+position', () {
    expect(profileStatPriority('Futsal', 'GK').take(3).toList(),
        ['games', 'cleanSheets', 'saves']);
    expect(profileStatPriority('Futsal', 'DEF').take(3).toList(),
        ['games', 'dpl', 'assists']);
    expect(profileStatPriority('Futsal', 'ATT').take(2).toList(),
        ['games', 'goals']);
    expect(profileStatPriority('Basketball', 'GUARD').first, 'points');
  });

  test('detectKeeper uses position then stats', () {
    expect(detectKeeper({'saves': 1, 'goals': 0}, 'GK'), true);
    expect(detectKeeper({'saves': 10, 'goals': 1}, ''), true);  // stats dominate
    expect(detectKeeper({'saves': 0, 'goals': 5}, ''), false);
  });

  test('currentParticipation picks active, else most recent', () {
    final stints = [
      ParticipationStint(sport: 'Futsal', label: '2026', sortKey: 2026, team: 'Eagles', position: 'FWD', isActive: true),
      ParticipationStint(sport: 'Basketball', label: '2025', sortKey: 2025, team: 'Hawks', position: 'G', isActive: false),
    ];
    expect(currentParticipation(stints)!.sport, 'Futsal');
    final none = [stints[1]];
    expect(currentParticipation(none)!.sport, 'Basketball'); // fallback most recent
  });

  test('careerHistory sorts newest first', () {
    final stints = [
      ParticipationStint(sport: 'Basketball', label: '2025', sortKey: 2025, team: 'Hawks', position: 'G', isActive: false),
      ParticipationStint(sport: 'Futsal', label: '2026', sortKey: 2026, team: 'Eagles', position: 'FWD', isActive: true),
    ];
    expect(careerHistory(stints).first.sortKey, 2026);
  });

  group('pickHeadlineStatKeys (release report #2)', () {
    test('a striker with saves fills the third slot with Saves, not a dash',
        () {
      // Futsal ATT priority is games/goals/assists/dpl, but a single-season
      // futsal map only carries goals/assists/saves.
      final keys = pickHeadlineStatKeys(
        profileStatPriority('Futsal', 'ATT'),
        {'goals': 39, 'assists': 19, 'saves': 43},
      );
      expect(keys, ['goals', 'assists', 'saves']);
    });

    test('priority keys come first, in priority order', () {
      final keys = pickHeadlineStatKeys(
        ['games', 'goals', 'assists', 'dpl'],
        {'saves': 4, 'assists': 2, 'goals': 9, 'games': 7},
      );
      expect(keys, ['games', 'goals', 'assists']);
    });

    test('zero-valued fallbacks are skipped; only two stats → two keys', () {
      final keys = pickHeadlineStatKeys(
        profileStatPriority('Futsal', 'ATT'),
        {'goals': 39, 'assists': 19, 'saves': 0},
      );
      expect(keys, ['goals', 'assists']);
    });

    test('never pads and never exceeds the maximum', () {
      expect(pickHeadlineStatKeys(['goals'], const {}), isEmpty);
      expect(
        pickHeadlineStatKeys(
            ['a', 'b'], {'a': 1, 'b': 2, 'c': 3, 'd': 4}),
        ['a', 'b', 'c'],
      );
    });
  });
}
