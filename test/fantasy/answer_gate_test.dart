// Live everywhere, Task 7 — the reveal gate the squad viewer and the match tab
// share (lib/fantasy/data/answer_gate.dart): ready when every registered
// stream has answered (data or error) or the bound has passed, latched.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/answer_gate.dart';

void main() {
  test('nothing registered: ready at once', () {
    final gate = AnswerGate(onChanged: () {});
    expect(gate.ready, isTrue);
  });

  test('ready only once EVERY registered stream has answered', () {
    final gate = AnswerGate(onChanged: () {})
      ..expect('live')
      ..expect('voided');
    expect(gate.ready, isFalse);
    gate.answer('live');
    expect(gate.ready, isFalse);
    gate.answer('voided');
    expect(gate.ready, isTrue);
  });

  test(
      'registering the same name twice waits for it once; answering first '
      'then registering is no wait', () {
    final gate = AnswerGate(onChanged: () {})
      ..expect('live')
      ..expect('live');
    gate.answer('live');
    expect(gate.ready, isTrue);

    final early = AnswerGate(onChanged: () {})
      ..answer('live')
      ..expect('live');
    expect(early.ready, isTrue);
  });

  testWidgets('the bound opens the gate for a silent stream and repaints',
      (tester) async {
    var repaints = 0;
    final gate = AnswerGate(
        onChanged: () => repaints++, bound: const Duration(seconds: 2))
      ..expect('live')
      ..start();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(gate.ready, isFalse);
    expect(repaints, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(gate.ready, isTrue);
    expect(repaints, 1);
    gate.dispose();
  });

  test('latched: a stream registered after the gate opened never closes it',
      () {
    final gate = AnswerGate(onChanged: () {})..expect('a');
    gate.answer('a');
    expect(gate.ready, isTrue);
    gate.expect('history-3');
    expect(gate.ready, isTrue);
  });

  testWidgets('dispose cancels the bound: no repaint afterwards',
      (tester) async {
    var repaints = 0;
    final gate = AnswerGate(
        onChanged: () => repaints++, bound: const Duration(seconds: 2))
      ..expect('live')
      ..start();
    gate.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(repaints, 0);
  });
}
