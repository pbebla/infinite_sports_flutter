// The My Team court squad builder (P3b — the product's centerpiece). One
// layout for both states (spec §10 adopted decision): while editing is open
// it shows the budget bar, court, bench, chips, inline validation and Save;
// when the gameweek locks the SAME layout stays and only the header swaps to
// the compact locked-week strip (live points with the LIVE pill, Final, Voided,
// or "waiting for kickoff" — live_logic.dart) while every edit affordance
// disables and each court chip shows that player's counted points.
//
// Draft model (P3c: lifted into the shared SquadDraftController so the
// Players market edits the same draft): fixed slots from the live config (a
// GK slot only ever holds a GK), the engine's validateSquad running live on
// every change, human sentences inline, Save enabled only when the draft is
// valid AND changed AND its money is real (FPL selling, spec §4: every
// money figure — the bar, the picker, the chips, the over-budget sentence —
// is the shared draft's; see squad_draft.dart). Self-echo safety: a
// successful save marks the draft clean; the write then echoes back on the
// squad stream and is adopted as-is (identical content — no double-apply,
// no flicker). When the hub passes a
// shared [draft] it also feeds the squad stream into it; standalone (tests),
// the builder owns a private controller and subscribes itself.
//
// Transfers (plan 2026-11-03, spec §5–§6): while editable, one line under the
// budget bar says how many transfers the draft uses against the squad the
// manager came into the week with (the draft's transferPreview — "Your first
// team is free", "2 of 2 free transfers used", "3 transfers · 2 free · −4
// pts this week", the chip in play, or "Transfer count updating…"; no line
// for an older node). A save that RAISES the week's points cost above what
// the saved squad already costs asks "Take a points hit?" first; with the
// count unknown (notReady / hidden) Save is never blocked or questioned — the
// lock's own recount is the truth. Wildcard and Free Hit play from the chip
// row like the other two chips — except that arming them waits while the team
// is a first team, while the transfer count is not known, and while the chip
// history is not known (the chip would be spent for nothing, or voided).
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
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/chip_row.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart'
    show kDeadlineUnavailable;
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart'
    show movementDirection;
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart'
    show movementColor;
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_picker_sheet.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_dialogs.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_preview.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_logic.dart'
    show captainMultiplierFor;

class FantasySquadBuilder extends StatefulWidget {
  const FantasySquadBuilder({
    super.key,
    required this.config,
    required this.lockOverride,
    required this.gameweeks,
    this.scheduleUnknown = false,
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
    this.readOnly = false,
    this.header,
    this.lockedWeek,
  });

  /// The locked week's live / settled view (live everywhere, Task 5): the
  /// strip's content, the court's squad (the one that was LOCKED) and each chip's
  /// week line, resolved by the hub from its locked-week feed
  /// (live_logic.resolveLockedWeek). Only used while the court is locked, and
  /// the last one is kept until this builder is itself editable. null = nothing
  /// known — the strip reads just "Locked" and the court is the draft's with
  /// no points lines (a standalone builder, a week with no data).
  final LockedWeekModel? lockedWeek;

  /// Paid access (spec 2026-11-01 §5): an existing manager without an
  /// active season pass sees their court but cannot edit it — no budget
  /// bar / locked strip (the [header] explains), picker and chips inert,
  /// Save hidden. The rules refuse their saves anyway; this keeps the UI
  /// honest. Viewing a player's profile from a filled chip still works.
  final bool readOnly;

  /// Rendered first, above the court (the pay card in read-only mode).
  final Widget? header;

  /// Opens a player's fantasy profile (the hub's one opener, bound to its
  /// sport/season/shared draft): the chip action sheet's first item, and —
  /// when the court is locked — a filled chip's direct tap. null (standalone
  /// builder/tests) = no profile affordance.
  final void Function(String playerName)? onOpenPlayer;

  /// The manager's finalized chips by gameweek (`History/<gw>/<uid>`, via
  /// FantasyService.watchChipHistoryFor) — drives the chip row's real
  /// "1 left" / "Used" / "Active" badges (chip_usage.dart). An empty map =
  /// loaded, nothing spent. null = UNKNOWN (the read failed): the badges
  /// still read "1 left", but Wildcard and Free Hit can't be armed (a spent
  /// one would be voided at the lock and every transfer charged).
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

