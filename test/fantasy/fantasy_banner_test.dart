// P3b feedback Task 1 — the banner follows the theme: dark mode keeps the
// dark gradient card + gold accent; light mode renders a light colorScheme
// card with primary (red) accents and a dark backdrop pill behind the gold
// logo (whose dark outlines would wash out on white).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

void main() {
  Future<BuildContext> pumpBanner(WidgetTester tester,
      {required Brightness brightness}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 208, 0, 0),
            brightness: brightness),
      ),
      home: const Scaffold(
        body: FantasyBanner(subtitle: 'Futsal · Season 15'),
      ),
    ));
    return tester.element(find.byType(FantasyBanner));
  }

  BoxDecoration bannerDecoration(WidgetTester tester) => tester
      .widget<Container>(find
          .descendant(
              of: find.byType(FantasyBanner),
              matching: find.byType(Container))
          .first)
      .decoration! as BoxDecoration;

  testWidgets('dark mode: dark gradient card, gold accent, bare logo',
      (tester) async {
    final context =
        await pumpBanner(tester, brightness: Brightness.dark);
    final deco = bannerDecoration(tester);
    expect(deco.gradient, isNotNull);
    expect((deco.gradient! as LinearGradient).colors,
        [FantasyBanner.gradientTop, FantasyBanner.gradientBottom]);
    // No backdrop pill on the dark card.
    expect(find.byKey(const ValueKey('fantasy_logo_backdrop')), findsNothing);
    expect(FantasyBanner.accent(context), TournamentColors.gold);
    expect(FantasyBanner.foreground(context), Colors.white);
  });

  testWidgets('light mode: light colorScheme card, primary accent, logo gets '
      'its dark backdrop pill', (tester) async {
    final context =
        await pumpBanner(tester, brightness: Brightness.light);
    final scheme = Theme.of(context).colorScheme;
    final deco = bannerDecoration(tester);
    // A normal elevated light card: flat colorScheme surface, no forced
    // dark gradient (the owner's light-mode bug).
    expect(deco.gradient, isNull);
    expect(deco.color, scheme.surfaceContainerLow);
    // The gold logo keeps a subtle dark pill JUST behind it.
    expect(
        find.byKey(const ValueKey('fantasy_logo_backdrop')), findsOneWidget);
    expect(FantasyBanner.accent(context), scheme.primary);
    expect(FantasyBanner.foreground(context), scheme.onSurface);
    // Subtitle readable on the light card (never the dark-card white70).
    final subtitle = tester.widget<Text>(find.text('Futsal · Season 15'));
    expect(subtitle.style!.color, scheme.onSurfaceVariant);
  });
}
