import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:intl/intl.dart';

/// Horizontal strip of tappable day boxes (DOW / MMM / day number) —
/// extracted from TournamentDayView (P2.1) so the league Fixtures tab shows
/// the exact tournament Matches-tab date boxes. Renders nothing when there
/// is at most one day; centers the selected pill on first layout.
class DayPillStrip extends StatefulWidget {
  /// MMDDYYYY day keys in ascending calendar order.
  final List<String> days;
  final String selectedDay;
  final ValueChanged<String> onSelect;

  const DayPillStrip({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.onSelect,
  });

  @override
  State<DayPillStrip> createState() => _DayPillStripState();
}

class _DayPillStripState extends State<DayPillStrip> {
  // Pill box (52) + horizontal margin (4 each side) = 60 logical px per pill.
  static const double _pillExtent = 60;

  final ScrollController _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollSelectedIntoView();
    });
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  void _scrollSelectedIntoView() {
    if (!_stripController.hasClients) return;
    final index = widget.days.indexOf(widget.selectedDay);
    if (index < 0) return;
    final viewport = _stripController.position.viewportDimension;
    final target = (index * _pillExtent) - (viewport / 2) + (_pillExtent / 2);
    final max = _stripController.position.maxScrollExtent;
    _stripController.jumpTo(target.clamp(0.0, max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to switch between when there is a single day.
    if (widget.days.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 70,
      child: ListView.builder(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: widget.days.length,
        itemBuilder: (context, index) =>
            _buildPill(context, widget.days[index]),
      ),
    );
  }

  Widget _buildPill(BuildContext context, String day) {
    final selected = day == widget.selectedDay;
    final dt = parseDatabaseDate(day);
    final dow = dt != null ? DateFormat('EEE').format(dt).toUpperCase() : '';
    final month = dt != null ? DateFormat.MMM().format(dt).toUpperCase() : '';
    final dayNumber = dt != null ? DateFormat('d').format(dt) : day;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        if (day == widget.selectedDay) return;
        widget.onSelect(day);
      },
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? infiniteSportsPrimaryColor
              : onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dow,
              style: TextStyle(
                fontSize: 10,
                color:
                    selected ? Colors.white : onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              month,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color:
                    selected ? Colors.white : onSurface.withValues(alpha: 0.7),
              ),
            ),
            Text(
              dayNumber,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
