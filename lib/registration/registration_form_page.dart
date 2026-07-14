import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Loads the registration's form + the player's profile prefill, renders the
/// questions visible on [path] ('individual' | 'captain' | 'joiner'),
/// submits through the matching service call, then routes to the payment
/// screen (when a payment is owed — captains owe the TEAM fee) or straight
/// to the status page.
class RegistrationFormPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;
  final String path; // 'individual' | 'captain' | 'joiner'
  final String teamName; // captain path: the new team's cleaned name
  final RegTeam? team; // joiner path: the approved team being joined

  const RegistrationFormPage({
    super.key,
    required this.regId,
    required this.config,
    this.path = 'individual',
    this.teamName = '',
    this.team,
  });

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
    final visible = form.where((q) => q.visibleFor(widget.path)).toList();
    return (visible, prefill);
  }

  Future<bool> _submitForPath(Map<String, dynamic> answers) {
    switch (widget.path) {
      case 'captain':
        return RegistrationService.submitCaptain(
          regId: widget.regId,
          config: widget.config,
          teamName: widget.teamName,
          answers: answers,
        );
      case 'joiner':
        return RegistrationService.submitJoiner(
          regId: widget.regId,
          config: widget.config,
          team: widget.team!,
          answers: answers,
        );
      default:
        return RegistrationService.submitIndividual(
          regId: widget.regId,
          config: widget.config,
          answers: answers,
        );
    }
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    final ok = await _submitForPath(answers);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Something went wrong — try again, and contact us if it keeps failing.')));
      return;
    }
    // Mirror of what the service just wrote — enough for the owed check.
    final waived = widget.team?.codeWaivesPayment ?? false;
    final bornPaid = widget.path == 'joiner' && waived;
    final submission = RegSubmission(
      path: widget.path,
      answers: answers,
      teamId: widget.team?.id ?? '',
      paid: bornPaid,
      paidVia: bornPaid ? 'team code' : '',
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
    // A successful submission ends the registration flow — clear the whole
    // entry -> path -> [join code] -> form stack underneath so the back
    // button (and the status page's own back arrow) can't walk the user
    // back into "register again" screens. (route) => route.isFirst keeps
    // whatever the flow was pushed onto (the app's root navigator when
    // opened from the drawer, or the Matches tab's nested navigator when
    // opened from the frontpage banner) landing on that navigator's home
    // route.
    if (paymentOwed(
        config: widget.config,
        submission: submission,
        codeWaivesPayment: waived)) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => PaymentScreen(
                regId: widget.regId,
                config: widget.config,
                amount: amountOwed(
                    config: widget.config,
                    submission: submission,
                    codeWaivesPayment: waived),
                fromSubmission: true)),
        (route) => route.isFirst,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => RegistrationStatusPage(
                regId: widget.regId, config: widget.config)),
        (route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
        bottom: widget.path == 'individual'
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.path == 'captain'
                        ? 'New team: ${widget.teamName}'
                        : 'Joining ${widget.team?.name ?? 'team'}',
                    style: TextStyle(color: appBarForeground(context), fontSize: 14),
                  ),
                ),
              ),
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
