import 'package:flutter/material.dart';

/// Presentational tier-accent colors shared by the public leaderboard's
/// tier badge chips (Task F6) and the public profile Insider box's diamond
/// icon (Task F7) — pure UI, not a model concern, hence living here rather
/// than in lib/model/insider.dart (which stays Flutter/Color-free for unit
/// testing, see that file's header comment).
///
/// Fixed hex accents (not scheme-derived) are intentional here — these are
/// brand/tier identifiers (like a medal color), not surface fills, so they
/// stay recognizable across light/dark. Callers use them as small
/// icon/chip-foreground accents against the ambient surface, never as a
/// full-bleed background behind body text, so contrast holds in both themes.
///
/// Tier 0 (an approved Insider who hasn't reached Bronze yet) gets a
/// neutral grey — no tier has been earned yet.
Color insiderTierColor(int tier) {
  switch (tier) {
    case 1:
      return const Color(0xFFCD7F32); // Bronze
    case 2:
      return const Color(0xFFAEB4BD); // Silver
    case 3:
      return const Color(0xFFFFC107); // Gold
    case 4:
      return const Color(0xFF8C9EFF); // Platinum (cool steel-blue)
    case 5:
      return const Color(0xFF9C6ADE); // Infinite (premium violet)
    default:
      return const Color(0xFF9E9E9E); // no tier yet
  }
}

/// Medal accent for a leaderboard RANK position (1st/2nd/3rd), distinct
/// from [insiderTierColor] — this is about finishing position on the
/// currently-filtered board, not the Insider's own tier. Returns null for
/// rank 4+ (no medal accent).
Color? rankMedalColor(int rank) {
  switch (rank) {
    case 1:
      return const Color(0xFFFFD700); // gold medal
    case 2:
      return const Color(0xFFC0C0C0); // silver medal
    case 3:
      return const Color(0xFFCD7F32); // bronze medal
    default:
      return null;
  }
}
