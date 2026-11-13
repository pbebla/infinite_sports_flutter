// The ONE tolerant int reader behind every fantasy parser (parse_ints.dart):
// RTDB hands numbers back as ints, doubles or — from hand-edited nodes —
// strings, and none of them may throw.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/parse_ints.dart';

void main() {
  group('tolerantInt', () {
    test('ints pass through, negatives and zero included', () {
      expect(tolerantInt(42), 42);
      expect(tolerantInt(0), 0);
      expect(tolerantInt(-7), -7);
    });

    test('finite doubles truncate toward zero', () {
      expect(tolerantInt(3.9), 3);
      expect(tolerantInt(-3.9), -3);
      expect(tolerantInt(12.0), 12);
    });

    test('non-finite doubles are null, never a throw', () {
      expect(tolerantInt(double.nan), isNull);
      expect(tolerantInt(double.infinity), isNull);
      expect(tolerantInt(double.negativeInfinity), isNull);
    });

    test('numeric strings parse, padding trimmed', () {
      expect(tolerantInt('42'), 42);
      expect(tolerantInt('  42 '), 42);
      expect(tolerantInt('-5'), -5);
      expect(tolerantInt('\t7\n'), 7);
    });

    test('garbage and null are null', () {
      expect(tolerantInt(null), isNull);
      expect(tolerantInt(''), isNull);
      expect(tolerantInt('   '), isNull);
      expect(tolerantInt('abc'), isNull);
      expect(tolerantInt('7.5'), isNull);
      expect(tolerantInt(true), isNull);
      expect(tolerantInt(<String, Object?>{'a': 1}), isNull);
      expect(tolerantInt(<Object?>[1]), isNull);
    });
  });
}
