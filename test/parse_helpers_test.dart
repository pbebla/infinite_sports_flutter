import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

void main() {
  group('parseBool', () {
    test('returns bool from bool', () {
      expect(parseBool(true), true);
      expect(parseBool(false), false);
    });

    test('returns bool from "true"/"false" string', () {
      expect(parseBool('true'), true);
      expect(parseBool('false'), false);
      expect(parseBool('TRUE'), true);
      expect(parseBool('False'), false);
    });

    test('returns bool from int 0/1', () {
      expect(parseBool(1), true);
      expect(parseBool(0), false);
    });

    test('returns default for unknown values', () {
      expect(parseBool(null), false);
      expect(parseBool('yes'), false);
      expect(parseBool('no'), false);
      expect(parseBool(2), false);
      expect(parseBool(null, defaultValue: true), true);
    });
  });

  group('parseInt', () {
    test('returns int from int', () {
      expect(parseInt(42), 42);
      expect(parseInt(0), 0);
    });

    test('returns int from double', () {
      expect(parseInt(3.7), 3);
      expect(parseInt(0.0), 0);
    });

    test('returns int from numeric string', () {
      expect(parseInt('42'), 42);
      expect(parseInt('-7'), -7);
    });

    test('returns default for non-numeric', () {
      expect(parseInt(null), 0);
      expect(parseInt('abc'), 0);
      expect(parseInt('1.5'), 0); // not a valid int string
      expect(parseInt(null, defaultValue: 99), 99);
    });
  });

  group('parseDouble', () {
    test('returns double from double', () {
      expect(parseDouble(3.14), 3.14);
      expect(parseDouble(0.0), 0.0);
    });

    test('returns double from int', () {
      expect(parseDouble(42), 42.0);
    });

    test('returns double from numeric string', () {
      expect(parseDouble('3.14'), 3.14);
      expect(parseDouble('42'), 42.0);
    });

    test('returns default for non-numeric', () {
      expect(parseDouble(null), 0.0);
      expect(parseDouble('abc'), 0.0);
      expect(parseDouble(null, defaultValue: 9.9), 9.9);
    });
  });

  group('parseString', () {
    test('returns string from string', () {
      expect(parseString('hello'), 'hello');
      expect(parseString(''), '');
    });

    test('converts non-strings to strings', () {
      expect(parseString(42), '42');
      expect(parseString(true), 'true');
      expect(parseString(3.14), '3.14');
    });

    test('returns default for null', () {
      expect(parseString(null), '');
      expect(parseString(null, defaultValue: 'fallback'), 'fallback');
    });
  });

  group('parseMap', () {
    test('returns map from map', () {
      expect(parseMap({'a': 1}), {'a': 1});
    });

    test('returns empty for non-map', () {
      expect(parseMap(null), <dynamic, dynamic>{});
      expect(parseMap('not a map'), <dynamic, dynamic>{});
      expect(parseMap([1, 2, 3]), <dynamic, dynamic>{});
    });
  });

  group('firstNonNull', () {
    test('returns first non-null value from a map for given keys', () {
      final data = {'Name': 'Alice', 'age': 30};
      expect(firstNonNull(data, ['name', 'Name']), 'Alice');
      expect(firstNonNull(data, ['Age', 'age']), 30);
      expect(firstNonNull(data, ['missing1', 'missing2']), null);
    });

    test('returns null when all keys are missing', () {
      expect(firstNonNull({}, ['a', 'b']), null);
    });
  });
}
