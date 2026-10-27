import 'fantasy_config.dart';

/// Point cost of making [used] transfers with [free] available (spec §5).
/// Wildcard / Free Hit weeks ([unlimited]) are always free.
int transferCost(
    {required int used,
    required int free,
    required FantasyConfig cfg,
    bool unlimited = false}) {
  if (unlimited) return 0;
  final extra = used - free;
  return extra > 0 ? extra * cfg.extraTransferCost : 0;
}

/// Free transfers available next gameweek. Unused ones bank (cap 7); a
/// wildcard/free-hit week doesn't consume the bank.
int rolloverFreeTransfers(
    {required int free,
    required int used,
    required FantasyConfig cfg,
    bool unlimited = false}) {
  final remaining = unlimited ? free : (free - used).clamp(0, free);
  return (remaining + cfg.freeTransfersPerWeek)
      .clamp(0, cfg.maxBankedTransfers);
}
