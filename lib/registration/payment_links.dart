// The outside-the-app payment identities and links shared by the
// registration payment screen and the fantasy season-pass card (spec
// 2026-11-01 §2: nothing is bought inside the app). ONE source for the Venmo
// deep link and the Zelle identity — never copy them into a screen.

import 'dart:ui' show Color;

/// Venmo handle for the business profile.
const String kVenmoHandle = 'infinite-sports';

/// The Zelle account's registered number (shown + copyable).
const String kZelleNumber = '408-693-9436';

/// The recipient name Zelle displays for 408-693-9436 (owner-confirmed).
const String kZelleDisplayName = 'Zaya Shahbaz Arami';

/// Venmo's brand blue — the "Pay with Venmo" button on both screens.
const Color kVenmoBlue = Color(0xFF008CFF);

/// The amount as Venmo's `amount` query expects it: whole dollars plain
/// ("55"), cents with two decimals ("46.75") — never "55.0".
String venmoAmountText(num amount) => amount == amount.roundToDouble()
    ? amount.toInt().toString()
    : amount.toStringAsFixed(2);

/// venmo.com profile links open the Venmo app when it is installed (Android
/// App Links / iOS Universal Links); otherwise the browser loads the profile
/// page. `txn=pay` + amount + note pre-fill the payment.
Uri venmoPayUri({required num amount, required String note}) => Uri.parse(
    'https://venmo.com/$kVenmoHandle?txn=pay&amount=${venmoAmountText(amount)}'
    '&note=${Uri.encodeComponent(note)}');
