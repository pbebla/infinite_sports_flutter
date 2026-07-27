import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/insiders/insider_dashboard_page.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';

/// Sports offered in the "sports of interest" multi-select (Task F2) —
/// mirrors the sport set in lib/onboarding/favorite_sports_page.dart, scoped
/// to the sports Infinite Sports currently runs.
const List<String> kInsiderInterestSports = [
  'Futsal',
  'Soccer',
  'Basketball',
  'Flag Football',
  'Volleyball',
];

// TODO(owner): replace with the final legal Program Terms copy once
// supplied — spec §7 only calls for "info + terms", no final legal text yet.
const String kInsiderPlaceholderTerms =
    'By applying, you agree to represent Infinite Sports honestly and to '
    'share your referral code only with genuine prospective players. Tier '
    'discounts apply only to your own individual registration fees — never '
    'team fees. Infinite Sports may suspend, decline, or void referrals for '
    'suspected abuse at its sole discretion. Final program terms will be '
    'provided by Infinite Sports.';

/// Infinite Insiders explainer + terms + Accept & Apply page (Task F2).
/// Reached from the "Infinite Insiders" drawer row (lib/navbar.dart) in
/// every state: no application, pending, declined, or active.
///
/// LIVE: rides [InsiderService.watchMyInsider] so an approval/decline that
/// happens while this page is open flips its body immediately, no refresh
/// (spec §7).
class InsidersInfoPage extends StatefulWidget {
  const InsidersInfoPage({
    super.key,
    this.insiderStream,
    this.prefillName,
    this.prefillEmail,
    this.applyOverride,
    this.dashboardPageBuilder,
  });

  /// Test seam: replaces the live `/Insiders/<uid>` stream. Defaults to
  /// InsiderService.watchMyInsider for the signed-in uid.
  final Stream<Insider?>? insiderStream;

  /// Test seams for the read-only Name/Email display rows — production
  /// reads `Users/<uid>` First/Last Name and FirebaseAuth.currentUser.email.
  final String? prefillName;
  final String? prefillEmail;

  /// Test seam: replaces the real InsiderService.apply call, matching the
  /// `writeOverride` pattern in lib/onboarding/about_you_page.dart.
  final Future<void> Function({
    required String name,
    required String email,
    required List<String> sports,
  })? applyOverride;

  /// Test seam replacing the real `Navigator.push(... InsiderDashboardPage
  /// ...)` call the active state's "Open your Insider dashboard" button
  /// makes (Task F4) — the real page reaches for FirebaseAuth.instance in
  /// its own default stream wiring, which isn't available in widget tests.
  final Widget Function()? dashboardPageBuilder;

  @override
  State<InsidersInfoPage> createState() => _InsidersInfoPageState();
}

