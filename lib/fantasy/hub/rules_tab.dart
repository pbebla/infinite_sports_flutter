// The Rules tab (P3a Task 3, spec §10a): the one obvious place players learn
// and re-check how everything works. EVERY number here renders from the live
// streamed FantasyConfig — the same object the engine scores with — so a
// tuned value updates this page by itself; it can never drift from reality.
// The worked transfer example literally calls the engine's transferCost().

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/transfers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/support/support_form_page.dart';

/// The Deadlines copy's margin before an early first game: "an hour" for the
/// default 60, otherwise whole minutes ("45 minutes").
String _kickoffMargin(int minutes) => switch (minutes) {
      60 => 'an hour',
      1 => '1 minute',
      _ => '$minutes minutes',
    };

class FantasyRulesTab extends StatelessWidget {
  const FantasyRulesTab({
    super.key,
    required this.configStates,
    this.initialState,
    this.gameweeks = const [],
    this.scheduleUnknown = false,
    this.onRetrySchedule,
    this.nowUtc,
    this.supportPageBuilder,
  });

  /// The live config stream (the hub hands FantasyService.watchConfig over);
  /// a changed config re-renders the whole page.
  final Stream<FantasyConfigState?> configStates;
  final FantasyConfigState? initialState;
  final List<Gameweek> gameweeks;

  /// The schedule read failed (FantasyScheduleFeed.scheduleUnknown, review 6
  /// I2): never "Locked" / "Season complete" from that empty list.
  final bool scheduleUnknown;

  /// Non-null once the schedule feed has given up: "Try again".
  final VoidCallback? onRetrySchedule;
  final DateTime Function()? nowUtc;

  /// Test seam replacing the real SupportFormPage push (whose default wiring
  /// reaches for FirebaseAuth/package_info) — mirrors
  /// `myTicketsPageBuilder` in support_form_page.dart.
  final Widget Function()? supportPageBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FantasyConfigState?>(
      initialData: initialState,
      stream: configStates,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();
        return _RulesBody(
            state: state,
            gameweeks: gameweeks,
            scheduleUnknown: scheduleUnknown,
            onRetrySchedule: onRetrySchedule,
            nowUtc: nowUtc,
            supportPageBuilder: supportPageBuilder);
      },
    );
  }
}

class _RulesBody extends StatelessWidget {
  const _RulesBody({
    required this.state,
    required this.gameweeks,
    required this.scheduleUnknown,
    this.onRetrySchedule,
    required this.nowUtc,
    required this.supportPageBuilder,
  });

  final FantasyConfigState state;
  final List<Gameweek> gameweeks;

  /// The schedule read failed (FantasyScheduleFeed.scheduleUnknown, review 6
  /// I2): never "Locked" / "Season complete" from that empty list.
  final bool scheduleUnknown;

  /// Non-null once the schedule feed has given up: "Try again".
  final VoidCallback? onRetrySchedule;
  final DateTime Function()? nowUtc;
  final Widget Function()? supportPageBuilder;

  FantasyConfig get cfg => state.config;

