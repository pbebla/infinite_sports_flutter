import 'package:flutter/material.dart';

/// The app's one sport → Material icon mapping (profile career list, profile
/// "Last Team" card, calendar day sheet, onboarding favourite-sports picker —
/// release report #7 found the calendar hard-coding a soccer ball for Flag
/// Football). Null when [sport] is not a sport this app knows.
IconData? sportIconOrNull(String sport) {
  final s = sport.toLowerCase();
  if (s.contains('basket')) return Icons.sports_basketball;
  if (s.contains('flag') || s.contains('football')) return Icons.sports_football;
  if (s.contains('volley')) return Icons.sports_volleyball;
  if (s.contains('pickle')) return Icons.sports_tennis;
  // Futsal, AFC San Jose, Soccer.
  if (s.contains('futsal') || s.contains('afc') || s.contains('soccer')) {
    return Icons.sports_soccer;
  }
  return null;
}

/// [sportIconOrNull] with a trophy for tournaments / anything unknown.
IconData sportIcon(String sport) => sportIconOrNull(sport) ?? Icons.emoji_events;
