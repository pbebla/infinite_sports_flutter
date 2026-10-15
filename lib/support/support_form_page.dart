import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/support/my_tickets_page.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';
import 'package:infinite_sports_flutter/support/support_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The in-app "Help & Feedback" form (spec decision #1) — category cards
/// with emoji + helper text, required message (≤5,000 chars), up to 5
/// screenshots (downscaled ≤1600px JPEG at pick time), auto-captured context
/// (uid, name, email, app version, platform, device, the screen the player
/// came from). Submitting writes the full ticket through
/// [SupportService.createTicket] and lands on an in-place success body with
/// the reference number.
///
/// Test seams (insiders_info_page.dart pattern): [submitOverride] replaces
/// the real createTicket call and receives the fully assembled context;
/// `prefill*` replace the FirebaseAuth/Users-node/package_info lookups;
/// [pickImagesOverride] replaces the image_picker flow;
/// [myTicketsPageBuilder] replaces the real MyTicketsPage (which reaches for
/// FirebaseAuth.instance in its default stream wiring).
class SupportFormPage extends StatefulWidget {
  const SupportFormPage({
    super.key,
    this.fromScreen = 'Unknown',
    this.submitOverride,
    this.prefillName,
    this.prefillEmail,
    this.prefillUid,
    this.prefillAppVersion,
    this.prefillPlatform,
    this.prefillDevice,
    this.pickImagesOverride,
    this.myTicketsPageBuilder,
  });

  /// Label of the screen the player opened the form from ('Drawer',
  /// 'Settings', ...) — stored on the ticket as `Screen`.
  final String fromScreen;

  /// Test seam: replaces [SupportService.createTicket]. Receives the exact
  /// assembled ticket payload and returns the new reference number.
  final Future<int> Function({
    required String category,
    required String message,
    required List<XFile> screenshots,
    required String name,
    required String email,
    required String uid,
    required String appVersion,
    required String platform,
    required String device,
    required String screen,
  })? submitOverride;

  /// Test seams for the auto-captured context — production reads
  /// FirebaseAuth + `Users/<uid>` (name/email/uid via `.once()`),
  /// package_info_plus (app version) and dart:io Platform
  /// (platform/device).
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillUid;
  final String? prefillAppVersion;
  final String? prefillPlatform;
  final String? prefillDevice;

  /// Test seam: replaces the image_picker multi-pick (which already
  /// downscales to ≤[kScreenshotMaxDimension]px JPEG at
  /// [kScreenshotJpegQuality] quality on the way in).
  final Future<List<XFile>> Function()? pickImagesOverride;

  /// Test seam replacing the real MyTicketsPage pushes (app-bar icon +
  /// success body button) — the real page touches FirebaseAuth.instance in
  /// its default stream wiring.
  final Widget Function()? myTicketsPageBuilder;

  @override
  State<SupportFormPage> createState() => _SupportFormPageState();
}

class _SupportFormPageState extends State<SupportFormPage> {
  final TextEditingController _messageController = TextEditingController();
  String? _category;
  List<XFile> _screenshots = [];
  bool _submitting = false;
  int? _submittedNum; // set → the success body replaces the form

  String _name = '';
  String _email = '';
  String _uid = '';
  String _appVersion = '';
  late final String _platform;
  late final String _device;

