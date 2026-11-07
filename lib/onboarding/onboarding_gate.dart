/// Which one-time onboarding prompts the post-sign-in gate
/// (`MyHomePage._setupNotificationPrefs`, lib/main.dart) may show for a
/// `Users/<uid>` snapshot value.
///
/// Kept pure (no Firebase, no navigation) so the rule can be unit-tested.
///
/// A MERGED account (stamped `MergedInto` by the duplicate-account merge tool)
/// gets NO prompt at all. Old S9-S14 accounts almost always have an incomplete
/// profile, and the mandatory About You page has no way back: the person would
/// have to fill in a profile on an account they are about to be signed out of,
/// or a page would be pushed while the merged-account watcher is signing them
/// out and end up stranded over the welcome wall. The watcher
/// (lib/account/merged_account_notice.dart) owns merged accounts.
library;

import 'package:infinite_sports_flutter/account/merged_account_notice.dart'
    show mergedNoticeFor;
import 'package:infinite_sports_flutter/onboarding/profile_completion.dart';

enum OnboardingGateDecision {
  /// Merged account: show neither About You nor Favorites.
  skipMergedAccount,

  /// Incomplete profile: mandatory About You, then the favorites prompt.
  askAboutYou,

  /// Profile already complete: no About You, but the favorites prompt may run.
  profileComplete;

  bool get showsAboutYou => this == OnboardingGateDecision.askAboutYou;

  bool get showsFavorites => this != OnboardingGateDecision.skipMergedAccount;
}

/// The gate's decision for [usersNode] (the value of `Users/<uid>`; a missing
/// or non-Map node is "incomplete", the safer default, exactly as before).
OnboardingGateDecision onboardingGateDecisionFor(dynamic usersNode) {
  if (usersNode is Map &&
      mergedNoticeFor(usersNode['MergedInto'], null) != null) {
    return OnboardingGateDecision.skipMergedAccount;
  }
  return profileCompleted(usersNode)
      ? OnboardingGateDecision.profileComplete
      : OnboardingGateDecision.askAboutYou;
}
