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
///
/// [firstWeek]: the week just finished was the manager's FIRST team. Building
/// it cost nothing, so there is no unused allowance to carry — he starts the
/// next week on the plain weekly grant, whatever the stored Free says (without
/// this a GW1 manager opened GW2 with 4, a bank he never earned). Not "no
/// squad last week": a manager who deletes and rebuilds a squad inside an open
/// week still has the week before's locked squad (callers decide firstWeek
/// from that).
int rolloverFreeTransfers(
    {required int free,
    required int used,
    required FantasyConfig cfg,
    bool unlimited = false,
    bool firstWeek = false}) {
  if (firstWeek) return cfg.freeTransfersPerWeek;
  final remaining = unlimited ? free : (free - used).clamp(0, free);
  return (remaining + cfg.freeTransfersPerWeek)
      .clamp(0, cfg.maxBankedTransfers);
}
