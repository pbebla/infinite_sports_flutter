// Review 6, fix round 1 — the collapsed header must always be escapable and
// never entered when it cannot be left (I1), a tab switch drops the keyboard
// (M-a), and only the ACTIVE tab answers the route's primary scroll
// controller — iOS's tap-the-status-bar-to-top (M-c).
//
// Geometry at 360 × 740 (no keyboard): app bar 56, header 260 expanded / 40
// collapsed, tab row 48 → the tab body is 376 px tall expanded and 596 px
// collapsed. Rows are 48 px. The "fits only when collapsed" band is content
// between 376 and 596 px (8–12 rows); there, collapsing would leave a
// scroll view that only drags when it overflows with nothing to drag — so
// the header must never collapse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/collapsing_tab_shell.dart';

const _labels = ['A', 'B', 'C'];

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.rows, this.withField = false});

  /// Rows per tab.
  final Map<String, int> rows;
  final bool withField;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late Map<String, int> rows = Map.of(widget.rows);
  void setRows(String tab, int n) => setState(() => rows[tab] = n);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hub')),
      body: CollapsingTabShell(
        expandedHeader: const SizedBox(
            height: 260, child: Center(child: Text('BIG HEADER'))),
        collapsedHeader:
            const SizedBox(height: 40, child: Center(child: Text('SLIM BAR'))),
        tabs: _labels,
        children: [
          // A: like My Team / News — its OWN controller, so it only drags
          // while its content overflows.
          _OwnControllerList(
              key: const ValueKey('list_A'),
              rows: rows['A']!,
              withField: widget.withField),
          // B: like Players — the route's primary controller (always drags).
          ListView.builder(
            key: const ValueKey('list_B'),
            itemCount: rows['B']!,
            itemBuilder: (_, i) => SizedBox(height: 48, child: Text('B row $i')),
          ),
          _OwnControllerList(key: const ValueKey('list_C'), rows: rows['C']!),
        ],
      ),
    );
  }
}

class _OwnControllerList extends StatefulWidget {
  const _OwnControllerList(
      {super.key, required this.rows, this.withField = false});
  final int rows;
  final bool withField;

  @override
  State<_OwnControllerList> createState() => _OwnControllerListState();
}

class _OwnControllerListState extends State<_OwnControllerList> {
  final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _c,
      child: Column(children: [
        if (widget.withField)
          const SizedBox(height: 48, child: TextField(key: ValueKey('field'))),
        for (var i = 0; i < widget.rows; i++)
          SizedBox(height: 48, child: Text('row $i')),
      ]),
    );
  }
}

Future<GlobalKey<_HarnessState>> _pump(WidgetTester tester,
    {required Map<String, int> rows, bool withField = false}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(MaterialApp(
    home: _Harness(key: key, rows: rows, withField: withField),
  ));
  await tester.pumpAndSettle();
  return key;
}

bool _collapsed(WidgetTester tester) =>
    find.text('SLIM BAR').evaluate().isNotEmpty &&
    find.text('BIG HEADER').evaluate().isEmpty;

ScrollPosition _pos(WidgetTester tester, String tab) => tester
    .state<ScrollableState>(find.descendant(
        of: find.byKey(ValueKey('list_$tab'), skipOffstage: false),
        matching: find.byType(Scrollable),
        skipOffstage: false))
    .position;

/// A slow finger drag of [dy] in small steps with the finger held down
/// (the reviewer's case: the collapse runs while the finger is still on the
/// glass), then release; counts header state changes while pumping.
Future<int> _slowDrag(WidgetTester tester, double dy,
    {Offset at = const Offset(180, 600)}) async {
  var changes = 0;
  var last = _collapsed(tester);
  void sample() {
    final now = _collapsed(tester);
    if (now != last) changes++;
    last = now;
  }

  final g = await tester.startGesture(at);
  final steps = (dy.abs() / 4).ceil();
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
    sample();
  }
  await g.up();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    sample();
  }
  return changes;
}

void main() {
  group('I1 — never stuck collapsed', () {
    for (final rows in [3, 8, 10, 12]) {
      testWidgets('$rows rows (${rows * 48} px; short or fits only when '
          'collapsed): a slow drag never collapses the header', (tester) async {
        await _pump(tester, rows: {'A': rows, 'B': 60, 'C': 60});
        final changes = await _slowDrag(tester, -200);
        expect(_collapsed(tester), isFalse);
        expect(changes, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long content: collapses, stays draggable, a pull-down at '
        'the top expands it again', (tester) async {
      await _pump(tester, rows: {'A': 30, 'B': 60, 'C': 60});
      final changes = await _slowDrag(tester, -200);
      expect(_collapsed(tester), isTrue);
      expect(changes, 1);
      expect(_pos(tester, 'A').maxScrollExtent, greaterThan(0));
      await _slowDrag(tester, 400, at: const Offset(180, 300));
      expect(_collapsed(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every drag that ends collapsed leaves the tab scrollable — '
        'swept across the boundary band (8 to 20 rows)', (tester) async {
      for (var rows = 8; rows <= 20; rows++) {
        await _pump(tester, rows: {'A': rows, 'B': 60, 'C': 60});
        final changes = await _slowDrag(tester, -240);
        expect(changes, lessThanOrEqualTo(1), reason: '$rows rows');
        if (_collapsed(tester)) {
          expect(_pos(tester, 'A').maxScrollExtent, greaterThan(16),
              reason: '$rows rows collapsed with nothing left to drag');
        }
        expect(tester.takeException(), isNull, reason: '$rows rows');
      }
    });

    testWidgets('content shrinking under a collapsed header expands it (no '
        'flicker back)', (tester) async {
      final key = await _pump(tester, rows: {'A': 30, 'B': 60, 'C': 60});
      await _slowDrag(tester, -200);
      expect(_collapsed(tester), isTrue);
      key.currentState!.setRows('A', 9); // fits once collapsed
      var changes = 0;
      var last = true;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final now = _collapsed(tester);
        if (now != last) changes++;
        last = now;
      }
      expect(_collapsed(tester), isFalse);
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tab switch from a scrolled tab to a short one expands; back '
        'restores the long tab collapsed', (tester) async {
      await _pump(tester, rows: {'A': 30, 'B': 60, 'C': 3});
      await _slowDrag(tester, -200);
      expect(_collapsed(tester), isTrue);
      await tester.tap(find.widgetWithText(Tab, 'C'));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isFalse);
      await tester.tap(find.widgetWithText(Tab, 'A'));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isTrue);
      expect(_pos(tester, 'A').maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard: collapsed while it is open, closing it (content '
        'now fits) expands the header', (tester) async {
      await _pump(tester, rows: {'A': 11, 'B': 60, 'C': 60});
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _slowDrag(tester, -120, at: const Offset(180, 380));
      expect(_collapsed(tester), isTrue);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
