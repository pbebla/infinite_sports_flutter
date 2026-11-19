// Second review, Minor 1: a screen's newer-value followers register only
// while mounted and are always removed on dispose (FreshFollowers mixin).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_follow.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

class _Page extends StatefulWidget {
  const _Page(this.read);
  final Completer<void> read;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with FreshFollowers {
  String name = 'saved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.read.future; // the read in flight
    followNewer('name', 'Users/u1', (v) {
      if (mounted) setState(() => name = '$v');
    });
  }

  @override
  Widget build(BuildContext context) => Text(name);
}

void main() {
  testWidgets('a page closed while its read is in flight registers nothing',
      (tester) async {
    final before = FreshReads.debugNewerCallbackCount;
    final read = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: _Page(read)));
    await tester.pumpWidget(const SizedBox()); // closed
    read.complete();
    await tester.pump();
    expect(FreshReads.debugNewerCallbackCount, before);
  });

  testWidgets('a mounted page follows, and dispose removes the follower',
      (tester) async {
    final before = FreshReads.debugNewerCallbackCount;
    final read = Completer<void>()..complete();
    await tester.pumpWidget(MaterialApp(home: _Page(read)));
    await tester.pump();
    expect(FreshReads.debugNewerCallbackCount, before + 1);
    FreshReads.debugReportNewer('Users/u1', 'Newer Name');
    await tester.pump();
    expect(find.text('Newer Name'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(FreshReads.debugNewerCallbackCount, before);
  });

  group('CoalescedRefresh (second review, Minor 4)', () {
    test('a request during a run queues exactly one more run', () async {
      var runs = 0;
      final gates = <Completer<void>>[];
      final r = CoalescedRefresh(() {
        runs++;
        final c = Completer<void>();
        gates.add(c);
        return c.future;
      });
      r.request();
      r.request(); // during run 1
      r.request(); // still during run 1: coalesced
      expect(runs, 1);
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2, reason: 'one queued run, not dropped');
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2, reason: 'nothing more queued');
    });

    test('minGap spaces runs out', () async {
      final starts = <DateTime>[];
      final r = CoalescedRefresh(() async => starts.add(DateTime.now()),
          minGap: const Duration(milliseconds: 40));
      r.request();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      r.request();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(starts, hasLength(2));
      expect(starts[1].difference(starts[0]).inMilliseconds,
          greaterThanOrEqualTo(35));
    });

    test('a failing run does not stop later runs; dispose stops them',
        () async {
      var runs = 0;
      final r = CoalescedRefresh(() async {
        runs++;
        throw StateError('x');
      });
      r.request();
      await Future<void>.delayed(Duration.zero);
      r.request();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
      r.dispose();
      r.request();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
    });
  });
}
