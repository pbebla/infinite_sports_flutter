import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/widgets/glass_surface.dart';

class GlassNavDestination {
  const GlassNavDestination({required this.icon, this.selectedIcon, required this.label});
  final Widget icon;
  final Widget? selectedIcon;
  final String label;
}

/// Floating frosted pill of tab destinations plus a detached round search
/// button (FotMob-style). Designed for the Scaffold.bottomNavigationBar slot
/// with extendBody: true so page content scrolls and blurs underneath.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSearchTap,
  });

  final List<GlassNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSearchTap;

  static const double _barHeight = 62;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unselected = scheme.onSurface.withOpacity(0.65);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? bottomInset : 10),
      child: Row(
        children: [
          Expanded(
            child: GlassSurface(
              borderRadius: const BorderRadius.all(Radius.circular(31)),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.all(Radius.circular(31)),
                            onTap: () => onDestinationSelected(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconTheme(
                                  data: IconThemeData(
                                    size: 24,
                                    color: i == selectedIndex ? scheme.primary : unselected,
                                  ),
                                  child: (i == selectedIndex
                                          ? destinations[i].selectedIcon
                                          : null) ??
                                      destinations[i].icon,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  destinations[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == selectedIndex
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: i == selectedIndex ? scheme.primary : unselected,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(31)),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(31)),
                onTap: onSearchTap,
                child: SizedBox(
                  width: _barHeight,
                  height: _barHeight,
                  child: Icon(Icons.search, size: 26, color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
