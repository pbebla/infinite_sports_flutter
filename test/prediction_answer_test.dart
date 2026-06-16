import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';

void main() {
  test('QuestionAnswer round-trips', () {
    final a = QuestionAnswer.fromFirebase({'Answer': 'team1', 'UpdatedAt': 123});
    expect(a!.value, 'team1');
    expect(a.updatedAt, 123);
    expect(a.toFirebase(), {'Answer': 'team1', 'UpdatedAt': 123});
  });
  test('null/!map => null', () {
    expect(QuestionAnswer.fromFirebase(null), isNull);
    expect(QuestionAnswer.fromFirebase('x'), isNull);
  });
}
