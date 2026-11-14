// Fresh reads, Task 3 — onboarding (survey list A #9: #6, #7, #8, #21, #22).
// A fan who already completed About You or the favorites prompt is never
// asked again because of the phone's saved copy or a failed read; a "not
// completed" the server did not confirm does not block the fan behind the
// mandatory About You page — they get in and are asked next launch. Merged
// accounts keep getting neither prompt.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';
import 'package:infinite_sports_flutter/onboarding/google_profile.dart';
import 'package:infinite_sports_flutter/onboarding/onboarding_gate.dart';

const _complete = {
  'ProfileCompleted': true,
  'Phone Number': '4085551234',
};

void main() {
  group('About You gate (#8)', () {
    test('"completed" in the saved copy is trusted', () {
      expect(onboardingGateDecisionForRead(_complete, fromServer: false),
          OnboardingGateDecision.profileComplete);
    });

    test('"not completed" from the server asks (mandatory, as before)', () {
      expect(
          onboardingGateDecisionForRead({'First Name': 'A'}, fromServer: true),
          OnboardingGateDecision.askAboutYou);
    });

    test(
        '"not completed" the server did not confirm does not block: '
        'neither prompt this launch', () {
      final d =
          onboardingGateDecisionForRead({'First Name': 'A'}, fromServer: false);
      expect(d, OnboardingGateDecision.notCheckedYet);
      expect(d.showsAboutYou, isFalse);
      expect(d.showsFavorites, isFalse);
    });

    test('no node at all, unconfirmed, does not block either', () {
      expect(onboardingGateDecisionForRead(null, fromServer: false),
          OnboardingGateDecision.notCheckedYet);
    });

    test('a merged account gets neither prompt from any source', () {
      for (final fromServer in [true, false]) {
        expect(
            onboardingGateDecisionForRead({'MergedInto': 'keptUid'},
                fromServer: fromServer),
            OnboardingGateDecision.skipMergedAccount);
      }
    });
  });

  group('Google/Apple new-user decision (#6, #7)', () {
    test('an unknown node (saved copy or failed read) is not "new"', () {
      expect(isNewSignInUser(isNewUserFlag: false, usersNodeExists: null),
          isFalse);
    });

    test("Firebase's own new-user flag still wins", () {
      expect(
          isNewSignInUser(isNewUserFlag: true, usersNodeExists: null), isTrue);
    });

    test('a node the server says is missing is new (as before)', () {
      expect(isNewSignInUser(isNewUserFlag: false, usersNodeExists: false),
          isTrue);
    });

    test(
        'usersNodeFromRead: exists from any source, missing only from the '
        'server', () {
      expect(usersNodeFromRead(const FreshValue({'a': 1}, fromServer: false)),
          isTrue);
      expect(
          usersNodeFromRead(const FreshValue(null, fromServer: true)), isFalse);
      expect(
          usersNodeFromRead(const FreshValue(null, fromServer: false)), isNull);
    });
  });

  group('favorites prompt (#21, #22)', () {
    late Map<String, FreshValue Function()> answers;

    setUp(() {
      answers = {};
      FreshReads.serverFirstValueOverride = (path) async {
        final a = answers[path];
        if (a == null) throw StateError('unexpected read of $path');
        return a();
      };
    });

    tearDown(() => FreshReads.serverFirstValueOverride = null);

    Future<bool?> answered() => NotificationPrefs().favoritesAnswered('u1');

    test('"answered" in the saved copy is trusted', () async {
      answers['Users/u1/FavoriteSportsAnswered'] =
          () => const FreshValue(true, fromServer: false);
      answers['Users/u1/FavoriteSports'] =
          () => const FreshValue(null, fromServer: false);
      expect(await answered(), isTrue);
    });

    test('favorites recorded in the saved copy count as answered', () async {
      answers['Users/u1/FavoriteSportsAnswered'] =
          () => const FreshValue(null, fromServer: false);
      answers['Users/u1/FavoriteSports'] =
          () => const FreshValue({'Futsal': true}, fromServer: false);
      expect(await answered(), isTrue);
    });

    test('"not answered" only counts when the server said so', () async {
      answers['Users/u1/FavoriteSportsAnswered'] =
          () => const FreshValue(null, fromServer: true);
      answers['Users/u1/FavoriteSports'] =
          () => const FreshValue(null, fromServer: true);
      expect(await answered(), isFalse);
    });

    test('an unconfirmed or failed "not answered" is unknown (no prompt)',
        () async {
      answers['Users/u1/FavoriteSportsAnswered'] =
          () => const FreshValue(null, fromServer: false);
      answers['Users/u1/FavoriteSports'] =
          () => const FreshValue(null, fromServer: true);
      expect(await answered(), isNull);
      answers['Users/u1/FavoriteSportsAnswered'] =
          () => throw StateError('offline');
      expect(await answered(), isNull);
    });
  });
}
