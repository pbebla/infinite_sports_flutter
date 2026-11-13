// Live everywhere, Task 7 — the reveal gate the squad viewer and the match tab
// share (lib/fantasy/data/answer_gate.dart): ready when every registered
// stream has answered (data or error) or the bound has passed, latched.

import 'dart:async';

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

  // Final review I4: THE defensive gated listen (it used to exist four times).
  group('listen', () {
    test('a value: stored, answered (not failed), one repaint', () async {
      var repaints = 0;
      final gate = AnswerGate(onChanged: () => repaints++);
      final source = StreamController<int>();
      int? stored;
      final sub = gate.listen<int>('feed', () => source.stream,
          onData: (v) => stored = v);
      expect(sub, isNotNull);
      expect(gate.ready, isFalse);
      source.add(7);
      await Future<void>.delayed(Duration.zero);
      expect(stored, 7);
      expect(gate.ready, isTrue);
      expect(gate.allAnswered, isTrue);
      expect(gate.anyFailed, isFalse);
      expect(repaints, 1);
      await sub!.cancel();
      await source.close();
      gate.dispose();
    });

    test('an error: answered as FAILED, onError runs, one repaint — and the '
        'next value clears the failure', () async {
      var repaints = 0;
      var resets = 0;
      final gate = AnswerGate(onChanged: () => repaints++);
      final source = StreamController<int>();
      int? stored;
      final sub = gate.listen<int>('feed', () => source.stream,
          onData: (v) => stored = v, onError: () => resets++);
      source.addError(StateError('permission denied'));
      await Future<void>.delayed(Duration.zero);
      expect(gate.ready, isTrue);
      expect(gate.anyFailed, isTrue);
      expect(stored, isNull);
      expect(resets, 1);
      expect(repaints, 1);

      source.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(stored, 3);
      expect(gate.anyFailed, isFalse);
      expect(repaints, 2);
      await sub!.cancel();
      await source.close();
      gate.dispose();
    });

    test('a stream that cannot even be created: answered (failed) at once, '
        'onError runs, NO repaint, null subscription, never throws', () {
      var repaints = 0;
      var resets = 0;
      final gate = AnswerGate(onChanged: () => repaints++);
      final sub = gate.listen<int>(
          'feed', () => throw StateError('no Firebase app'),
          onData: (_) {}, onError: () => resets++);
      expect(sub, isNull);
      expect(gate.ready, isTrue);
      expect(gate.anyFailed, isTrue);
      expect(resets, 1);
      expect(repaints, 0);
      gate.dispose();
    });

    test('every listened feed must answer before the gate opens', () async {
      final gate = AnswerGate(onChanged: () {});
      final a = StreamController<int>();
      final b = StreamController<int>();
      gate.listen<int>('a', () => a.stream, onData: (_) {});
      gate.listen<int>('b', () => b.stream, onData: (_) {});
      a.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(gate.allAnswered, isFalse);
      expect(gate.ready, isFalse);
      b.addError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(gate.ready, isTrue);
      await a.close();
      await b.close();
      gate.dispose();
    });

    test('cancel stops: no value, no repaint after the subscription is '
        'cancelled — nor after the gate is disposed', () async {
      var repaints = 0;
      final gate = AnswerGate(onChanged: () => repaints++);
      final source = StreamController<int>.broadcast();
      final stored = <int>[];
      final sub = gate.listen<int>('feed', () => source.stream,
          onData: stored.add);
      await sub!.cancel();
      source.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(stored, isEmpty);
      expect(repaints, 0);
      expect(gate.ready, isFalse, reason: 'it never answered');

      final second = gate.listen<int>('other', () => source.stream,
          onData: stored.add);
      gate.dispose();
      source
        ..add(2)
        ..addError('late');
      await Future<void>.delayed(Duration.zero);
      expect(stored, isEmpty);
      expect(repaints, 0);
      await second!.cancel();
      await source.close();
    });

    testWidgets(
        'settle: a no-op while a feed is silent; once everything answered it '
        'stops the bound (no stray timer, no repaint at the bound) and opens '
        'the gate for good', (tester) async {
      var repaints = 0;
      final gate = AnswerGate(
          onChanged: () => repaints++, bound: const Duration(seconds: 2))
        ..start();
      final source = StreamController<int>();
      gate.listen<int>('feed', () => source.stream, onData: (_) {});
      gate.settle();
      expect(gate.ready, isFalse, reason: 'still silent: settle waits');
      source.add(1);
      await tester.pump();
      expect(repaints, 1);
      gate.settle();
      // A later registration can no longer close it.
      gate.expect('late');
      expect(gate.ready, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(repaints, 1, reason: 'the bound was stopped');
      gate.dispose();
      await source.close();
    });
  });
}
