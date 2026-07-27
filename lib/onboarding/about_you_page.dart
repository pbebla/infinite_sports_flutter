import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
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

  Future<void> _continue() async {
    if (_saving) return;
    if (!_validate()) return;
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
      child: Scaffold(
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
      ),
    );
  }
}
