import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/insider_promo_field.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Everything [_RegistrationFormPageState._loadAll] fetches once per form
/// session. [priorSubmissions]/[promo] stay empty/disabled-default on the
/// joiner path (spec §7 — the promo code field is individual/captain only)
/// so that path never pays for the extra reads.
typedef _LoadedForm = ({
  List<RegQuestion> questions,
  Map<String, dynamic> prefill,
  List<Map<String, dynamic>> priorSubmissions,
  RegPromo promo,
});

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
  late Future<_LoadedForm> _load;

  /// The promo code field is offered on individual + team-captain paths only
  /// (spec §7) — the joiner path already skips payment via a team code and
  /// never sees it.
  bool get _showPromoField =>
      widget.path == 'individual' || widget.path == 'captain';

  /// config.teamFee for the captain path (the fee THIS registrant would owe
  /// before any discount), config.fee otherwise — the promo's "eligible fee"
  /// (spec §4).
  double get _eligibleFee => (widget.path == 'captain'
          ? widget.config.teamFee
          : widget.config.fee)
      .toDouble();

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<_LoadedForm> _loadAll() async {
    final form = await RegistrationService.getForm(widget.regId);
    final prefill = await RegistrationService.getPrefill(widget.config.sport);
    final visible = form.where((q) => q.visibleFor(widget.path)).toList();
    final priorSubmissions = _showPromoField
        ? await RegistrationService.getAllSubmissionAnswersForMatch()
        : const <Map<String, dynamic>>[];
    final promo = _showPromoField
        ? await RegistrationService.getPromo(widget.regId)
        : const RegPromo();
    return (
      questions: visible,
      prefill: prefill,
      priorSubmissions: priorSubmissions,
      promo: promo,
    );
  }

  Future<bool> _submitForPath(
      Map<String, dynamic> answers, InsiderPromoOutcome? promo) {
    switch (widget.path) {
      case 'captain':
        return RegistrationService.submitCaptain(
          regId: widget.regId,
          config: widget.config,
          teamName: widget.teamName,
          answers: answers,
          insiderCode: promo?.insiderCode ?? '',
          firstTimer: promo?.firstTimer,
          discountSource: promo?.discountSource ?? '',
          discountPct: promo?.discountPct,
          eligibleFee: promo?.eligibleFee,
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
          insiderCode: promo?.insiderCode ?? '',
          firstTimer: promo?.firstTimer,
          discountSource: promo?.discountSource ?? '',
          discountPct: promo?.discountPct,
          eligibleFee: promo?.eligibleFee,
        );
    }
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    // The promo field (when rendered) registers its resolved
    // InsiderPromoOutcome under this reserved key via the SAME FormBuilder
    // — pull it back out here so it never gets persisted inside the plain
    // question Answers map (lib/registration/insider_promo_field.dart).
    final promo =
        answers.remove(kInsiderPromoAnswerKey) as InsiderPromoOutcome?;
    final ok = await _submitForPath(answers, promo);
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
            // Skeleton sweep (F3 Fix 2): matches the form fields below.
            return const Padding(
              padding: EdgeInsets.all(15),
              child: Column(
                children: [
                  SkeletonBox(width: double.infinity, height: 56),
                  SizedBox(height: 14),
                  SkeletonBox(width: double.infinity, height: 56),
                  SizedBox(height: 14),
                  SkeletonBox(width: double.infinity, height: 56),
                  SizedBox(height: 14),
                  SkeletonBox(width: double.infinity, height: 56),
                ],
              ),
            );
          }
          final loaded = snapshot.data ??
              (
                questions: const <RegQuestion>[],
                prefill: const <String, dynamic>{},
                priorSubmissions: const <Map<String, dynamic>>[],
                promo: const RegPromo(),
              );
          if (loaded.questions.isEmpty) {
            return const Center(
                child: Text(
                    'This registration has no form yet — please try again later.'));
          }
          return DynamicRegistrationForm(
            questions: loaded.questions,
            initialValues: loaded.prefill,
            submitLabel: 'Register',
            onSubmit: _onSubmit,
            promoField: _showPromoField
                ? InsiderPromoCodeField(
                    eligibleFee: _eligibleFee,
                    promo: loaded.promo,
                    priorSubmissions: loaded.priorSubmissions,
                    myEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                    myPhone: (loaded.prefill['phone'] ?? '').toString(),
                  )
                : null,
          );
        },
      ),
    );
  }
}
