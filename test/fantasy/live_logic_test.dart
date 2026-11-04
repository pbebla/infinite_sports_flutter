// Live everywhere, Task 5 — the locked My Team's pure copy and sources
// (lib/fantasy/hub/live_logic.dart): the strip text for each state of a
// locked gameweek, the chip's week text per player status, and the resolver
// that turns the locked week's sources (the live feed, the manager's live
// squad, the settled History week, the official Overall row) into ONE view.
// Copy is the plan's, verbatim.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';

LiveSlot slot(String id, int tenths, {int x = 1, bool sub = false}) => LiveSlot(
    playerId: id, countedTenths: tenths, multiplier: x, autoSubbedIn: sub);

LivePlayer player(LivePlayerStatus st, {int pts = 0}) =>
    LivePlayer(pts: pts, st: st, total: 0, form: 0, ppg: 0, games: 0, own: 0);

const liveMeta = LiveMeta(gw: 3, state: LiveState.live);
const settledMeta = LiveMeta(gw: 3, state: LiveState.settled);

void main() {
  group('lockedStripText (the strip copy, verbatim)', () {
    test('before any game started', () {
      expect(lockedStripText(const LockedWeekView.waiting()),
          'Locked · waiting for kickoff');
    });

    test('live: "{W} pts · #{R}" and the movement only when it moved', () {
      expect(
          lockedStripText(
              const LockedWeekView.live(weekPoints: 34, rank: 5, movement: 2)),
          '34 pts · #5 ▲2');
      expect(
          lockedStripText(
              const LockedWeekView.live(weekPoints: 34, rank: 5, movement: -1)),
          '34 pts · #5 ▼1');
      expect(
          lockedStripText(
              const LockedWeekView.live(weekPoints: 34, rank: 5, movement: 0)),
          '34 pts · #5');
      expect(
          lockedStripText(const LockedWeekView.live(weekPoints: 0, rank: 12)),
          '0 pts · #12');
    });

    test('settled, until editing reopens', () {
      expect(
          lockedStripText(
              const LockedWeekView.settled(weekPoints: 34, rank: 5)),
          'Final · 34 pts · #5');
    });

    test('voided', () {
      expect(lockedStripText(const LockedWeekView.voided()),
          'Voided · this week counts 0');
    });

    test('invalid squad', () {
      expect(lockedStripText(const LockedWeekView.invalid()),
          "0 pts · this week didn't count");
    });

    test('a rank that is not known yet is left out, never a made-up #0', () {
      expect(
          lockedStripText(const LockedWeekView.live(weekPoints: 9)), '9 pts');
      expect(lockedStripText(const LockedWeekView.settled(weekPoints: 9)),
          'Final · 9 pts');
    });

    test('the parts: the movement is separate so the strip can colour it', () {
      final up = lockedStripParts(
          const LockedWeekView.live(weekPoints: 34, rank: 5, movement: 2));
      expect(up.main, '34 pts · #5');
      expect(up.movement, '▲2');
      final down = lockedStripParts(
          const LockedWeekView.live(weekPoints: 34, rank: 5, movement: -3));
      expect(down.movement, '▼3');
      expect(
          lockedStripParts(const LockedWeekView.settled(
                  weekPoints: 34, rank: 5, movement: 4))
              .movement,
          isNull,
          reason: 'the settled copy has no movement');
    });

    test('only the live view shows the pill', () {
      expect(const LockedWeekView.live(weekPoints: 1).isLive, isTrue);
      for (final v in [
        const LockedWeekView.waiting(),
        const LockedWeekView.settled(weekPoints: 1),
        const LockedWeekView.voided(),
        const LockedWeekView.invalid(),
      ]) {
        expect(v.isLive, isFalse);
      }
    });
  });

  group('chipWeekText (the chip copy, verbatim)', () {
    test('pending → Not started', () {
      expect(
          chipWeekText(slot('A', 0), LivePlayerStatus.pending), 'Not started');
    });

    test('live → "{pts} pts · live"', () {
      expect(chipWeekText(slot('A', 80, x: 2), LivePlayerStatus.live),
          '8 pts · live');
    });

    test('done → "{pts} pts"', () {
      expect(chipWeekText(slot('A', 120), LivePlayerStatus.done), '12 pts');
      expect(chipWeekText(slot('A', 0), LivePlayerStatus.done), '0 pts');
    });

    test('out → Out', () {
      expect(chipWeekText(slot('A', 0), LivePlayerStatus.out), 'Out');
    });

    test('one decimal only when not whole (bench half points)', () {
      expect(chipWeekText(slot('A', 25), LivePlayerStatus.done), '2.5 pts');
      expect(
          chipWeekText(slot('A', 25), LivePlayerStatus.live), '2.5 pts · live');
      expect(chipWeekText(slot('A', 30), LivePlayerStatus.done), '3 pts');
      expect(chipWeekText(slot('A', 105), LivePlayerStatus.done), '10.5 pts');
    });

    test('a negative week reads as a negative number', () {
      expect(chipWeekText(slot('A', -20), LivePlayerStatus.done), '-2 pts');
      expect(chipWeekText(slot('A', -5), LivePlayerStatus.done), '-0.5 pts');
    });

    test('no slot → no text', () {
      expect(chipWeekText(null, LivePlayerStatus.done), isNull);
      expect(chipWeekText(null, LivePlayerStatus.out), isNull);
    });
  });

  group('resolveLockedWeek', () {
    LiveSquad liveSquad() => LiveSquad(totalTenths: 345, week: 34, slots: [
          slot('Ava', 160, x: 2),
          slot('Deb', 40),
          slot('Bench Bob', 25),
        ]);

    FantasyLiveState liveState({LiveMeta? meta = liveMeta}) => FantasyLiveState(
          meta: meta,
          board: const {
            'me': LiveBoardRow(o: 90, r: 5, m: 2, w: 34, wr: 1),
          },
          players: {
            'Ava': player(LivePlayerStatus.live, pts: 8),
            'Deb': player(LivePlayerStatus.pending),
            'Bench Bob': player(LivePlayerStatus.done, pts: 5),
          },
        );

    LockedWeekModel resolve({
      Set<int> voided = const {},
      LockedWeekSources sources = const LockedWeekSources(),
      String? uid = 'me',
    }) =>
        resolveLockedWeek(
            week: 3, uid: uid, voidedWeeks: voided, sources: sources);

    test(
        'nothing known (before kickoff, or no data yet) → waiting, no chip '
        'text', () {
      final m = resolve();
      expect(lockedStripText(m.view), 'Locked · waiting for kickoff');
      expect(m.chipTextFor('Ava'), isNull);
    });

    test(
        'live: week points from the live squad, rank + movement from the '
        'live board, chip text from each player\'s live status', () {
      final m = resolve(
          sources:
              LockedWeekSources(live: liveState(), liveSquad: liveSquad()));
      expect(m.view.isLive, isTrue);
      expect(lockedStripText(m.view), '34 pts · #5 ▲2');
      expect(m.chipTextFor('Ava'), '16 pts · live');
      expect(m.chipTextFor('Deb'), 'Not started');
      expect(m.chipTextFor('Bench Bob'), '2.5 pts');
      expect(m.chipTextFor('Nobody'), isNull);
    });

    test(
        'live: a player the live feed does not carry still shows his '
        'counted points (done), never a made-up status', () {
      final m = resolve(
          sources: LockedWeekSources(
              live: FantasyLiveState(
                  meta: liveMeta,
                  board: const {'me': LiveBoardRow(o: 1, r: 1)}),
              liveSquad: liveSquad()));
      expect(m.chipTextFor('Ava'), '16 pts');
    });

    test('a settled tombstone or another week\'s meta overlays nothing', () {
      for (final meta in [
        settledMeta,
        const LiveMeta(gw: 2, state: LiveState.live)
      ]) {
        final m = resolve(
            sources: LockedWeekSources(
                live: liveState(meta: meta), liveSquad: liveSquad()));
        expect(m.view.kind, LockedWeekKind.waiting);
        expect(m.chipTextFor('Ava'), isNull);
      }
    });

    test(
        'settled: History net tenths (truncated) + the official Overall '
        'rank, every chip "done"', () {
      final m = resolve(
        sources: LockedWeekSources(
          live: liveState(meta: settledMeta),
          history: HistoryWeek(totalTenths: 349, slots: [
            slot('Ava', 160, x: 2),
            slot('Bench Bob', 25),
          ]),
          overall: const OverallStanding(rank: 4, movement: 1),
        ),
      );
      expect(lockedStripText(m.view), 'Final · 34 pts · #4');
      expect(m.view.isLive, isFalse);
      expect(m.chipTextFor('Ava'), '16 pts');
      expect(m.chipTextFor('Bench Bob'), '2.5 pts');
    });

    test(
        'settled: a negative net week truncates toward zero like '
        'wholePoints', () {
      final m = resolve(
          sources: const LockedWeekSources(
              history: HistoryWeek(totalTenths: -45, slots: []),
              overall: OverallStanding(rank: 9)));
      expect(lockedStripText(m.view), 'Final · -4 pts · #9');
    });

    test(
        'voided comes from the Voided set — never from a live record that '
        'reads "not voided"', () {
      final m = resolve(voided: {
        3
      }, sources: LockedWeekSources(live: liveState(), liveSquad: liveSquad()));
      expect(lockedStripText(m.view), 'Voided · this week counts 0');
      expect(m.chipTextFor('Ava'), isNull,
          reason: 'nothing counted in a voided week');
    });

    test('voided also when History says so (the re-finalize mirror)', () {
      final m = resolve(
          sources: const LockedWeekSources(
              history: HistoryWeek(totalTenths: 0, voided: true, slots: [])));
      expect(m.view.kind, LockedWeekKind.voided);
    });

    test('another week voided does not void this one', () {
      final m = resolve(voided: {
        2
      }, sources: LockedWeekSources(live: liveState(), liveSquad: liveSquad()));
      expect(m.view.isLive, isTrue);
    });

    test(
        'invalid squad: live (a squad with no slots) and settled (the '
        'Invalid marker)', () {
      final live = resolve(
          sources: LockedWeekSources(
              live: liveState(),
              liveSquad: const LiveSquad(totalTenths: 0, week: 0, slots: [])));
      expect(lockedStripText(live.view), "0 pts · this week didn't count");

      final settled = resolve(
          sources: const LockedWeekSources(
              history: HistoryWeek(totalTenths: 0, invalid: true, slots: [])));
      expect(lockedStripText(settled.view), "0 pts · this week didn't count");
    });

    test(
        'live but the manager has no live squad (no team scored) and no '
        'History → waiting, never a made-up 0', () {
      final m = resolve(sources: LockedWeekSources(live: liveState()));
      expect(m.view.kind, LockedWeekKind.waiting);
    });

    test(
        'live numbers win over a History row of the same week while live '
        'still applies (the hand-over order: History first, tombstone last)',
        () {
      final m = resolve(
          sources: LockedWeekSources(
              live: liveState(),
              liveSquad: liveSquad(),
              history: HistoryWeek(totalTenths: 350, slots: [slot('Ava', 1)])));
      expect(lockedStripText(m.view), '34 pts · #5 ▲2');
    });

    test('settled without a rank yet still says Final and the points', () {
      final m = resolve(
          sources: const LockedWeekSources(
              history: HistoryWeek(totalTenths: 120, slots: [])));
      expect(lockedStripText(m.view), 'Final · 12 pts');
    });

    test('History without its net tenths is not a number to show → waiting',
        () {
      final m = resolve(
          sources: const LockedWeekSources(history: HistoryWeek(slots: [])));
      expect(m.view.kind, LockedWeekKind.waiting);
    });

    test('signed out (no uid): no board row, so no rank', () {
      final m = resolve(
          uid: null,
          sources:
              LockedWeekSources(live: liveState(), liveSquad: liveSquad()));
      expect(lockedStripText(m.view), '34 pts');
    });
  });

  // Which gameweek the locked My Team is about, and when that changes.
  group('lockedWeekNumber / nextLockTransition', () {
    // GW n locks Oct 4 + 7(n-1) at 22:00 UTC; each stays "current" for 24 h
    // after its lock (currentGameweek).
    final gws = [
      for (var n = 1; n <= 3; n++)
        Gameweek(
          number: n,
          date: '10${(4 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];
    int? week(DateTime now,
            {FantasyLockOverride override = FantasyLockOverride.auto,
            List<Gameweek>? schedule}) =>
        lockedWeekNumber(
            lockOverride: override, gameweeks: schedule ?? gws, nowUtc: now);

    test('editing open (auto): no locked week', () {
      expect(week(DateTime.utc(2026, 10, 10, 12)), isNull);
    });

    test('from the lock until the day ends: that gameweek', () {
      expect(week(DateTime.utc(2026, 10, 11, 22, 0, 1)), 2);
      expect(week(DateTime.utc(2026, 10, 12, 21, 59)), 2);
    });

    test('24 h after the lock editing reopens on the next gameweek: none', () {
      expect(week(DateTime.utc(2026, 10, 12, 22)), isNull);
    });

    test(
        'the owner\'s lock override: the current gameweek is the locked '
        'one', () {
      expect(
          week(DateTime.utc(2026, 10, 9, 12),
              override: FantasyLockOverride.locked),
          2);
    });

    test('the owner\'s open override: never locked, even past the lock', () {
      expect(
          week(DateTime.utc(2026, 10, 11, 23),
              override: FantasyLockOverride.open),
          isNull);
    });

    test('season over (no current gameweek): the last gameweek, final', () {
      expect(week(DateTime.utc(2026, 12, 1)), 3);
    });

    test('no schedule yet: unknown, never guessed', () {
      expect(week(DateTime.utc(2026, 10, 11, 23), schedule: const []), isNull);
      expect(
          lockedWeekNumber(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: null,
              nowUtc: DateTime.utc(2026, 10, 11, 23)),
          isNull);
    });

    test(
        'the next transition: the lock while open, the day end while locked, '
        'none once the season is over', () {
      expect(nextLockTransition(gws, DateTime.utc(2026, 10, 10, 12)),
          DateTime.utc(2026, 10, 11, 22));
      expect(nextLockTransition(gws, DateTime.utc(2026, 10, 11, 23)),
          DateTime.utc(2026, 10, 12, 22));
      expect(nextLockTransition(gws, DateTime.utc(2026, 12, 1)), isNull);
      expect(nextLockTransition(const [], DateTime.utc(2026, 10, 10)), isNull);
    });
  });
}
