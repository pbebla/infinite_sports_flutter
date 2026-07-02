import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

/// The player's registration state: Paid badge, submitted answers, and a
/// persistent "Complete payment" button (reopening the payment screen) while
/// unpaid.
class RegistrationStatusPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationStatusPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationStatusPage> createState() => _RegistrationStatusPageState();
}

class _RegistrationStatusPageState extends State<RegistrationStatusPage> {
  late Future<(RegSubmission?, List<RegQuestion>)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(RegSubmission?, List<RegQuestion>)> _loadAll() async {
    final sub = await RegistrationService.getMySubmission(widget.regId);
    final form = await RegistrationService.getForm(widget.regId);
    return (sub, form);
  }

  void _refresh() {
    setState(() => _load = _loadAll());
  }

  String _displayValue(RegQuestion? q, Object? value) {
    if (value is List) return value.map((v) => v.toString()).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    if (q?.type == 'phone') return formatPhone(value?.toString() ?? '');
    return value?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Registration'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final (sub, form) = snapshot.data ?? (null, const <RegQuestion>[]);
          if (sub == null) {
            return const Center(
                child: Text('No registration found for your account.'));
          }
          final byKey = {for (final q in form) q.key: q};
          final orderedKeys = [
            ...form.map((q) => q.key).where(sub.answers.containsKey),
            ...sub.answers.keys.where((k) => !byKey.containsKey(k)),
          ];
          final owes = paymentOwed(config: widget.config, submission: sub);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(15),
                  children: [
                    Card(
                      elevation: 2,
                      child: ListTile(
                        title: Text(widget.config.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Registered as: ${sub.path}'),
                        trailing: Chip(
                          label:
                              Text(sub.paid ? 'Paid' : 'Payment pending'),
                          backgroundColor: sub.paid
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final key in orderedKeys)
                      ListTile(
                        dense: true,
                        title: Text(byKey[key]?.label ?? key),
                        subtitle:
                            Text(_displayValue(byKey[key], sub.answers[key])),
                      ),
                  ],
                ),
              ),
              if (owes)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                    regId: widget.regId,
                                    config: widget.config,
                                    amount: amountOwed(
                                        config: widget.config,
                                        submission: sub))),
                          ).then((_) => _refresh());
                        },
                        child: const Text('Complete payment',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