  @override
  Widget build(BuildContext context) {
    final extra1 = transferCost(
        used: cfg.freeTransfersPerWeek + 1,
        free: cfg.freeTransfersPerWeek,
        cfg: cfg);
    final extra2 = transferCost(
        used: cfg.freeTransfersPerWeek + 2,
        free: cfg.freeTransfersPerWeek,
        cfg: cfg);
    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        _Section(
          title: 'How to play',
          child: _Body(
            'Build a squad of ${cfg.squadSize} real league players within a '
            '${formatMoneyTenths(cfg.budgetTenths)} budget. '
            '${FantasyPosition.gk.count(cfg.startersGk)}, '
            '${FantasyPosition.def.count(cfg.startersDef)} and '
            '${FantasyPosition.att.count(cfg.startersAtt)} start; '
            '${FantasyPosition.def.count(cfg.benchDef)} and '
            '${FantasyPosition.att.count(cfg.benchAtt)} sit on your bench and '
            'normally score '
            '${cfg.benchFactorPercent}% of their points. Pick a captain — '
            'their points count ×${cfg.captainMultiplier} — and a '
            'vice-captain who wears the armband any week the captain does '
            'not play. Points come from what really happens on court, live '
            'during games.',
          ),
        ),
        _Section(
          title: 'Scoring',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScoringTable(cfg: cfg),
              const SizedBox(height: 10),
              const _Body(
                'A clean sheet is earned by being present for a game your '
                'team concedes 0 goals in — the same definition as the '
                'league\'s Clean Sheets stat.',
              ),
              const SizedBox(height: 8),
              // Spec §7 stand-in goalkeeper (owner-approved copy).
              const _Body(
                'Stepping in goal: if an outfield player plays goalkeeper '
                'for a game, his saves, clean sheet and goals conceded count '
                'as a goalkeeper\'s for that game; his goals and assists '
                'still count at his own position.',
              ),
            ],
          ),
        ),
        _Section(
          title: 'Bonus points — the published formula',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Body(
                'After every match the three best performers earn +3, +2 and '
                '+1 bonus points, ranked by a published score — no black '
                'box. Ties share the higher bonus. The weights:',
              ),
              const SizedBox(height: 10),
              _BpsWeightsWrap(bps: cfg.bps),
            ],
          ),
        ),
        _Section(
          title: 'Deadlines',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Body(
                'Each game day is one gameweek. Your team locks at '
                '${formatLockHour(cfg.lockHour)} league time '
                '(America/Los_Angeles) on game day — or '
                '${_kickoffMargin(state.schedule.minutesBeforeKickoff)} '
                'before that day\'s first game if it starts earlier — and '
                'reopens 24 hours later. The league can move a deadline; the '
                'countdown always shows the real one. Late joiners start '
                'scoring from their first completed gameweek.',
              ),
              const SizedBox(height: 12),
              FantasyDeadlineChip(
                gameweeks: gameweeks,
                lockOverride: state.lockOverride,
                nowUtc: nowUtc,
                scheduleUnknown: scheduleUnknown,
                onRetry: onRetrySchedule,
              ),
            ],
          ),
        ),
        _Section(
          title: 'Transfers',
          child: _Body(
            'Your first team is free: change it as much as you like until '
            'your first deadline. After that you get '
            '${cfg.freeTransfersPerWeek} free transfers each gameweek; '
            'unused ones bank up to ${cfg.maxBankedTransfers}. '
            'Every transfer beyond your free ones costs '
            '${pointsText(cfg.extraTransferCost, long: true)} off that '
            'week\'s score.\n\n'
            'Worked example: with ${cfg.freeTransfersPerWeek} free '
            'transfers, making ${cfg.freeTransfersPerWeek + 1} costs '
            '−${pointsText(extra1, long: true)} and making '
            '${cfg.freeTransfersPerWeek + 2} costs −$extra2.',
          ),
        ),
        _Section(
          title: 'Chips',
          child: Column(
            children: [
              _ChipRow(
                asset: 'assets/fantasy/chip_triple_captain.png',
                name: 'Triple Captain',
                effect:
                    'Your captain scores ×${cfg.tripleCaptainMultiplier} '
                    'that week instead of ×${cfg.captainMultiplier}.',
              ),
              _ChipRow(
                asset: 'assets/fantasy/chip_bench_boost.png',
                name: 'Bench Boost',
                effect: 'Your bench earns FULL points that week instead of '
                    '${cfg.benchFactorPercent}%.',
              ),
              const _ChipRow(
                asset: 'assets/fantasy/chip_wildcard.png',
                name: 'Wildcard',
                effect: 'Unlimited free transfers for a permanent rebuild.',
              ),
              const _ChipRow(
                asset: 'assets/fantasy/chip_free_hit.png',
                name: 'Free Hit',
                effect: 'Unlimited transfers for one week — your previous '
                    'squad returns afterwards.',
              ),
              const SizedBox(height: 6),
              // Set windows from the live config (P3b Task 6) — the same
              // values the chips row renders, never hard-coded.
              _Body(
                'One chip may be active per gameweek. You get two sets per '
                'season: Set 1 covers GW1–${cfg.chipSet1EndGw} and expires '
                'after GW${cfg.chipSet1EndGw} (unused chips do not carry '
                'over); Set 2 covers GW${cfg.chipSet1EndGw + 1} through the '
                'end of the season, playoffs included.',
              ),
            ],
          ),
        ),
        _Section(
          title: 'Prices',
          child: _Body(
            'Prices run ${formatMoneyTenths(cfg.priceMinTenths)} to '
            '${formatMoneyTenths(cfg.priceMaxTenths)} in '
            '${formatMoneyTenths(cfg.priceStepTenths)} steps. The morning '
            'after each game day, prices move on performance: score well '
            'compared with other players in YOUR position and your price '
            'rises one step; fall behind and it drops one. Brand-new players '
            'start around ${formatMoneyTenths(cfg.rookiePriceTenths)}.',
          ),
        ),
        // FPL selling rule — keep half of any rise (rounded down to $0.1M),
        // take the full drop. The server, builder, picker and market all
        // price a sale this way; the $8.0M / $9.0M / $7.0M figures are fixed
        // illustrative numbers, not config.
        const _Section(
          title: 'Selling',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Body(
                'You buy at today\'s price. When you sell, you keep half of '
                'any rise (rounded down to \$0.1M) and take the full drop.',
              ),
              SizedBox(height: 10),
              _Body(
                'Example: bought at \$8.0M, now \$9.0M → sells for \$8.5M. '
                'Bought at \$8.0M, now \$7.0M → sells for \$7.0M.',
              ),
              SizedBox(height: 10),
              _Body(
                'Changed your mind? Put a player you sold this week back '
                'before the deadline and the sale is undone — he keeps the '
                'price you paid and no transfer is used.',
              ),
              SizedBox(height: 10),
              _Body(
                'Prices change the morning after each game day. If a change '
                'puts your saved team over budget, you\'ll get a message so '
                'you can fix it before the deadline.',
              ),
            ],
          ),
        ),
        _Section(
          title: 'Auto-subs, captain & bench',
          child: _Body(
            'If a starter does not appear, the bench player of the same '
            'position automatically steps in and scores FULL points that '
            'week. Otherwise the bench scores ${cfg.benchFactorPercent}% of '
            'their points. If your captain does not appear, the '
            'vice-captain\'s points count ×${cfg.captainMultiplier} instead.',
          ),
        ),
        _Section(
          title: 'Eligibility',
          child: const _Body(
            'Guest players play real games and their real stats count, but '
            'they are not selectable in fantasy until the league promotes '
            'them — promoted players enter the market the next gameweek. '
            'Position reassignments by the league apply at the next unlock; '
            'if a change makes your squad invalid, you\'ll be flagged to '
            'fix it before the deadline.',
          ),
        ),
        _Section(
          title: 'FAQ',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Faq(
                q: 'I joined mid-season — am I behind forever?',
                a: 'Leaderboards also run per gameweek, so you can win any '
                    'week outright. Your season total starts from your first '
                    'completed gameweek.',
              ),
              _Faq(
                q: 'What if one of my players misses the game?',
                a: 'They score 0 and, if they started, your matching bench '
                    'player is auto-subbed in at full points.',
              ),
              _Faq(
                q: 'What if a match day is cancelled or voided?',
                a: 'If a whole game day is called off, that gameweek is '
                    'skipped as if it never happened: your team, transfers '
                    'and chips stay as you set them, no points hit is '
                    'charged, and teams reopen until the next game day\'s '
                    'deadline. If only some games are played, those count '
                    'that week and the rest count in the week they\'re '
                    'played. If games move onto a day that already has '
                    'games, that gameweek has both rounds — those teams play '
                    'twice. A voided gameweek scores nobody — no points '
                    'gained or lost, and chips played that week are '
                    'returned.',
              ),
            ],
          ),
        ),
        _FeedbackCard(supportPageBuilder: supportPageBuilder),
      ],
    );
  }
}

