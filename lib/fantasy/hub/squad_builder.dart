// The My Team court squad builder (P3b — the product's centerpiece). One
// layout for both states (spec §10 adopted decision): while editing is open
// it shows the budget bar, court, bench, chips, inline validation and Save;
// when the gameweek locks the SAME layout stays and only the header swaps to
// the compact live-strip placeholder while every edit affordance disables.
//
// Draft model (P3c: lifted into the shared SquadDraftController so the
// Players market edits the same draft): fixed slots from the live config (a
// GK slot only ever holds a GK), the engine's validateSquad running live on
// every change, human sentences inline, Save enabled only when the draft is
// valid AND changed. Self-echo safety: a successful save marks the draft
// clean; the write then echoes back on the squad stream and is adopted as-is
// (identical content — no double-apply, no flicker). When the hub passes a
// shared [draft] it also feeds the squad stream into it; standalone (tests),
// the builder owns a private controller and subscribes itself.
//
// House rules: streams only; colorScheme + the gold/primary fantasy accent
// pairing; scrollable clears the glass navbar; snackbars surface every
// armband side effect (nothing silent).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/chip_row.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_picker_sheet.dart';

class FantasySquadBuilder extends StatefulWidget {
  const FantasySquadBuilder({
    super.key,
    required this.config,
    required this.lockOverride,
    required this.gameweeks,
    required this.players,
    required this.squadStates,
    this.initialSquad,
    required this.onSaveSquad,
    this.draft,
    this.nowUtc,
    this.alert,
    this.chipHistory,
    this.voidedWeeks = const {},
    this.onOpenPlayer,
  });

  /// Opens a player's fantasy profile (the hub's one opener, bound to its
  /// sport/season/shared draft): the chip action sheet's first item, and —
  /// when the court is locked — a filled chip's direct tap. null (standalone
  /// builder/tests) = no profile affordance.
  final void Function(String playerName)? onOpenPlayer;

  /// The manager's finalized chips by gameweek (`History/<gw>/<uid>`, via
  /// FantasyService.watchChipHistoryFor) — drives the chip row's real
  /// "1 left" / "Used" / "Active" badges (chip_usage.dart). null = unknown
  /// (signed out / not loaded): nothing counts as spent.
  final Map<int, ChipHistoryEntry>? chipHistory;

  /// The season's owner-voided gameweeks (`Voided/<gw>`, via
  /// FantasyService.watchVoidedWeeks — the node the server's refund reads):
  /// a chip played in one is refunded, even before the re-finalize mirrors
  /// `Voided` into History. The hub's reveal gate waits for it.
  final Set<int> voidedWeeks;

  /// The manager's live squad alert (spec §3 holder protection,
  /// FantasyService.watchMySquadAlert): shown as a banner at the top while
  /// it exists. null = no banner.
  final FantasySquadAlert? alert;

  final FantasyConfig config;
  final FantasyLockOverride lockOverride;
  final List<Gameweek> gameweeks;

  /// The live market (guests arrive eligible=false and are filtered by the
  /// picker).
  final List<FantasyPlayer> players;

  /// Re-listen-safe squad stream (the hub broadcasts
  /// FantasyService.watchMySquad) — null until the first save.
  final Stream<FantasySquad?> squadStates;
  final FantasySquad? initialSquad;

  /// FantasyService.saveMySquad in production.
  final Future<void> Function(FantasySquad squad) onSaveSquad;

  /// The shared draft (P3c): the hub passes its sport/season-scoped
  /// controller so the Players tab edits the same draft and an unsaved draft
  /// survives tab swipes. null (standalone/tests) = the builder owns a
  /// private one and subscribes to [squadStates] itself.
  final SquadDraftController? draft;

  /// Test seam: injected clock (lock computation). null = real UTC now.
  final DateTime Function()? nowUtc;

  @override
  State<FantasySquadBuilder> createState() => _FantasySquadBuilderState();
}

class _FantasySquadBuilderState extends State<FantasySquadBuilder> {
  late SquadDraftController _draft;
  bool _ownsDraft = false;
  bool _saving = false;

