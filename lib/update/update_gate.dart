// Part D (forced updates): the gate around the whole app and the
// "Update required" screen.
//
// The gate sits ABOVE the Navigator (MaterialApp.builder in lib/main.dart),
// so the screen uses nothing that needs a Navigator or an Overlay (no
// dialogs, no tooltips, no app bar).
//
// Fails open: only a positive, complete store answer blocks. A check that
// throws, times out or cannot tell lets the fan in, and the check never
// delays the first frame.

import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/update/store_update_check.dart';
import 'package:infinite_sports_flutter/update/update_decision.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `shared_preferences` key: the installed `version+build` a check last said
/// must update. A fan who was already told sees the screen at once on the
/// next launch; after updating, the installed build differs, so it no
/// longer matches.
const String kBlockedBuildPrefKey = 'forceUpdate.blockedBuild';

/// While not blocked, a foreground return re-checks at most this often.
const Duration kUpdateRecheckInterval = Duration(minutes: 30);

/// A check that has not answered by then counts as "not required" (the
/// checkers bound their own calls; this guards against one that hangs).
const Duration kUpdateCheckLimit = Duration(seconds: 20);

/// The live `AppConfig/ForceUpdate` node (the Manager's pause switch).
Stream<Object?> _liveForceUpdateNode() => FirebaseDatabase.instance
    .ref('AppConfig/ForceUpdate')
    .onValue
    .map((event) => event.snapshot.value);

class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.child,
    required this.checker,
    required this.installedBuild,
    this.cachedBlockedBuild,
    this.pauseStates,
    this.now,
  });

  /// The app (the Navigator). Always mounted; while an update is required it
  /// sits under the Update screen with no taps, focus or semantics.
  final Widget child;
  final StoreUpdateChecker checker;

  /// The installed `version+build`, e.g. `5.0.0+30`.
  final String installedBuild;

  /// [kBlockedBuildPrefKey]'s saved value, read before `runApp`.
  final String? cachedBlockedBuild;

  /// `AppConfig/ForceUpdate` values; defaults to the live `onValue` stream.
  final Stream<Object?>? pauseStates;

  final DateTime Function()? now;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  /// The latest store answer (or the remembered one until the first check).
  late UpdateNeed _need;

  /// The latest `AppConfig/ForceUpdate` value; an error clears it.
  Object? _pauseNode;
  StreamSubscription<Object?>? _pauseSub;

  bool _checking = false;
  DateTime? _lastCheckStarted;

  /// An update is starting (Play's flow may be open): further taps on
  /// `Update` are ignored so it can never run twice.
  bool _starting = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  bool get _paused =>
      forceUpdatePaused(_pauseNode, _now().millisecondsSinceEpoch);

  bool get _blocked => _need.required && !_paused;

  @override
  void initState() {
    super.initState();
    final remembered = widget.installedBuild.isNotEmpty &&
        widget.cachedBlockedBuild == widget.installedBuild;
    _need = UpdateNeed(required: remembered);
    WidgetsBinding.instance.addObserver(this);
    _listenToPause();
    unawaited(_check());
  }

  void _listenToPause() {
    Stream<Object?> states;
    try {
      states = widget.pauseStates ?? _liveForceUpdateNode();
    } catch (_) {
      return; // no pause switch readable: forced updates stay on
    }
    _pauseSub = states.listen(
      (node) => _onPauseNode(node),
      onError: (Object _) => _onPauseNode(null),
    );
  }

  void _onPauseNode(Object? node) {
    if (!mounted) return;
    setState(() => _pauseNode = node);
    unawaited(_rememberBlocked());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back from the store (or Play's update flow): `Update` works again.
    _starting = false;
    // A pause that ran out while the app was away takes effect now.
    setState(() {});
    final last = _lastCheckStarted;
    final due = _need.required ||
        last == null ||
        _now().difference(last) >= kUpdateRecheckInterval;
    if (due) unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    _lastCheckStarted = _now();
    UpdateNeed need;
    try {
      need = await widget.checker.check().timeout(kUpdateCheckLimit);
    } catch (_) {
      need = const UpdateNeed(required: false);
    }
    _checking = false;
    if (!mounted) return;
    setState(() => _need = need);
    await _rememberBlocked();
  }

  /// Saves the installed build only while the fan is really blocked
  /// (required and not paused); clears it otherwise. So a pause never makes
  /// a cold start flash the Update screen.
  Future<void> _rememberBlocked() async {
    final blocked = _blocked;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (blocked && widget.installedBuild.isNotEmpty) {
        await prefs.setString(kBlockedBuildPrefKey, widget.installedBuild);
      } else {
        await prefs.remove(kBlockedBuildPrefKey);
      }
    } catch (_) {}
  }

  void _startUpdate() {
    if (_starting) return;
    _starting = true;
    Future<void> run() async {
      try {
        await widget.checker.startUpdate(_need);
      } catch (_) {}
    }

    unawaited(run().whenComplete(() => _starting = false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    final openStore = widget.checker.openStore;
    // The app stays mounted (always the first child, so blocking and
    // unblocking never rebuild it): a mid-session block keeps its Navigator,
    // open pages, half-typed forms and mainContext. While blocked it gets no
    // taps, no keyboard focus and no semantics, and the opaque Update screen
    // covers it.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: IgnorePointer(
            ignoring: blocked,
            child: ExcludeSemantics(
              excluding: blocked,
              child: widget.child,
            ),
          ),
        ),
        if (blocked)
          UpdateRequiredPage(
            onUpdate: _startUpdate,
            onOpenStore: openStore == null
                ? null
                : () => unawaited(openStore().catchError((Object _) {})),
          ),
      ],
    );
  }
}

/// The "Update required" screen. No back or close control. It sits above
/// the Navigator, so it has its own [Material] surface and uses nothing
/// that needs a Navigator or an Overlay.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({
    super.key,
    required this.onUpdate,
    this.onOpenStore,
  });

  final VoidCallback onUpdate;

  /// Android only: the `Open Google Play` button. Null hides it.
  final VoidCallback? onOpenStore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 64)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/infinite_mark.png',
                      height: 88,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A new version of Infinite Sports is ready. '
                    'Update to keep using the app.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: onUpdate,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text(
                      'Update',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (onOpenStore != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onOpenStore,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text(
                        'Open Google Play',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