  /// The schedule read failed (FantasyScheduleFeed.scheduleUnknown, review 6
  /// I2): never "Locked" / "Season complete" from that empty list.
  final bool scheduleUnknown;

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

  /// The last locked-week model the hub handed down. The hub drops its model
  /// the instant editing reopens (lock + 24 h) while this builder flips on its
  /// own 30 s ticker; until the SCHEDULE reopens editing here it keeps showing
  /// the last model — never a placeholder flash in between. Cleared once the
  /// schedule is open — for a read-only manager too, whose court can never be
  /// edited but must not keep last week's locked squad and lines.
  LockedWeekModel? _lastLocked;

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  /// The schedule's verdict alone (the owner's lock override, the deadline):
  /// whether the WEEK is open for editing — what decides the locked view.
  bool get _scheduleEditable => _editState == SquadEditState.open;

  /// open / locked / unknown — unknown = the schedule read failed (review 6,
  /// I2): the court is not editable, and the strip says the deadline can't
  /// be checked instead of "Locked".
  SquadEditState get _editState => squadEditState(
        lockOverride: widget.lockOverride,
        gameweeks: widget.gameweeks,
        nowUtc: _now,
        scheduleUnknown: widget.scheduleUnknown,
      );

  /// Whether THIS manager can edit right now (the schedule, and a pass).
  bool get _editable => !widget.readOnly && _scheduleEditable;

