import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/match_status.dart';

void main() {
  group('MatchStatus', () {
    test('fromInt maps 0 to pending', () {
      expect(MatchStatus.fromInt(0), MatchStatus.pending);
    });

    test('fromInt maps 1 to live', () {
      expect(MatchStatus.fromInt(1), MatchStatus.live);
    });

    test('fromInt maps 2 to finished', () {
      expect(MatchStatus.fromInt(2), MatchStatus.finished);
    });

    test('fromInt maps unknown ints to pending', () {
      expect(MatchStatus.fromInt(99), MatchStatus.pending);
      expect(MatchStatus.fromInt(-1), MatchStatus.pending);
    });

    test('toInt round-trips', () {
      for (final status in MatchStatus.values) {
        expect(MatchStatus.fromInt(status.toInt()), status);
      }
    });

    test('label returns human-readable text', () {
      expect(MatchStatus.pending.label, 'Upcoming');
      expect(MatchStatus.live.label, 'Live');
      expect(MatchStatus.finished.label, 'Final');
    });

    test('isLive, isFinished, isPending getters work', () {
      expect(MatchStatus.live.isLive, true);
      expect(MatchStatus.live.isFinished, false);
      expect(MatchStatus.live.isPending, false);
      expect(MatchStatus.finished.isFinished, true);
      expect(MatchStatus.pending.isPending, true);
    });
  });
}
