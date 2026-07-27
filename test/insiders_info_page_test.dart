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
    testWidgets(
        'terms checkbox is locked and Accept & Apply disabled until the Playbook is opened',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        playbookUrl: 'https://example.com/playbook.pdf',
        openPlaybookOverride: (url) async {
          opened++;
          return true;
        },
        applyOverride: ({required name, required email}) async {},
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

      CheckboxListTile terms() => tester.widget(
          find.byKey(const ValueKey('insiders_terms_checkbox')));

      // Playbook not opened: checkbox locked, helper text shown, button off.
      expect(isEnabled(), isFalse);
      expect(terms().onChanged, isNull);
      expect(find.text('Open the Playbook above first'), findsOneWidget);
      expect(find.byKey(const ValueKey('insiders_playbook_card')),
          findsOneWidget);

      // Open the Playbook — checkbox unlocks, button still off (terms).
      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_playbook_card')));
      await tester.pump();
      expect(opened, 1);
      expect(terms().onChanged, isNotNull);
      expect(isEnabled(), isFalse);

      // Accept terms — button enables.
      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_terms_checkbox')));
      await tester.pump();
      expect(isEnabled(), isTrue);
    });

    testWidgets(
        'no Playbook configured: card hidden and terms usable immediately',
        (tester) async {
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        playbookUrl: '',
        applyOverride: ({required name, required email}) async {},
      )));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('insiders_playbook_card')), findsNothing);
      final terms = tester.widget<CheckboxListTile>(
          find.byKey(const ValueKey('insiders_terms_checkbox')));
      expect(terms.onChanged, isNotNull);
    });

    testWidgets('shows read-only prefilled name/email rows', (tester) async {
      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        playbookUrl: '',
        applyOverride: ({required name, required email}) async {},
      )));
      await tester.pump();

      expect(find.text('Zaya Arami'), findsOneWidget);
      expect(find.text('zaya@example.com'), findsOneWidget);
    });

    testWidgets(
        'tapping Accept & Apply calls applyOverride with prefilled name/email',
        (tester) async {
      String? capturedName;
      String? capturedEmail;

      await tester.pumpWidget(wrap(InsidersInfoPage(
        insiderStream: Stream<Insider?>.value(null),
        prefillName: 'Zaya Arami',
        prefillEmail: 'zaya@example.com',
        playbookUrl: 'https://example.com/playbook.pdf',
        openPlaybookOverride: (url) async => true,
        applyOverride: ({required name, required email}) async {
          capturedName = name;
          capturedEmail = email;
        },
      )));
      await tester.pump();

      await _tapVisible(
          tester, find.byKey(const ValueKey('insiders_playbook_card')));
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
      playbookUrl: '',
      applyOverride: ({required name, required email}) async {},
    )));
    await tester.pump();

    expect(find.textContaining('declined'), findsOneWidget);
    expect(find.byKey(const ValueKey('insiders_apply_button')), findsOneWidget);
  });

  testWidgets(
      'active state shows the tier badge, code, and an "Open your Insider dashboard" button',
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
    expect(find.textContaining('coming'), findsNothing);
    expect(find.byKey(const ValueKey('insiders_copy_code_button')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('insiders_open_dashboard_button')),
        findsOneWidget);
  });

  testWidgets(
      'tapping "Open your Insider dashboard" pushes the dashboard page builder',
      (tester) async {
    // dashboardPageBuilder is a test seam (like applyOverride) so this test
    // never constructs the real InsiderDashboardPage — which, unwrapped,
    // reaches for FirebaseAuth.instance in its own default stream wiring.
    await tester.pumpWidget(wrap(InsidersInfoPage(
      insiderStream: Stream<Insider?>.value(Insider.fromFirebase('u1', {
        'Status': 'active',
        'Code': 'ZA4K9P2',
        'Tier': 1,
      })),
      prefillName: 'Zaya Arami',
      prefillEmail: 'zaya@example.com',
      dashboardPageBuilder: () =>
          const Scaffold(body: Center(child: Text('stub dashboard'))),
    )));
    await tester.pump();

    await _tapVisible(tester,
        find.byKey(const ValueKey('insiders_open_dashboard_button')));
    await tester.pumpAndSettle();

    expect(find.text('stub dashboard'), findsOneWidget);
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
