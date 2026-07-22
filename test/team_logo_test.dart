// L6.2 Task 3: TeamLogo must never crop or stretch a real logo — it renders
// BoxFit.contain with no ClipOval around the image. Only the missing-logo
// fallback keeps its circular shield shape.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

void main() {
  testWidgets('a real logo renders BoxFit.contain with no ClipOval crop',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TeamLogo(url: 'https://example.com/logo.png', size: 40),
      ),
    ));

    final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage));
    expect(image.fit, BoxFit.contain);
    expect(
      find.descendant(
          of: find.byType(TeamLogo), matching: find.byType(ClipOval)),
      findsNothing,
      reason: 'the real logo image must not be masked into a circle',
    );
  });

  testWidgets('missing logo (null url) still renders the circular shield '
      'fallback', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TeamLogo(url: null, size: 40)),
    ));
    expect(find.byType(CachedNetworkImage), findsNothing);
    final container = tester.widget<Container>(find.descendant(
        of: find.byType(TeamLogo), matching: find.byType(Container)));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });

  testWidgets('empty-string url also falls back to the shield',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TeamLogo(url: '', size: 40)),
    ));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });
}
