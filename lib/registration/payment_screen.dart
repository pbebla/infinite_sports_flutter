import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Zelle account's registered number (shown + copyable).
const String kZelleNumber = '408-693-9436';

/// The recipient name Zelle displays for 408-693-9436 (owner-confirmed).
const String kZelleDisplayName = 'Zaya Shahbaz Arami';

/// Venmo handle for the business profile.
const String kVenmoHandle = 'infinite-sports';

/// Stripe's brand purple, used for the "Pay with card" button so it reads as
/// a distinct payment method next to Venmo blue and the Zelle card.
const Color kStripePurple = Color(0xFF635BFF);

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

  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    required this.amount,
    this.fromSubmission = false,
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

  late final Stream<RegSubmission?> _submission;

  @override
  void initState() {
    super.initState();
    if (widget.config.stripe) _loadPublishableKey();
    _submission = RegistrationService.watchMySubmission(widget.regId);
  }

  @override
  void dispose() {
    _processingFallback?.cancel();
    super.dispose();
  }

  Future<void> _loadPublishableKey() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('AppConfig/StripePublishableKey')
          .get();
      final key = snap.value;
      if (!mounted) return;
      setState(() => _publishableKey = key is String ? key : '');
    } catch (_) {
      if (mounted) setState(() => _publishableKey = '');
    }
  }

  /// venmo.com profile links open the Venmo app when it is installed
  /// (Android App Links / iOS Universal Links); otherwise the browser loads
  /// the profile page. txn=pay + amount + note pre-fill the payment. Takes
  /// the live EFFECTIVE amount (after any manual admin adjustment) so the
  /// pre-filled Venmo request never asks for more than is actually owed.
  Uri _venmoUri(num amount) {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final note = Uri.encodeComponent('${widget.regId} - $name');
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=$amount&note=$note');
  }

  /// The amount THIS registrant currently owes, combining the base
  /// [PaymentScreen.amount] (unadjusted config fee) with whichever discount
  /// is live on [sub] — a manual admin adjustment (Infinite Insiders
  /// §6/Task F1, `DiscountSource == 'manual'`) OR an automatic first-timer
  /// promo applied at registration time (§4/§5/Task F3,
  /// `DiscountSource == 'first_timer_promo'`). [bestDiscountedTotal] picks
  /// the larger discount if a future scenario ever has both signals present
  /// at once (spec §5's best-discount-wins rule). An owner edit made in the
  /// Manager shows up here instantly since [_submission] is a live stream.
  num _effectiveAmount(RegSubmission? sub) => bestDiscountedTotal(
        baseFee: widget.amount.toDouble(),
        eligibleFee: sub?.eligibleFee,
        adjustedFee: sub?.adjustedFee,
        discountPct: sub?.discountPct,
        discountSource: sub?.discountSource ?? '',
      );

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
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: true, // flip to false for the production Stripe key
          ),
          // Apple Pay stays off until an Apple merchant identifier exists
          // (Stripe.merchantIdentifier) — passing applePay without one
          // asserts at runtime. Card + Google Pay cover Android fully.
        ),
      );
      await Stripe.instance.presentPaymentSheet();

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Card payment failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _payingWithCard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payment'),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
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

  Widget _processingBody(BuildContext context) {
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
    final showCardButton = widget.config.stripe &&
        effectiveAmount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isNotEmpty;
    final cardUnavailable = widget.config.stripe &&
        effectiveAmount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(15),
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
                backgroundColor: const Color(0xFF008CFF),
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

  /// The amount card: a plain total when unadjusted (unchanged from before
  /// Infinite Insiders), or an itemized Registration fee / discount line /
  /// Total due breakdown the instant EITHER an admin manually adjusts this
  /// submission's payment in the Manager (§6/Task M1) OR a first-timer
  /// promo applied at registration time (§4/Task F3) — [_submission] is a
  /// live stream, so no refresh is needed to see it. The discount line's
  /// label/amount follow whichever source [sub.discountSource] carries:
  /// 'first_timer_promo' -> "First-time player promo (−Y%)"; anything else
  /// (today, only 'manual') -> the original "Adjusted by Infinite Sports".
  Widget _amountCard(
      BuildContext context, RegSubmission? sub, num effectiveAmount) {
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color;
    if (sub == null || !sub.isAdjusted) {
      return Card(
        elevation: 2,
        child: ListTile(
          leading: const Icon(Icons.attach_money),
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
    final discountLabel = isPromo
        ? 'First-time player promo (−${_pctLabel(sub.discountPct)}%)'
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
