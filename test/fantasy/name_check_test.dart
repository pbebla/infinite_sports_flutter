// P3a feedback — client-side team-name check: length, profanity, leetspeak
// folding, and Scunthorpe-problem awareness (clean names must pass).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/name_check.dart';

void main() {
  group('length', () {
    test('3–30 chars pass, outside fails with the length reason', () {
      expect(checkTeamName('Abc').ok, isTrue);
      expect(checkTeamName('A' * 30).ok, isTrue);

      final tooShort = checkTeamName('Ab');
      expect(tooShort.ok, isFalse);
      expect(tooShort.reason, contains('3–30'));

      expect(checkTeamName('A' * 31).ok, isFalse);
      // Trimmed before measuring: two chars padded with spaces still fail.
      expect(checkTeamName('  Ab  ').ok, isFalse);
    });
  });

  group('clean names pass', () {
    const clean = [
      'Golden Boots',
      'Zaya FC',
      'The Mighty Ducks',
      // Scunthorpe problem: embedded letters in a known-clean word.
      'Scunthorpe-free',
      // Embedded short terms must not trip the word-only tier.
      'Spice Boys', // sPICe
      'Class Act', // no "ass" on the list at all
      'Fagerberg XI', // FAGerberg is a surname, "fag" is word-only
      'Team 2026',
    ];
    for (final name in clean) {
      test('"$name" is allowed', () {
        expect(checkTeamName(name).ok, isTrue,
            reason: '"$name" should pass: ${checkTeamName(name).reason}');
      });
    }
  });

  group('profanity blocked', () {
    const blocked = [
      'Shit Squad',
      'FUCK UNITED', // case-insensitive
      'The Bitches',
      'total asshole fc',
      'Nazi XI', // word-tier term
      'you retard', // word-tier term
    ];
    for (final name in blocked) {
      test('"$name" is rejected with a reason', () {
        final r = checkTeamName(name);
        expect(r.ok, isFalse);
        expect(r.reason, isNotNull);
      });
    }
  });

  group('leetspeak variants blocked', () {
    const leet = [
      'Sh1t Happens', // 1 → i
      r'$hit Show', // $ → s
      'b!tch mode', // ! → i
      'F@gg0t FC', // @ → a, 0 → o
      'ShI7 7eam', // 7 → t
      's.h.i.t.', // punctuation-spaced letters collapse
      'A55hole United', // 5 → s
    ];
    for (final name in leet) {
      test('"$name" is rejected', () {
        expect(checkTeamName(name).ok, isFalse);
      });
    }
  });

  group('containsBlockedWord core', () {
    test('collapse joins spaced letters', () {
      expect(containsBlockedWord('f u c k'), isTrue);
    });
    test('allowlisted token stripped whole, not as a shield', () {
      expect(containsBlockedWord('scunthorpe'), isFalse);
      // Glued into one token it is NOT the allowlisted word any more.
      expect(containsBlockedWord('xscunthorpecuntx'), isTrue);
    });
    test('mild/real-name collisions deliberately not on the list', () {
      expect(containsBlockedWord('Dick Tracy'), isFalse);
      expect(containsBlockedWord('Hell Raisers'), isFalse);
    });
  });
}
