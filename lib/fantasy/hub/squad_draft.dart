// The ONE squad draft (P3c) — lifted out of the My Team builder's local
// state so the Players market edits the SAME draft the court renders. The
// hub owns a single instance per sport/season, feeds it the live squad
// stream (adoptions skip while the draft is dirty — in-progress edits always
// survive remote emits and our own save echo), and hands it to both tabs.
// Nothing here auto-saves: mutations only mark the draft dirty; the write
// stays on My Team's Save button.
//
// Two server-driven changes reach the draft (spec §3/§6):
// - a player whose fantasy position changed no longer fits his slot (the
//   server re-labels holders): he lands in [unplaced] — the builder's
//   "Needs a new spot" strip (Swap/Remove) — never silently dropped;
// - chips are one-week: after a gameweek settles the server switches the
//   spent chip off. A clean draft adopts that like any emit; a dirty draft
//   adopts it too unless the user toggled the chip in this draft, so a
//   draft left dirty since before the lock can't quietly re-arm the chip.
//
// FPL selling (spec §4, selling.dart): the hub feeds [setSaleContext] the
// own `Baselines/<uid>` state, today's market prices and the gameweek being
// edited, and the draft charges what the server's lock judge will charge —
// a baseline player kept (or re-added) costs his BASELINE price whatever
// the pick says; a sold one banks his FPL sell price into [realizedTenths];
// the room is budget + realized − spent. Error ≠ fact: [moneyReady] is
// false until a current baseline (or a known first squad) has loaded, and
// the UI must not present the money as real before then.
//
// Pure-ish: flutter/foundation only (ChangeNotifier), all placement/armband
// math delegated to squad_builder_logic.dart; unit-tested in
// test/fantasy/squad_draft_test.dart.

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

/// The gameweek whose money the draft shows (the `editingGw` the hub hands
/// [SquadDraftController.setSaleContext]): the first gameweek whose lock is
/// still ahead ([chipEditingGameweek]; `Baselines/<uid>.ForGw` names the
/// same week once the server has locked the previous one). null while the
/// schedule is unknown — a baseline can't be judged current then.
///
/// Under the owner's OPEN override the lock sweep stands down entirely
/// (orchestration.ts), so no lock can move the stored baseline even after
/// the clock deadline: the stored node IS the week being edited — saves are
/// still accepted then, and a clock-based week would block them as stale.
int? saleEditingGameweek({
  required List<Gameweek>? gameweeks,
  required FantasyLockOverride lockOverride,
  required SaleBaseline? baseline,
  required DateTime nowUtc,
}) {
  if (lockOverride == FantasyLockOverride.open && baseline != null) {
    return baseline.forGw;
  }
  if (gameweeks == null) return null;
  return chipEditingGameweek(gameweeks, nowUtc);
}

class SquadDraftController extends ChangeNotifier {
  SquadDraftController({required FantasyConfig config, FantasySquad? initial})
      : _config = config {
    _slots = buildSlots(config);
    _stored = initial;
    _adopt(initial);
  }

  FantasyConfig _config;
  late List<SquadSlot> _slots;
  late List<SquadPick?> _picks;
  late List<SquadPick> _unplaced;
  String? _captainId;
  String? _viceId;
  String? _chip;
  bool _dirty = false;

  /// The user toggled the chip since the last clean adoption/save.
  bool _chipTouched = false;

  /// The squad as last STORED (the latest stream value — adopted or, while
  /// dirty, only remembered — or our own successful save): what
  /// [revertToStored] goes back to.
  FantasySquad? _stored;

  // ── FPL selling context ([setSaleContext]) ─────────────────────────────
  SaleBaselineState? _sale;
  Map<String, int> _currentPrices = const {};
  int? _editingGw;

  SaleBaseline? get _baseline => _sale?.baseline;

  FantasyConfig get config => _config;
  List<SquadSlot> get slots => _slots;
  List<SquadPick?> get picks => _picks;

  /// Owned picks with no fitting slot (a position change, or a config
  /// shrink) — the builder's "Needs a new spot" strip. Save stays blocked
  /// while any remain (issueSentences says so).
  List<SquadPick> get unplaced => List.unmodifiable(_unplaced);
  String? get captainId => _captainId;
  String? get viceId => _viceId;
  String? get chip => _chip;

  /// True once the user edits; cleared by [markSaved] and clean adoptions.
  /// The Players tab's "unsaved changes — save on My Team" pill reads this.
  bool get dirty => _dirty;

  Set<String> get playerIds => {
        for (final p in _picks)
          if (p != null) p.playerId,
        for (final p in _unplaced) p.playerId,
      };

  /// Everything owned is paid for — unplaced picks included — each at
  /// [priceOfPick] (a held baseline player at his baseline price).
  int get spentTenths => _ownedPicks.fold<int>(0, (a, p) => a + priceOfPick(p));

  /// Every owned pick: the slots' plus the unplaced.
  Iterable<SquadPick> get _ownedPicks =>
      [..._picks.whereType<SquadPick>(), ..._unplaced];

