// P3b — the squad builder's pure logic: slot layout, draft<->engine mapping,
// picker filtering, armband reassignment, lock state and the human sentences
// rendered from the engine's validateSquad.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();

  SquadPick pick(String id, FantasyPosition pos,
          {int price = 50, bool bench = false}) =>
      SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

  FantasyPlayer player(String name, FantasyPosition pos,
          {int price = 50, bool eligible = true, String team = 'Team A'}) =>
      FantasyPlayer(
          name: name,
          position: pos,
          priceTenths: price,
          eligible: eligible,
          teamName: team);

  group('buildSlots', () {
    test('futsal default: 7 slots in GK/DEF/DEF/ATT/ATT + bench DEF/ATT order',
        () {
      final slots = buildSlots(cfg);
      expect(slots.length, 7);
      expect(
          slots.map((s) => s.position).toList(),
          [
            FantasyPosition.gk,
            FantasyPosition.def,
            FantasyPosition.def,
            FantasyPosition.att,
            FantasyPosition.att,
            FantasyPosition.def,
            FantasyPosition.att,
          ]);
      expect(slots.map((s) => s.bench).toList(),
          [false, false, false, false, false, true, true]);
    });
  });

  group('starterOffsets', () {
    test('GK centered up top, DEF and ATT rows spread evenly', () {
      final offsets = starterOffsets(cfg);
      expect(offsets.length, 5);
      expect(offsets[0].x, 0.5); // GK centered
      expect(offsets[0].y, lessThan(offsets[1].y)); // GK above DEF
      expect(offsets[1].y, lessThan(offsets[3].y)); // DEF above ATT
      // Owner feedback round: wider spreads — DEF ±0.24, ATT ±0.26.
      expect(offsets[1].x, closeTo(0.26, 1e-9));
      expect(offsets[2].x, closeTo(0.74, 1e-9));
      expect(offsets[3].x, closeTo(0.24, 1e-9));
      expect(offsets[4].x, closeTo(0.76, 1e-9));
      // Rows keep symmetric pairs.
      expect(offsets[1].x + offsets[2].x, closeTo(1, 1e-9));
      expect(offsets[3].x + offsets[4].x, closeTo(1, 1e-9));
    });

    test('pitchAssetPerspective lands rows on the artwork grass', () {
      // Center column stays centered at every depth.
      expect(pitchAssetPerspective((x: 0.5, y: 0.0)).x, 0.5);
      expect(pitchAssetPerspective((x: 0.5, y: 1.0)).x, 0.5);
      // y maps into the image's pitch span.
      expect(pitchAssetPerspective((x: 0.5, y: 0.0)).y,
          closeTo(pitchAssetTopY, 1e-9));
      expect(pitchAssetPerspective((x: 0.5, y: 1.0)).y,
          closeTo(pitchAssetBottomY, 1e-9));
      // x squeezes to the image's half-width: far edge tighter than near.
      final far = pitchAssetPerspective((x: 1.0, y: 0.0)).x;
      final near = pitchAssetPerspective((x: 1.0, y: 1.0)).x;
      expect(far, closeTo(0.5 + pitchAssetHalfTop, 1e-9));
      expect(near, closeTo(0.5 + pitchAssetHalfBottom, 1e-9));
      expect(far, lessThan(near));
    });
  });

  group('picksToSlots / draftToSquad', () {
    test('a saved squad round-trips through the slots', () {
      final squad = FantasySquad(
        picks: [
          pick('GK One', FantasyPosition.gk),
          pick('Def One', FantasyPosition.def),
          pick('Def Two', FantasyPosition.def),
          pick('Att One', FantasyPosition.att),
          pick('Att Two', FantasyPosition.att),
          pick('Bench Def', FantasyPosition.def, bench: true),
          pick('Bench Att', FantasyPosition.att, bench: true),
        ],
        captainId: 'Att One',
        viceId: 'Def One',
        chip: 'benchBoost',
      );
      final slots = buildSlots(cfg);
      final slotPicks = picksToSlots(squad, slots);
      expect(slotPicks.whereType<SquadPick>().length, 7);
      expect(slotPicks[0]!.playerId, 'GK One');
      expect(slotPicks[5]!.playerId, 'Bench Def');
      expect(slotPicks[6]!.playerId, 'Bench Att');

      final back = draftToSquad(
          slotPicks: slotPicks,
          captainId: 'Att One',
          viceId: 'Def One',
          chip: 'benchBoost');
      expect(back.picks.map((p) => p.playerId).toSet(),
          squad.picks.map((p) => p.playerId).toSet());
      expect(validateSquad(back, cfg), isEmpty);
    });

    test('null squad → all slots empty; overflow picks are dropped', () {
      final slots = buildSlots(cfg);
      expect(picksToSlots(null, slots).whereType<SquadPick>(), isEmpty);

      final overflow = FantasySquad(
        picks: [
          pick('GK One', FantasyPosition.gk),
          pick('GK Two', FantasyPosition.gk), // no second GK slot
        ],
        captainId: '',
        viceId: '',
      );
      final slotPicks = picksToSlots(overflow, slots);
      expect(slotPicks.whereType<SquadPick>().length, 1);
      expect(slotPicks[0]!.playerId, 'GK One');
    });

    test('placePicks keeps a pick whose position no longer fits (spec §3)',
        () {
      // The server re-labelled the GK as a DEF: both starter DEF slots and
      // the bench DEF slot are taken, so he has no slot — and the GK slot is
      // the hole his move left.
      final relabelled = FantasySquad(
        picks: [
          pick('Moved Keeper', FantasyPosition.def, price: 80),
          pick('Def One', FantasyPosition.def),
          pick('Def Two', FantasyPosition.def),
          pick('Att One', FantasyPosition.att),
          pick('Att Two', FantasyPosition.att),
          pick('Bench Def', FantasyPosition.def, bench: true),
          pick('Bench Att', FantasyPosition.att, bench: true),
        ],
        captainId: 'Att One',
        viceId: 'Def One',
      );
      final slots = buildSlots(cfg);
      final placed = placePicks(relabelled, slots);
      expect(placed.slotPicks[0], isNull); // GK hole
      expect(placed.unplaced.map((p) => p.playerId), ['Moved Keeper']);
      expect(placed.unplaced.single.position, FantasyPosition.def);
      // picksToSlots is the slot half (read-only viewers).
      expect(picksToSlots(relabelled, slots), placed.slotPicks);
    });

    test('draftToSquad writes missing armbands as empty strings', () {
      final squad =
          draftToSquad(slotPicks: List.filled(7, null), captainId: null);
      expect(squad.captainId, '');
      expect(squad.viceId, '');
      expect(squad.picks, isEmpty);
    });

    test('draftSpentTenths sums only the filled slots', () {
      expect(
          draftSpentTenths([
            pick('A', FantasyPosition.gk, price: 45),
            null,
            pick('B', FantasyPosition.def, price: 60),
          ]),
          105);
    });
  });

  group('holder protection copy', () {
    test('squadAlertText: spec sentence, free-swap promise only this week',
        () {
      expect(
          squadAlertText(
            changes: [(player: 'Ann Keeper', to: FantasyPosition.def)],
            deadline: 'Sun, Oct 19 · 3:00 PM',
            freeThisWeek: true,
          ),
          'Ann Keeper moved to DEF — your team needs rearranging before '
          'Sun, Oct 19 · 3:00 PM. Swapping him out is free this week.');
      expect(
          squadAlertText(
            changes: [
              (player: 'A', to: FantasyPosition.def),
              (player: 'B', to: FantasyPosition.att),
              (player: 'C', to: FantasyPosition.gk),
            ],
            deadline: 'x',
            freeThisWeek: true,
          ),
          'A moved to DEF, B moved to ATT and C moved to GK — your team needs '
          'rearranging before x. Swapping them out is free this week.');
      expect(
          squadAlertText(
            changes: [(player: 'A', to: FantasyPosition.att)],
            deadline: 'x',
            freeThisWeek: false,
          ),
          'A moved to ATT — your team needs rearranging before x.');
    });

    test('issueSentences blocks Save while a pick needs a new spot', () {
      final slots = buildSlots(cfg);
      final slotPicks = <SquadPick?>[
        null,
        pick('Def One', FantasyPosition.def),
        pick('Def Two', FantasyPosition.def),
        pick('Att One', FantasyPosition.att),
        pick('Att Two', FantasyPosition.att),
        pick('Bench Def', FantasyPosition.def, bench: true),
        pick('Bench Att', FantasyPosition.att, bench: true),
      ];
      final out = issueSentences(
        slots: slots,
        slotPicks: slotPicks,
        captainId: 'Att One',
        viceId: 'Def One',
        cfg: cfg,
        unplaced: [pick('Moved Keeper', FantasyPosition.def)],
      );
      expect(out.first,
          'Find Moved Keeper a new spot — swap him out or remove him.');
      expect(out, contains('Pick a goalkeeper.'));
    });
  });

  group('pickerCandidates', () {
    final players = [
      player('Alan Keeper', FantasyPosition.gk, price: 50),
      player('Gus Glove', FantasyPosition.gk, price: 45, team: 'Team B'),
      player('Dana Wall', FantasyPosition.def, price: 60),
      player('Guest Guy', FantasyPosition.gk, price: 70, eligible: false),
    ];

    test('filters to the slot position and drops guests + squad members', () {
      final out = pickerCandidates(
        players: players,
        position: FantasyPosition.gk,
        excludeIds: {'Gus Glove'},
      );
      expect(out.map((p) => p.name), ['Alan Keeper']);
    });

    test('price sort is descending with name tiebreak; name sort is A-Z', () {
      final gks = pickerCandidates(
          players: players, position: FantasyPosition.gk, excludeIds: {});
      expect(gks.map((p) => p.name), ['Alan Keeper', 'Gus Glove']);
      final byName = pickerCandidates(
          players: players,
          position: FantasyPosition.gk,
          excludeIds: {},
          sortByPrice: false);
      expect(byName.map((p) => p.name), ['Alan Keeper', 'Gus Glove']);
    });

    test('query matches name or team, case-insensitively', () {
      expect(
          pickerCandidates(
              players: players,
              position: FantasyPosition.gk,
              excludeIds: {},
              query: 'team b').map((p) => p.name),
          ['Gus Glove']);
      expect(
          pickerCandidates(
              players: players,
              position: FantasyPosition.gk,
              excludeIds: {},
              query: 'alan').map((p) => p.name),
          ['Alan Keeper']);
    });
  });

  group('armbands', () {
    test('captaining the vice swaps the bands — nothing lost silently', () {
      final bands = assignCaptain(id: 'B', captainId: 'A', viceId: 'B');
      expect(bands.captainId, 'B');
      expect(bands.viceId, 'A');
    });

    test('a plain captain change keeps the vice', () {
      final bands = assignCaptain(id: 'C', captainId: 'A', viceId: 'B');
      expect(bands.captainId, 'C');
      expect(bands.viceId, 'B');
    });

    test('vicing the captain swaps too; re-assignments are no-ops', () {
      final bands = assignVice(id: 'A', captainId: 'A', viceId: 'B');
      expect(bands.captainId, 'B');
      expect(bands.viceId, 'A');
      final same = assignCaptain(id: 'A', captainId: 'A', viceId: 'B');
      expect(same.captainId, 'A');
      expect(same.viceId, 'B');
    });

    test('armbandLossMessage names what was lost', () {
      expect(armbandLossMessage(removedId: 'A', captainId: 'A', viceId: 'B'),
          contains('captain'));
      expect(armbandLossMessage(removedId: 'B', captainId: 'A', viceId: 'B'),
          contains('vice-captain'));
      expect(armbandLossMessage(removedId: 'C', captainId: 'A', viceId: 'B'),
          isNull);
    });
  });

  group('squadEditable', () {
    final now = DateTime.utc(2026, 10, 27, 12);
    // A gameweek whose lock is a day ahead of [now].
    final openGw = Gameweek(
        number: 1,
        date: '10282026',
        lockUtc: DateTime.utc(2026, 10, 28, 22),
        opensUtc: null);

    test("owner override wins: 'open' edits with no gameweeks at all", () {
      expect(
          squadEditable(
              lockOverride: FantasyLockOverride.open,
              gameweeks: const [],
              nowUtc: now),
          isTrue);
      expect(
          squadEditable(
              lockOverride: FantasyLockOverride.locked,
              gameweeks: [openGw],
              nowUtc: now),
          isFalse);
    });

    test('auto follows the current gameweek; season over = locked', () {
      expect(
          squadEditable(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: [openGw],
              nowUtc: now),
          isTrue);
      expect(
          squadEditable(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: [openGw],
              nowUtc: DateTime.utc(2026, 11, 30)),
          isFalse);
      expect(
          squadEditable(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: const [],
              nowUtc: now),
          isFalse);
    });
  });

  group('issueSentences', () {
    final slots = buildSlots(cfg);

    test('empty squad: per-position formation sentences, no armband nag', () {
      final out = issueSentences(
        slots: slots,
        slotPicks: List.filled(slots.length, null),
        captainId: null,
        viceId: null,
        cfg: cfg,
      );
      expect(out, contains('Pick a goalkeeper.'));
      expect(out, contains('Pick 2 defenders — you have 0.'));
      expect(out, contains('Pick 2 attackers — you have 0.'));
      expect(out, contains('Pick a bench defender.'));
      expect(out, contains('Pick a bench attacker.'));
      expect(out.any((s) => s.contains('captain')), isFalse);
    });

    test('partial squad counts what you have', () {
      final picks = List<SquadPick?>.filled(slots.length, null);
      picks[1] = pick('Dana Wall', FantasyPosition.def);
      final out = issueSentences(
        slots: slots,
        slotPicks: picks,
        captainId: null,
        viceId: null,
        cfg: cfg,
      );
      expect(out, contains('Pick 2 defenders — you have 1.'));
    });

    List<SquadPick?> fullPicks({int price = 50}) => [
          pick('GK One', FantasyPosition.gk, price: price),
          pick('Def One', FantasyPosition.def, price: price),
          pick('Def Two', FantasyPosition.def, price: price),
          pick('Att One', FantasyPosition.att, price: price),
          pick('Att Two', FantasyPosition.att, price: price),
          pick('Bench Def', FantasyPosition.def, price: price, bench: true),
          pick('Bench Att', FantasyPosition.att, price: price, bench: true),
        ];

    test('full squad without an armband asks for captain and vice', () {
      final out = issueSentences(
        slots: slots,
        slotPicks: fullPicks(),
        captainId: null,
        viceId: null,
        cfg: cfg,
      );
      expect(out, ['Choose a captain and vice-captain.']);

      final onlyVice = issueSentences(
        slots: slots,
        slotPicks: fullPicks(),
        captainId: null,
        viceId: 'Def One',
        cfg: cfg,
      );
      expect(onlyVice, ['Choose a captain.']);
    });

    test('over budget renders the exact overage in money', () {
      // 7 × $8.0M = $56.0M against the $50.0M budget → $6.0M over.
      final out = issueSentences(
        slots: slots,
        slotPicks: fullPicks(price: 80),
        captainId: 'GK One',
        viceId: 'Def One',
        cfg: cfg,
      );
      expect(out, ["You're \$6.0M over budget."]);
    });

    test('a valid squad has no sentences', () {
      final out = issueSentences(
        slots: slots,
        slotPicks: fullPicks(),
        captainId: 'GK One',
        viceId: 'Def One',
        cfg: cfg,
      );
      expect(out, isEmpty);
    });
  });

  group('small helpers', () {
    test('pickerTitle', () {
      expect(pickerTitle(FantasyPosition.gk), 'Pick a goalkeeper');
      expect(pickerTitle(FantasyPosition.def), 'Pick a defender');
      expect(pickerTitle(FantasyPosition.att), 'Pick an attacker');
    });

    test('pitchPerspective squeezes far rows toward the center, keeps the '
        'center and the near edge fixed (Task 2 trapezoid)', () {
      // Center column never moves.
      expect(pitchPerspective((x: 0.5, y: 0.0)).x, 0.5);
      expect(pitchPerspective((x: 0.5, y: 1.0)).x, 0.5);
      // The near (bottom) edge keeps its full spread…
      expect(pitchPerspective((x: 0.0, y: 1.0)).x, 0.0);
      expect(pitchPerspective((x: 1.0, y: 1.0)).x, 1.0);
      // …while the far (top) edge squeezes to pitchTopScale of it.
      expect(pitchPerspective((x: 0.0, y: 0.0)).x,
          closeTo(0.5 - 0.5 * pitchTopScale, 1e-9));
      expect(pitchPerspective((x: 1.0, y: 0.0)).x,
          closeTo(0.5 + 0.5 * pitchTopScale, 1e-9));
      // Rows squeeze monotonically: the same left-of-center fraction sits
      // wider (farther from center) on a nearer row.
      final gkRow = pitchPerspective((x: 1 / 3, y: 0.16)).x;
      final defRow = pitchPerspective((x: 1 / 3, y: 0.48)).x;
      expect(defRow, lessThan(gkRow));
      // y never changes — rows stay rows.
      expect(pitchPerspective((x: 0.2, y: 0.48)).y, 0.48);
    });

    test('initialsFor', () {
      expect(initialsFor('Dana Wall'), 'DW');
      expect(initialsFor('Pelé'), 'P');
      expect(initialsFor('  '), '?');
      expect(initialsFor('Jean Claude van Damme'), 'JD');
    });
  });

  // Squad hardening (audit I2/I3).
  group('integrity alert sentence', () {
    test('one issue, several issues (fixed order), unknown names dropped', () {
      expect(squadInvalidAlertText(gameweek: 3, issues: ['overBudget']),
          "Your Gameweek 3 team didn't count: over budget. "
          'Fix it before the next deadline.');
      expect(
          squadInvalidAlertText(gameweek: 4, issues: [
            'overBudget', 'duplicatePlayer', 'somethingNew', 'tooManyPlayers',
          ]),
          "Your Gameweek 4 team didn't count: too many players, duplicate "
          'player and over budget. Fix it before the next deadline.');
      expect(
          squadInvalidAlertText(
              gameweek: 2, issues: ['unknownPlayer', 'ineligiblePlayer']),
          "Your Gameweek 2 team didn't count: unknown player and ineligible "
          'player. Fix it before the next deadline.');
      expect(
          squadInvalidAlertText(
              gameweek: 5, issues: ['overBudget', 'tooManyStarters']),
          "Your Gameweek 5 team didn't count: too many starters and over "
          'budget. Fix it before the next deadline.');
    });

    test('no known issue / no gameweek still reads as a sentence', () {
      expect(squadInvalidAlertText(gameweek: 0, issues: const []),
          "Your team didn't count: it broke the squad rules. "
          'Fix it before the next deadline.');
    });
  });

  // FPL selling (spec §4): the sweep's over-budget preview.
  group('over-budget preview sentence', () {
    test('the exact copy, amount in the app money format', () {
      expect(
          squadOverBudgetPreviewText(overTenths: 10),
          "Your team is \$1.0M over budget after this week's price changes. "
          "Fix it before the deadline or this week won't count.");
      expect(
          squadOverBudgetPreviewText(overTenths: 5),
          "Your team is \$0.5M over budget after this week's price changes. "
          "Fix it before the deadline or this week won't count.");
    });

    test('no amount (0 / negative): the same sentence without one', () {
      for (final over in [0, -3]) {
        expect(
            squadOverBudgetPreviewText(overTenths: over),
            "Your team is over budget after this week's price changes. "
            "Fix it before the deadline or this week won't count.");
      }
    });
  });

  group('isSaveRefusedByRules', () {
    test('the database permission-denied (both platforms) is a refusal', () {
      expect(
          isSaveRefusedByRules(FirebaseException(
              plugin: 'firebase_database',
              code: 'permission-denied',
              message:
                  "Client doesn't have permission to access the desired data.")),
          isTrue);
      expect(isSaveRefusedByRules(StateError('PERMISSION_DENIED')), isTrue);
    });

    test('anything else is not (network, unknown)', () {
      expect(
          isSaveRefusedByRules(FirebaseException(
              plugin: 'firebase_database',
              code: 'unavailable',
              message: 'The service is currently unavailable.')),
          isFalse);
      expect(isSaveRefusedByRules(StateError('Not signed in')), isFalse);
      expect(isSaveRefusedByRules(Exception('timeout')), isFalse);
    });

    test('the locked copy (owner wording)', () {
      expect(
          squadSaveLockedMessage,
          "The deadline passed while you were editing — this week's team is "
          "locked. Your changes weren't saved.");
    });
  });
}
