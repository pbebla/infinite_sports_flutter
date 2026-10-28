// The My Team court squad builder (P3b — the product's centerpiece). One
// layout for both states (spec §10 adopted decision): while editing is open
// it shows the budget bar, court, bench, chips, inline validation and Save;
// when the gameweek locks the SAME layout stays and only the header swaps to
// the compact live-strip placeholder while every edit affordance disables.
//
// Draft model: fixed slots from the live config (a GK slot only ever holds a
// GK), the engine's validateSquad running live on every change, human
// sentences inline, Save enabled only when the draft is valid AND changed.
// Self-echo safety: a successful save marks the draft clean; the write then
// echoes back on the squad stream and is adopted as-is (identical content —
// no double-apply, no flicker).
//
// House rules: streams only; colorScheme + the gold/primary fantasy accent
// pairing; scrollable clears the glass navbar; snackbars surface every
// armband side effect (nothing silent).

import 'dart:async';

import 'package:flutter/material.dart';
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
    this.nowUtc,
  });

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

  /// Test seam: injected clock (lock computation). null = real UTC now.
  final DateTime Function()? nowUtc;

  @override
  State<FantasySquadBuilder> createState() => _FantasySquadBuilderState();
}

class _FantasySquadBuilderState extends State<FantasySquadBuilder> {
  late List<SquadSlot> _slots;
  late List<SquadPick?> _picks;
  String? _captainId;
  String? _viceId;
  String? _chip;

  /// True once the user edits; the stream only overwrites a CLEAN draft, so
  /// in-progress edits survive remote emits and our own save echo (which
  /// arrives after save marks the draft clean again) applies a no-op.
  bool _dirty = false;
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
    _slots = buildSlots(widget.config);
    _adopt(widget.initialSquad);
    _subscribe();
    // 30s tick keeps the editable/locked flip honest around the deadline
    // (same cadence as the deadline chip); cancelled in dispose.
    _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(FantasySquadBuilder old) {
    super.didUpdateWidget(old);
    if (old.squadStates != widget.squadStates) {
      _subscribe();
    }
    // A formation change in the live config re-shapes the slots; the current
    // picks re-map into whatever still fits.
    if (old.config.squadSize != widget.config.squadSize ||
        old.config.startersDef != widget.config.startersDef ||
        old.config.startersAtt != widget.config.startersAtt ||
        old.config.startersGk != widget.config.startersGk ||
        old.config.benchDef != widget.config.benchDef ||
        old.config.benchAtt != widget.config.benchAtt) {
      final current = draftToSquad(
          slotPicks: _picks,
          captainId: _captainId,
          viceId: _viceId,
          chip: _chip);
      _slots = buildSlots(widget.config);
      _picks = picksToSlots(current, _slots);
    }
  }

  void _subscribe() {
    _squadSub?.cancel();
    _squadSub = widget.squadStates.listen((squad) {
      if (!mounted || _dirty) return;
      setState(() => _adopt(squad));
    });
  }

  void _adopt(FantasySquad? squad) {
    _picks = picksToSlots(squad, _slots);
    _captainId =
        (squad?.captainId.isNotEmpty ?? false) ? squad!.captainId : null;
    _viceId = (squad?.viceId.isNotEmpty ?? false) ? squad!.viceId : null;
    _chip = squad?.chip;
    _dirty = false;
  }

  @override
  void dispose() {
    _squadSub?.cancel();
    _lockTicker?.cancel();
    super.dispose();
  }

  // ── Edit actions ───────────────────────────────────────────────────────

  Set<String> get _squadIds =>
      {for (final p in _picks) if (p != null) p.playerId};

  int get _spent => draftSpentTenths(_picks);

  Future<void> _onSlotTap(int i) async {
    if (!_editable) return;
    final pick = _picks[i];
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
        widget.config.budgetTenths - _spent + remainingExtraTenths;
    final player = await showSquadPickerSheet(
      context,
      position: _slots[i].position,
      players: widget.players,
      excludeIds: _squadIds,
      remainingTenths: remaining,
    );
    if (player == null || !mounted) return;
    final outgoing = _picks[i];
    setState(() {
      _picks[i] = SquadPick(
        playerId: player.name,
        position: player.position,
        priceTenths: player.priceTenths,
        bench: _slots[i].bench,
      );
      _dirty = true;
      if (outgoing != null) _clearArmbandFor(outgoing.playerId);
    });
  }

  Future<void> _chipActions(int i, SquadPick pick) async {
    final action = await showSquadChipActions(
      context,
      playerName: pick.playerId,
      bench: _slots[i].bench,
      isCaptain: pick.playerId == _captainId,
      isVice: pick.playerId == _viceId,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case SquadChipAction.makeCaptain:
        setState(() {
          final bands = assignCaptain(
              id: pick.playerId, captainId: _captainId, viceId: _viceId);
          _captainId = bands.captainId;
          _viceId = bands.viceId;
          _dirty = true;
        });
      case SquadChipAction.makeVice:
        setState(() {
          final bands = assignVice(
              id: pick.playerId, captainId: _captainId, viceId: _viceId);
          _captainId = bands.captainId;
          _viceId = bands.viceId;
          _dirty = true;
        });
      case SquadChipAction.swap:
        await _pickInto(i, remainingExtraTenths: pick.priceTenths);
      case SquadChipAction.remove:
        setState(() {
          _picks[i] = null;
          _dirty = true;
          _clearArmbandFor(pick.playerId);
        });
    }
  }

  /// Clears a removed player's armband and SAYS SO — nothing happens
  /// silently (spec §2 kindness rule).
  void _clearArmbandFor(String playerId) {
    final message = armbandLossMessage(
        removedId: playerId, captainId: _captainId, viceId: _viceId);
    if (playerId == _captainId) _captainId = null;
    if (playerId == _viceId) _viceId = null;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    final squad = draftToSquad(
        slotPicks: _picks, captainId: _captainId, viceId: _viceId, chip: _chip);
    setState(() => _saving = true);
    try {
      await widget.onSaveSquad(squad);
      if (!mounted) return;
      setState(() {
        // Clean: the stream echo of this very write adopts as a no-op.
        _dirty = false;
        _saving = false;
      });
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
    final issues = issueSentences(
      slots: _slots,
      slotPicks: _picks,
      captainId: _captainId,
      viceId: _viceId,
      chip: _chip,
      cfg: widget.config,
    );
    final valid = issues.isEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        key: const ValueKey('my_team_ready'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Same layout both states: only this header swaps (spec §10).
          if (editable)
            _BudgetBar(spent: _spent, budget: widget.config.budgetTenths)
          else
            const _LockedLiveStrip(),
          const SizedBox(height: 12),
          FantasyCourtView(
            config: widget.config,
            slots: _slots,
            slotPicks: _picks,
            captainId: _captainId,
            viceId: _viceId,
            onSlotTap: editable ? _onSlotTap : null,
          ),
          const SizedBox(height: 14),
          FantasyChipRow(
            config: widget.config,
            activeChip: _chip,
            enabled: editable,
            onChipChanged: (chip) => setState(() {
              _chip = chip;
              _dirty = true;
            }),
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
                  valid && _dirty && !_saving ? _save : null,
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
/// the error color when over.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.spent, required this.budget});

  final int spent;
  final int budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
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
                  color: over ? scheme.error : accent,
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
                color: over ? scheme.error : accent,
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
                      ? scheme.error
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
                          ? scheme.error
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
