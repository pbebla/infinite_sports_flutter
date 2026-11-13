import 'fantasy_config.dart';

int _snap(int tenths, FantasyConfig cfg) {
  final step = cfg.priceStepTenths;
  final snapped = ((tenths + step ~/ 2) ~/ step) * step;
  return snapped.clamp(cfg.priceMinTenths, cfg.priceMaxTenths);
}

/// Opening prices from a historical score per player (any comparable
/// aggregate — the caller computes fantasy-points-per-season from historical
/// stats). Percentile WITHIN the given group (callers pass one position at a
/// time) maps linearly onto [priceMin, priceMax], snapped to the step.
/// Rookies are absent here; the caller assigns cfg.rookiePriceTenths.
Map<String, int> openingPrices(Map<String, double> scoreByPlayer, FantasyConfig cfg) {
  if (scoreByPlayer.isEmpty) return {};
  final values = scoreByPlayer.values.toList()..sort();
  final lo = values.first, hi = values.last;
  final span = hi - lo;
  return scoreByPlayer.map((id, v) {
    final t = span == 0 ? 0.5 : (v - lo) / span;
    final tenths = cfg.priceMinTenths +
        ((cfg.priceMaxTenths - cfg.priceMinTenths) * t).round();
    return MapEntry(id, _snap(tenths, cfg));
  });
}

/// Monday repricing (spec §4): performance-based and position-relative.
/// Input: this gameweek's fantasy points for every eligible player of ONE
/// position (absent players included at their real score, usually 0).
/// A player [repriceGap]+ points above the position mean rises one step;
/// [repriceGap]+ below falls one step.
Map<String, int> repriceDeltas(Map<String, int> weekPoints, FantasyConfig cfg) {
  if (weekPoints.isEmpty) return {};
  final mean =
      weekPoints.values.fold<int>(0, (a, b) => a + b) / weekPoints.length;
  return weekPoints.map((id, pts) {
    var d = 0;
    if (pts >= mean + cfg.repriceGap) d = cfg.priceStepTenths;
    if (pts <= mean - cfg.repriceGap) d = -cfg.priceStepTenths;
    return MapEntry(id, d);
  });
}

int applyDelta(int priceTenths, int delta, FantasyConfig cfg) =>
    (priceTenths + delta).clamp(cfg.priceMinTenths, cfg.priceMaxTenths);
