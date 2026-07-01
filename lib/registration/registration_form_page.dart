import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Loads the registration's form + the player's profile prefill, renders the
/// individual-path questions, submits, then routes to the payment screen
/// (when a payment is owed) or straight to the status page.
class RegistrationFormPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationFormPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage> {
  late Future<(List<RegQuestion>, Map<String, dynamic>)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(List<RegQuestion>, Map<String, dynamic>)> _loadAll() async {
    final form = await RegistrationService.getForm(widget.regId);
    final prefill = await RegistrationService.getPrefill(widget.config.sport);
    final visible = form.where((q) => q.visibleFor('individual')).toList();
    return (visible, prefill);
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    final ok = await RegistrationService.submitIndividual(
      regId: widget.regId,
      config: widget.config,
      answers: answers,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Something went wrong — try again, and contact us if it keeps failing.')));
      return;
    }
    final submission = RegSubmission(
      path: 'individual',
      answers: answers,
      paid: false,
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (paymentOwed(config: widget.config, submission: submission)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PaymentScreen(
                regId: widget.regId,
                config: widget.config,
                fromSubmission: true)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RegistrationStatusPage(
                regId: widget.regId, config: widget.config)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
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
          final (questions, prefill) =
              snapshot.data ?? (const <RegQuestion>[], const <String, dynamic>{});
          if (questions.isEmpty) {
            return const Center(
                child: Text(
                    'This registration has no form yet — please try again later.'));
          }
          return DynamicRegistrationForm(
            questions: questions,
            initialValues: prefill,
            submitLabel: 'Register',
            onSubmit: _onSubmit,
          );
        },
      ),
    );
  }
}
