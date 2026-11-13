// The live gameweek list (season setup + schedule changes): the app derives
// its weeks from THREE RTDB nodes — the season's `Date`, the server's frozen
// `LockedWeeks` ledger and the legacy `Start Time` — and must show a week list
// only once it has heard all three. One missing piece gives a wrong list: a
// ledger that has not arrived would renumber a locked week, a Start Time that
// has not arrived would leave an early-kickoff deadline too late.
//
// Pure Dart (the RTDB reads arrive as streams of raw node values), so the
// all-answered rule, the re-derive and the error forwarding are unit-tested in
// test/fantasy/fantasy_schedule_feed_test.dart. The derivation itself is
// `gameweeksFromNodes` (fantasy_parsers.dart), the twin of the server's
// loadSeasonGameweeks.

import 'dart:async';

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

/// The gameweeks derived from [dates] (`<sport>/<season>/Date`), [lockedWeeks]
/// (`Fantasy/<sport>/<season>/LockedWeeks`) and [startTime]
/// (`<sport>/<season>/Start Time`) with [config]'s lock hour and the owner's
/// [overrides].
///
/// Emits nothing until ALL THREE have produced an event — an absent node
/// arrives as a null event, and that is an answer — then re-derives on every
/// later event of any of them. An error on any node is forwarded as an error
/// (never as an empty list: a read that failed is not "no weeks"), and so is
/// a derivation that throws. Cancelling cancels all three listeners.
Stream<List<Gameweek>> gameweeksFromNodeStreams({
  required Stream<Object?> dates,
  required Stream<Object?> lockedWeeks,
  required Stream<Object?> startTime,
  required FantasyConfig config,
  required ScheduleOverrides overrides,
}) {
  final subs = <StreamSubscription<Object?>>[];
  Object? dateNode;
  Object? lockedNode;
  Object? startNode;
  var dateAnswered = false;
  var lockedAnswered = false;
  var startAnswered = false;
  late final StreamController<List<Gameweek>> controller;

  void emit() {
    if (!(dateAnswered && lockedAnswered && startAnswered)) return;
    try {
      controller.add(gameweeksFromNodes(
        dateNode: dateNode,
        lockedWeeksNode: lockedNode,
        startTimeNode: startNode,
        config: config,
        overrides: overrides,
      ));
    } catch (e, s) {
      controller.addError(e, s);
    }
  }

  controller = StreamController<List<Gameweek>>(
    onListen: () {
      subs.add(dates.listen((node) {
        dateNode = node;
        dateAnswered = true;
        emit();
      }, onError: controller.addError));
      subs.add(lockedWeeks.listen((node) {
        lockedNode = node;
        lockedAnswered = true;
        emit();
      }, onError: controller.addError));
      subs.add(startTime.listen((node) {
        startNode = node;
        startAnswered = true;
        emit();
      }, onError: controller.addError));
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
