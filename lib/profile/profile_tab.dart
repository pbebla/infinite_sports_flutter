import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/widgets/trophy_cabinet.dart';

/// The "Profile" tab of the tabbed player profile.
///
/// Renders:
/// 1. A flexible **Info** card showing known biographical fields in a fixed
///    order, followed by any remaining unknown fields (excluding per-sport
///    `*Position` keys).
/// 2. [TrophyCabinet] below the info card.
///
/// [information] is the raw `Users/{uid}/Information` Firebase map; may be
/// null or empty. [awards] is the pre-loaded award list.
class ProfileTab extends StatelessWidget {
  final Map<dynamic, dynamic> information;
  final List<Award> awards;

  const ProfileTab({
    super.key,
    required this.information,
    required this.awards,
  });

  // Known fields shown in this exact order when present and non-empty.
  static const List<({String key, String label})> _knownFields = [
    (key: 'Height', label: 'Height'),
    (key: 'Weight', label: 'Weight'),
    (key: 'Age', label: 'Age'),
    (key: 'Foot', label: 'Preferred Foot'),
    (key: 'PreferredFoot', label: 'Preferred Foot'),
    (key: 'Hand', label: 'Preferred Hand'),
    (key: 'PreferredHand', label: 'Preferred Hand'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_hasAnyInfo()) _infoCard(context),
        TrophyCabinet(awards: awards),
      ],
    );
  }

  bool _hasAnyInfo() {
    if (information.isEmpty) return false;
    // True if at least one known field has a non-empty value, or there are
    // remaining unknown fields.
    return _resolvedRows().isNotEmpty;
  }

  /// Build the ordered list of (label, value) pairs to display.
  List<({String label, String value})> _resolvedRows() {
    final rows = <({String label, String value})>[];
    final usedKeys = <String>{};
    // Deduplicate known labels (Foot / PreferredFoot both map to the same
    // display row — show the first one that has a value).
    final shownLabels = <String>{};

    for (final field in _knownFields) {
      if (shownLabels.contains(field.label)) continue; // already shown
      final raw = information[field.key];
      final value = _stringify(raw);
      if (value.isNotEmpty) {
        rows.add((label: field.label, value: value));
        shownLabels.add(field.label);
      }
      usedKeys.add(field.key);
    }

    // Remaining keys: exclude *Position variants and already-used keys.
    for (final entry in information.entries) {
      final key = entry.key.toString();
      if (usedKeys.contains(key)) continue;
      if (key.endsWith('Position')) continue; // FutsalPosition, etc.
      final value = _stringify(entry.value);
      if (value.isEmpty) continue;
      rows.add((label: _humanize(key), value: value));
    }

    return rows;
  }

  static String _stringify(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    return s == 'null' || s == '0' ? '' : s;
  }

  /// Insert spaces before capital letters: `JerseySize` → `Jersey Size`.
  static String _humanize(String key) {
    return key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(0)}',
    ).trim();
  }

  Widget _infoCard(BuildContext context) {
    final rows = _resolvedRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INFO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 10),
            ...rows.map((r) => _InfoRow(label: r.label, value: r.value)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
