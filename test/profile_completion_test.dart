// Unit tests for the pure "About You" / profile-completion helpers
// (lib/onboarding/profile_completion.dart). No Firebase involved — these are
// plain validators and a completeness check so the auth-wall gate ordering
// (B2 plan) can be tested without standing up real Firebase.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/onboarding/profile_completion.dart';

void main() {
  group('kReferralOptions', () {
    test('is the exact owner-specified list, in order', () {
      expect(kReferralOptions, [
        'Instagram',
        'Facebook',
        'TikTok',
        'Friend or family',
        'Flyer / promo',
        'At a game or event',
        'Google / app store search',
        'Other',
      ]);
    });
  });

  group('validateZip', () {
    test('accepts exactly 5 digits', () {
      expect(validateZip('94088'), isNull);
    });

    test('rejects a short numeric string', () {
      expect(validateZip('9408'), isNotNull);
    });

    test('rejects a long numeric string', () {
      expect(validateZip('940888'), isNotNull);
    });

    test('rejects alphabetic input', () {
      expect(validateZip('abcde'), isNotNull);
    });

    test('rejects an empty string', () {
      expect(validateZip(''), isNotNull);
    });
  });

  group('validateDob', () {
    test('rejects null (required field)', () {
      expect(validateDob(null), isNotNull);
    });

    test('rejects a future date', () {
      final future = DateTime.now().add(const Duration(days: 30));
      expect(validateDob(future), isNotNull);
    });

    test('rejects a date older than 120 years', () {
      final now = DateTime.now();
      final ancient = DateTime(now.year - 130, now.month, now.day);
      expect(validateDob(ancient), isNotNull);
    });

    test('accepts a reasonable date of birth', () {
      expect(validateDob(DateTime(2000, 1, 1)), isNull);
    });

    test('accepts exactly the 120-year boundary', () {
      final now = DateTime.now();
      final boundary = DateTime(now.year - 120, now.month, now.day);
      expect(validateDob(boundary), isNull);
    });
  });

  group('profileCompleted', () {
    test('true via the ProfileCompleted shortcut flag alone', () {
      expect(profileCompleted({'ProfileCompleted': true}), isTrue);
    });

    test('true when all five fields are present and non-empty', () {
      expect(
        profileCompleted({
          'DOB': '01/01/2000',
          'City': 'San Jose',
          'Zip': '95123',
          'Gender': 'Female',
          'ReferralSource': 'Instagram',
        }),
        isTrue,
      );
    });

    test('false when one of the five fields is missing', () {
      expect(
        profileCompleted({
          'DOB': '01/01/2000',
          'City': 'San Jose',
          'Zip': '95123',
          'Gender': 'Female',
          // ReferralSource missing
        }),
        isFalse,
      );
    });

    test('false when a field is present but empty', () {
      expect(
        profileCompleted({
          'DOB': '01/01/2000',
          'City': '',
          'Zip': '95123',
          'Gender': 'Female',
          'ReferralSource': 'Instagram',
        }),
        isFalse,
      );
    });

    test('false for a non-map value (null)', () {
      expect(profileCompleted(null), isFalse);
    });

    test('false for a non-map value (String)', () {
      expect(profileCompleted('nope'), isFalse);
    });

    test('false for a non-map value (List)', () {
      expect(profileCompleted(<String>[]), isFalse);
    });
  });

  group('needsPhoneNumber', () {
    test('true when the node has no Phone Number field at all', () {
      expect(
        needsPhoneNumber({
          'DOB': '01/01/2000',
          'City': 'San Jose',
          'Zip': '95123',
          'Gender': 'Female',
          'ReferralSource': 'Instagram',
        }),
        isTrue,
      );
    });

    test('true when Phone Number is present but empty', () {
      expect(needsPhoneNumber({'Phone Number': ''}), isTrue);
    });

    test('true when Phone Number is whitespace-only', () {
      expect(needsPhoneNumber({'Phone Number': '   '}), isTrue);
    });

    test('false when Phone Number is a non-empty string', () {
      expect(needsPhoneNumber({'Phone Number': '4085551234'}), isFalse);
    });

    test('true for a non-map value (null — node does not exist yet)', () {
      expect(needsPhoneNumber(null), isTrue);
    });

    test('true for a non-map value (String)', () {
      expect(needsPhoneNumber('nope'), isTrue);
    });
  });

  group('shouldSkipOnboardingGate', () {
    test('true when an onboarding flow is active', () {
      expect(shouldSkipOnboardingGate(onboardingFlowActive: true), isTrue);
    });

    test('false when no onboarding flow is active (returning user)', () {
      expect(shouldSkipOnboardingGate(onboardingFlowActive: false), isFalse);
    });
  });

  group('formatDob', () {
    test('zero-pads single-digit month and day', () {
      expect(formatDob(DateTime(2000, 1, 5)), '01/05/2000');
    });

    test('leaves double-digit month/day alone', () {
      expect(formatDob(DateTime(1999, 12, 31)), '12/31/1999');
    });
  });
}
