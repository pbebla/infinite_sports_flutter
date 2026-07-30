import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';

void main() {
  group('MatchClock.elapsed', () {
    test('running: now - startedAt - pausedAccum', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: null);
      expect(c.elapsedAt(61000), const Duration(seconds: 60));
    });
    test('subtracts accumulated pauses while running', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 10000, pausedAtMs: null);
      expect(c.elapsedAt(61000), const Duration(seconds: 50));
    });
    test('frozen while paused: uses pausedAt, not now', () {
      const c = MatchClock(startedAtMs: 1000, pausedAccumMs: 0, pausedAtMs: 31000);
      expect(c.elapsedAt(99999), const Duration(seconds: 30));
    });
    test('never negative', () {
      const c = MatchClock(startedAtMs: 5000, pausedAccumMs: 0, pausedAtMs: null);
      expect(c.elapsedAt(1000), Duration.zero);
    });
    test('isPaused reflects pausedAt presence', () {
      expect(const MatchClock(startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: 5).isPaused, true);
      expect(const MatchClock(startedAtMs: 0, pausedAccumMs: 0, pausedAtMs: null).isPaused, false);
    });
  });

  group('labels', () {
    test('minuteLabel is 1-based, min 1', () {
      expect(minuteLabel(Duration.zero), "1'");
      expect(minuteLabel(const Duration(seconds: 59)), "1'");
      expect(minuteLabel(const Duration(seconds: 60)), "2'");
      expect(minuteLabel(const Duration(minutes: 36, seconds: 30)), "37'");
    });
    test('clockLabel is mm:ss zero-padded', () {
      expect(clockLabel(Duration.zero), '00:00');
      expect(clockLabel(const Duration(minutes: 47, seconds: 30)), '47:30');
      expect(clockLabel(const Duration(minutes: 5, seconds: 4)), '05:04');
    });
  });

  group('MatchClock.fromMap', () {
    test('reads PascalCase fields', () {
      final c = MatchClock.fromMap({'StartedAt': 1000, 'PausedAccumMs': 200, 'PausedAt': 3000});
      expect(c, isNotNull);
      expect(c!.startedAtMs, 1000);
      expect(c.pausedAccumMs, 200);
      expect(c.pausedAtMs, 3000);
    });
    test('missing PausedAt means running', () {
      final c = MatchClock.fromMap({'StartedAt': 1000});
      expect(c!.pausedAtMs, isNull);
      expect(c.pausedAccumMs, 0);
    });
    test('null/!map/absent StartedAt -> null (graceful, show LIVE without minute)', () {
      expect(MatchClock.fromMap(null), isNull);
      expect(MatchClock.fromMap('nope'), isNull);
      expect(MatchClock.fromMap({'PausedAccumMs': 5}), isNull);
    });
  });
}
