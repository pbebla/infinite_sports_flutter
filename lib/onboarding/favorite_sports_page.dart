import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';

/// "What are you into?" — pick favorite sports/categories. Shown once after
/// signup and once to existing users who haven't answered. Choosing a category
/// subscribes its notifications (auto opt-in, opt-out later in settings).
/// Pops itself when done or skipped.
class FavoriteSportsPage extends StatefulWidget {
  const FavoriteSportsPage({super.key, this.initial = const {}});

  final Set<String> initial;

  @override
  State<FavoriteSportsPage> createState() => _FavoriteSportsPageState();
}

class _FavoriteSportsPageState extends State<FavoriteSportsPage> {
  late final Set<String> _selected = {...widget.initial};
  final _prefs = NotificationPrefs();
  bool _saving = false;

  IconData _iconFor(String category) {
    switch (category) {
      case 'Futsal':
      case 'Soccer':
        return Icons.sports_soccer;
      case 'Basketball':
        return Icons.sports_basketball;
      case 'Flag Football':
        return Icons.sports_football;
      case 'Volleyball':
        return Icons.sports_volleyball;
      case 'Pickleball':
        return Icons.sports_tennis;
      case 'Tournaments':
        return Icons.emoji_events;
      default:
        return Icons.celebration;
    }
  }

  Future<void> _finish({required bool save}) async {
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      if (save) await _prefs.setFavorites(_selected, uid: uid);
      if (uid != null) await _prefs.markAnswered(uid);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick your favorites'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _finish(save: false),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'What are you into?',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Choose the sports and events you care about. We\'ll keep you '
              'posted on games, schedules, and reminders — and nothing else. '
              'You can change these anytime in Settings.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final category in kNotificationCategories)
                  _CategoryTile(
                    label: category,
                    icon: _iconFor(category),
                    selected: _selected.contains(category),
                    onTap: () => setState(() {
                      if (!_selected.remove(category)) _selected.add(category);
                    }),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : () => _finish(save: true),
                  child: Text(
                    _selected.isEmpty ? 'Done' : 'Done (${_selected.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: scheme.onPrimary, size: 20),
          ],
        ),
      ),
    );
  }
}
