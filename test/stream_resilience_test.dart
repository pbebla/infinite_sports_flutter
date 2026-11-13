// Unit tests for lib/misc/stream_resilience.dart (DB lockdown B8): a
// rules-denied RTDB stream error must become a fallback VALUE, so screens
// degrade to an empty state instead of an error state.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/stream_resilience.dart';

void main() {
  test('values pass through unchanged', () async {
    final out =
        await streamErrorsAs(Stream.fromIterable([1, 2, 3]), 0).toList();
    expect(out, [1, 2, 3]);
  });

  test('an error becomes the fallback value and the stream stays alive',
      () async {
    final controller = StreamController<List<String>>();
    controller.add(['a']);
    controller.addError(StateError('permission-denied'));
    controller.add(['b']); // later data still flows after the error
    unawaited(controller.close());

    final events =
        await streamErrorsAs(controller.stream, const <String>[]).toList();

    expect(events, [
      ['a'],
      <String>[], // the denied read degraded to the empty fallback
      ['b'],
    ]);
  });

  test('an error as the FIRST event still emits the fallback (no stuck '
      'loading state)', () async {
    final controller = StreamController<int>();
    controller.addError(Exception('denied'));
    unawaited(controller.close());
    final out = await streamErrorsAs(controller.stream, -1).toList();
    expect(out, [-1]);
  });
}