class _InsidersInfoPageState extends State<InsidersInfoPage> {
  late final Stream<Insider?> _insiderStream;
  String _name = '';
  String _email = '';
  final Set<String> _selectedSports = {};
  bool _termsAccepted = false;
  bool _applying = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // `??` short-circuits: when a test supplies insiderStream, _uid (and
    // therefore FirebaseAuth.instance) is never touched.
    _insiderStream =
        widget.insiderStream ?? InsiderService.watchMyInsider(_uid);
    _name = widget.prefillName ?? '';
    _email = widget.prefillEmail ?? '';
    if (widget.prefillName == null || widget.prefillEmail == null) {
      _loadPrefill();
    }
  }

  Future<void> _loadPrefill() async {
    try {
      if (widget.prefillEmail == null) {
        _email = FirebaseAuth.instance.currentUser?.email ?? '';
      }
      if (widget.prefillName == null) {
        final uid = _uid;
        if (uid.isNotEmpty) {
          final snap =
              await FirebaseDatabase.instance.ref('Users/$uid').get();
          final raw = snap.value;
          if (raw is Map) {
            final first = raw['First Name']?.toString() ?? '';
            final last = raw['Last Name']?.toString() ?? '';
            final combined =
                [first, last].where((s) => s.isNotEmpty).join(' ');
            if (combined.isNotEmpty) _name = combined;
          }
        }
      }
    } catch (_) {
      // Silent/best-effort (utility.dart convention) — prefill just stays
      // blank on failure; the fields are read-only anyway.
    }
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_applying) return;
    setState(() => _applying = true);
    final sports = _selectedSports.toList();
    try {
      final apply = widget.applyOverride ??
          ({
            required String name,
            required String email,
            required List<String> sports,
          }) =>
              InsiderService.apply(
                  uid: _uid, name: name, email: email, sports: sports);
      await apply(name: _name, email: _email, sports: sports);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Infinite Insiders'),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: StreamBuilder<Insider?>(
        stream: _insiderStream,
        builder: (context, snapshot) {
          final insider = snapshot.data;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _explainer(context),
                  const SizedBox(height: 20),
                  _tierTable(context),
                  const SizedBox(height: 20),
                  _termsSection(context),
                  const SizedBox(height: 20),
                  _stateBody(context, insider),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _explainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.diamond, color: scheme.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Infinite Insiders',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Refer players into Infinite Sports leagues, tournaments, and '
          'events with your own personal code. Every friend who joins and '
          'pays using your code grows your referral count — climb the '
          'tiers below to unlock a growing discount on your OWN '
          'registrations.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _tierTable(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Referral thresholds mirror spec §2 (Bronze 5, Silver 10, Gold 15,
    // Platinum 20, Infinite 25+) — display-only, paired with the pure
    // tierName/tierDiscountPct helpers (lib/model/insider.dart).
    const thresholds = [5, 10, 15, 20, 25];
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var tier = 1; tier <= 5; tier++)
              ListTile(
                dense: true,
                leading: Icon(Icons.emoji_events, color: scheme.primary),
                title: Text(tierName(tier),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${thresholds[tier - 1]}+ referrals'),
                trailing: Text('${tierDiscountPct(tier)}% off',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: scheme.primary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _termsSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Program terms',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(kInsiderPlaceholderTerms,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _stateBody(BuildContext context, Insider? insider) {
    if (insider == null) return _applyForm(context);
    if (insider.isPending) return _pendingBody(context);
    if (insider.isDeclined) return _applyForm(context, declined: true);
    if (insider.isActive) return _activeBody(context, insider);
    if (insider.isSuspended) return _suspendedBody(context);
    return _applyForm(context);
  }

  Widget _applyForm(BuildContext context, {bool declined = false}) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit =
        _selectedSports.isNotEmpty && _termsAccepted && !_applying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (declined)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Your previous application was declined. You can apply again '
              'below.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        Text('Apply to become an Insider',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(
          key: const ValueKey('insiders_name_row'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Name'),
          subtitle: Text(_name.isEmpty ? '—' : _name),
        ),
        ListTile(
          key: const ValueKey('insiders_email_row'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Email'),
          subtitle: Text(_email.isEmpty ? '—' : _email),
        ),
        const SizedBox(height: 8),
        Text('Sports of interest',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sport in kInsiderInterestSports)
              FilterChip(
                key: ValueKey('insider_sport_chip_$sport'),
                label: Text(sport),
                selected: _selectedSports.contains(sport),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _selectedSports.add(sport);
                  } else {
                    _selectedSports.remove(sport);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('insiders_terms_checkbox'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _termsAccepted,
          onChanged: (value) =>
              setState(() => _termsAccepted = value ?? false),
          title: const Text('I have read and accept the Program terms above'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('insiders_apply_button'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: canSubmit ? _submit : null,
            child: _applying
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.onPrimary),
                  )
                : const Text('Accept & Apply',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _pendingBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.hourglass_top, color: scheme.primary, size: 48),
            const SizedBox(height: 12),
            Text('We got your application!',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              "We're reviewing it now — we'll let you know the moment "
              'there\'s an update.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suspendedBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.pause_circle_outline, color: scheme.error, size: 48),
            const SizedBox(height: 12),
            Text('Your Insider account is currently suspended.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Contact us for details.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _openDashboard(BuildContext context) {
    final builder = widget.dashboardPageBuilder ??
        () => const InsiderDashboardPage();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => builder()),
    );
  }

  Widget _activeBody(BuildContext context, Insider insider) {
    final scheme = Theme.of(context).colorScheme;
    final label = insider.tier == 0 ? 'Insider' : tierName(insider.tier);
    final pct = tierDiscountPct(insider.tier);
    return Card(
      elevation: 2,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.diamond, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  insider.tier == 0 ? label : '$label — $pct% off',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: scheme.onPrimaryContainer),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Your code',
                style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(insider.code,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: scheme.onPrimaryContainer)),
                IconButton(
                  key: const ValueKey('insiders_copy_code_button'),
                  icon: Icon(Icons.copy, color: scheme.onPrimaryContainer),
                  tooltip: 'Copy code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: insider.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Referrals: ${insider.totalReferred}',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('insiders_open_dashboard_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _openDashboard(context),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('Open your Insider dashboard',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
