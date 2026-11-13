import 'package:flutter/material.dart';

/// The app's one sport → Material icon mapping (profile career list, profile
/// "Last Team" card, calendar day sheet — release report #7 found the
/// calendar hard-coding a soccer ball for Flag Football).
IconData sportIcon(String sport) {
  final s = sport.toLowerCase();
  if (s.contains('basket')) return Icons.sports_basketball;
  if (s.contains('flag') || s.contains('football')) return Icons.sports_football;
  // Futsal, AFC San Jose, Soccer, or any tournament defaulting to soccer-style
  if (s.contains('futsal') || s.contains('afc') || s.contains('soccer')) {
    return Icons.sports_soccer;
  }
  // Tournaments / unknown
  return Icons.emoji_events;
}