/// P3a feedback — the Rules tab's door into the in-app support form (spec
/// §10b): "Spotted an issue or have feedback? Tell us". Pushes the real
/// Help & Feedback form tagged with the Fantasy Hub as the origin screen.
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.supportPageBuilder});

  final Widget Function()? supportPageBuilder;

  void _open(BuildContext context) {
    final builder = supportPageBuilder ??
        () => const SupportFormPage(fromScreen: 'Fantasy Hub');
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => builder()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        key: const ValueKey('fantasy_rules_feedback'),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.support_agent, size: 22, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Spotted an issue or have feedback? Tell us',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section + text building blocks ─────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Scoring table (values straight from cfg.scoring) ───────────────────────

class _ScoringTable extends StatelessWidget {
  const _ScoringTable({required this.cfg});
  final FantasyConfig cfg;

  static String _signed(int v) {
    if (v == 0) return '—'; // — not applicable
    return v > 0 ? '+$v' : '−${-v}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ScoringRow row(FantasyPosition p) => cfg.scoring[p]!;

    final rows = <(String, String Function(ScoringRow))>[
      ('Plays (appearance)', (r) => _signed(r.plays)),
      ('Goal', (r) => _signed(r.goal)),
      ('Assist', (r) => _signed(r.assist)),
      ('Clean sheet', (r) => _signed(r.cleanSheet)),
      ('Every 2 saves', (r) => _signed(r.per2Saves)),
      ('Penalty save', (r) => _signed(r.penSave)),
      ('Penalty miss', (r) => _signed(r.penMiss)),
      ('Every 2 conceded', (r) => _signed(r.per2Conceded)),
      ('Yellow card', (r) => _signed(r.yellow)),
      ('Red card', (r) => _signed(r.red)),
      ('Own goal', (r) => _signed(r.ownGoal)),
      (
        'Defensive plays',
        (r) => r.dplThreshold == null || r.dplBonus == 0
            ? '—'
            : '${r.dplThreshold}+ → +${r.dplBonus}'
      ),
    ];

    TextStyle head = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );
    TextStyle cell = TextStyle(
      fontSize: 12.5,
      color: scheme.onSurfaceVariant,
    );

    Widget valueCell(String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(s, textAlign: TextAlign.center, style: cell),
        );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4), width: 0.5),
      ),
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Action', style: head),
            ),
            for (final p in FantasyPosition.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child:
                    Text(p.short, textAlign: TextAlign.center, style: head),
              ),
          ],
        ),
        for (final (label, value) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label, style: cell),
              ),
              for (final p in FantasyPosition.values) valueCell(value(row(p))),
            ],
          ),
      ],
    );
  }
}

// ── BPS weights (the published formula, spec §7) ───────────────────────────

class _BpsWeightsWrap extends StatelessWidget {
  const _BpsWeightsWrap({required this.bps});
  final BpsWeights bps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <(String, int)>[
      ('Goal', bps.goal),
      ('Assist', bps.assist),
      ('Save', bps.save),
      ('Defensive play', bps.dpl),
      ('Clean sheet', bps.cleanSheet),
      ('Penalty save', bps.penSave),
      ('Penalty miss', bps.penMiss),
      ('Own goal', bps.ownGoal),
      ('Yellow', bps.yellow),
      ('Red', bps.red),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, v) in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$label ${v >= 0 ? '+$v' : '−${-v}'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// ── Chips + FAQ rows ───────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  const _ChipRow(
      {required this.asset, required this.name, required this.effect});
  final String asset;
  final String name;
  final String effect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(asset, width: 36, height: 36, fit: BoxFit.contain),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  effect,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.q, required this.a});
  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            a,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