  StreamSubscription<FantasySquad?>? _squadSub;
  Timer? _lockTicker;

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  bool get _editable => squadEditable(
        lockOverride: widget.lockOverride,
        gameweeks: widget.gameweeks,
        nowUtc: _now,
      );

  @override
  void initState() {
    super.initState();
    _attachDraft();
    // 30s tick keeps the editable/locked flip honest around the deadline
    // (same cadence as the deadline chip); cancelled in dispose.
    _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Shared draft: use the hub's controller as-is (the hub feeds it the
  /// squad stream and config). Own draft: create, adopt the initial squad
  /// and subscribe to the stream ourselves.
  void _attachDraft() {
    final shared = widget.draft;
    _ownsDraft = shared == null;
    _draft = shared ??
        SquadDraftController(
            config: widget.config, initial: widget.initialSquad);
    _draft.addListener(_onDraftChanged);
    _squadSub?.cancel();
    if (_ownsDraft) {
      _squadSub = widget.squadStates.listen((squad) {
        if (mounted) _draft.adoptFromStream(squad);
      });
    }
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(FantasySquadBuilder old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      _draft.removeListener(_onDraftChanged);
      if (_ownsDraft) _draft.dispose();
      _attachDraft();
    } else if (_ownsDraft && old.squadStates != widget.squadStates) {
      _squadSub?.cancel();
      _squadSub = widget.squadStates.listen((squad) {
        if (mounted) _draft.adoptFromStream(squad);
      });
    }
    // A formation change in the live config re-shapes the slots; the
    // controller re-maps the current picks into whatever still fits. (The
    // hub syncs its shared controller too — syncConfig is idempotent.)
    _draft.syncConfig(widget.config);
  }

  @override
  void dispose() {
    _squadSub?.cancel();
    _lockTicker?.cancel();
    _draft.removeListener(_onDraftChanged);
    if (_ownsDraft) _draft.dispose();
    super.dispose();
  }

  // ── Edit actions ───────────────────────────────────────────────────────

  Future<void> _onSlotTap(int i) async {
    final pick = _draft.picks[i];
    if (!_editable) {
      // The deadline passed since the last rebuild (the 30s ticker hasn't
      // re-locked the court yet): editing is closed, but viewing a profile
      // never is.
      if (pick != null) widget.onOpenPlayer?.call(pick.playerId);
      return;
    }
    if (pick == null) {
      await _pickInto(i, remainingExtraTenths: 0);
    } else {
      await _chipActions(i, pick);
    }
  }

  /// Opens the picker for slot [i]; [remainingExtraTenths] is the outgoing
  /// player's price on a swap (their money comes back for this pick).
  Future<void> _pickInto(int i, {required int remainingExtraTenths}) async {
    final remaining =
        widget.config.budgetTenths - _draft.spentTenths + remainingExtraTenths;
    final player = await showSquadPickerSheet(
      context,
      position: _draft.slots[i].position,
      players: widget.players,
      excludeIds: _draft.playerIds,
      remainingTenths: remaining,
    );
    if (player == null || !mounted) return;
    final message = _draft.setPickAt(
        i,
        SquadPick(
          playerId: player.name,
          position: player.position,
          priceTenths: player.priceTenths,
          bench: _draft.slots[i].bench,
        ));
    _announceArmbandLoss(message);
  }

  Future<void> _chipActions(int i, SquadPick pick) async {
    final action = await showSquadChipActions(
      context,
      playerName: pick.playerId,
      bench: _draft.slots[i].bench,
      isCaptain: pick.playerId == _draft.captainId,
      isVice: pick.playerId == _draft.viceId,
      showProfile: widget.onOpenPlayer != null,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case SquadChipAction.profile:
        widget.onOpenPlayer?.call(pick.playerId);
      case SquadChipAction.makeCaptain:
        _draft.makeCaptain(pick.playerId);
      case SquadChipAction.makeVice:
        _draft.makeVice(pick.playerId);
      case SquadChipAction.swap:
        await _pickInto(i, remainingExtraTenths: pick.priceTenths);
      case SquadChipAction.remove:
        _announceArmbandLoss(_draft.removeAt(i));
    }
  }

  /// "Swap" on the Needs-a-new-spot strip: pick a replacement for the hole
  /// the moved player left (the first empty slot), his money back.
  Future<void> _swapUnplaced(SquadPick pick) async {
    if (!_editable) return;
    final slot = _draft.firstEmptySlot;
    if (slot == null) {
      // Unreachable for a position change (the move always leaves a hole);
      // removing is the honest fallback.
      _announceArmbandLoss(_draft.removeUnplaced(pick.playerId));
      return;
    }
    final remaining = widget.config.budgetTenths -
        _draft.spentTenths +
        pick.priceTenths;
    final player = await showSquadPickerSheet(
      context,
      position: _draft.slots[slot].position,
      players: widget.players,
      excludeIds: _draft.playerIds,
      remainingTenths: remaining,
    );
    if (player == null || !mounted) return;
    _announceArmbandLoss(_draft.swapUnplaced(
        pick.playerId,
        slot,
        SquadPick(
          playerId: player.name,
          position: player.position,
          priceTenths: player.priceTenths,
          bench: _draft.slots[slot].bench,
        )));
  }

  /// The alert banner sentence: the deadline the manager is editing for
  /// (the current gameweek; the alert's own when none is current), and the
  /// free-swap promise only while it still holds (the alert's gameweek).
  String _alertText(FantasySquadAlert alert) {
    final current = currentGameweek(widget.gameweeks, _now);
    Gameweek? target = current;
    if (target == null) {
      for (final g in widget.gameweeks) {
        if (g.number == alert.gameweek) target = g;
      }
    }
    return squadAlertText(
      changes: [
        for (final c in alert.changes) (player: c.player, to: c.to),
      ],
      deadline: target == null ? 'the deadline' : formatAbsoluteLock(target),
      freeThisWeek: current == null || current.number == alert.gameweek,
    );
  }

  /// A removed/swapped-out captain or vice is SAID out loud — nothing
  /// happens silently (spec §2 kindness rule).
  void _announceArmbandLoss(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final squad = _draft.squad;
    setState(() => _saving = true);
    try {
      await widget.onSaveSquad(squad);
      if (!mounted) return;
      setState(() => _saving = false);
      // Clean: the stream echo of this very write adopts as a no-op.
      _draft.markSaved();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Squad saved — good luck!')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text("Couldn't save — try again.")));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final editable = _editable;
    final photoByName = {
      for (final p in widget.players)
        if (p.photoUrl != null) p.name: p.photoUrl,
    };
    final issues = issueSentences(
      slots: _draft.slots,
      slotPicks: _draft.picks,
      captainId: _draft.captainId,
      viceId: _draft.viceId,
      chip: _draft.chip,
      cfg: widget.config,
      unplaced: _draft.unplaced,
    );
    final valid = issues.isEmpty;
    final alert = widget.alert;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        key: const ValueKey('my_team_ready'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Holder protection (spec §3): a position change broke this
          // squad's formation — say so first, until the server clears it.
          if (alert != null) ...[
            _SquadAlertBanner(text: _alertText(alert)),
            const SizedBox(height: 12),
          ],
          // Same layout both states: only this header swaps (spec §10).
          if (editable)
            _BudgetBar(
                spent: _draft.spentTenths, budget: widget.config.budgetTenths)
          else
            const _LockedLiveStrip(),
          const SizedBox(height: 12),
          FantasyCourtView(
            config: widget.config,
            slots: _draft.slots,
            slotPicks: _draft.picks,
            captainId: _draft.captainId,
            viceId: _draft.viceId,
            onSlotTap: editable ? _onSlotTap : null,
            // Locked: viewing a profile is still allowed (filled chips only;
            // empty slots stay inert).
            onPlayerTap: widget.onOpenPlayer,
            // Big photo chips (Task 3): the market's photoUrl per pick;
            // initials fall back instantly when a player has none.
            photoUrlFor: (id) => photoByName[id],
          ),
          if (_draft.unplaced.isNotEmpty) ...[
            const SizedBox(height: 12),
            _NeedsNewSpotStrip(
              picks: _draft.unplaced,
              enabled: editable,
              onSwap: _swapUnplaced,
              onRemove: (pick) =>
                  _announceArmbandLoss(_draft.removeUnplaced(pick.playerId)),
            ),
          ],
          const SizedBox(height: 14),
          FantasyChipRow(
            config: widget.config,
            activeChip: _draft.chip,
            enabled: editable,
            onChipChanged: _draft.setChip,
            // Real usage: spent-in-this-set from History, the armed chip on
            // the squad on screen (the live squad, or its unsaved edit).
            availability: chipAvailability(
              historyByWeek: widget.chipHistory ?? const {},
              editingGw: chipEditingGameweek(widget.gameweeks, _now),
              armedChip: _draft.chip,
              config: widget.config,
              voidedWeeks: widget.voidedWeeks,
            ),
          ),
          if (editable && issues.isNotEmpty) ...[
            const SizedBox(height: 14),
            _IssueList(issues: issues),
          ],
          if (editable) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('squad_save'),
              onPressed:
                  valid && _draft.dirty && !_saving ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: fantasyAccent(context),
                foregroundColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child: Text(_saving ? 'Saving…' : 'Save squad'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Spent vs budget with the remaining amount — fills as picks land, flips to
/// the error color when over. Restyled in the P3b feedback round (Task 5):
/// the fill is the pitch-green family (works both themes), the remaining
/// text reads in onSurface, and ONLY the over-budget state goes error-red.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.spent, required this.budget});

  final int spent;
  final int budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = fantasyPitchGreen(context);
    final over = spent > budget;
    final remaining = budget - spent;
    final fill = budget == 0 ? 1.0 : (spent / budget).clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      key: const ValueKey('budget_bar'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatMoneyTenths(spent)} spent',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                over
                    ? '${formatMoneyTenths(-remaining)} over'
                    : '${formatMoneyTenths(remaining)} left',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  // onSurface (white in dark, near-black in light) — the
                  // error color is reserved for the over-budget state.
                  color: over ? fantasyDownRed(context) : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fill),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                color: over ? fantasyDownRed(context) : green,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The locked state's compact header — live points wiring lands in P4/P6;
/// the placeholder keeps the one-layout promise meanwhile.
class _LockedLiveStrip extends StatelessWidget {
  const _LockedLiveStrip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    return Container(
      key: const ValueKey('locked_live_strip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gameweek locked — live points coming here',
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The holder-protection alert (spec §3): "Ann moved to DEF — your team
/// needs rearranging before Sun, Oct 19 · 3:00 PM. Swapping him out is
/// free this week." The error-container pair is a Material 3 scheme role, so it reads
/// correctly in both light and dark mode.
class _SquadAlertBanner extends StatelessWidget {
  const _SquadAlertBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('squad_alert_banner'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz_rounded,
              size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks that fit no slot any more (a position change moved them) — shown
/// instead of silently dropped, each with Swap (pick a replacement for the
/// hole) and Remove. Disabled while the gameweek is locked.
class _NeedsNewSpotStrip extends StatelessWidget {
  const _NeedsNewSpotStrip({
    required this.picks,
    required this.enabled,
    required this.onSwap,
    required this.onRemove,
  });

  final List<SquadPick> picks;
  final bool enabled;
  final void Function(SquadPick pick) onSwap;
  final void Function(SquadPick pick) onRemove;

  static String _nowA(FantasyPosition p) => switch (p) {
        FantasyPosition.gk => 'Now a goalkeeper',
        FantasyPosition.def => 'Now a defender',
        FantasyPosition.att => 'Now an attacker',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    return Container(
      key: const ValueKey('unplaced_strip'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Needs a new spot',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          for (final pick in picks)
            Padding(
              key: ValueKey('unplaced_${pick.playerId}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pick.playerId,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          '${_nowA(pick.position)} · '
                          '${formatMoneyTenths(pick.priceTenths)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey('unplaced_swap_${pick.playerId}'),
                    onPressed: enabled ? () => onSwap(pick) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.7)),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Swap'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    key: ValueKey('unplaced_remove_${pick.playerId}'),
                    onPressed: enabled ? () => onRemove(pick) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline validation sentences — plain guidance while building, the
/// over-budget line in the error color.
class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: issue.contains('over budget')
                      ? fantasyDownRed(context)
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    issue,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: issue.contains('over budget')
                          ? fantasyDownRed(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
