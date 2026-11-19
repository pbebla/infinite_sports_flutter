/// Every tunable number in Infinite Fantasy. Values live in RTDB at
/// `Fantasy/<sport>/<season>/Config`; this default IS the futsal launch config
/// and the Rules page renders from the same object (spec §10a).
library;

enum FantasyPosition {
  gk,
  def,
  att;

  String get db => switch (this) { gk => 'GK', def => 'DEF', att => 'ATT' };

  // ── Display vocabulary (release report #11) ─────────────────────────────
  // The ONE source of every fantasy position word shown to a fan. The
  // fantasy group is NOT the player's own playing position (registration's
  // "Striker" etc. — see misc/playing_position.dart); never mix the two.
  // Display only: [db] stays the stored key.

  /// Chips, filters, table cells and badges: GK / DEF / ATT.
  String get short => switch (this) { gk => 'GK', def => 'DEF', att => 'ATT' };

  /// Where a full word is spelled out (headings): Goalkeeper / Defender /
  /// Attacker.
  String get long => switch (this) {
        gk => 'Goalkeeper',
        def => 'Defender',
        att => 'Attacker',
      };

  /// Goalkeepers / Defenders / Attackers.
  String get longPlural => '${long}s';

  /// The same word inside a sentence: goalkeeper / defender / attacker.
  String get noun => long.toLowerCase();

  /// goalkeepers / defenders / attackers.
  String get nounPlural => '${noun}s';

  /// "a goalkeeper" / "a defender" / "an attacker".
  String get withArticle => this == att ? 'an $noun' : 'a $noun';

  /// "1 goalkeeper", "2 defenders".
  String count(int n) => '$n ${n == 1 ? noun : nounPlural}';

  /// Outside the Fantasy hub (profile, league game, search) and next to a
  /// playing position: "Fantasy: ATT", so it can't pass for the position a
  /// player plays.
  String get fantasyTag => 'Fantasy: $short';

  static FantasyPosition parse(String s) => switch (s) {
        'GK' => gk,
        'DEF' => def,
        'ATT' => att,
        _ => throw ArgumentError('Unknown fantasy position: $s'),
      };
}

class ScoringRow {
  const ScoringRow({
    required this.plays,
    required this.goal,
    required this.assist,
    required this.cleanSheet,
    required this.per2Saves,
    required this.penSave,
    required this.penMiss,
    required this.per2Conceded,
    required this.yellow,
    required this.red,
    required this.ownGoal,
    this.dplThreshold,
    this.dplBonus = 0,
  });

  final int plays, goal, assist, cleanSheet, per2Saves, penSave, penMiss;
  final int per2Conceded, yellow, red, ownGoal;
  final int? dplThreshold;
  final int dplBonus;

  Map<String, dynamic> toMap() => {
        'plays': plays, 'goal': goal, 'assist': assist,
        'cleanSheet': cleanSheet, 'per2Saves': per2Saves,
        'penSave': penSave, 'penMiss': penMiss,
        'per2Conceded': per2Conceded, 'yellow': yellow, 'red': red,
        'ownGoal': ownGoal,
        if (dplThreshold != null) 'dplThreshold': dplThreshold,
        'dplBonus': dplBonus,
      };

  static ScoringRow fromMap(Map m, ScoringRow fallback) => ScoringRow(
        plays: _i(m['plays'], fallback.plays),
        goal: _i(m['goal'], fallback.goal),
        assist: _i(m['assist'], fallback.assist),
        cleanSheet: _i(m['cleanSheet'], fallback.cleanSheet),
        per2Saves: _i(m['per2Saves'], fallback.per2Saves),
        penSave: _i(m['penSave'], fallback.penSave),
        penMiss: _i(m['penMiss'], fallback.penMiss),
        per2Conceded: _i(m['per2Conceded'], fallback.per2Conceded),
        yellow: _i(m['yellow'], fallback.yellow),
        red: _i(m['red'], fallback.red),
        ownGoal: _i(m['ownGoal'], fallback.ownGoal),
        dplThreshold: m['dplThreshold'] == null
            ? fallback.dplThreshold
            : _i(m['dplThreshold'], 0),
        dplBonus: _i(m['dplBonus'], fallback.dplBonus),
      );
}

