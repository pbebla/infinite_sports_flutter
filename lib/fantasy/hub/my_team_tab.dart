// The hub's My Team tab (P3a feedback, spec §10b; P3b). Three stream-driven
// faces: no Managers entry → name-your-team prompt; NameFlagged → the
// moderation gate (rename is the ONLY action, and renaming unlocks
// immediately because the same stream feeds this widget); named + clean →
// the court squad builder (P3b). The gate wraps WHATEVER the ready face is —
// a flagged manager never reaches the builder.
//
// Paid access (spec 2026-11-01 §5): in pass mode without an active
// `Access/<uid>` the season-pass pay card takes the name step's place
// (no manager yet) or sits above a READ-ONLY court (an existing manager —
// grandfathering declined, or revoked). Both are live: the moment the
// Access stream turns active the card is gone and the normal face shows.
// Free mode: nothing changes.
//
// House rules: theme-safe via colorScheme (gold accent in dark, primary red
// in light — the deadline chip's pairing), glass-navbar bottom clearance,
// stream-driven (no one-shot reads), names wrap.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/access_pay_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/team_name_dialog.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

class FantasyMyTeamTab extends StatelessWidget {
  const FantasyMyTeamTab({
    super.key,
    required this.managerStates,
    this.initialManager,
    required this.onSaveName,
    required this.configState,
    required this.players,
    required this.gameweeks,
    this.scheduleUnknown = false,
    this.onRetrySchedule,
    required this.squadStates,
    this.initialSquad,
    required this.onSaveSquad,
    this.draft,
    this.nowUtc,
    this.alertStates,
    this.initialAlert,
    this.chipHistory,
    this.voidedWeeks = const {},
    this.onOpenPlayer,
    this.sport = '',
    this.season = '',
    this.accessConfig = FantasyAccessConfig.free,
    this.accessStates,
    this.initialAccess,
    this.accessActions,
    this.displayName = '',
    this.lockedWeek,
  });

  /// The locked week's live / settled view (the hub's locked-week feed,
  /// resolved): the builder's strip and chip lines while the court is locked.
  /// null = nothing known yet.
  final LockedWeekModel? lockedWeek;

  /// Paid access (spec 2026-11-01): the live `Config/Access` block, the
  /// hub's re-listen-safe broadcast of FantasyService.watchMyAccess + its
  /// latest value, the pay card's side effects and the claim note's name.
  /// Defaults = free mode (standalone / tests): no gate at all.
  final String sport;
  final String season;
  final FantasyAccessConfig accessConfig;
  final Stream<FantasyAccessState>? accessStates;
  final FantasyAccessState? initialAccess;
  final FantasyAccessActions? accessActions;
  final String displayName;

  /// The hub's one profile opener (squad builder: the chip sheet's "Player
  /// profile", and a locked chip's direct tap). null = no profile taps.
  final void Function(String playerName)? onOpenPlayer;

  /// The manager's finalized chips by gameweek (the hub's
  /// FantasyService.watchChipHistoryFor feed) — the chip row's real counts.
  /// null = unknown (the read failed): Wildcard / Free Hit can't be armed.
  final Map<int, ChipHistoryEntry>? chipHistory;

  /// The season's owner-voided gameweeks (the hub's
  /// FantasyService.watchVoidedWeeks feed) — their chips are refunded.
  final Set<int> voidedWeeks;

  /// Re-listen-safe broadcast of FantasyService.watchMySquadAlert (spec §3
  /// holder protection) + its latest value: drives the "your team needs
  /// rearranging" banner at the top of the builder. null = no alerts feed.
  final Stream<FantasySquadAlert?>? alertStates;
  final FantasySquadAlert? initialAlert;

  /// The hub's re-listen-safe broadcast of FantasyService.watchMyManager —
  /// a TabBarView remounts far tabs, so this must tolerate re-listening.
  final Stream<FantasyManager?> managerStates;
  final FantasyManager? initialManager;

  /// Performs the name write (FantasyService.saveTeamName in production).
  final Future<void> Function(String name) onSaveName;

  /// Current config (the hub rebuilds this tab when it changes).
  final FantasyConfigState configState;
  final List<FantasyPlayer> players;
  final List<Gameweek> gameweeks;

  /// The schedule read failed (FantasyScheduleFeed.scheduleUnknown, review 6
  /// I2): never "Locked" / "Season complete" from that empty list.
  final bool scheduleUnknown;

  /// Non-null once the schedule feed has given up: "Try again".
  final VoidCallback? onRetrySchedule;

  /// Re-listen-safe squad stream (hub broadcast of watchMySquad) + its
  /// latest value, so a tab remount paints without waiting for an emit.
  final Stream<FantasySquad?> squadStates;
  final FantasySquad? initialSquad;

