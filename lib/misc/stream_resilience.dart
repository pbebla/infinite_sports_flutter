// Stream hardening for rules-denied RTDB reads (DB lockdown B8) — pure
// dart:async, no Flutter/Firebase imports (activity_entry.dart-style), so
// test/stream_resilience_test.dart covers it without a Firebase app.

import 'dart:async';

/// Re-emits [source] with every error replaced by a [fallback] VALUE, so a
/// consumer (StreamBuilder etc.) degrades to an empty state instead of an
/// error state — e.g. an onValue read the default-deny rules refuse for
/// this viewer. The stream stays alive: later data events still flow.
Stream<T> streamErrorsAs<T>(Stream<T> source, T fallback) =>
    source.transform(StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) => sink.add(fallback),
    ));
