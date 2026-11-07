// Pins the post-sign-in onboarding gate's decision (lib/onboarding/
// onboarding_gate.dart) for merged accounts (Merge Duplicate Player Accounts,
// final-review fix 1).
//
// An old S9-S14 account that was merged into the real one almost always has an
// incomplete profile. MyHomePage's gate used to push the MANDATORY About You
// page (no way back) and then the Favorites page over it — so the person had to
// fill in a profile on an account they are about to be signed out of, or got a
// page stranded over the welcome wall after the merged-account watcher signed
// them out. The watcher owns merged accounts, so the gate must show NOTHING.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/onboarding/onboarding_gate.dart';

void main() {
  group('onboardingGateDecisionFor', () {
    test('a merged node with an INCOMPLETE profile asks for nothing', () {
      final decision = onboardingGateDecisionFor({
        'MergedInto': 'keptUid',
        'MergedHint': 'k***@example.test',
        'Phone Number': '',
      });
      expect(decision, OnboardingGateDecision.skipMergedAccount);
      expect(decision.showsAboutYou, isFalse);
      expect(decision.showsFavorites, isFalse);
    });

    test('a merged node with a COMPLETE profile still asks for nothing', () {
      final decision = onboardingGateDecisionFor({
        'MergedInto': 'keptUid',
        'ProfileCompleted': true,
      });
      expect(decision, OnboardingGateDecision.skipMergedAccount);
      expect(decision.showsAboutYou, isFalse);
      expect(decision.showsFavorites, isFalse);
    });

    test('the hint is optional: MergedInto alone marks the node merged', () {
      expect(
        onboardingGateDecisionFor({'MergedInto': 'keptUid'}),
        OnboardingGateDecision.skipMergedAccount,
      );
    });

    test('a blank / non-string MergedInto is not a merge stamp', () {
      for (final into in <Object?>['', 7, true, null, <String>[]]) {
        expect(
          onboardingGateDecisionFor({'MergedInto': into}).showsAboutYou,
          isTrue,
          reason: 'into: $into',
        );
      }
    });

    test('an ordinary incomplete profile still gets About You, then favorites',
        () {
      final decision = onboardingGateDecisionFor({'Phone Number': '555'});
      expect(decision, OnboardingGateDecision.askAboutYou);
      expect(decision.showsAboutYou, isTrue);
      expect(decision.showsFavorites, isTrue);
    });

    test('a missing / non-map node is treated as incomplete (as before)', () {
      expect(
          onboardingGateDecisionFor(null), OnboardingGateDecision.askAboutYou);
      expect(onboardingGateDecisionFor('nope'),
          OnboardingGateDecision.askAboutYou);
    });

    test(
        'a completed, unmerged profile skips About You but still offers '
        'favorites', () {
      final decision = onboardingGateDecisionFor({'ProfileCompleted': true});
      expect(decision, OnboardingGateDecision.profileComplete);
      expect(decision.showsAboutYou, isFalse);
      expect(decision.showsFavorites, isTrue);
    });
  });
}
