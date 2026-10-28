// Golden FORFEIT gameweek — the cross-engine contract for spec §8a.
//
// Loads test/fantasy/fixtures/golden_forfeit.json and replays the pipeline
// exactly like golden_test.dart:
//   mapper -> scoring -> bps/bonus -> player weeks -> squad weeks,
// asserting every expected number. The expectations were hand-computed from
// FantasyConfig.futsalDefault() BEFORE this test first ran (the math is in
// the fixture's _notes) — if the pipeline ever disagrees, find the bug;
// never copy actual values into the file. The TS port replays the same JSON
// (functions/src/lib/fantasy/golden_forfeit_replay.test.ts).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/bps.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad_week.dart';
import 'package:infinite_sports_flutter/fantasy/engine/stats_mapper.dart';

void main() {
  final fixture = jsonDecode(
          File('test/fantasy/fixtures/golden_forfeit.json').readAsStringSync())
      as Map<String, dynamic>;
  final cfg = FantasyConfig.futsalDefault(); // fixture: "config": "futsalDefault"

  final players = (fixture['players'] as List).cast<Map<String, dynamic>>();
  final posOf = {
    for (final p in players)
      p['id'] as String: FantasyPosition.parse(p['position'] as String)
  };
  final games = (fixture['games'] as List).cast<Map<String, dynamic>>();
  final expected = fixture['expected'] as Map<String, dynamic>;

  // ---- Stage 1: mapper (both teams of every game) ----
  final statsByGame = <Map<String, PlayerGameStats>>[];
  for (final g in games) {
    final node = g['node'] as Map;
    final attendanceByTeam = g['attendance'] as Map?;
    final merged = <String, PlayerGameStats>{};
    for (final team in [node['team1'] as String, node['team2'] as String]) {
      final raw = attendanceByTeam?[team] as Map?;
      merged.addAll(mapGameToStats(
        node,
        teamName: team,
        attendance: raw?.map((k, v) => MapEntry(k.toString(), v == true)),
      ));
    }
    statsByGame.add(merged);
  }

  // ---- Stage 2: per-game base points, BPS, bonus ----
  final baseByGame = <Map<String, int>>[];
  final bpsByGame = <Map<String, int>>[];
  final bonusByGame = <Map<String, int>>[];
  for (final stats in statsByGame) {
    baseByGame.add({
      for (final e in stats.entries)
        e.key: scorePlayerGame(e.value, posOf[e.key]!, cfg).total
    });
    final bps = {
      for (final e in stats.entries) e.key: bpsScore(e.value, cfg)
    };
    bpsByGame.add(bps);
    bonusByGame.add(awardBonus(bps));
  }

  // ---- Stage 3: player weeks (base + bonus) ----
  final week = <String, PlayerWeek>{};
  for (final id in posOf.keys) {
    final wk = scorePlayerWeek(
      [
        for (final stats in statsByGame)
          if (stats.containsKey(id)) stats[id]!
      ],
      posOf[id]!,
      cfg,
    );
    final bonus = bonusByGame.fold<int>(0, (a, b) => a + (b[id] ?? 0));
    week[id] = PlayerWeek(points: wk.total + bonus, played: wk.played);
  }

  test('mapper: forfeit side per player; stray-event-only players excluded',
      () {
    final exp = (expected['forfeitByGame'] as List).cast<Map>();
    expect(statsByGame.length, exp.length);
    for (var i = 0; i < exp.length; i++) {
      expect(
        {for (final e in statsByGame[i].entries) e.key: e.value.forfeit.name},
        exp[i].cast<String, String>(),
        reason: 'game $i',
      );
    }
    // Every stray event on the forfeited game was ignored: nothing tallied.
    for (final s in statsByGame[0].values) {
      expect(
          s.goals + s.assists + s.saves + s.yellows + s.reds + s.dpl, 0);
    }
    expect(statsByGame[0].containsKey('Gus'), isFalse);
  });

  test('per-game base points match hand math', () {
    final exp = (expected['basePointsByGame'] as List).cast<Map>();
    expect(baseByGame.length, exp.length);
    for (var i = 0; i < exp.length; i++) {
      expect(baseByGame[i], exp[i].cast<String, int>(), reason: 'game $i');
    }
  });

  test('per-game BPS (0 for the whole forfeited game) and bonus', () {
    final expBps = (expected['bpsByGame'] as List).cast<Map>();
    final expBonus = (expected['bonusByGame'] as List).cast<Map>();
    for (var i = 0; i < expBps.length; i++) {
      expect(bpsByGame[i], expBps[i].cast<String, int>(), reason: 'game $i');
      expect(bonusByGame[i], expBonus[i].cast<String, int>(),
          reason: 'game $i bonus');
    }
  });

  test('per-player week points and played flags (forfeiters did not play)',
      () {
    final exp = (expected['playerWeeks'] as Map).cast<String, dynamic>();
    expect(week.keys, unorderedEquals(exp.keys));
    exp.forEach((id, e) {
      expect(week[id]!.points, (e as Map)['points'], reason: id);
      expect(week[id]!.played, e['played'], reason: '$id played');
    });
  });

  test('squad weeks: forfeiting captain -> vice armband, auto-subs, no-armband '
      'week', () {
    final expSquads = (expected['squads'] as Map).cast<String, dynamic>();
    for (final s in (fixture['squads'] as List).cast<Map<String, dynamic>>()) {
      final name = s['name'] as String;
      final squad = FantasySquad.fromMap(s['squad'] as Map);
      expect(validateSquad(squad, cfg), isEmpty, reason: '$name legality');

      final exp = expSquads[name] as Map;
      final result = scoreSquadWeek(squad, week, cfg);
      expect(result.totalTenths, exp['totalTenths'], reason: name);
      expect(
        {for (final slot in result.slots) slot.playerId: slot.countedTenths},
        (exp['countedTenths'] as Map).cast<String, int>(),
        reason: '$name slots',
      );

      final armbands = [
        for (final slot in result.slots)
          if (slot.multiplier > 1) slot.playerId
      ];
      final armband = exp['armband'] as String?;
      expect(armbands, armband == null ? isEmpty : [armband],
          reason: '$name armband');
      if (armband != null) {
        expect(result.slot(armband).multiplier, exp['armbandMultiplier'],
            reason: '$name armband multiplier');
      }
      final promoted = [
        for (final slot in result.slots)
          if (slot.autoSubbedIn) slot.playerId
      ];
      expect(promoted,
          unorderedEquals((exp['autoSubbedIn'] as List).cast<String>()),
          reason: '$name auto-subs');
    }
  });
}
