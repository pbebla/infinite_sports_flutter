import 'package:flutter/material.dart';

/// A shimmering grey placeholder block. Animates on its own; drop several into
/// a column shaped like the real content while data loads.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.white12
        : Colors.black12;
    final hi = Theme.of(context).brightness == Brightness.dark
        ? Colors.white24
        : Colors.black26;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * _c.value, 0),
                end: Alignment(1 - 2 * _c.value, 0),
                colors: [base, hi, base],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A skeleton placeholder shaped like a match-list row.
class SkeletonMatchRow extends StatelessWidget {
  const SkeletonMatchRow({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          const SkeletonBox(width: 30, height: 30, radius: 15),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 120, height: 11),
                SizedBox(height: 7),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
          const SkeletonBox(width: 26, height: 26),
        ],
      ),
    );
  }
}

/// A column of [count] skeleton match rows separated by dividers.
class SkeletonMatchList extends StatelessWidget {
  final int count;
  const SkeletonMatchList({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 1),
          child: SkeletonMatchRow(),
        ),
      ),
    );
  }
}
