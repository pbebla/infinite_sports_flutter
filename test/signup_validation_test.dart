// Unit tests for lib/onboarding/signup_validation.dart — pure phone
// formatting/parsing helpers and field validators used by the Create
// Account (lib/createaccountpage.dart) and About You
// (lib/onboarding/about_you_page.dart) forms (F1 owner-feedback round).
//
// TDD: written before lib/onboarding/signup_validation.dart exists, so the
// whole file fails to compile until that file is created.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/onboarding/signup_validation.dart';

/// Helper: run the formatter for a single simulated edit and return the
/// resulting TextEditingValue.
TextEditingValue _edit(TextEditingValue oldValue, TextEditingValue newValue) {
  return const UsPhoneInputFormatter().formatEditUpdate(oldValue, newValue);
}

void main() {
  group('digitsOnly', () {
    test('strips non-digit characters', () {
      expect(digitsOnly('(408)693-9436'), '4086939436');
      expect(digitsOnly('408-693-9436'), '4086939436');
      expect(digitsOnly('abc'), '');
      expect(digitsOnly(''), '');
    });

    test('caps at 10 digits', () {
      expect(digitsOnly('40869394361234'), '4086939436');
    });
  });

  group('formatUsPhone', () {
    test('progressive formatting matches the owner spec exactly', () {
      expect(formatUsPhone(''), '');
      expect(formatUsPhone('4'), '(4');
      expect(formatUsPhone('408'), '(408');
      expect(formatUsPhone('4086'), '(408)6');
      expect(formatUsPhone('408693'), '(408)693');
      expect(formatUsPhone('4086939'), '(408)693-9');
      expect(formatUsPhone('4086939436'), '(408)693-9436');
    });

    test('no space after the closing paren (owner spec)', () {
      expect(formatUsPhone('4086'), isNot(contains(') ')));
      expect(formatUsPhone('4086939436'), '(408)693-9436');
    });
  });

  group('validatePhone', () {
    test('null iff exactly 10 digits are present', () {
      expect(validatePhone('(408)693-9436'), isNull);
      expect(validatePhone('(408)693-943'),
          'Enter a valid 10-digit phone number');
      expect(
          validatePhone(''), 'Enter a valid 10-digit phone number');
      expect(validatePhone('(408)693-94366'),
          'Enter a valid 10-digit phone number');
    });
  });

  group('validateRequiredName', () {
    test('trims before checking emptiness', () {
      expect(validateRequiredName('  Zaya ', 'First Name'), isNull);
      expect(validateRequiredName('   ', 'First Name'),
          'First Name is required');
      expect(validateRequiredName('', 'Last Name'), 'Last Name is required');
      expect(validateRequiredName('Rami', 'Last Name'), isNull);
    });
  });

  group('validateEmailTrimmed', () {
    test('trims then requires a non-empty, valid email', () {
      expect(validateEmailTrimmed(' a@b.com '), isNull);
      expect(validateEmailTrimmed('a@b.com'), isNull);
      expect(validateEmailTrimmed('   '), isNotNull);
      expect(validateEmailTrimmed(''), isNotNull);
      expect(validateEmailTrimmed('not-an-email'), isNotNull);
      expect(validateEmailTrimmed(' not-an-email '), isNotNull);
    });
  });

  group('UsPhoneInputFormatter — typing forward', () {
    test('digit by digit builds the progressive display', () {
      var value = const TextEditingValue(text: '');

      TextEditingValue type(String appended) {
        final newValue = TextEditingValue(
          text: value.text + appended,
          selection: TextSelection.collapsed(
              offset: value.text.length + appended.length),
        );
        return _edit(value, newValue);
      }

      value = type('4');
      expect(value.text, '(4');
      expect(value.selection.baseOffset, value.text.length);

      value = type('0');
      expect(value.text, '(40');

      value = type('8');
      expect(value.text, '(408');

      value = type('6');
      expect(value.text, '(408)6');

      value = type('9');
      expect(value.text, '(408)69');

      value = type('3');
      expect(value.text, '(408)693');

      value = type('9');
      expect(value.text, '(408)693-9');

      value = type('4');
      expect(value.text, '(408)693-94');

      value = type('3');
      expect(value.text, '(408)693-943');

      value = type('6');
      expect(value.text, '(408)693-9436');
      expect(value.selection.baseOffset, '(408)693-9436'.length);
    });

    test('typing an 11th digit is ignored (capped at 10)', () {
      const full = TextEditingValue(
        text: '(408)693-9436',
        selection: TextSelection.collapsed(offset: 13),
      );
      final attempt = TextEditingValue(
        text: '${full.text}7',
        selection: const TextSelection.collapsed(offset: 14),
      );
      final result = _edit(full, attempt);
      expect(result.text, '(408)693-9436');
    });
  });

  group('UsPhoneInputFormatter — deleting', () {
    test('backspacing from the end walks the format back down, dropping the dash', () {
      var value = const TextEditingValue(
        text: '(408)693-9436',
        selection: TextSelection.collapsed(offset: 13),
      );

      TextEditingValue backspace() {
        final newText = value.text.substring(0, value.text.length - 1);
        final newValue = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
        return _edit(value, newValue);
      }

      value = backspace(); // '(408)693-943' -> 9 digits, still has dash
      expect(value.text, '(408)693-943');

      value = backspace(); // 8 digits
      expect(value.text, '(408)693-94');

      value = backspace(); // 7 digits
      expect(value.text, '(408)693-9');

      value = backspace(); // 6 digits — dash disappears
      expect(value.text, '(408)693');

      value = backspace(); // 5 digits
      expect(value.text, '(408)69');

      value = backspace(); // 4 digits
      expect(value.text, '(408)6');

      value = backspace(); // 3 digits — closing paren disappears
      expect(value.text, '(408');

      value = backspace(); // 2 digits
      expect(value.text, '(40');

      value = backspace(); // 1 digit
      expect(value.text, '(4');

      value = backspace(); // 0 digits — empty
      expect(value.text, '');
      expect(value.selection.baseOffset, 0);
    });

    test('clearing the field entirely yields empty text', () {
      const value = TextEditingValue(
        text: '(408)693-9436',
        selection: TextSelection.collapsed(offset: 13),
      );
      const cleared = TextEditingValue.empty;
      final result = _edit(value, cleared);
      expect(result.text, '');
    });
  });
}