  // ── FPL selling money (spec §4) ────────────────────────────────────────

  /// The hub's feed: the own `Baselines/<uid>` state ([sale]; null = not
  /// answered yet), today's market prices by player id ([currentPrices])
  /// and the gameweek being edited ([editingGw], see
  /// [saleEditingGameweek]; null = the schedule is unknown). Notifies only
  /// when something changed.
  void setSaleContext({
    SaleBaselineState? sale,
    Map<String, int> currentPrices = const {},
    int? editingGw,
  }) {
    if (identical(sale, _sale) &&
        editingGw == _editingGw &&
        mapEquals(currentPrices, _currentPrices)) {
      return;
    }
    _sale = sale;
    _currentPrices = Map.unmodifiable(currentPrices);
    _editingGw = editingGw;
    notifyListeners();
  }

  /// What [p] costs the squad: his baseline price when he is a baseline
  /// player (HELD — the server ignores the pick's own price), else the
  /// price on the pick (what it was bought at this window).
  int priceOfPick(SquadPick p) =>
      _baseline?.prices[p.playerId] ?? p.priceTenths;

  /// The profit/loss the lock would book for this draft: the carried total
  /// plus every baseline player no longer owned (unplaced picks still are),
  /// sold at today's price.
  int get realizedTenths => realizedNowTenths(
      _baseline, _ownedPicks.map((p) => p.playerId), _currentPrices);

  /// The money to spend: budget + realized sales.
  int get availableTenths => _config.budgetTenths + realizedTenths;

  /// The room left (negative = over budget).
  int get remainingTenths => availableTenths - spentTenths;

  /// The room after removing the owned [pick] (a swap's outgoing player):
  /// his price back, and — a baseline player — his sale booked.
  int remainingIfRemovedTenths(SquadPick pick) {
    final ids = [for (final p in _ownedPicks) p.playerId];
    ids.remove(pick.playerId); // one copy only
    final realized = realizedNowTenths(_baseline, ids, _currentPrices);
    return _config.budgetTenths + realized - (spentTenths - priceOfPick(pick));
  }

  /// What adding [p] costs: a baseline player is bought back at his
  /// baseline price (no sale, no transfer), anyone else at today's price.
  int buyPriceOf(FantasyPlayer p) =>
      buyPriceTenths(_baseline, p.name, p.priceTenths);

  /// The ONE way a pick is made from a market player (market add, picker,
  /// the Needs-a-new-spot swap), priced by [buyPriceOf].
  SquadPick newPick(FantasyPlayer p, {required bool bench}) => SquadPick(
        playerId: p.name,
        position: p.position,
        priceTenths: buyPriceOf(p),
        bench: bench,
      );

  /// What selling [playerId] banks (the FPL rule); null unless he is a
  /// baseline player. With no usable market price (gone, or ≤ 0) he sells
  /// for what was paid — the server adds 0 for him.
  int? sellPriceOf(String playerId) {
    final paid = _baseline?.prices[playerId];
    if (paid == null) return null;
    final current = _currentPrices[playerId];
    if (current == null || current <= 0) return paid;
    return sellPriceTenths(purchaseTenths: paid, currentTenths: current);
  }

  /// The money above is real: the baseline feed has loaded (not degraded)
  /// and is for the week being edited. A known-absent node (a first squad)
  /// is always ready.
  bool get moneyReady {
    final sale = _sale;
    if (sale == null || !sale.loaded || sale.degraded) return false;
    final b = sale.baseline;
    return b == null || b.forGw == _editingGw;
  }

  /// The first empty slot (where a moved player's swap-in lands), or null.
  int? get firstEmptySlot {
    final i = _picks.indexWhere((p) => p == null);
    return i < 0 ? null : i;
  }

  /// The engine squad this draft saves as (unplaced picks included — they
  /// are still owned; Save is blocked while any remain).
  FantasySquad get squad => draftToSquad(
      slotPicks: [..._picks, ..._unplaced],
      captainId: _captainId,
      viceId: _viceId,
      chip: _chip);

  /// A formation change in the live config re-shapes the slots; current
  /// picks re-map into whatever still fits. Non-formation tweaks (budget,
  /// scoring) just swap the config reference silently.
  void syncConfig(FantasyConfig config) {
    final reshape = config.startersGk != _config.startersGk ||
        config.startersDef != _config.startersDef ||
        config.startersAtt != _config.startersAtt ||
        config.benchDef != _config.benchDef ||
        config.benchAtt != _config.benchAtt;
    _config = config;
    if (!reshape) return;
    final current = squad;
    _slots = buildSlots(config);
    final placed = placePicks(current, _slots);
    _picks = placed.slotPicks;
    _unplaced = [...placed.unplaced];
    notifyListeners();
  }