  @override
  void initState() {
    super.initState();
    // Rebuilds the submit button's enabled state as the player types.
    _messageController.addListener(() => setState(() {}));
    _name = widget.prefillName ?? '';
    _email = widget.prefillEmail ?? '';
    _uid = widget.prefillUid ?? '';
    _appVersion = widget.prefillAppVersion ?? '';
    // `??` short-circuits: with every prefill supplied (tests), FirebaseAuth
    // / FirebaseDatabase / package_info are never touched.
    if (widget.prefillName == null ||
        widget.prefillEmail == null ||
        widget.prefillUid == null) {
      _loadIdentity();
    }
    if (widget.prefillAppVersion == null) _loadAppVersion();
    _platform = widget.prefillPlatform ?? (Platform.isIOS ? 'iOS' : 'Android');
    _device = widget.prefillDevice ?? _bestEffortDevice();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  static String _bestEffortDevice() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadIdentity() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (widget.prefillUid == null) _uid = user?.uid ?? '';
      if (widget.prefillEmail == null) _email = user?.email ?? '';
      if (widget.prefillName == null) {
        _name = user?.displayName ?? '';
        if (_name.isEmpty && _uid.isNotEmpty) {
          final snap =
              (await FirebaseDatabase.instance.ref('Users/$_uid').once())
                  .snapshot;
          final raw = snap.value;
          if (raw is Map) {
            final first = raw['First Name']?.toString() ?? '';
            final last = raw['Last Name']?.toString() ?? '';
            _name = [first, last].where((s) => s.isNotEmpty).join(' ');
          }
        }
      }
    } catch (_) {
      // Silent/best-effort (utility.dart convention) — the ticket still
      // carries the uid, so support can always find the player.
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = '';
    }
    if (mounted) setState(() {});
  }

  bool get _canSubmit =>
      !_submitting &&
      _category != null &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _pickScreenshots() async {
    final pick = widget.pickImagesOverride ??
        () async {
          try {
            // image_picker downscales + re-encodes at pick time: the longest
            // side never exceeds kScreenshotMaxDimension and the JPEG is
            // written at kScreenshotJpegQuality — exactly the "client-side
            // downscale ≤1600px JPEG ~80" rule, before anything is uploaded.
            return await ImagePicker().pickMultiImage(
              maxWidth: kScreenshotMaxDimension.toDouble(),
              maxHeight: kScreenshotMaxDimension.toDouble(),
              imageQuality: kScreenshotJpegQuality,
              limit: kMaxScreenshots,
            );
          } catch (_) {
            return <XFile>[];
          }
        };
    final picked = await pick();
    if (picked.isEmpty || !mounted) return;
    final dropped = _screenshots.length + picked.length > kMaxScreenshots;
    setState(() => _screenshots = capScreenshots(_screenshots, picked));
    if (dropped) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Up to $kMaxScreenshots screenshots per ticket — '
              'the extras were left out.')));
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final submit = widget.submitOverride ?? _realSubmit;
      final n = await submit(
        category: _category!,
        message: _messageController.text.trim(),
        screenshots: List<XFile>.of(_screenshots),
        name: _name,
        email: _email,
        uid: _uid,
        appVersion: _appVersion,
        platform: _platform,
        device: _device,
        screen: widget.fromScreen,
      );
      if (mounted) setState(() => _submittedNum = n);
    } on SupportRateLimitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<int> _realSubmit({
    required String category,
    required String message,
    required List<XFile> screenshots,
    required String name,
    required String email,
    required String uid,
    required String appVersion,
    required String platform,
    required String device,
    required String screen,
  }) =>
      SupportService.createTicket(
        uid: uid,
        name: name,
        email: email,
        category: category,
        message: message,
        appVersion: appVersion,
        platform: platform,
        device: device,
        screen: screen,
        screenshots: [for (final x in screenshots) File(x.path)],
      );

  void _openMyTickets() {
    final builder = widget.myTicketsPageBuilder ?? () => const MyTicketsPage();
    Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Feedback'),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
        actions: [
          IconButton(
            key: const ValueKey('support_my_tickets_button'),
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'My Tickets',
            onPressed: _openMyTickets,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // Glass-navbar clearance (house rule): the page's own 16 plus the
          // floating nav inset.
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          child: _submittedNum != null
              ? _successBody(context, _submittedNum!)
              : _formBody(context),
        ),
      ),
    );
  }

  Widget _formBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Support & feedback',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Tell us what you need — or what Infinite Sports should do next.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _categoryGrid(context),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('support_message_field'),
          controller: _messageController,
          maxLength: kSupportMessageMaxLength,
          maxLines: 6,
          minLines: 4,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Your message',
            alignLabelWithHint: true,
            hintText: 'The more detail the better — what you were doing, '
                'what you expected, what happened.',
            hintMaxLines: 4,
          ),
        ),
        const SizedBox(height: 12),
        _screenshotSection(context),
        const SizedBox(height: 16),
        Text(
          "We'll include your name, email, app version and the screen you "
          'came from automatically.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('support_submit_button'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.onPrimary),
                  )
                : const Text('Send it',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _categoryGrid(BuildContext context) {
    const spacing = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final cat in kSupportCategories)
              SizedBox(width: itemWidth, child: _categoryCard(context, cat)),
          ],
        );
      },
    );
  }

  Widget _categoryCard(BuildContext context, SupportCategory cat) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _category == cat.key;
    return InkWell(
      key: ValueKey('support_cat_${cat.key}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _category = cat.key),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cat.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(cat.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                )),
            const SizedBox(height: 2),
            Text(cat.helper,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }

  Widget _screenshotSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _screenshots.length; i++)
              _thumbnail(context, i),
            if (_screenshots.length < kMaxScreenshots)
              OutlinedButton.icon(
                key: const ValueKey('support_add_screenshot_button'),
                onPressed: _pickScreenshots,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_screenshots.isEmpty
                    ? 'Add screenshots'
                    : 'Add more (${_screenshots.length}/$kMaxScreenshots)'),
              ),
          ],
        ),
        if (_screenshots.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Optional — up to $kMaxScreenshots.',
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _thumbnail(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_screenshots[index].path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Container(
                width: 72,
                height: 72,
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.image_outlined,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              key: ValueKey('support_shot_remove_$index'),
              onTap: () => setState(() {
                _screenshots = List<XFile>.of(_screenshots)..removeAt(index);
              }),
              child: Container(
                decoration: BoxDecoration(
                  // Scrim over an unknown image — intentionally the same in
                  // both themes for contrast against any screenshot.
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successBody(BuildContext context, int num) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('support_success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(Icons.check_circle_outline, size: 64, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Thanks — your reference is #$num',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          "We've emailed you a copy. Replies land in the app under "
          "My Tickets, and you'll hear from us there.",
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('support_view_tickets_button'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _openMyTickets,
          child: const Text('View my tickets',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
