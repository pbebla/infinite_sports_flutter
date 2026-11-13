import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/registration/payment_links.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:url_launcher/url_launcher.dart';

// The Venmo handle, the Zelle number + display name and the Venmo deep link
// live in payment_links.dart (shared with the fantasy season-pass card).

/// Stripe's brand purple, used for the "Pay with card" button so it reads as
/// a distinct payment method next to Venmo blue and the Zelle card.
const Color kStripePurple = Color(0xFF635BFF);

/// How long after the payment sheet reports success the screen waits for
/// the Paid confirmation before saying the payment went through and may
/// take a few minutes to show.
const Duration kCardConfirmationWait = Duration(seconds: 60);

/// A plain sentence for a card payment that could not be started — never
/// the raw exception text ("[firebase_functions/failed-precondition] …").
String cardPaymentErrorMessage(Object error) {
  if (error is FirebaseFunctionsException &&
      error.code == 'failed-precondition') {
    final message = (error.message ?? '').toLowerCase();
    if (message.contains('already paid')) {
      return 'This registration is already paid.';
    }
    if (message.contains('nothing is owed')) {
      return 'Nothing is owed for this registration.';
    }
  }
  return "Card payment couldn't be started. Try again.";
}

/// Payment screen (L1a: Venmo + Zelle; L1c adds card via Stripe PaymentSheet;
/// L1c.2 makes the screen itself live).
///
/// The whole body rides RegistrationService.watchMySubmission so ANY method
/// flipping Paid — the card webhook, the owner manually marking Paid in the
/// Manager, anything — swaps this screen straight to a paid state and hides
/// the pay buttons (no double-pay window). After presentPaymentSheet
/// succeeds the screen shows a brief "processing" state while it waits for
/// the webhook; a ~10s fallback timer surfaces the old "still processing"
/// snackbar if the stream hasn't flipped yet. Re-openable from the status
/// page until Paid.
class PaymentScreen extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  /// The dollar amount THIS registrant owes — captains owe config.teamFee,
  /// individuals/joiners config.fee. Callers compute it with [amountOwed].
  final num amount;

  /// True when reached straight from a fresh submission (the status page is
  /// not underneath us) — the exit button pushes the status page instead of
  /// popping.
  final bool fromSubmission;

  /// Test seams (Firebase-free widget tests): the live submission stream,
  /// the Stripe publishable key (skips the AppConfig read) and the whole
  /// card round trip (callable + payment sheet; throw to simulate a failure).
  final Stream<RegSubmission?>? submissionStream;
  final String? publishableKeyOverride;
  final Future<void> Function()? cardPaymentOverride;

  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    required this.amount,
    this.fromSubmission = false,
    this.submissionStream,
    this.publishableKeyOverride,
    this.cardPaymentOverride,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// null while loading, '' when no key is configured (card button hidden).
  String? _publishableKey;
  bool _payingWithCard = false;

  /// True right after presentPaymentSheet succeeds, until the submission
  /// stream reports Paid (or the fallback timer below gives up waiting).
  bool _processing = false;

  /// Started when _processing turns true; if the stream still hasn't
  /// flipped Paid after ~10s, shows the old "webhook delayed" snackbar
  /// as a fallback instead of leaving the user staring at a spinner.
  Timer? _processingFallback;

  /// Set when the Paid confirmation still hasn't arrived
  /// [kCardConfirmationWait] after the sheet succeeded: "Processing…" gives
  /// way to "Your payment went through…" (pay buttons stay hidden).
  bool _confirmationSlow = false;
  Timer? _confirmationTimer;

  late Stream<RegSubmission?> _submission;

  @override
  void initState() {
    super.initState();
    if (widget.config.stripe) _loadPublishableKey();
    _submission = _watchSubmission();
  }

  /// The live submission; a Paid read stops both processing timers at once
  /// (no "still processing" snackbar / "went through" state after Paid).
  Stream<RegSubmission?> _watchSubmission() =>
      (widget.submissionStream ??
              RegistrationService.watchMySubmission(widget.regId))
          .map((sub) {
        if (sub != null && sub.paid) _stopProcessingTimers();
        return sub;
      });

  void _stopProcessingTimers() {
    _processingFallback?.cancel();
    _processingFallback = null;
    _confirmationTimer?.cancel();
    _confirmationTimer = null;
  }

  @override
  void dispose() {
    _processingFallback?.cancel();
    _confirmationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPublishableKey() async {
    final override = widget.publishableKeyOverride;
    if (override != null) {
      _publishableKey = override;
      return;
    }
    try {
      final snap = (await FirebaseDatabase.instance
              .ref('AppConfig/StripePublishableKey')
              .once())
          .snapshot;
      final key = snap.value;
      if (!mounted) return;
      setState(() => _publishableKey = key is String ? key : '');
    } catch (_) {
      if (mounted) setState(() => _publishableKey = '');
    }
  }

  /// The shared Venmo deep link (payment_links.dart) with the live
  /// EFFECTIVE amount (after any manual admin adjustment) so the pre-filled
  /// Venmo request never asks for more than is actually owed.
  Uri _venmoUri(num amount) {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    return venmoPayUri(amount: amount, note: '${widget.regId} - $name');
  }

  /// The amount THIS registrant currently owes, combining the base
  /// [PaymentScreen.amount] (unadjusted config fee) with whichever discount
  /// is live on [sub] — a manual admin adjustment (Infinite Insiders
  /// §6/Task F1, `DiscountSource == 'manual'`), an automatic first-timer
  /// promo applied at registration time (§4/§5/Task F3,
  /// `DiscountSource == 'first_timer_promo'`), or the registrant's OWN
  /// Insider tier discount (§2/§5/Task F5, `DiscountSource ==
  /// 'insider_tier'`) — best-discount-wins already picked the single
  /// winning source at submission time (registration_form_page.dart
  /// _resolveDiscountStamp), so only one of these is ever stamped.
  /// [bestDiscountedTotal] picks the larger discount if a future scenario
  /// ever has both signals present at once (spec §5's best-discount-wins
  /// rule). An owner edit made in the Manager shows up here instantly since
  /// [_submission] is a live stream.
  num _effectiveAmount(RegSubmission? sub) =>
      discountedTotal(baseFee: widget.amount.toDouble(), submission: sub);

  void _exit() {
    if (widget.fromSubmission) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RegistrationStatusPage(
                regId: widget.regId, config: widget.config)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _payWithCard() async {
    setState(() => _payingWithCard = true);
    try {
      final override = widget.cardPaymentOverride;
      if (override != null) {
        await override();
      } else {
        await _startCardPayment();
      }

      if (!mounted) return;
      // The submission stream flips to Paid on its own once the webhook
      // lands (typically 1-3s) and the StreamBuilder in build() swaps to
      // the paid state automatically. Show a brief processing state in the
      // meantime; if the webhook is unusually slow, fall back to the old
      // snackbar after ~10s so the user isn't left guessing.
      setState(() => _processing = true);
      _processingFallback?.cancel();
      _processingFallback = Timer(const Duration(seconds: 10), () {
        if (!mounted || !_processing) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Still processing — your status page will update once the payment is confirmed.')));
      });
      // Still no Paid flip after a minute: the card was charged (the sheet
      // said so), the confirmation is just slow — say exactly that, and
      // keep every pay button hidden so nobody pays twice.
      _confirmationTimer?.cancel();
      _confirmationTimer = Timer(kCardConfirmationWait, () {
        if (!mounted || !_processing) return;
        setState(() => _confirmationSlow = true);
      });
    } on StripeException catch (e) {
      // User-cancelled the sheet is the common case — stay silent for that,
      // show everything else.
      final isCancel = e.error.code == FailureCode.Canceled;
      if (!isCancel && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.error.localizedMessage ?? 'Card payment failed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(cardPaymentErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _payingWithCard = false);
    }
  }

  /// The real card round trip: createRegistrationPaymentIntent, then the
  /// Stripe PaymentSheet. Throws on any failure (a cancelled sheet throws a
  /// [StripeException] with [FailureCode.Canceled]).
  Future<void> _startCardPayment() async {
    final callable = FirebaseFunctions.instance
        .httpsCallable('createRegistrationPaymentIntent');
    final result = await callable.call<Map<String, dynamic>>({
      'regId': widget.regId,
    });
    final clientSecret = result.data['clientSecret'] as String?;
    final publishableKey =
        (result.data['publishableKey'] as String?) ?? _publishableKey ?? '';
    if (clientSecret == null || clientSecret.isEmpty) {
      throw Exception('No client secret returned.');
    }
    if (publishableKey.isEmpty) {
      throw Exception('No Stripe publishable key configured.');
    }

    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Infinite Sports',
        googlePay: PaymentSheetGooglePay(
          merchantCountryCode: 'US',
          // Follows the configured key: test environment for pk_test,
          // production for pk_live — no manual flip on go-live.
          testEnv: publishableKey.startsWith('pk_test_'),
        ),
        // Apple Pay stays off until an Apple merchant identifier exists
        // (Stripe.merchantIdentifier) — passing applePay without one
        // asserts at runtime. Card + Google Pay cover Android fully.
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payment'),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: StreamBuilder<RegSubmission?>(
        stream: _submission,
        builder: (context, snapshot) {
          final sub = snapshot.data;
          // Paid wins regardless of how it happened — card webhook, manual
          // admin flip, anything — and regardless of our own local
          // _processing flag, killing the double-pay window for good.
          if (sub != null && sub.paid) return _paidBody(context);
          if (_processing) return _processingBody(context);
          // A failed read must not fall back to the undiscounted base fee.
          if (snapshot.hasError) return _loadFailedBody(context);
          return _unpaidBody(context, sub);
        },
      ),
    );
  }

  Widget _paidBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 96),
            const SizedBox(height: 24),
            Text(
              "Payment received — you're all set.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _exit,
                child: const Text('View my registration'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadFailedBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load your registration. Try again.",
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _submission = _watchSubmission();
              }),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _processingBody(BuildContext context) {
    if (_confirmationSlow) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Your payment went through. It can take a few minutes to '
                "show here — you don't need to pay again.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _exit,
                  child: const Text('View my registration'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            const Text('Processing…', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Confirming your payment — this only takes a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unpaidBody(BuildContext context, RegSubmission? sub) {
    final effectiveAmount = _effectiveAmount(sub);
    // Comped to $0 / 100% discount: nothing to pay — no pay buttons at all.
    if (sub != null && effectiveAmount <= 0) {
      return _coveredBody(context, sub, effectiveAmount);
    }
    final showCardButton = widget.config.stripe &&
        effectiveAmount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isNotEmpty;
    final cardUnavailable = widget.config.stripe &&
        effectiveAmount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isEmpty;

    return ListView(
      // Bottom inset lets the pay buttons scroll clear of the floating glass
      // nav bar (PR #12 review).
      padding: EdgeInsets.fromLTRB(
          15, 15, 15, 15 + MediaQuery.paddingOf(context).bottom),
      children: [
        _amountCard(context, sub, effectiveAmount),
        const SizedBox(height: 15),
        if (showCardButton) ...[
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kStripePurple,
                foregroundColor: Colors.white,
              ),
              icon: _payingWithCard
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.credit_card),
              label:
                  const Text('Pay with card', style: TextStyle(fontSize: 18)),
              onPressed: _payingWithCard ? null : _payWithCard,
            ),
          ),
          const SizedBox(height: 15),
        ] else if (cardUnavailable) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Text(
              'Card payments unavailable right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (widget.config.venmo) ...[
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kVenmoBlue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.open_in_new),
              label:
                  const Text('Pay with Venmo', style: TextStyle(fontSize: 18)),
              onPressed: () async {
                await launchUrl(_venmoUri(effectiveAmount),
                    mode: LaunchMode.externalApplication);
              },
            ),
          ),
          const SizedBox(height: 15),
        ],
        if (widget.config.zelle) ...[
          Card(
            elevation: 2,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: const Text('Zelle',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle:
                      const Text(kZelleNumber, style: TextStyle(fontSize: 18)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy number',
                    onPressed: () {
                      Clipboard.setData(
                          const ClipboardData(text: kZelleNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Zelle number copied.')),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(15, 0, 15, 12),
                  child: Text(
                      'Before sending, confirm the recipient name shows "$kZelleDisplayName".'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
        ],
        Text(
          showCardButton
              ? 'Card payments confirm automatically — your status page updates as soon as Stripe processes it. Venmo/Zelle still require an admin to mark you Paid.'
              : 'Nothing confirms automatically yet — an admin marks you Paid once your payment arrives. You can reopen this screen from your registration status any time until then.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 15),
        OutlinedButton(
          onPressed: _exit,
          child: const Text('View my registration'),
        ),
      ],
    );
  }

  Widget _coveredBody(
      BuildContext context, RegSubmission sub, num effectiveAmount) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          15, 15, 15, 15 + MediaQuery.paddingOf(context).bottom),
      children: [
        _amountCard(context, sub, effectiveAmount),
        const SizedBox(height: 15),
        const Card(
          elevation: 2,
          child: ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text("Nothing to pay — you're covered"),
          ),
        ),
        const SizedBox(height: 15),
        OutlinedButton(
          onPressed: _exit,
          child: const Text('View my registration'),
        ),
      ],
    );
  }

  /// The amount card: a plain total when unadjusted (unchanged from before
  /// Infinite Insiders), or an itemized Registration fee / discount line /
  /// Total due breakdown the instant EITHER an admin manually adjusts this
  /// submission's payment in the Manager (§6/Task M1), a first-timer promo
  /// applied at registration time (§4/Task F3), or the registrant's OWN
  /// Insider tier discount applied at registration time (§2/Task F5) —
  /// [_submission] is a live stream, so no refresh is needed to see it. The
  /// discount line's label/amount follow whichever source
  /// [sub.discountSource] carries: 'first_timer_promo' -> "First-time player
  /// promo (−Y%)"; 'insider_tier' -> "Insider discount (Tier name −Y%)"
  /// ([tierNameForDiscountPct] recovers the tier name from the stamped
  /// pct — this screen never reads the registrant's live Insider record);
  /// anything else (today, only 'manual') -> the original "Adjusted by
  /// Infinite Sports".
  Widget _amountCard(
      BuildContext context, RegSubmission? sub, num effectiveAmount) {
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color;
    if (sub == null || !sub.isAdjusted) {
      return Card(
        elevation: 2,
        child: ListTile(
          title: Text('\$${widget.amount}',
              style: Theme.of(context).textTheme.headlineSmall),
          subtitle: Text([
            widget.config.label,
            if (widget.config.feeNote.isNotEmpty) widget.config.feeNote,
          ].join(' — ')),
        ),
      );
    }

    final baseFee = widget.amount;
    final discount = baseFee - effectiveAmount;
    final isPromo = sub.discountSource == 'first_timer_promo';
    final isInsiderTier = sub.discountSource == 'insider_tier';
    final discountLabel = isPromo
        ? 'First-time player promo (−${_pctLabel(sub.discountPct)}%)'
        : isInsiderTier
            ? 'Insider discount (${tierNameForDiscountPct(sub.discountPct ?? 0)} '
                '−${_pctLabel(sub.discountPct)}%)'
            : 'Adjusted by Infinite Sports';
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              widget.config.label,
              if (widget.config.feeNote.isNotEmpty) widget.config.feeNote,
            ].join(' — '), style: TextStyle(color: mutedColor)),
            const SizedBox(height: 12),
            _amountRow(context, 'Registration fee', _money(baseFee)),
            const SizedBox(height: 4),
            _amountRow(context, discountLabel, '−${_money(discount)}',
                muted: true),
            const Divider(height: 20),
            _amountRow(context, 'Total due', _money(effectiveAmount),
                bold: true),
          ],
        ),
      ),
    );
  }

  /// Formats a discount percent without a trailing ".0" ('15' not '15.0').
  String _pctLabel(double? pct) {
    if (pct == null) return '';
    return pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toString();
  }

  Widget _amountRow(BuildContext context, String label, String value,
      {bool bold = false, bool muted = false}) {
    final color =
        muted ? Theme.of(context).textTheme.bodySmall?.color : null;
    final style = (bold
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.bodyLarge)
        ?.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }

  /// Two-decimal dollar formatting for the itemized breakdown only — the
  /// plain (unadjusted) amount display above keeps its existing bare
  /// '\$${widget.amount}' style so this change stays scoped to the new
  /// adjustment UI.
  String _money(num n) => '\$${n.toStringAsFixed(2)}';
}
