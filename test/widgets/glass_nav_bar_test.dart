import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';

Widget _host({required int selected, required void Function(int) onTab, required VoidCallback onSearch}) {
  return MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: GlassNavBar(
        destinations: const [
          GlassNavDestination(icon: Icon(Icons.sports_soccer), label: 'Matches'),
          GlassNavDestination(icon: Icon(Icons.shield_outlined), label: 'Leagues'),
          GlassNavDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Tournaments'),
          GlassNavDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
        ],
        selectedIndex: selected,
        onDestinationSelected: onTab,
        onSearchTap: onSearch,
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a destination reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(_host(selected: 0, onTab: (i) => tapped = i, onSearch: () {}));
    await tester.tap(find.text('Calendar'));
    expect(tapped, 3);
  });

  testWidgets('tapping the search circle fires onSearchTap', (tester) async {
    var searched = false;
    await tester.pumpWidget(_host(selected: 0, onTab: (_) {}, onSearch: () => searched = true));
    await tester.tap(find.byIcon(Icons.search));
    expect(searched, isTrue);
  });

  testWidgets('shows all four labels', (tester) async {
    await tester.pumpWidget(_host(selected: 0, onTab: (_) {}, onSearch: () {}));
    for (final label in ['Matches', 'Leagues', 'Tournaments', 'Calendar']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