  /// Stream adoptions (the saved squad node, including this device's own
  /// save echo). A dirty draft is NEVER overwritten — the in-progress edit
  /// wins until saved or re-adopted clean — with ONE exception: the chip,
  /// when the user hasn't toggled it in this draft (the server switching a
  /// spent chip off must not be undone by a stale draft's next save).
  void adoptFromStream(FantasySquad? squad) {
    _stored = squad;
    if (_dirty) {
      if (!_chipTouched && squad?.chip != _chip) {
        _chip = squad?.chip;
        notifyListeners();
      }
      return;
    }
    _adopt(squad);
    notifyListeners();
  }

  void _adopt(FantasySquad? squad) {
    final placed = placePicks(squad, _slots);
    _picks = placed.slotPicks;
    _unplaced = [...placed.unplaced];
    _captainId =
        (squad?.captainId.isNotEmpty ?? false) ? squad!.captainId : null;
    _viceId = (squad?.viceId.isNotEmpty ?? false) ? squad!.viceId : null;
    _chip = squad?.chip;
    _chipTouched = false;
    _dirty = false;
  }

  /// A successful save marks the draft clean: the write's stream echo then
  /// adopts as a no-op (identical content — no flicker, no double-apply).
  void markSaved() {
    _stored = squad;
    _dirty = false;
    _chipTouched = false;
    notifyListeners();
  }

  /// A save the server REFUSED (the deadline passed while editing — squad
  /// hardening, audit I3): the edits are dropped and the draft goes back to
  /// the stored squad (the live stream's latest value), clean.
  void revertToStored() {
    _adopt(_stored);
    notifyListeners();
  }

  /// "Remove" on the Needs-a-new-spot strip. Returns the armband-loss
  /// sentence when the player wore one; null also when not unplaced.
  String? removeUnplaced(String playerId) {
    final i = _unplaced.indexWhere((p) => p.playerId == playerId);
    if (i < 0) return null;
    _unplaced.removeAt(i);
    _dirty = true;
    final message = _clearArmbandFor(playerId);
    notifyListeners();
    return message;
  }

  /// "Swap" on the strip: the unplaced player leaves and [pick] fills slot
  /// [slot] (normally the hole his move left — see [firstEmptySlot]).
  /// Returns the armband-loss sentence when applicable.
  String? swapUnplaced(String playerId, int slot, SquadPick pick) {
    final i = _unplaced.indexWhere((p) => p.playerId == playerId);
    if (i < 0) return null;
    _unplaced.removeAt(i);
    final displaced = _picks[slot];
    _picks[slot] = pick;
    _dirty = true;
    final message = _clearArmbandFor(playerId);
    if (displaced != null) {
      _unplaced.add(displaced); // never lose an owned pick silently
    }
    notifyListeners();
    return message;
  }

  /// Places [pick] into slot [i] (the builder's picker flow). Returns the
  /// armband-loss sentence when a swapped-out player wore one — the caller
  /// surfaces it (nothing happens silently).
  String? setPickAt(int i, SquadPick pick) {
    final outgoing = _picks[i];
    _picks[i] = pick;
    _dirty = true;
    final message =
        outgoing == null ? null : _clearArmbandFor(outgoing.playerId);
    notifyListeners();
    return message;
  }

  /// Empties slot [i]. Returns the armband-loss sentence when applicable.
  String? removeAt(int i) {
    final outgoing = _picks[i];
    if (outgoing == null) return null;
    _picks[i] = null;
    _dirty = true;
    final message = _clearArmbandFor(outgoing.playerId);
    notifyListeners();
    return message;
  }

  /// Market add (P3c): lands in the first empty slot matching the player's
  /// position — starters fill before the bench (buildSlots order). False
  /// when no slot fits (the market disables the control first via
  /// marketAddState; this is the belt to that suspender).
  bool addPlayer(FantasyPlayer player) {
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i].position == player.position && _picks[i] == null) {
        _picks[i] = newPick(player, bench: _slots[i].bench);
        _dirty = true;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// Market remove (P3c): drops the player wherever they sit. Returns the
  /// armband-loss sentence when applicable; null also when absent (no-op).
  String? removePlayer(String playerId) {
    for (var i = 0; i < _picks.length; i++) {
      if (_picks[i]?.playerId == playerId) return removeAt(i);
    }
    return removeUnplaced(playerId);
  }

  void makeCaptain(String id) {
    final bands =
        assignCaptain(id: id, captainId: _captainId, viceId: _viceId);
    _captainId = bands.captainId;
    _viceId = bands.viceId;
    _dirty = true;
    notifyListeners();
  }

  void makeVice(String id) {
    final bands = assignVice(id: id, captainId: _captainId, viceId: _viceId);
    _captainId = bands.captainId;
    _viceId = bands.viceId;
    _dirty = true;
    notifyListeners();
  }

  void setChip(String? chip) {
    _chip = chip;
    _chipTouched = true;
    _dirty = true;
    notifyListeners();
  }

  /// Computes the message BEFORE clearing (armbandLossMessage reads the
  /// current bands), then clears.
  String? _clearArmbandFor(String playerId) {
    final message = armbandLossMessage(
        removedId: playerId, captainId: _captainId, viceId: _viceId);
    if (playerId == _captainId) _captainId = null;
    if (playerId == _viceId) _viceId = null;
    return message;
  }
}
