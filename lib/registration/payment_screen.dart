import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:infinite_sports_flutter/registration/registration_models.dart';
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

/// Payment screen (L1a: Venmo + Zelle; L1c adds card via Stripe PaymentSheet).
/// Venmo/Zelle never auto-confirm — the admin flips Paid in the Manager.
/// Card payments DO auto-confirm: a webhook flips Paid the moment Stripe
/// reports success, and the status page (which streams the submission live)
/// picks it up with no extra work here. Re-openable from the status page
/// until Paid.
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

  @override
  void initState() {
    super.initState();
    if (widget.config.stripe) _loadPublishableKey();
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
  /// the profile page. txn=pay + amount + note pre-fill the payment.
  Uri get _venmoUri {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final note = Uri.encodeComponent('${widget.regId} - $name');
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=${widget.amount}&note=$note');
  }

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
      final callable =
          FirebaseFunctions.instance.httpsCallable('createRegistrationPaymentIntent');
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
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'US',
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment received — confirming...')));
    } on StripeException catch (e) {
      // User-cancelled the sheet is the common case — stay silent for that,
      // show everything else.
      final isCancel = e.error.code == FailureCode.Canceled;
      if (!isCancel && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                e.error.localizedMessage ?? 'Card payment failed.')));
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
    final showCardButton = widget.config.stripe &&
        widget.amount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isNotEmpty;
    final cardUnavailable = widget.config.stripe &&
        widget.amount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payment'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          Card(
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
          ),
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
                label: const Text('Pay with card',
                    style: TextStyle(fontSize: 18)),
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
                label: const Text('Pay with Venmo',
                    style: TextStyle(fontSize: 18)),
                onPressed: () async {
                  await launchUrl(_venmoUri,
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
                    subtitle: const Text(kZelleNumber,
                        style: TextStyle(fontSize: 18)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy number',
                      onPressed: () {
                        Clipboard.setData(
                            const ClipboardData(text: kZelleNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Zelle number copied.')),
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
      ),
    );
  }
}
