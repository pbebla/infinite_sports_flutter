import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Zelle account's registered number (shown + copyable).
const String kZelleNumber = '408-693-9436';

/// The recipient name Zelle displays for 408-693-9436 (owner-confirmed).
const String kZelleDisplayName = 'Zaya Shahbaz Arami';

/// Venmo handle for the business profile.
const String kVenmoHandle = 'infinite-sports';

/// Payment screen (L1a: Venmo + Zelle only; Stripe lands in L1c). Nothing
/// auto-confirms — the admin flips Paid in the Manager. Re-openable from the
/// status page until Paid.
class PaymentScreen extends StatelessWidget {
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

  /// venmo.com profile links open the Venmo app when it is installed
  /// (Android App Links / iOS Universal Links); otherwise the browser loads
  /// the profile page. txn=pay + amount + note pre-fill the payment.
  Uri get _venmoUri {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final note = Uri.encodeComponent('$regId - $name');
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=$amount&note=$note');
  }

  void _exit(BuildContext context) {
    if (fromSubmission) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RegistrationStatusPage(regId: regId, config: config)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              title: Text('\$$amount',
                  style: Theme.of(context).textTheme.headlineSmall),
              subtitle: Text([
                config.label,
                if (config.feeNote.isNotEmpty) config.feeNote,
              ].join(' — ')),
            ),
          ),
          const SizedBox(height: 15),
          if (config.venmo) ...[
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
          if (config.zelle) ...[
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
          const Text(
            'Nothing confirms automatically yet — an admin marks you Paid once your payment arrives. You can reopen this screen from your registration status any time until then.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: () => _exit(context),
            child: const Text('View my registration'),
          ),
        ],
      ),
    );
  }
}
