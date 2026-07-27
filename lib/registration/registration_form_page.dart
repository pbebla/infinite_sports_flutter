import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
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
/// so that path never pays for the extra reads. [insider] is a one-shot read
/// of the SIGNED-IN registrant's own `/Insiders/{uid}` node (Task F5) — null
/// on every path except individual (spec §2: the tier discount only ever
/// applies to the Insider's own individual fee, enforced by
/// [insiderTierDiscountApplies]), and null there too when signed out or the
/// account has never applied to the program.
typedef _LoadedForm = ({
  List<RegQuestion> questions,
  Map<String, dynamic> prefill,
  List<Map<String, dynamic>> priorSubmissions,
  RegPromo promo,
  Insider? insider,
});

/// The discount stamp [RegistrationFormPage._resolveDiscountStamp] settles
/// on before writing a submission — either the promo-code field's own
/// InsiderPromoOutcome carried through unchanged, or (Task F5) the
/// registrant's OWN Insider tier discount when it beats/ties the promo
/// under [pickBestDiscount]. insiderCode/firstTimer always describe a code
/// the registrant entered (referring someone ELSE) — entirely independent
/// of which discount source wins on their OWN fee.
typedef _DiscountStamp = ({
  String insiderCode,
  bool? firstTimer,
  String discountSource,
  double? discountPct,
  double? eligibleFee,
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
    // Task F5 — the Insider tier discount only ever applies on the
    // individual path (spec §2), so every other path skips this read.
    final insider =
        widget.path == 'individual' ? await _loadMyInsider() : null;
    return (
      questions: visible,
      prefill: prefill,
      priorSubmissions: priorSubmissions,
      promo: promo,
      insider: insider,
    );
  }

  /// One-shot read of the signed-in account's own Insider record via
  /// [InsiderService.watchMyInsider]'s first emission — null when signed
  /// out, never applied, or on a stream error (defensive: a broken read
  /// here should never block registration, it just means no tier discount
  /// preview/stamp this session).
  Future<Insider?> _loadMyInsider() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      return await InsiderService.watchMyInsider(uid).first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _submitForPath(
      Map<String, dynamic> answers, _DiscountStamp stamp) {
    switch (widget.path) {
      case 'captain':
        return RegistrationService.submitCaptain(
          regId: widget.regId,
          config: widget.config,
          teamName: widget.teamName,
          answers: answers,
          insiderCode: stamp.insiderCode,
          firstTimer: stamp.firstTimer,
          discountSource: stamp.discountSource,
          discountPct: stamp.discountPct,
          eligibleFee: stamp.eligibleFee,
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
          insiderCode: stamp.insiderCode,
          firstTimer: stamp.firstTimer,
          discountSource: stamp.discountSource,
          discountPct: stamp.discountPct,
          eligibleFee: stamp.eligibleFee,
        );
    }
  }

  /// Resolves the discount actually stamped onto this submission (Task F5 —
  /// spec §2/§5): the promo-code field's own outcome (if a code was entered
  /// and it won the first-timer-promo check, `promo.discountSource ==
  /// 'first_timer_promo'`) competes best-discount-wins
  /// ([pickBestDiscount]) against this registrant's OWN active-Insider tier
  /// discount — never a candidate on the captain/joiner paths
  /// ([insiderTierDiscountApplies], spec §2 "individual fees only").
  ///
  /// [promo]'s insiderCode/firstTimer are carried through UNCHANGED
  /// regardless of which discount wins: those describe a code the
  /// registrant entered (referring someone ELSE), entirely independent of
  /// whose discount ends up applied to their OWN fee. An Insider paying
  /// their own fee with their OWN tier discount therefore stamps no
  /// InsiderCode at all unless they separately entered someone else's valid
  /// code — self-referral (own code on own registration) is already
  /// rejected at code-entry time (evaluateCode's selfReferral branch), and
  /// the payment-watcher's decideOnPaidFlip only ever counts a referral when
  /// InsiderCode is present, so an Insider's own insider_tier-discounted
  /// registration never creates a referral for themselves (functions/src/
  /// lib/insiders.ts).
  Future<_DiscountStamp> _resolveDiscountStamp(
      InsiderPromoOutcome? promo) async {
    final insider = (await _load).insider;
    final tierApplies = insider != null &&
        insiderTierDiscountApplies(
          path: widget.path,
          active: insider.isActive,
          tier: insider.tier,
        );
    final insiderPct =
        tierApplies ? tierDiscountPct(insider.tier).toDouble() : null;
    final promoPct = promo?.discountSource == 'first_timer_promo'
        ? promo?.discountPct
        : null;
    final best = pickBestDiscount(insiderPct: insiderPct, promoPct: promoPct);

    if (best.source == DiscountWinner.insiderTier) {
      return (
        insiderCode: promo?.insiderCode ?? '',
        firstTimer: promo?.firstTimer,
        discountSource: 'insider_tier',
        discountPct: best.pct,
        eligibleFee: _eligibleFee,
      );
    }
    return (
      insiderCode: promo?.insiderCode ?? '',
      firstTimer: promo?.firstTimer,
      discountSource: promo?.discountSource ?? '',
      discountPct: promo?.discountPct,
      eligibleFee: promo?.eligibleFee,
    );
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    // The promo field (when rendered) registers its resolved
    // InsiderPromoOutcome under this reserved key via the SAME FormBuilder
    // — pull it back out here so it never gets persisted inside the plain
    // question Answers map (lib/registration/insider_promo_field.dart).
    final promo =
        answers.remove(kInsiderPromoAnswerKey) as InsiderPromoOutcome?;
    final stamp = await _resolveDiscountStamp(promo);
    final ok = await _submitForPath(answers, stamp);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Something went wrong — try again, and contact us if it keeps failing.')));
      return;
    }
    // Task F5 — a brief confirmation before navigating away; the payment
    // screen's itemized breakdown (payment_screen.dart _amountCard) is the
    // authoritative, persistent display of this same stamped discount.
    if (stamp.discountSource == 'insider_tier' && stamp.discountPct != null) {
      final tier = tierNameForDiscountPct(stamp.discountPct!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Insider perk applied: $tier −${_pctLabel(stamp.discountPct)}%')));
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
                insider: null,
              );
          if (loaded.questions.isEmpty) {
            return const Center(
                child: Text(
                    'This registration has no form yet — please try again later.'));
          }
          final insider = loaded.insider;
          final showInsiderBanner = insider != null &&
              insiderTierDiscountApplies(
                path: widget.path,
                active: insider.isActive,
                tier: insider.tier,
              );
          return Column(
            children: [
              if (showInsiderBanner) _insiderPerkBanner(context, insider),
              Expanded(
                child: DynamicRegistrationForm(
                  questions: loaded.questions,
                  initialValues: loaded.prefill,
                  submitLabel: 'Register',
                  onSubmit: _onSubmit,
                  promoField: _showPromoField
                      ? InsiderPromoCodeField(
                          eligibleFee: _eligibleFee,
                          promo: loaded.promo,
                          priorSubmissions: loaded.priorSubmissions,
                          myEmail:
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          myPhone: (loaded.prefill['phone'] ?? '').toString(),
                        )
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Task F5 preview banner: shown above the form whenever the signed-in
  /// registrant is themselves an active Insider whose tier discount applies
  /// on THIS path (always individual — [insiderTierDiscountApplies]). This
  /// is a preview, not the authoritative outcome: in the rare edge case
  /// where the registrant ALSO enters another Insider's code and turns out
  /// to be a first-timer with a bigger promo percent, [pickBestDiscount]
  /// may stamp 'first_timer_promo' instead at submit time — the payment
  /// screen's itemized line always reflects whichever source actually won
  /// (payment_screen.dart _amountCard).
  Widget _insiderPerkBanner(BuildContext context, Insider insider) {
    final scheme = Theme.of(context).colorScheme;
    final pct = tierDiscountPct(insider.tier);
    final tier = tierName(insider.tier);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(15, 15, 15, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.star, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Insider perk applied: $tier −$pct%',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a discount percent without a trailing ".0" ('15' not '15.0') —
  /// same convention as payment_screen.dart/insider_promo_field.dart.
  String _pctLabel(double? pct) {
    if (pct == null) return '';
    return pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toString();
  }
}