int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

/// Weights for the published bonus-points formula (spec §7).
class BpsWeights {
  const BpsWeights({
    this.goal = 12, this.assist = 9, this.save = 2, this.dpl = 2,
    this.cleanSheet = 5, this.penSave = 8, this.penMiss = -6,
    this.ownGoal = -8, this.yellow = -4, this.red = -9,
  });
  final int goal, assist, save, dpl, cleanSheet, penSave, penMiss;
  final int ownGoal, yellow, red;

  Map<String, dynamic> toMap() => {
        'goal': goal, 'assist': assist, 'save': save, 'dpl': dpl,
        'cleanSheet': cleanSheet, 'penSave': penSave, 'penMiss': penMiss,
        'ownGoal': ownGoal, 'yellow': yellow, 'red': red,
      };
  static BpsWeights fromMap(Map m) {
    const d = BpsWeights();
    return BpsWeights(
      goal: _i(m['goal'], d.goal), assist: _i(m['assist'], d.assist),
      save: _i(m['save'], d.save), dpl: _i(m['dpl'], d.dpl),
      cleanSheet: _i(m['cleanSheet'], d.cleanSheet),
      penSave: _i(m['penSave'], d.penSave),
      penMiss: _i(m['penMiss'], d.penMiss),
      ownGoal: _i(m['ownGoal'], d.ownGoal),
      yellow: _i(m['yellow'], d.yellow), red: _i(m['red'], d.red),
    );
  }
}

class FantasyConfig {
  const FantasyConfig({
    required this.scoring,
    required this.bps,
    required this.budgetTenths,
    required this.priceMinTenths,
    required this.priceMaxTenths,
    required this.priceStepTenths,
    required this.rookiePriceTenths,
    required this.repriceGap,
    required this.freeTransfersPerWeek,
    required this.maxBankedTransfers,
    required this.extraTransferCost,
    required this.lockHour,
    required this.benchFactorPercent,
    required this.captainMultiplier,
    required this.tripleCaptainMultiplier,
    required this.chipSet1EndGw,
    required this.startersGk,
    required this.startersDef,
    required this.startersAtt,
    required this.benchDef,
    required this.benchAtt,
  });

  final Map<FantasyPosition, ScoringRow> scoring;
  final BpsWeights bps;
  final int budgetTenths, priceMinTenths, priceMaxTenths, priceStepTenths;
  final int rookiePriceTenths;
  /// Points above/below the position's gameweek mean that move a price ±1 step.
  final int repriceGap;
  final int freeTransfersPerWeek, maxBankedTransfers, extraTransferCost;
  final int lockHour; // league-local (Task 1)
  final int benchFactorPercent; // 50 = half points
  final int captainMultiplier, tripleCaptainMultiplier;

  /// Last gameweek of chip set 1 (owner decision: GW1–6, then set 2 runs
  /// GW7 through the playoffs). Set 1's unused chips do not carry over.
  final int chipSet1EndGw;
  final int startersGk, startersDef, startersAtt, benchDef, benchAtt;

  int get squadSize =>
      startersGk + startersDef + startersAtt + benchDef + benchAtt;

  factory FantasyConfig.futsalDefault() => FantasyConfig(
        scoring: {
          FantasyPosition.gk: const ScoringRow(
              plays: 1, goal: 10, assist: 5, cleanSheet: 8, per2Saves: 1,
              penSave: 5, penMiss: -2, per2Conceded: -1, yellow: -1,
              red: -3, ownGoal: -2),
          FantasyPosition.def: const ScoringRow(
              plays: 1, goal: 6, assist: 4, cleanSheet: 5, per2Saves: 0,
              penSave: 0, penMiss: -2, per2Conceded: -1, yellow: -1,
              red: -3, ownGoal: -2, dplThreshold: 5, dplBonus: 2),
          FantasyPosition.att: const ScoringRow(
              plays: 1, goal: 4, assist: 3, cleanSheet: 2, per2Saves: 0,
              penSave: 0, penMiss: -2, per2Conceded: 0, yellow: -1,
              red: -3, ownGoal: -2, dplThreshold: 7, dplBonus: 2),
        },
        bps: const BpsWeights(),
        budgetTenths: 500,
        priceMinTenths: 40,
        priceMaxTenths: 150,
        priceStepTenths: 5,
        rookiePriceTenths: 60,
        repriceGap: 4,
        freeTransfersPerWeek: 2,
        maxBankedTransfers: 7,
        extraTransferCost: 4,
        lockHour: 15,
        benchFactorPercent: 50,
        captainMultiplier: 2,
        tripleCaptainMultiplier: 3,
        chipSet1EndGw: 6,
        startersGk: 1,
        startersDef: 2,
        startersAtt: 2,
        benchDef: 1,
        benchAtt: 1,
      );

