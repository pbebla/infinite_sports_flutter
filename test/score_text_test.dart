import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/score_text.dart';

Widget _host(int value) => MaterialApp(home: Scaffold(body: Center(child: ScoreText(value: value))));

void main() {
  testWidgets('renders the score value', (tester) async {
    await tester.pumpWidget(_host(2));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('updates when the value changes', (tester) async {
    await tester.pumpWidget(_host(1));
    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(_host(2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('2'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
