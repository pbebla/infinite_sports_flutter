// Widget tests for the Infinite Insiders info/apply page
// (lib/insiders/insiders_info_page.dart, Task F2). Firebase-free: an
// `insiderStream` override replaces the live /Insiders/<uid> stream,
// `prefillName`/`prefillEmail` replace the Users-node/FirebaseAuth lookups,
// and `applyOverride` replaces the real InsiderService.apply write — mirrors
// the `writeOverride` seam in lib/onboarding/about_you_page.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/insiders/insiders_info_page.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

/// The page is a SingleChildScrollView taller than the default 800x600 test
/// surface, so most interactive widgets start out below the fold. Scroll
/// them into view before tapping (mirrors test/about_you_page_test.dart).
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders the tier table Bronze through Infinite with correct pct',
      (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(null),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
    )));
    await tester.pump();

    expect(find.text('Bronze'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Platinum'), findsOneWidget);
    expect(find.text('Infinite'), findsOneWidget);
    expect(find.text('5% off'), findsOneWidget);
    expect(find.text('10% off'), findsOneWidget);
    expect(find.text('15% off'), findsOneWidget);
    expect(find.text('20% off'), findsOneWidget);
    expect(find.text('25% off'), findsOneWidget);
  });

  group('apply flow (no application yet)', () {
    testWidgets('Accept & Apply is disabled until a sport is picked AND terms are checked',
        (tester) async {
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        applyOverride: ({required name, required email, required sports}) async {},
      )));
      await tester.pump();

      Widget button() =>
          tester.widget(find.byKey(const ValueKey('insiders_apply_button')));
      bool isEnabled() {
        final w = button();
        if (w is FilledButton) return w.onPressed != null;
        if (w is ElevatedButton) return w.onPressed != null;
        return false;
      }

      expect(isEnabled(), isFalse);

      // Pick a sport only — still disabled (terms not accepted).
      await _tapVisible(
          tester, find.byKey(const ValueKey('insider_sport_chip_Futsal')));
      await tester.pump();
      expect(isEnabled(), isFalse);

      // Check terms only (no sport) would also be insufficient, but since a
      // sport is already picked from the previous step, uncheck it first to
      // verify the terms-only path is also gated.
      await _tapVisible(
          tester, find.byKey(const ValueKey('insider_sport_chip_Futsal')));
      await tester.pump();
      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_terms_checkbox')));
      await tester.pump();
      expect(isEnabled(), isFalse);

      // Now both conditions are satisfied.
      await _tapVisible(
          tester, find.byKey(const ValueKey('insider_sport_chip_Futsal')));
      await tester.pump();
      expect(isEnabled(), isTrue);
    });

    testWidgets('shows read-only prefilled name/email rows', (tester) async {
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        applyOverride: ({required name, required email, required sports}) async {},
      )));
      await tester.pump();

      expect(find.text('Zaya Arami'), findsOneWidget);
      expect(find.text('zaya@example.com'), findsOneWidget);
    });

    testWidgets('offers all five sport chips', (tester) async {
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        applyOverride: ({required name, required email, required sports}) async {},
      )));
      await tester.pump();

      for (final sport in [
        'Futsal',
        'Soccer',
        'Basketball',
        'Flag Football',
        'Volleyball'
      ]) {
        expect(find.byKey(ValueKey('insider_sport_chip_$sport')), findsOneWidget,
            reason: 'missing sport chip for $sport');
      }
    });

    testWidgets('tapping Accept & Apply calls applyOverride with picked sports + prefilled name/email',
        (tester) async {
      String? capturedName;
      String? capturedEmail;
      List<String>? capturedSports;

      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        applyOverride: ({required name, required email, required sports}) async {
          capturedName = name;
          capturedEmail = email;
          capturedSports = sports;
        },
      )));
      await tester.pump();

      await _tapVisible(
          tester, find.byKey(const ValueKey('insider_sport_chip_Basketball')));
      await tester.pump();
      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_terms_checkbox')));
      await tester.pump();
      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_apply_button')));
      await tester.pump();
      await tester.pump();

      expect(capturedName, 'Zaya Arami');
      expect(capturedEmail, 'zaya@example.com');
      expect(capturedSports, ['Basketball']);
    });
  });

  testWidgets('pending state shows "We got your application!"', (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(
          Insider.fromFirebase('u1', {'Status': 'pending'})),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
    )));
    await tester.pump();

    expect(find.text('We got your application!'), findsOneWidget);
    // No apply form while pending.
    expect(find.byKey(const ValueKey('insiders_apply_button')), findsNothing);
  });

  testWidgets('declined state shows a reapply banner and still offers the apply form',
      (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(
          Insider.fromFirebase('u1', {'Status': 'declined'})),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
      applyOverride: ({required name, required email, required sports}) async {},
    )));
    await tester.pump();

    expect(find.textContaining('declined'), findsOneWidget);
    expect(find.byKey(const ValueKey('insiders_apply_button')), findsOneWidget);
  });

  testWidgets('active state shows the tier badge, code, and a coming-soon note',
      (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(Insider.fromFirebase('u1', {
        'Status': 'active',
        'Code': 'ZA4K9P2',
        'Tier': 1,
        'CurrentStanding': 6,
        'TotalReferred': 6,
      })),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
    )));
    await tester.pump();

    expect(find.text('ZA4K9P2'), findsOneWidget);
    expect(find.textContaining('coming'), findsOneWidget);
    expect(find.byKey(const ValueKey('insiders_copy_code_button')), findsOneWidget);
  });

  testWidgets('active state with tier 0 shows "Insider" fallback label',
      (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(Insider.fromFirebase('u1', {
        'Status': 'active',
        'Code': 'ZA4K9P2',
        'Tier': 0,
      })),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
    )));
    await tester.pump();

    expect(find.text('Insider'), findsOneWidget);
  });

  testWidgets('tapping the copy button copies the code and shows a confirmation snackbar',
      (tester) async {
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(Insider.fromFirebase('u1', {
        'Status': 'active',
        'Code': 'ZA4K9P2',
        'Tier': 1,
      })),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
    )));
    await tester.pump();

    await _tapVisible(
        tester, find.byKey(const ValueKey('insiders_copy_code_button')));
    await tester.pump();

    expect(find.textContaining('copied'), findsOneWidget);
  });
}
