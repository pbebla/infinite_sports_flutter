import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/categories.dart';

void main() {
  group('parseCategories', () {
    test('parses an ordered array, trimming and de-duping', () {
      expect(parseCategories(['Futsal', ' Tennis ', 'Futsal', '']),
          ['Futsal', 'Tennis']);
    });

    test('parses an index-keyed map in numeric order', () {
      expect(parseCategories({'1': 'Basketball', '0': 'Futsal', '2': 'Tennis'}),
          ['Futsal', 'Basketball', 'Tennis']);
    });

    test('falls back to defaults when empty or wrong type', () {
      expect(parseCategories(null), kDefaultCategories);
      expect(parseCategories([]), kDefaultCategories);
      expect(parseCategories('nope'), kDefaultCategories);
    });

    test('keeps custom owner order', () {
      final list = ['Backgammon', 'Tennis', 'Community'];
      expect(parseCategories(list), list);
    });
  });
}
