import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

void main() {
  testWidgets('renders awards + empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrophyCabinet(awards: []))));
    expect(find.textContaining('No trophies'), findsOneWidget);

    const a = Award(id: 'a', trophyId: 't', name: 'Golden Boot', icon: 'boot',
        iconType: 'builtin', tier: 'gold', sport: 'Futsal', scopeType: 'tournament',
        scopeId: 'x', season: '', edition: '2026', context: 'Summer Cup 2026',
        date: '08302026', source: 'auto');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrophyCabinet(awards: [a]))));
    expect(find.text('Golden Boot'), findsOneWidget);
  });
}
