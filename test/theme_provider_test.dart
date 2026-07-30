// Unit tests for the pure startup dark-mode default resolver
// (lib/misc/theme_provider.dart). No Firebase/SharedPreferences involved —
// this only tests the `bool? -> bool` decision `main()` feeds into
// `ThemeProvider` (auth-wall F2 owner feedback: default to dark for
// brand-new installs).

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/theme_provider.dart';

void main() {
  group('resolveDarkModeDefault', () {
    test('defaults to dark (true) when no pref is stored yet', () {
      expect(resolveDarkModeDefault(null), isTrue);
    });

    test('keeps an explicit stored false (user chose light)', () {
      expect(resolveDarkModeDefault(false), isFalse);
    });

    test('keeps an explicit stored true (user chose dark)', () {
      expect(resolveDarkModeDefault(true), isTrue);
    });
  });
}
