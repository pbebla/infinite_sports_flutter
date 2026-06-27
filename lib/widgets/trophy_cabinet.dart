import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/trophy_icons.dart';
import 'package:infinite_sports_flutter/model/award.dart';

class TrophyCabinet extends StatelessWidget {
  final List<Award> awards;

  const TrophyCabinet({super.key, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (awards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Text(
            'No trophies yet — go win some! 🏆',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.6),
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Trophy Cabinet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: awards.map((a) => _TrophyChip(award: a)).toList(),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _TrophyChip extends StatelessWidget {
  final Award award;

  const _TrophyChip({required this.award});

  String _formatDate(String raw) {
    // raw = MMDDYYYY (e.g. "08302026")
    if (raw.length == 8) {
      try {
        final month = raw.substring(0, 2);
        final day = raw.substring(2, 4);
        final year = raw.substring(4, 8);
        const monthNames = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final m = int.tryParse(month) ?? 0;
        final d = int.tryParse(day) ?? 0;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return '${monthNames[m]} $d, $year';
        }
      } catch (_) {}
    }
    return raw;
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final color = tierColor(award.tier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    isAssetIcon(award.icon)
                        ? trophyIconWidget(award.icon, size: 56)
                        : CircleAvatar(
                            radius: 28,
                            backgroundColor: color,
                            child: Icon(
                              trophyIconData(award.icon),
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        award.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (award.sport.isNotEmpty) ...[
                  _DetailRow(label: 'Sport', value: award.sport),
                  const SizedBox(height: 6),
                ],
                if (award.context.isNotEmpty) ...[
                  _DetailRow(label: 'Event', value: award.context),
                  const SizedBox(height: 6),
                ],
                if (award.date.isNotEmpty) ...[
                  _DetailRow(label: 'Date', value: _formatDate(award.date)),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = tierColor(award.tier);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha:0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isAssetIcon(award.icon)
                ? trophyIconWidget(award.icon, size: 44)
                : CircleAvatar(
                    radius: 22,
                    backgroundColor: color,
                    child: Icon(
                      trophyIconData(award.icon),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
            const SizedBox(height: 6),
            Text(
              award.name,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (award.context.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                award.context,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: onSurface.withValues(alpha:0.6),
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.5),
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
