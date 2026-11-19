import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/account/delete_account_flow.dart'
    show isSignedInAccountGone;
import 'package:infinite_sports_flutter/account/session_sign_out.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart'
    show FreshAccountDeletion;
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart' show auth;
import 'package:infinite_sports_flutter/onboarding/profile_completion.dart';
import 'package:infinite_sports_flutter/onboarding/signup_validation.dart';

/// Reusable "About You" profile step (auth-wall B2 plan): date of birth,
/// city, ZIP, gender, and referral source. Serves THREE callers:
/// - signup step 2 of 3 (`stepIndex`/`stepCount` supplied, `askPhone: false`
///   since email signup already collected a phone number)
/// - Google/Apple first-run (`askPhone: true` — those providers never
///   collect a phone number)
/// - the existing-user one-time mandatory completion gate (no step labels)
///
/// Mandatory in all three cases — owner decision, no skip. `PopScope(canPop:
/// false)` blocks the hardware/gesture back-driven skip.
class AboutYouPage extends StatefulWidget {
  const AboutYouPage({
    super.key,
    required this.onDone,
    this.askPhone = false,
    this.stepIndex,
    this.stepCount,
    this.writeOverride,
    this.deleteFreshAccountOverride,
    this.signOutOverride,
    this.accountCreatedAtOverride,
    this.accountGoneOverride,
  });

  /// Called after a successful write. Callers decide what "done" means next
  /// (push the following step, or just pop back to the gate).
  final VoidCallback onDone;

  /// Google/Apple first-run also needs a phone number (email signup already
  /// collected one in Step 1).
  final bool askPhone;

  /// When both are supplied, the AppBar shows a "Step X of Y" subtitle
  /// (signup flow). Omitted for the existing-user completion gate.
  final int? stepIndex;
  final int? stepCount;

  /// Test seam: replaces the real `Users/<uid>` RTDB write so widget tests
  /// don't need Firebase running. Defaults to the real write in production.
  final Future<void> Function(Map<String, Object?> data)? writeOverride;

  /// Test seam: replaces `FirebaseAuthService.deleteFreshAccount` (the
  /// under-13 exit's server-side deletion of a recent account).
  final Future<FreshAccountDeletion> Function()? deleteFreshAccountOverride;

  /// Test seam: replaces `signOutAndClearSession` on the under-13 exit and
  /// on the "account no longer exists" save failure.
  final Future<void> Function()? signOutOverride;

  /// Test seam: the signed-in account's creation time (Firebase Auth
  /// metadata in production; null when unknown).
  final DateTime? Function()? accountCreatedAtOverride;

  /// Test seam: replaces `isSignedInAccountGone` (a save failure check).
  final Future<bool> Function()? accountGoneOverride;

  @override
  State<AboutYouPage> createState() => _AboutYouPageState();
}

class _AboutYouPageState extends State<AboutYouPage> {
  DateTime? _dob;
  final _cityController = TextEditingController();
  final _zipController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _gender;
  String? _referralSource;
  bool _saving = false;

  String? _dobError;
  String? _cityError;
  String? _zipError;
  String? _genderError;
  String? _referralError;
  String? _phoneError;

  @override
  void dispose() {
    _cityController.dispose();
    _zipController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1905),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  bool _validate() {
    setState(() {
      _dobError = validateDob(_dob);
      _cityError =
          _cityController.text.trim().isEmpty ? 'City is required' : null;
      _zipError = validateZip(_zipController.text.trim());
      _genderError = _gender == null ? 'Select one' : null;
      _referralError = _referralSource == null ? 'Select one' : null;
      _phoneError =
          widget.askPhone ? validatePhone(_phoneController.text) : null;
    });
    return _dobError == null &&
        _cityError == null &&
        _zipError == null &&
        _genderError == null &&
        _referralError == null &&
        _phoneError == null;
  }

  Future<void> _defaultWrite(Map<String, Object?> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseDatabase.instance.ref('Users/$uid').update(data);
  }

  /// How recent an account must be for the under-13 exit to delete it. The
  /// server's `deleteAccount` skips the recent-sign-in requirement for an
  /// account with an incomplete profile created within this window.
  static const _freshAccountWindow = Duration(days: 7);

