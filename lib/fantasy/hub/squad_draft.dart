// The ONE squad draft (P3c) — lifted out of the My Team builder's local
// state so the Players market edits the SAME draft the court renders. The
// hub owns a single instance per sport/season, feeds it the live squad
// stream (adoptions skip while the draft is dirty — in-progress edits always
// survive remote emits and our own save echo), and hands it to both tabs.
// Nothing here auto-saves: mutations only mark the draft dirty; the write
// stays on My Team's Save button.
//
// Pure-ish: flutter/foundation only (ChangeNotifier), all placement/armband
// math delegated to squad_builder_logic.dart; unit-tested in
// test/fantasy/squad_draft_test.dart.

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

class SquadDraftController extends ChangeNotifier {
  SquadDraftController({required FantasyConfig config, FantasySquad? initial})
      : _config = config {
    _slots = buildSlots(config);
    _adopt(initial);
  }

  FantasyConfig _config;
  late List<SquadSlot> _slots;
  late List<SquadPick?> _picks;
  String? _captainId;
  String? _viceId;
  String? _chip;
  bool _dirty = false;

  FantasyConfig get config => _config;
  List<SquadSlot> get slots => _slots;
  List<SquadPick?> get picks => _picks;
  String? get captainId => _captainId;
  String? get viceId => _viceId;
  String? get chip => _chip;

  /// True once the user edits; cleared by [markSaved] and clean adoptions.
  /// The Players tab's "unsaved changes — save on My Team" pill reads this.
  bool get dirty => _dirty;

  Set<String> get playerIds =>
      {for (final p in _picks) if (p != null) p.playerId};

  int get spentTenths => draftSpentTenths(_picks);

  /// The engine squad this draft saves as.
  FantasySquad get squad => draftToSquad(
      slotPicks: _picks, captainId: _captainId, viceId: _viceId, chip: _chip);

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
    _picks = picksToSlots(current, _slots);
    notifyListeners();
  }

  /// Stream adoptions (the saved squad node, including this device's own
  /// save echo). A dirty draft is NEVER overwritten — the in-progress edit
  /// wins until saved or re-adopted clean.
  void adoptFromStream(FantasySquad? squad) {
    if (_dirty) return;
    _adopt(squad);
    notifyListeners();
  }

  void _adopt(FantasySquad? squad) {
    _picks = picksToSlots(squad, _slots);
    _captainId =
        (squad?.captainId.isNotEmpty ?? false) ? squad!.captainId : null;
    _viceId = (squad?.viceId.isNotEmpty ?? false) ? squad!.viceId : null;
    _chip = squad?.chip;
    _dirty = false;
  }

  /// A successful save marks the draft clean: the write's stream echo then
  /// adopts as a no-op (identical content — no flicker, no double-apply).
  void markSaved() {
    _dirty = false;
    notifyListeners();
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
        _picks[i] = SquadPick(
          playerId: player.name,
          position: player.position,
          priceTenths: player.priceTenths,
          bench: _slots[i].bench,
        );
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
    return null;
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