  Map<String, dynamic> toMap() => {
        'scoring': {for (final e in scoring.entries) e.key.db: e.value.toMap()},
        'bps': bps.toMap(),
        'budgetTenths': budgetTenths,
        'priceMinTenths': priceMinTenths,
        'priceMaxTenths': priceMaxTenths,
        'priceStepTenths': priceStepTenths,
        'rookiePriceTenths': rookiePriceTenths,
        'repriceGap': repriceGap,
        'freeTransfersPerWeek': freeTransfersPerWeek,
        'maxBankedTransfers': maxBankedTransfers,
        'extraTransferCost': extraTransferCost,
        'lockHour': lockHour,
        'benchFactorPercent': benchFactorPercent,
        'captainMultiplier': captainMultiplier,
        'tripleCaptainMultiplier': tripleCaptainMultiplier,
        'chipSet1EndGw': chipSet1EndGw,
        'startersGk': startersGk,
        'startersDef': startersDef,
        'startersAtt': startersAtt,
        'benchDef': benchDef,
        'benchAtt': benchAtt,
      };

  static FantasyConfig fromMap(Map m) {
    final d = FantasyConfig.futsalDefault();
    final rawScoring = m['scoring'];
    return FantasyConfig(
      scoring: {
        for (final p in FantasyPosition.values)
          p: rawScoring is Map && rawScoring[p.db] is Map
              ? ScoringRow.fromMap(rawScoring[p.db] as Map, d.scoring[p]!)
              : d.scoring[p]!,
      },
      bps: m['bps'] is Map ? BpsWeights.fromMap(m['bps'] as Map) : d.bps,
      budgetTenths: _i(m['budgetTenths'], d.budgetTenths),
      priceMinTenths: _i(m['priceMinTenths'], d.priceMinTenths),
      priceMaxTenths: _i(m['priceMaxTenths'], d.priceMaxTenths),
      priceStepTenths: _i(m['priceStepTenths'], d.priceStepTenths),
      rookiePriceTenths: _i(m['rookiePriceTenths'], d.rookiePriceTenths),
      repriceGap: _i(m['repriceGap'], d.repriceGap),
      freeTransfersPerWeek:
          _i(m['freeTransfersPerWeek'], d.freeTransfersPerWeek),
      maxBankedTransfers: _i(m['maxBankedTransfers'], d.maxBankedTransfers),
      extraTransferCost: _i(m['extraTransferCost'], d.extraTransferCost),
      lockHour: _i(m['lockHour'], d.lockHour),
      benchFactorPercent: _i(m['benchFactorPercent'], d.benchFactorPercent),
      captainMultiplier: _i(m['captainMultiplier'], d.captainMultiplier),
      tripleCaptainMultiplier:
          _i(m['tripleCaptainMultiplier'], d.tripleCaptainMultiplier),
      chipSet1EndGw: _i(m['chipSet1EndGw'], d.chipSet1EndGw),
      startersGk: _i(m['startersGk'], d.startersGk),
      startersDef: _i(m['startersDef'], d.startersDef),
      startersAtt: _i(m['startersAtt'], d.startersAtt),
      benchDef: _i(m['benchDef'], d.benchDef),
      benchAtt: _i(m['benchAtt'], d.benchAtt),
    );
  }
}