  @override
  void initState() {
    super.initState();
    _lastLocked = widget.lockedWeek;
    _attachDraft();
    // 30s tick keeps the editable/locked flip honest around the deadline
    // (same cadence as the deadline chip); cancelled in dispose.
    _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Shared draft: use the hub's controller as-is (the hub feeds it the
  /// squad stream, config and money context). Own draft: create, adopt the
  /// initial squad, feed its money context and subscribe to the stream
  /// ourselves.
  void _attachDraft() {
    final shared = widget.draft;
    _ownsDraft = shared == null;
    _draft = shared ??
        SquadDraftController(
            config: widget.config, initial: widget.initialSquad);
    _feedOwnSaleContext();
    _draft.addListener(_onDraftChanged);
    _squadSub?.cancel();
    if (_ownsDraft) {
      _squadSub = widget.squadStates.listen((squad) {
        if (mounted) _draft.adoptFromStream(squad);
      });
    }
  }

  /// FPL selling (spec §4) for the STANDALONE builder only (tests — in the
  /// app the hub always shares its draft, which it feeds the real
  /// `Baselines/<uid>`, market and price history): with no baseline feed
  /// it prices as a first squad (nothing held, nothing sold) at the
  /// widget's market, so its Save isn't held for a feed that doesn't exist.
  void _feedOwnSaleContext() {
    if (!_ownsDraft) return;
    _draft.setSaleContext(
      sale: const SaleBaselineState(loaded: true),
      currentPrices: {for (final p in widget.players) p.name: p.priceTenths},
    );
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(FantasySquadBuilder old) {
    super.didUpdateWidget(old);
    if (widget.lockedWeek != null) _lastLocked = widget.lockedWeek;
    if (old.draft != widget.draft) {
      _draft.removeListener(_onDraftChanged);
      if (_ownsDraft) _draft.dispose();
      _attachDraft();
    } else {
      if (_ownsDraft && old.squadStates != widget.squadStates) {
        _squadSub?.cancel();
        _squadSub = widget.squadStates.listen((squad) {
          if (mounted) _draft.adoptFromStream(squad);
        });
      }
      // A no-op unless the market changed (setSaleContext compares).
      if (old.players != widget.players) _feedOwnSaleContext();
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
      await _pickInto(i);
    } else {
      await _chipActions(i, pick);
    }
  }

  /// Opens the picker for slot [i]. On a swap, [outgoing] (the slot's
  /// current player) leaves first: the room offered is the draft's room
  /// after his removal — his charged price back and, a baseline player,
  /// his sale booked (FPL selling, spec §4).
  Future<void> _pickInto(int i, {SquadPick? outgoing}) async {
    final remaining = outgoing == null
        ? _draft.remainingTenths
        : _draft.remainingIfRemovedTenths(outgoing);
    final player = await showSquadPickerSheet(
      context,
      position: _draft.slots[i].position,
      players: widget.players,
      excludeIds: _draft.playerIds,
      remainingTenths: remaining,
      priceOf: _draft.addCostOf,
      moneyReady: _draft.moneyReady,
    );
    if (player == null || !mounted) return;
    final message = _draft.setPickAt(
        i, _draft.newPick(player, bench: _draft.slots[i].bench));
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
        await _pickInto(i, outgoing: pick);
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
    final player = await showSquadPickerSheet(
      context,
      position: _draft.slots[slot].position,
      players: widget.players,
      excludeIds: _draft.playerIds,
      // The moved player leaves: his money back, his sale booked.
      remainingTenths: _draft.remainingIfRemovedTenths(pick),
      priceOf: _draft.addCostOf,
      moneyReady: _draft.moneyReady,
    );
    if (player == null || !mounted) return;
    _announceArmbandLoss(_draft.swapUnplaced(pick.playerId, slot,
        _draft.newPick(player, bench: _draft.slots[slot].bench)));
  }

  /// The alert banner sentence: the deadline the manager is editing for
  /// (the current gameweek; the alert's own when none is current), and the
  /// free-swap promise only while it still holds (the alert's gameweek).
  String _alertText(FantasySquadAlert alert) {
    if (alert.isInvalid) {
      return squadInvalidAlertText(
          gameweek: alert.gameweek, issues: alert.issues);
    }
    if (alert.isOverBudgetPreview) {
      return squadOverBudgetPreviewText(overTenths: alert.overTenths);
    }
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
      // A failed schedule read promises nothing that depends on the
      // schedule (re-review 6b, item 3): no free swap, and "the deadline".
      freeThisWeek: !widget.scheduleUnknown &&
          (current == null || current.number == alert.gameweek),
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

  /// "Take a points hit?" — only for a save that RAISES the week's points
  /// cost above what the saved squad already costs (a hit already taken, a
  /// cost that stays or drops, and any week with no cost all go straight
  /// through). Never when the count isn't known: notReady / hidden / a first
  /// team claim nothing, so Save is never blocked by the line (D1d).
  Future<bool> _confirmPointsHit() async {
    final next = _draft.transferPreview;
    if (next.kind != TransferPreviewKind.counted) return true;
    if (next.costPoints <= _draft.storedTransferPreview.costPoints) return true;
    final yes = await showPointsHitDialog(context, next);
    return yes && mounted;
  }

  Future<void> _save() async {
    final squad = _draft.squad;
    if (!await _confirmPointsHit()) return;
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (isSaveRefusedByRules(error)) {
        // The rules refuse a save from the lock instant on by the SERVER's
        // clock (audit I3): this week is locked. Say so kindly, drop the
        // edits and show the team as stored.
        _draft.revertToStored();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              key: ValueKey('squad_save_locked'),
              content: Text(squadSaveLockedMessage)));
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text("Couldn't save — try again.")));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheduleOpen = _scheduleEditable;
    final editable = !widget.readOnly && scheduleOpen;
    // Locked: the week as the hub resolved it — kept until the schedule
    // reopens editing here (the hub drops it a moment before the 30 s ticker
    // flips us). Schedule-only, NOT [editable]: a read-only manager (no pass)
    // is never editable, yet once the week reopens his court is his saved
    // squad again, with no stale locked lines.
    if (scheduleOpen) _lastLocked = null;
    final locked = scheduleOpen ? null : (widget.lockedWeek ?? _lastLocked);
    // The court while locked is the squad that was LOCKED (live:
    // PublishedPicks, settled: History) — NOT Squads/<uid>, which the server
    // rewrites after finalize and which keeps a chip the lock voided. Until
    // it has loaded the court is the draft's and shows no points lines.
    final lockedSquad = locked?.squad;
    // The chip on screen: the locked squad's (null = none — a voided chip
    // included) once it has loaded, else the draft's.
    final shownChip = lockedSquad != null ? lockedSquad.chip : _draft.chip;
    final photoByName = {
      for (final p in widget.players)
        if (p.photoUrl != null) p.name: p.photoUrl,
    };
    // FPL selling (spec §4): the draft's money is shown as fact — the room,
    // the sales line, an over-budget verdict — only once it is real; until
    // then Save waits (error ≠ fact).
    final moneyReady = _draft.moneyReady;
    final issues = issueSentences(
      slots: _draft.slots,
      slotPicks: _draft.picks,
      captainId: _draft.captainId,
      viceId: _draft.viceId,
      chip: _draft.chip,
      cfg: widget.config,
      unplaced: _draft.unplaced,
      spentTenths: _draft.spentTenths,
      availableTenths: _draft.availableTenths,
      moneyReady: moneyReady,
    );
    final valid = issues.isEmpty;
    // Said whenever there are unsaved edits (valid or not — an unready
    // draft never gets an over-budget verdict, so this is its only money
    // sentence). A clean draft can't save anyway, so the baseline landing
    // just after the reveal never flashes it.
    final moneyPending = _draft.dirty && !moneyReady;
    final shownIssues = [
      ...issues,
      if (moneyPending) squadMoneyPendingMessage,
    ];
    final alert = widget.alert;
    final transfers = _draft.transferPreview;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        key: const ValueKey('my_team_ready'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Read-only (no season pass): the pay card sits above the court.
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 12),
          ],
          // Holder protection (spec §3): a position change broke this
          // squad's formation — or the lock judged it invalid (audit I2) —
          // say so first, until the server clears it.
          if (alert != null) ...[
            _SquadAlertBanner(
              text: _alertText(alert),
              icon: alert.isInvalid
                  ? Icons.error_outline_rounded
                  : alert.isOverBudgetPreview
                      ? Icons.account_balance_wallet_outlined
                      : Icons.swap_horiz_rounded,
              // FPL selling (spec §4): the preview is a money warning —
              // the bright fantasy "down" red in both themes.
              brightRed: alert.isOverBudgetPreview,
            ),
            const SizedBox(height: 12),
          ],
          // Same layout both states: only this header swaps (spec §10).
          // Read-only mode has neither — the header above says why.
          if (!widget.readOnly) ...[
            if (editable) ...[
              _BudgetBar(
                spent: _draft.spentTenths,
                available: _draft.availableTenths,
                realized: _draft.realizedTenths,
                moneyReady: moneyReady,
              ),
              // Plan 2026-11-03: what this team's transfers cost (nothing at
              // all for an older node with no baseline).
              if (transferLineText(transfers) != null) ...[
                const SizedBox(height: 8),
                _TransfersLine(preview: transfers),
              ],
            ] else if (_editState == SquadEditState.unknown)
              const _DeadlineUnknownStrip()
            else
              // Nothing known about the week (no model yet): just "Locked" —
              // never a claim about kickoff.
              _LockedWeekStrip(
                  view: locked?.view ?? const LockedWeekView.unknown()),
            const SizedBox(height: 12),
          ],
          FantasyCourtView(
            config: widget.config,
            slots: _draft.slots,
            slotPicks: lockedSquad == null
                ? _draft.picks
                : picksToSlots(lockedSquad, _draft.slots),
            captainId: lockedSquad?.captainId ?? _draft.captainId,
            viceId: lockedSquad?.viceId ?? _draft.viceId,
            // The REAL armband multiplier: ×3 while Triple Captain is the
            // squad's chip, else the config's ×2 — the squad on screen's.
            captainMultiplier:
                captainMultiplierFor(lockedSquad ?? _draft.squad, widget.config),
            // Locked: each chip carries that player's counted points (live or
            // settled) — nothing while editing is open, and only for a squad
            // the lines belong to (the resolver's chipTexts).
            weekPointsFor: locked?.chipTextFor,
            onSlotTap: editable ? _onSlotTap : null,
            // Locked: viewing a profile is still allowed (filled chips only;
            // empty slots stay inert).
            onPlayerTap: widget.onOpenPlayer,
            // Big photo chips (Task 3): the market's photoUrl per pick;
            // initials fall back instantly when a player has none.
            photoUrlFor: (id) => photoByName[id],
            // The charged price (a held player at his baseline price) —
            // the nameplates add up to the bar. The locked squad shows what
            // it was locked at.
            priceOf: lockedSquad == null ? _draft.priceOfPick : null,
          ),
          if (_draft.unplaced.isNotEmpty && lockedSquad == null) ...[
            const SizedBox(height: 12),
            _NeedsNewSpotStrip(
              picks: _draft.unplaced,
              priceOf: _draft.priceOfPick,
              enabled: editable,
              onSwap: _swapUnplaced,
              onRemove: (pick) =>
                  _announceArmbandLoss(_draft.removeUnplaced(pick.playerId)),
            ),
          ],
          const SizedBox(height: 14),
          FantasyChipRow(
            config: widget.config,
            // While locked the row shows the chip the week was LOCKED with
            // (inert, like the court): never Squads/<uid>'s, which keeps a
            // chip the lock voided and is switched off / restored after
            // finalize. Until the locked squad loads, the draft's (the court
            // falls back the same way).
            activeChip: shownChip,
            enabled: editable,
            onChipChanged: _draft.setChip,
            // A first team has nothing to transfer, and an unknown count may
            // be one (the server spends a first-team chip for nothing):
            // Wildcard / Free Hit can't be armed in either case. "Unknown"
            // covers notReady AND hidden (a node with no baseline). Nor can
            // they while the chip history is unknown (null).
            firstTeam: transfers.kind == TransferPreviewKind.firstTeam,
            transfersUnknown: transfers.kind == TransferPreviewKind.notReady ||
                transfers.kind == TransferPreviewKind.hidden,
            chipHistoryUnknown: widget.chipHistory == null,
            // Real usage: spent-in-this-set from History, the armed chip on
            // the squad on screen (the live squad, or its unsaved edit).
            availability: chipAvailability(
              historyByWeek: widget.chipHistory ?? const {},
              editingGw: chipEditingGameweek(widget.gameweeks, _now),
              armedChip: shownChip,
              config: widget.config,
              voidedWeeks: widget.voidedWeeks,
            ),
          ),
          if (editable && shownIssues.isNotEmpty) ...[
            const SizedBox(height: 14),
            _IssueList(issues: shownIssues),
          ],
          if (editable) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('squad_save'),
              onPressed: valid && _draft.dirty && moneyReady && !_saving
                  ? _save
                  : null,
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

/// Spent vs the money available with the remaining amount — fills as picks
/// land, flips to the error color when over. Restyled in the P3b feedback
/// round (Task 5): the fill is the pitch-green family (works both themes),
/// the remaining text reads in onSurface, and ONLY the over-budget state
/// goes error-red.
///
/// FPL selling (spec §4): the total is the draft's available money — the
/// budget plus the sales realized so far ([realized], may be negative) —
/// and a second line says so whenever that isn't zero: "Includes +$0.5M
/// from sales" (muted) / "Includes −$0.5M from sales" (the bright fantasy
/// down red, both themes).
///
/// Error ≠ fact: while the draft's money isn't real ([moneyReady] false —
/// the market or this week's baseline hasn't loaded, or the read failed)
/// the bar keeps "$X spent" but claims nothing else: "— left" in the same
/// style, no sales line, no over state, and an empty track (no total
/// implied).
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.spent,
    required this.available,
    required this.realized,
    required this.moneyReady,
  });

  final int spent;
  final int available;
  final int realized;
  final bool moneyReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = fantasyPitchGreen(context);
    final over = moneyReady && spent > available;
    final remaining = available - spent;
    final fill = !moneyReady
        ? 0.0
        : available <= 0
            ? 1.0
            : (spent / available).clamp(0.0, 1.0);
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
                !moneyReady
                    ? '— left'
                    : over
                        ? '${formatMoneyTenths(-remaining)} over'
                        : '${formatMoneyTenths(remaining)} left',
                key: const ValueKey('budget_left'),
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
          if (moneyReady && realized != 0) ...[
            const SizedBox(height: 2),
            Text(
              realizedSalesLine(realized),
              key: const ValueKey('budget_realized'),
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: realized < 0
                    ? fantasyDownRed(context)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
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

/// The transfers line (plan 2026-11-03): [transferLineText] for the draft's
/// preview, one muted line — except a points cost, which reads in the bright
/// fantasy "down" red (fantasyDownRed, both themes; never the soft dark-mode
/// error pink). No fill, so nothing to fit in either mode; it wraps rather
/// than clips at 360 px.
class _TransfersLine extends StatelessWidget {
  const _TransfersLine({required this.preview});

  final TransferPreview preview;

  @override
  Widget build(BuildContext context) {
    final text = transferLineText(preview);
    if (text == null) return const SizedBox.shrink();
    final hit = preview.kind == TransferPreviewKind.counted &&
        preview.costPoints > 0;
    final color = hit
        ? fantasyDownRed(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      key: const ValueKey('transfers_line'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.swap_horiz_rounded, size: 15, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('transfers_line_text'),
              softWrap: true,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                fontWeight: hit ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The locked state's compact header (live everywhere, Task 5): what the week
/// is doing for this manager — the LIVE pill while the numbers move, then
/// `34 pts · #5 ▲2`, `Final · 34 pts · #5`, `Voided · this week counts 0`,
/// `0 pts · this week didn't count`, `Locked · waiting for kickoff` (before
/// kickoff only) or just `Locked` (a week we cannot read)
/// (live_logic.lockedStripText; copy pinned by live_logic_test.dart). The
/// fantasy accent tint (gold in dark, primary red in light) like the rest of
/// the hub; the movement reads in the leaderboard's own up / down colours
/// (pitch green / the bright fantasy red), both themes. Text wraps, never
/// ellipsizes, so it fits 360 px.
/// My Team while the schedule could not be read (review 6, I2): editing is
/// paused because the deadline can't be checked — never "Locked". The
/// schedule feed retries on its own.
class _DeadlineUnknownStrip extends StatelessWidget {
  const _DeadlineUnknownStrip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('deadline_unknown_strip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$kDeadlineUnavailable — can't check whether editing is open "
              'right now. Trying again…',
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
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

class _LockedWeekStrip extends StatelessWidget {
  const _LockedWeekStrip({required this.view});

  final LockedWeekView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final parts = lockedStripParts(view);
    final numbers = view.kind == LockedWeekKind.live ||
        view.kind == LockedWeekKind.settled;
    final style = TextStyle(
      fontSize: numbers ? 15 : 13,
      height: 1.25,
      fontWeight: numbers ? FontWeight.w800 : FontWeight.w600,
      color: scheme.onSurface,
    );
    final movement = parts.movement;
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
          if (view.isLive) ...[
            const FantasyLivePill(),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                text: movement == null ? parts.main : '${parts.main} ',
                children: [
                  if (movement != null)
                    TextSpan(
                      text: movement,
                      style: TextStyle(
                        color: movementColor(
                            context, movementDirection(view.movement)),
                      ),
                    ),
                ],
              ),
              softWrap: true,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// The holder-protection alert (spec §3): "Ann moved to DEF — your team
/// needs rearranging before Sun, Oct 19 · 3:00 PM. Swapping him out is
/// free this week." — or the integrity alert (audit I2): "Your Gameweek 3
/// team didn't count: over budget. Fix it before the next deadline." The
/// error-container pair is a Material 3 scheme role, so it reads
/// correctly in both light and dark mode.
///
/// [brightRed] (the over-budget preview, FPL selling spec §4: "Your team is
/// $1.0M over budget after this week's price changes…") swaps the pair for
/// the bright fantasy "down" red (fantasyDownRed — never the soft dark-mode
/// error pink): red text, icon and outline on the plain surface, the
/// combination that constant is checked for (≥4.5:1 in both themes).
class _SquadAlertBanner extends StatelessWidget {
  const _SquadAlertBanner({
    required this.text,
    required this.icon,
    this.brightRed = false,
  });

  final String text;
  final IconData icon;
  final bool brightRed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final red = fantasyDownRed(context);
    final fg = brightRed ? red : scheme.onErrorContainer;
    return Container(
      key: const ValueKey('squad_alert_banner'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: brightRed ? scheme.surface : scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: brightRed ? Border.all(color: red, width: 1.5) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: brightRed ? FontWeight.w700 : FontWeight.w600,
                color: fg,
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
    required this.priceOf,
    required this.enabled,
    required this.onSwap,
    required this.onRemove,
  });

  final List<SquadPick> picks;

  /// The charged price (the draft's priceOfPick), as on the court.
  final int Function(SquadPick pick) priceOf;
  final bool enabled;
  final void Function(SquadPick pick) onSwap;
  final void Function(SquadPick pick) onRemove;

  static String _nowA(FantasyPosition p) => 'Now ${p.withArticle}';

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
                          '${formatMoneyTenths(priceOf(pick))}',
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
