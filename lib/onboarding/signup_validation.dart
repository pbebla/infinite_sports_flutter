import 'package:email_validator/email_validator.dart';
import 'package:flutter/services.dart';

/// Pure phone-formatting and field-validation helpers shared by the Create
/// Account (lib/createaccountpage.dart) and About You
/// (lib/onboarding/about_you_page.dart) forms (auth-wall F1 owner-feedback
/// round). Deliberately free of Flutter widget/BuildContext dependencies
/// (aside from `TextInputFormatter`/`TextEditingValue`, which are pure data
/// types) so this is trivially unit-testable.

/// Strips every non-digit character from [s] and caps the result at 10
/// digits (a US phone number has no more to give).
String digitsOnly(String s) {
  final digits = s.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

/// Progressive US phone display formatting: `(XXX)XXX-XXXX`. No space after
/// the closing paren — owner spec. [digits] must already be digit-only
/// (≤10 digits); use [digitsOnly] first if the input might contain other
/// characters.
String formatUsPhone(String digits) {
  if (digits.isEmpty) return '';
  if (digits.length <= 3) return '($digits';
  if (digits.length <= 6) {
    return '(${digits.substring(0, 3)})${digits.substring(3)}';
  }
  return '(${digits.substring(0, 3)})${digits.substring(3, 6)}-'
      '${digits.substring(6)}';
}

/// Null iff [display] contains exactly 10 digits, else a field error. Counts
/// raw digit characters (uncapped) rather than [digitsOnly]'s 10-digit cap,
/// so an over-long value (e.g. pasted in, bypassing the formatter) is
/// correctly rejected instead of silently truncated to "valid".
String? validatePhone(String display) {
  final digitCount = display.replaceAll(RegExp(r'\D'), '').length;
  return digitCount == 10 ? null : 'Enter a valid 10-digit phone number';
}

/// Null iff [s], trimmed, is non-empty. Otherwise `'$label is required'`.
String? validateRequiredName(String s, String label) {
  return s.trim().isEmpty ? '$label is required' : null;
}

/// Null iff [s], trimmed, is a non-empty, valid email address.
String? validateEmailTrimmed(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return 'Email is required';
  if (!EmailValidator.validate(trimmed)) {
    return 'Not a valid email address. Should be your@email.com';
  }
  return null;
}

/// Formats a US phone number as the user types or deletes, keeping the
/// cursor pinned to the end of the formatted text. Both typing forward and
/// deleting are handled by simply re-deriving the digits from whatever the
/// platform text field produced for this edit and reformatting from
/// scratch — there is no special-casing of "deleted a `)` or `-`" because
/// re-deriving digits and reformatting already produces the right visual
/// result (a formatting character with no digit next to it just doesn't
/// reappear).
class UsPhoneInputFormatter extends TextInputFormatter {
  const UsPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final formatted = formatUsPhone(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