  static DateTime? _firebaseCreatedAt() =>
      FirebaseAuth.instance.currentUser?.metadata.creationTime;

  /// How far in the future a creation time may look (phone clock slightly
  /// behind) and still count as recent.
  static const _clockSkewAllowance = Duration(minutes: 5);

  /// Whether the under-13 exit deletes the account. The sign-up flow
  /// ([stepIndex] set) ALWAYS does, whatever the phone clock says. Otherwise
  /// the account must be under [_freshAccountWindow] old; a clock running
  /// behind (creation time far in the "future") must not make an old account
  /// look new.
  bool _shouldDeleteAccount() {
    if (widget.stepIndex != null) return true;
    DateTime? created;
    try {
      created = (widget.accountCreatedAtOverride ?? _firebaseCreatedAt)();
    } catch (_) {
      created = null;
    }
    if (created == null) return false;
    final age = DateTime.now().difference(created);
    return age >= -_clockSkewAllowance && age <= _freshAccountWindow;
  }

  /// True while the under-13 exit is deleting / signing out: the page is
  /// covered by a blocking progress state and ignores every tap.
  bool _exiting = false;

  /// Under-13 exit (Terms of Use §1). The page is mandatory and blocks back,
  /// so someone too young needs a way out: explain, then sign out. An
  /// account created within [_freshAccountWindow] (the signup flow, or a
  /// later sign-in to the same incomplete account) is deleted first through
  /// the server's `deleteAccount` (all its data, the Auth user, and on iOS
  /// the Apple token revoke) so no orphan login keeps their email; an older
  /// account (an existing member completing their profile) only signs out.
  ///
  /// The deletion runs HERE, behind a blocking progress state, before the
  /// pop to the root (otherwise the signed-in home shows while it runs). If
  /// it did not delete the account, the person is still signed out and the
  /// welcome wall says so: never silent.
  Future<void> _showUnderageExit() async {
    if (_exiting) return;
    final shouldDelete = _shouldDeleteAccount();
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sorry, not yet'),
        content: Text(
            'Infinite Sports accounts are for people $kMinimumAccountAge and '
            'older. A parent or guardian can register you for a league from '
            'their own account. '
            '${shouldDelete ? 'This account will be removed and you will be '
                'signed out.' : 'You will be signed out.'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Fix date of birth'),
          ),
          FilledButton(
            key: const ValueKey('about_you_underage_sign_out'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text(shouldDelete ? 'Remove account and sign out' : 'Sign out'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted || _exiting) return;
    setState(() => _exiting = true);
    final deleteFresh =
        widget.deleteFreshAccountOverride ?? auth.deleteFreshAccount;
    // Captured NOW: the page is gone by the time the message shows. The
    // root ScaffoldMessenger sits above AuthGate, so it survives the swap
    // to the welcome wall (same as delete_account_flow.dart).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(
        Navigator.of(context, rootNavigator: true).context);
    var outcome = FreshAccountDeletion.nothingToRemove;
    if (shouldDelete) {
      try {
        outcome = await deleteFresh();
      } catch (e) {
        debugPrint('Under-13 account deletion failed: ${e.runtimeType}');
        outcome = FreshAccountDeletion.notDeleted;
      }
    }
    // Leave every onboarding route before the auth flip swaps the gate.
    await _popToRootAndSignOut(navigator);
    if (outcome == FreshAccountDeletion.notDeleted) {
      messenger?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 10),
        content: Text("We couldn't remove this account automatically. "
            "Email contact@infinitesports.org and we'll delete it."),
      ));
    }
  }

  /// Back to the root route, then the app's one sign-out. A sign-out
  /// hiccup must not leave the person on a dead page.
  Future<void> _popToRootAndSignOut(NavigatorState navigator) async {
    if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    final signOut = widget.signOutOverride ?? signOutAndClearSession;
    try {
      await signOut();
    } catch (e) {
      debugPrint('About You sign-out failed: ${e.runtimeType}');
    }
  }

  Future<bool> _accountGone() async {
    try {
      return await (widget.accountGoneOverride ?? isSignedInAccountGone)();
    } catch (_) {
      return false;
    }
  }

  Future<void> _continue() async {
    if (_saving || _exiting) return;
    if (!_validate()) {
      if (_dobError == kUnderageDobMessage) await _showUnderageExit();
      return;
    }
    setState(() => _saving = true);
    final data = <String, Object?>{
      'DOB': formatDob(_dob!),
      'City': _cityController.text.trim(),
      'Zip': _zipController.text.trim(),
      'Gender': _gender,
      'ReferralSource': _referralSource,
      'ProfileCompleted': true,
      if (widget.askPhone) 'Phone Number': _phoneController.text.trim(),
    };
    try {
      final write = widget.writeOverride ?? _defaultWrite;
      await write(data);
      widget.onDone();
    } catch (_) {
      if (!mounted) return;
      // An account deleted elsewhere (Manager admin delete, web request)
      // while this session is alive: every save is refused, and this page
      // blocks back, so leave instead of looping on "Something went wrong".
      // Captured NOW, like the under-13 exit: the page is gone by the time
      // the message shows, and the root ScaffoldMessenger (above AuthGate)
      // survives the swap to the welcome wall.
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.maybeOf(
          Navigator.of(context, rootNavigator: true).context);
      if (await _accountGone()) {
        await _popToRootAndSignOut(navigator);
        messenger?.showSnackBar(
            const SnackBar(content: Text('This account no longer exists.')));
        return;
      }
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSteps = widget.stepIndex != null && widget.stepCount != null;
    return PopScope(
      // Mandatory completion (owner decision) — no back-driven skip.
      canPop: false,
      child: Stack(
        children: [
          _buildPage(context, scheme, hasSteps),
          if (_exiting)
            Positioned.fill(
              key: const ValueKey('about_you_exit_progress'),
              child: Stack(
                children: [
                  ModalBarrier(
                    dismissible: false,
                    color: scheme.scrim.withValues(alpha: 0.4),
                  ),
                  Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: scheme.primary),
                            const SizedBox(height: 16),
                            Text('Signing out…',
                                style: TextStyle(color: scheme.onSurface)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, ColorScheme scheme, bool hasSteps) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('About you'),
            if (hasSteps)
              Text(
                'Step ${widget.stepIndex} of ${widget.stepCount}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date of birth',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('about_you_dob_field'),
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: _dobError,
                    suffixIcon: Icon(Icons.calendar_today,
                        color: scheme.onSurfaceVariant),
                  ),
                  child: Text(
                    _dob == null ? 'Select date of birth' : formatDob(_dob!),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('about_you_city_field'),
                controller: _cityController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'City',
                  border: const OutlineInputBorder(),
                  errorText: _cityError,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('about_you_zip_field'),
                controller: _zipController,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: InputDecoration(
                  labelText: 'ZIP code',
                  border: const OutlineInputBorder(),
                  errorText: _zipError,
                ),
              ),
              if (widget.askPhone) ...[
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('about_you_phone_field'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: const [UsPhoneInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    border: const OutlineInputBorder(),
                    errorText: _phoneError,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Gender', style: Theme.of(context).textTheme.titleMedium),
              if (_genderError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_genderError!,
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  ChoiceChip(
                    key: const ValueKey('gender_chip_Male'),
                    label: const Text('Male'),
                    selected: _gender == 'Male',
                    onSelected: (_) => setState(() => _gender = 'Male'),
                  ),
                  ChoiceChip(
                    key: const ValueKey('gender_chip_Female'),
                    label: const Text('Female'),
                    selected: _gender == 'Female',
                    onSelected: (_) => setState(() => _gender = 'Female'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('How did you hear about us?',
                  style: Theme.of(context).textTheme.titleMedium),
              if (_referralError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_referralError!,
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in kReferralOptions)
                    ChoiceChip(
                      key: ValueKey('referral_chip_$option'),
                      label: Text(option),
                      selected: _referralSource == option,
                      onSelected: (_) =>
                          setState(() => _referralSource = option),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('about_you_continue_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _continue,
                  child: _saving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.onPrimary),
                        )
                      : const Text('Continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