  /// FantasyService.saveMySquad in production.
  final Future<void> Function(FantasySquad squad) onSaveSquad;

  /// The hub's shared draft (P3c) — the Players market edits the same one.
  /// null (standalone/tests): the builder owns a private draft.
  final SquadDraftController? draft;

  /// Test seam: injected clock for the builder's lock computation.
  final DateTime Function()? nowUtc;

  void _openNameDialog(BuildContext context, {String initialName = ''}) {
    showTeamNameDialog(context, initialName: initialName, onSave: onSaveName);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FantasyManager?>(
      initialData: initialManager,
      stream: managerStates,
      builder: (context, snapshot) {
        final manager = snapshot.data;
        final accessFeed = accessStates;
        if (accessFeed == null) {
          return _face(
              context, manager, initialAccess ?? FantasyAccessState.none);
        }
        return StreamBuilder<FantasyAccessState>(
          initialData: initialAccess ?? FantasyAccessState.none,
          stream: accessFeed,
          builder: (context, accessSnap) => _face(
              context, manager, accessSnap.data ?? FantasyAccessState.none),
        );
      },
    );
  }

  /// The pay card for a gated fan (inert actions standalone / in tests
  /// that never tap it).
  Widget _payCard(FantasyAccessState access) => AccessPayCard(
        sport: sport,
        season: season,
        config: accessConfig,
        access: access,
        displayName: displayName,
        actions: accessActions ?? _inertAccessActions,
      );

  Widget _face(
      BuildContext context, FantasyManager? manager, FantasyAccessState access) {
    // Named and clean: the P3b court squad builder (it carries the
    // 'my_team_ready' key on its root), with the live squad alert.
    Widget builder(FantasySquadAlert? alert,
            {bool readOnly = false, Widget? header}) =>
        FantasySquadBuilder(
          config: configState.config,
          lockOverride: configState.lockOverride,
          gameweeks: gameweeks,
          scheduleUnknown: scheduleUnknown,
          onRetrySchedule: onRetrySchedule,
          players: players,
          squadStates: squadStates,
          initialSquad: initialSquad,
          onSaveSquad: onSaveSquad,
          draft: draft,
          nowUtc: nowUtc,
          alert: alert,
          chipHistory: chipHistory,
          voidedWeeks: voidedWeeks,
          onOpenPlayer: onOpenPlayer,
          readOnly: readOnly,
          header: header,
          lockedWeek: lockedWeek,
        );
    Widget withAlerts(Widget Function(FantasySquadAlert? alert) build) {
      final alerts = alertStates;
      if (alerts == null) return build(initialAlert);
      return StreamBuilder<FantasySquadAlert?>(
        initialData: initialAlert,
        stream: alerts,
        builder: (context, alertSnap) => build(alertSnap.data),
      );
    }

    // Pass mode without an active pass: the pay card, alone (no manager
    // yet) or above the read-only court (an existing manager — the flag
    // gate, if any, waits until they're in).
    if (accessConfig.isPass && !access.isActive) {
      final card = _payCard(access);
      if (manager == null) {
        return SingleChildScrollView(
          key: const ValueKey('my_team_pay_gate'),
          padding: EdgeInsets.fromLTRB(
              12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
          child: card,
        );
      }
      return withAlerts(
          (alert) => builder(alert, readOnly: true, header: card));
    }

    if (manager == null) {
      return _MessageCard(
        key: const ValueKey('my_team_name_prompt'),
        icon: Icons.badge_outlined,
        title: 'Name your team',
        message: 'Every manager plays under a team name — it shows on '
            'leaderboards next to your score. Pick yours to get started.',
        buttonLabel: 'Choose a name',
        onPressed: () => _openNameDialog(context),
      );
    }
    if (manager.nameFlagged) {
      return _MessageCard(
        key: const ValueKey('my_team_flag_gate'),
        icon: Icons.flag_outlined,
        title: 'Team name flagged',
        message: 'Your team name was flagged by the league. Choose a '
            'new name to continue.',
        buttonLabel: 'Choose a new name',
        onPressed: () =>
            _openNameDialog(context, initialName: manager.teamName),
      );
    }
    return withAlerts(builder);
  }
}

Future<Uri?> _noCheckout() async => null;
Future<bool> _noLaunch(Uri _) async => false;
Future<void> _noClaim(FantasyAccessMethod _, double __, String ___) async {}

/// Standalone (no hub) the card can't pay — the hub always injects the
/// real actions.
const FantasyAccessActions _inertAccessActions = FantasyAccessActions(
  createCheckoutUrl: _noCheckout,
  launch: _noLaunch,
  submitClaim: _noClaim,
);

/// Shared face for the name prompt and the moderation gate: centered icon,
/// title, copy and a single action.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? TournamentColors.gold : scheme.primary;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: isDark ? Colors.black : scheme.onPrimary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              textStyle:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

