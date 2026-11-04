// The profile's stat strip (round 3, spec §4, owner mockup): the price in
// the same ink as the other numbers (colorScheme.onSurface — white on dark,
// black on light) with this week's move under it ("▲ $0.5M this week"
// green, "▼ $0.5M this week" red, "No change" muted, nothing before the
// first reprice), then Total pts, PPG and Owned %. Once the season is over
// (the league's `Finished` flag) there is no move line: a muted "Final
// price" sits under the price instead. "—" wherever the truth is "no data
// yet" (never a made-up 0 / 0.0).
//
// Live everywhere (Task 7): while the numbers include the gameweek being played
// ([FantasyProfileModel.live]) the shared LIVE pill sits at the top right of the
// card; the numbers themselves move in place.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_common.dart';

class FantasyProfileStatStrip extends StatelessWidget {
  const FantasyProfileStatStrip({
    super.key,
    required this.model,
    this.seasonFinished = false,
  });

  final FantasyProfileModel model;

  /// The season is over: "Final price" replaces the move line.
  final bool seasonFinished;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final move = seasonFinished ? null : model.moveText;
    final divider = VerticalDivider(
      width: 1,
      thickness: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );
    return Container(
      key: const ValueKey('profile_stat_strip'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: profileCardDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The numbers below are the in-progress gameweek's.
          if (model.live)
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: FantasyLivePill(key: ValueKey('profile_live_pill')),
              ),
            ),
          _numbers(context, scheme, move, divider),
        ],
      ),
    );
  }

  Widget _numbers(BuildContext context, ColorScheme scheme, String? move,
      VerticalDivider divider) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            // Wide enough that "▲ $0.5M this week" fits one line at 360px.
            flex: 17,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatMoneyTenths(model.priceTenths),
                    key: const ValueKey('profile_price'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (seasonFinished) ...[
                    const SizedBox(height: 3),
                    Text(
                      kFinalPriceLabel,
                      key: const ValueKey('profile_final_price'),
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (move != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      move,
                      key: const ValueKey('profile_move'),
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            profileMoveColor(context, model.latestMoveTenths),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          divider,
          Expanded(
            flex: 10,
            child: _StripCell(
                value: model.totalPointsText,
                label: 'Total pts',
                valueKey: 'profile_total'),
          ),
          divider,
          Expanded(
            flex: 8,
            child: _StripCell(
                value: model.ppgText, label: 'PPG', valueKey: 'profile_ppg'),
          ),
          divider,
          Expanded(
            flex: 9,
            child: _StripCell(
                value: model.ownedText,
                label: 'Owned',
                valueKey: 'profile_owned'),
          ),
        ],
      ),
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.value,
    required this.label,
    required this.valueKey,
  });

  final String value;
  final String label;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            key: ValueKey(valueKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
