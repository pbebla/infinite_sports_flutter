// The season-pass pay card (paid-access spec 2026-11-01 §6), proved with
// recording seams (no Firebase, no url_launcher): every live state (none /
// pending / revoked / active / degraded), the card flow (callable seam →
// launch seam → "Finish in your browser" + Open again; errors + retry;
// already-active dismisses), the Venmo deep link + "I sent it" claim shape,
// the Zelle claim, Change payment method, and 360 px in light AND dark with
// no overflow, no ellipsis, no underline — and nothing fan-facing ever
// mentions grants, free access or admins.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/hub/access_pay_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/registration/payment_links.dart';

typedef _Claim = ({FantasyAccessMethod method, double amount, String note});

void main() {
  late int checkoutCalls;
  late List<Uri> launched;
  late List<_Claim> claims;
  late int retries;
  late Future<Uri?> Function() checkout;
  late bool launchOk;
  late Future<void> Function(FantasyAccessMethod, double, String)? claimImpl;

  final checkoutUri = Uri.parse('https://checkout.stripe.com/c/pay/cs_1');

  setUp(() {
    checkoutCalls = 0;
    launched = [];
    claims = [];
    retries = 0;
    checkout = () async => checkoutUri;
    launchOk = true;
    claimImpl = null;
  });

  FantasyAccessConfig passConfig({
    bool venmo = true,
    bool zelle = false,
    bool cash = false,
    bool card = true,
    double amount = 10,
  }) =>
      accessConfigFromNode({
        'Mode': 'pass',
        'AmountDollars': amount,
        'Methods': {'Venmo': venmo, 'Zelle': zelle, 'Cash': cash, 'Card': card},
      });

  FantasyAccessState state(String status) =>
      accessStateFromNode({'Status': status, 'Via': 'venmo'});

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pumpCard(
    WidgetTester tester, {
    FantasyAccessConfig? config,
    FantasyAccessState access = FantasyAccessState.none,
    Brightness brightness = Brightness.light,
    Size size = const Size(420, 1400),
    bool withRetry = true,
    String displayName = 'Ava',
    // A re-pump in the same test keeps the card's State (the live-stream
    // simulation relies on that); `fresh` mounts a brand-new card instead.
    bool fresh = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: AccessPayCard(
            key: fresh ? UniqueKey() : null,
            sport: 'Futsal',
            season: '16',
            config: config ?? passConfig(),
            access: access,
            displayName: displayName,
            actions: FantasyAccessActions(
              createCheckoutUrl: () {
                checkoutCalls++;
                return checkout();
              },
              launch: (uri) async {
                launched.add(uri);
                return launchOk;
              },
              submitClaim: (method, amount, note) async {
                if (claimImpl != null) {
                  await claimImpl!(method, amount, note);
                }
                claims.add((method: method, amount: amount, note: note));
              },
              retryAccess: withRetry ? () => retries++ : null,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Every rendered Text, lower-cased — the fan-facing vocabulary check.
  Iterable<String> allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? '').toLowerCase());

  void expectNoForbiddenWords(WidgetTester tester) {
    for (final text in allText(tester)) {
      for (final word in ['grant', 'admin', 'free access', 'ask zaya']) {
        expect(text, isNot(contains(word)),
            reason: 'fan-facing copy must never say "$word": "$text"');
      }
    }
  }

  void expectNoUnderlineOrEllipsis(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
      expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
      expect(t.maxLines, isNull, reason: t.data);
    }
  }

  group('none (unpaid)', () {
    testWidgets('headline, body, price line, then the enabled methods at '
        'once — the owner\'s Button copy labels the card button',
        (tester) async {
      await pumpCard(tester);
      expect(key('access_pay_card'), findsOneWidget);
      expect(find.text('Join Infinite Fantasy'), findsOneWidget);
      expect(
          find.text('A season pass for Futsal Season 16 is \$10. Pay once, '
              'play the whole season.'),
          findsOneWidget);
      expect(find.text('\$10'), findsOneWidget);
      expect(key('access_pay_card_card'), findsOneWidget);
      expect(
          find.descendant(
              of: key('access_pay_card_card'),
              matching: find.text('Pay with card')),
          findsOneWidget);
      expect(find.text('Pay by card'), findsNothing);
      expect(key('access_pay_card_venmo'), findsOneWidget);
      expect(find.text('Pay with Venmo'), findsOneWidget);
      expect(key('access_pay_card_zelle'), findsNothing, reason: 'Zelle off');
      expect(key('access_pay_card_pending'), findsNothing);
      // Spec §6 order: headline, body, price, then the methods.
      final headline = tester.getRect(find.text('Join Infinite Fantasy'));
      final price = tester.getRect(key('access_pay_card_price'));
      final card = tester.getRect(key('access_pay_card_card'));
      final venmo = tester.getRect(key('access_pay_card_venmo'));
      expect(headline.bottom, lessThanOrEqualTo(price.top));
      expect(price.bottom, lessThanOrEqualTo(card.top));
      expect(card.bottom, lessThanOrEqualTo(venmo.top));
      expectNoForbiddenWords(tester);
    });

    testWidgets('the owner\'s copy and a .50 price render as stored',
        (tester) async {
      await pumpCard(tester,
          config: accessConfigFromNode({
            'Mode': 'pass',
            'AmountDollars': 12.5,
            'Copy': {
              'Headline': 'Season 16 is here',
              'Body': '{amount} gets you {season}.',
              'Button': 'Pay now',
            },
          }));
      expect(find.text('Season 16 is here'), findsOneWidget);
      expect(find.text('\$12.50 gets you Futsal Season 16.'), findsOneWidget);
      expect(find.text('\$12.50'), findsOneWidget);
      expect(
          find.descendant(
              of: key('access_pay_card_card'), matching: find.text('Pay now')),
          findsOneWidget);
    });

    testWidgets('only the enabled methods show; with Card off nothing '
        'uses the Button copy', (tester) async {
      await pumpCard(tester, config: passConfig(card: false, zelle: true));
      expect(key('access_pay_card_card'), findsNothing);
      expect(find.text('Pay with card'), findsNothing);
      expect(key('access_pay_card_venmo'), findsOneWidget);
      expect(key('access_pay_card_zelle'), findsOneWidget);
      expect(find.text(kZelleNumber), findsOneWidget);
      expect(find.textContaining(kZelleDisplayName), findsOneWidget);

      await pumpCard(tester, config: passConfig(venmo: false), fresh: true);
      expect(key('access_pay_card_venmo'), findsNothing);
      expect(key('access_pay_card_card'), findsOneWidget);
    });
  });

  group('pay by card (Stripe Checkout in the browser)', () {
    testWidgets('calls the callable seam, launches the URL, then shows the '
        'browser line; Open again re-launches without a new session',
        (tester) async {
      await pumpCard(tester);
      expect(key('access_pay_card_browser'), findsNothing);

      await tester.tap(key('access_pay_card_card'));
      await tester.pumpAndSettle();
      expect(checkoutCalls, 1);
      expect(launched, [checkoutUri]);
      expect(find.text(kAccessBrowserText), findsOneWidget);
      expect(key('access_pay_card_open_again'), findsOneWidget);
      expect(key('access_pay_card_error'), findsNothing);

      await tester.tap(key('access_pay_card_open_again'));
      await tester.pumpAndSettle();
      expect(checkoutCalls, 1, reason: 'the same session link reopens');
      expect(launched, [checkoutUri, checkoutUri]);
    });

    testWidgets('a failing callable → friendly red line + Retry (both '
        'themes use the bright down red)', (tester) async {
      for (final brightness in Brightness.values) {
        checkout = () async => throw Exception('internal');
        await pumpCard(tester, brightness: brightness, fresh: true);
        await tester.tap(key('access_pay_card_card'));
        await tester.pumpAndSettle();
        expect(launched, isEmpty);
        expect(find.text(kAccessCardErrorText), findsOneWidget);
        final line = tester.widget<Text>(find.text(kAccessCardErrorText));
        final context = tester.element(find.text(kAccessCardErrorText));
        expect(line.style?.color, fantasyDownRed(context),
            reason: '$brightness');
        expect(key('access_pay_card_browser'), findsNothing);

        // Retry runs the callable again; success clears the line.
        checkout = () async => checkoutUri;
        await tester.tap(key('access_pay_card_retry'));
        await tester.pumpAndSettle();
        expect(find.text(kAccessCardErrorText), findsNothing);
        expect(launched, [checkoutUri]);
        expect(key('access_pay_card_browser'), findsOneWidget);
        launched.clear();
      }
    });

    testWidgets('already active (race) → nothing launches, no error; the '
        'stream dismisses the card', (tester) async {
      checkout = () async => null;
      await pumpCard(tester);
      await tester.tap(key('access_pay_card_card'));
      await tester.pumpAndSettle();
      expect(checkoutCalls, 1);
      expect(launched, isEmpty);
      expect(key('access_pay_card_error'), findsNothing);
      expect(key('access_pay_card_browser'), findsNothing);

      await pumpCard(tester, access: state('active'));
      expect(key('access_pay_card'), findsNothing);
    });

    testWidgets('the phone cannot open the link → the open error line',
        (tester) async {
      launchOk = false;
      await pumpCard(tester);
      await tester.tap(key('access_pay_card_card'));
      await tester.pumpAndSettle();
      expect(find.text(kAccessOpenErrorText), findsOneWidget);
      expect(key('access_pay_card_browser'), findsNothing);
    });
  });

  group('Venmo + "I sent it"', () {
    testWidgets('opens the shared deep link with amount + note, then the '
        '"I sent it" row writes the claim shape and shows pending at once',
        (tester) async {
      await pumpCard(tester);
      expect(key('access_pay_card_sent'), findsNothing);

      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      expect(launched,
          [venmoPayUri(amount: 10, note: 'Fantasy Futsal S16 Ava')]);
      expect(launched.single.queryParameters['amount'], '10');
      expect(launched.single.queryParameters['note'],
          'Fantasy Futsal S16 Ava');
      expect(find.text('Sent \$10 on Venmo?'), findsOneWidget);
      expect(key('access_pay_card_sent'), findsOneWidget);

      await tester.tap(key('access_pay_card_sent'));
      await tester.pumpAndSettle();
      expect(claims, hasLength(1));
      expect(claims.single.method, FantasyAccessMethod.venmo);
      expect(claims.single.amount, 10.0);
      expect(claims.single.note, 'Fantasy Futsal S16 Ava');
      // The server trigger hasn't flipped the stream yet — the card already
      // shows the pending face.
      expect(key('access_pay_card_pending'), findsOneWidget);
      expect(find.text(kAccessPendingText), findsOneWidget);
      expect(key('access_pay_card_venmo'), findsNothing);
      expectNoForbiddenWords(tester);
    });

    testWidgets('a blank display name leaves the note without a tail',
        (tester) async {
      await pumpCard(tester, displayName: '');
      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      expect(launched.single.queryParameters['note'], 'Fantasy Futsal S16');
    });

    testWidgets('Venmo cannot open → error line, no "I sent it" row',
        (tester) async {
      launchOk = false;
      await pumpCard(tester);
      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      expect(find.text(kAccessVenmoErrorText), findsOneWidget);
      expect(key('access_pay_card_sent'), findsNothing);
    });

    testWidgets('a failed claim write says so and keeps the methods open',
        (tester) async {
      claimImpl = (_, __, ___) async => throw Exception('permission-denied');
      await pumpCard(tester);
      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      await tester.tap(key('access_pay_card_sent'));
      await tester.pumpAndSettle();
      expect(find.text(kAccessClaimErrorText), findsOneWidget);
      expect(key('access_pay_card_pending'), findsNothing);
      expect(key('access_pay_card_sent'), findsOneWidget);
      expect(claims, isEmpty);
    });
  });

  group('Zelle + "I sent it"', () {
    testWidgets('the instructions carry their own I sent it → a zelle claim',
        (tester) async {
      await pumpCard(tester, config: passConfig(zelle: true));
      expect(find.text('Sent \$10 by Zelle?'), findsOneWidget);
      await tester.tap(key('access_pay_card_zelle_sent'));
      await tester.pumpAndSettle();
      expect(claims.single.method, FantasyAccessMethod.zelle);
      expect(claims.single.amount, 10.0);
      expect(claims.single.note, 'Fantasy Futsal S16 Ava');
      expect(key('access_pay_card_pending'), findsOneWidget);
    });

    testWidgets('cash on: the Cash box shows and "I paid cash" writes a cash '
        'claim', (tester) async {
      await pumpCard(tester, config: passConfig(cash: true));
      expect(find.byKey(const ValueKey('access_pay_card_cash')), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('access_pay_card_cash_sent')));
      await tester.pump();
      expect(claims.single.method, FantasyAccessMethod.cash);
    });

    testWidgets('cash off (default): no Cash box', (tester) async {
      await pumpCard(tester, config: passConfig());
      expect(find.byKey(const ValueKey('access_pay_card_cash')), findsNothing);
    });

    testWidgets('copy number → a SnackBar', (tester) async {
      await pumpCard(tester, config: passConfig(zelle: true));
      await tester.tap(key('access_pay_card_zelle_copy'));
      await tester.pump();
      expect(find.text('Zelle number copied.'), findsOneWidget);
    });
  });

  group('pending (live)', () {
    testWidgets('the waiting copy + Change payment method reopens the '
        'methods; a new claim returns to pending', (tester) async {
      await pumpCard(tester, access: state('pending'));
      expect(key('access_pay_card_pending'), findsOneWidget);
      expect(find.text(kAccessPendingText), findsOneWidget);
      expect(key('access_pay_card_venmo'), findsNothing);
      expect(key('access_pay_card_card'), findsNothing);
      expectNoForbiddenWords(tester);

      await tester.tap(key('access_pay_card_change'));
      await tester.pumpAndSettle();
      expect(key('access_pay_card_pending'), findsNothing);
      expect(key('access_pay_card_venmo'), findsOneWidget);
      expect(key('access_pay_card_card'), findsOneWidget);

      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      await tester.tap(key('access_pay_card_sent'));
      await tester.pumpAndSettle();
      expect(claims, hasLength(1));
      expect(key('access_pay_card_pending'), findsOneWidget);
    });

    testWidgets('a local claim, then the stream says pending, then none '
        '(rejected) → back to the pay face', (tester) async {
      await pumpCard(tester);
      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      await tester.tap(key('access_pay_card_sent'));
      await tester.pumpAndSettle();
      expect(key('access_pay_card_pending'), findsOneWidget);

      await pumpCard(tester, access: state('pending'));
      expect(key('access_pay_card_pending'), findsOneWidget);

      await pumpCard(tester); // the record was deleted (Reject)
      expect(key('access_pay_card_pending'), findsNothing);
      expect(key('access_pay_card_venmo'), findsOneWidget);
      expect(key('access_pay_card_card'), findsOneWidget);
    });
  });

  group('revoked', () {
    testWidgets('the removed line (bright red) and the methods straight away',
        (tester) async {
      for (final brightness in Brightness.values) {
        await pumpCard(tester, access: state('revoked'), brightness: brightness);
        expect(key('access_pay_card_revoked'), findsOneWidget);
        expect(find.text(kAccessRevokedText), findsOneWidget);
        final context = tester.element(find.text(kAccessRevokedText));
        expect(tester.widget<Text>(find.text(kAccessRevokedText)).style?.color,
            fantasyDownRed(context));
        expect(key('access_pay_card_card'), findsOneWidget);
        expect(key('access_pay_card_venmo'), findsOneWidget);
        expectNoForbiddenWords(tester);
      }
    });
  });

  group('active / degraded', () {
    testWidgets('active renders nothing at all', (tester) async {
      await pumpCard(tester, access: state('active'));
      expect(key('access_pay_card'), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a failed read before any value → retry line, never the '
        'methods', (tester) async {
      await pumpCard(tester,
          access: const FantasyAccessState(degraded: true));
      expect(key('access_pay_card_degraded'), findsOneWidget);
      expect(find.text(kAccessDegradedText), findsOneWidget);
      expect(key('access_pay_card_venmo'), findsNothing);
      expect(key('access_pay_card_card'), findsNothing);
      await tester.tap(key('access_pay_card_retry_access'));
      await tester.pump();
      expect(retries, 1);

      // Without a retry seam the line stands alone.
      await pumpCard(tester,
          access: const FantasyAccessState(degraded: true), withRetry: false);
      expect(key('access_pay_card_retry_access'), findsNothing);
    });
  });

  // Owner rule: every new surface at 360 px in BOTH themes.
  group('360 px, light + dark', () {
    for (final brightness in Brightness.values) {
      testWidgets('methods open (card + Venmo + Zelle, browser line, I sent '
          'it rows) fit with no overflow — $brightness', (tester) async {
        await pumpCard(tester,
            config: accessConfigFromNode({
              'Mode': 'pass',
              'AmountDollars': 12.5,
              'Methods': {'Venmo': true, 'Zelle': true, 'Card': true},
              'Copy': {
                'Headline': 'A deliberately long headline for the season '
                    'pass that has to wrap on a small phone',
                'Body': 'A season pass for {season} is {amount}. Pay once, '
                    'play the whole season — and this sentence keeps going '
                    'to make sure wrapping works everywhere.',
              },
            }),
            brightness: brightness,
            size: const Size(360, 1600),
            displayName: 'Maximiliano Bartholomew Featherstonehaugh');
        expect(tester.takeException(), isNull);
        await tester.tap(key('access_pay_card_card'));
        await tester.pumpAndSettle();
        await tester.tap(key('access_pay_card_venmo'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final k in [
          'access_pay_card',
          'access_pay_card_price',
          'access_pay_card_card',
          'access_pay_card_browser',
          'access_pay_card_venmo',
          'access_pay_card_sent',
          'access_pay_card_zelle',
          'access_pay_card_zelle_sent',
        ]) {
          final r = tester.getRect(key(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: k);
          expect(r.right, lessThanOrEqualTo(360), reason: k);
        }
        expectNoUnderlineOrEllipsis(tester);
        expectNoForbiddenWords(tester);
      });

      testWidgets('pending, revoked and degraded faces fit — $brightness',
          (tester) async {
        for (final access in [
          state('pending'),
          state('revoked'),
          const FantasyAccessState(degraded: true),
        ]) {
          await pumpCard(tester,
              access: access,
              brightness: brightness,
              size: const Size(360, 1200));
          expect(tester.takeException(), isNull, reason: '${access.status}');
          final r = tester.getRect(key('access_pay_card'));
          expect(r.right, lessThanOrEqualTo(360));
          expectNoUnderlineOrEllipsis(tester);
          expectNoForbiddenWords(tester);
        }
      });
    }
  });
}
