// Opus audit item 6 — the one helper every reveal-gating one-shot read goes
// through: RTDB once() never answers on a cold OFFLINE client, so the read
// is given up after the bound (logged) and degrades — to the caller's value,
// or a TimeoutException for callers whose failure path means "unknown".

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';

void main() {
  late List<String> logs;
  late DebugPrintCallback original;

  setUp(() {
    logs = [];
    original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() => debugPrint = original);

  const bound = Duration(milliseconds: 20);

  test('the production bound is 8 s', () {
    expect(kRevealReadTimeout, const Duration(seconds: 8));
  });

  test('an answer inside the bound passes through untouched (no log)',
      () async {
    expect(await Future.value(5).bounded('x', orElse: () => 0, timeout: bound),
        5);
    expect(logs, isEmpty);
  });

  test('no answer: the degrade value, logged', () async {
    final v = await Completer<int>()
        .future
        .bounded('Owner: start hour', orElse: () => 0, timeout: bound);
    expect(v, 0);
    expect(logs.single, 'Owner: start hour: no answer after 20ms — degrading');
  });

  test('no answer and no degrade value: a TimeoutException, logged',
      () async {
    await expectLater(
        Completer<String>().future.bounded('Pointer', timeout: bound),
        throwsA(isA<TimeoutException>()));
    expect(logs.single, 'Pointer: no answer after 20ms — failing');
  });

  test('a late answer or error after the bound is ignored', () async {
    final late = Completer<int>();
    final v = await late.future
        .bounded('Late', orElse: () => 0, timeout: bound);
    expect(v, 0);
    late.completeError(StateError('too late')); // must not surface
    await pumpEventQueue();
  });
}
