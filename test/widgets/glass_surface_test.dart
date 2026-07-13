import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/glass_surface.dart';

void main() {
  testWidgets('GlassSurface renders its child', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GlassSurface(child: Text('hello'))),
    ));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('GlassSurface uses a dark tint in dark mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(body: GlassSurface(child: Text('x'))),
    ));
    final container = tester.widget<Container>(find.descendant(
      of: find.byType(GlassSurface), matching: find.byType(Container)).first);
    final color = (container.decoration as BoxDecoration).color!;
    expect(color.computeLuminance() < 0.5, isTrue);
  });
}
