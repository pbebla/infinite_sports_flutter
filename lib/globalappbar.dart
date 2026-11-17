import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final double height;
  final PreferredSizeWidget? bottom;
  /// Optional shortcuts; null = no action in the bar.
  final Widget? tableWidget;
  final Widget? leaderboardWidget;
  const GlobalAppBar({super.key, required this.title, required this.height, this.bottom, this.tableWidget, this.leaderboardWidget});
  
  @override
  Widget build(BuildContext context) {
    return AppBar(
      // TRY THIS: Try changing the color here to a specific color (to
      // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
      // change color while the other colors stay the same.
      leading: Builder(
        builder: (context) {
          return IconButton(
            icon: const ImageIcon(AssetImage('assets/profile.png')),
            onPressed: () {
              Scaffold.of(mainScaffoldContext!).openDrawer();
            },);
        },
      ),
      actions: [
        if (tableWidget != null) tableWidget!,
        if (leaderboardWidget != null) leaderboardWidget!,
      ],
      // Here we take the value from the MyHomePage object that was created by
      // the App.build method, and use it to set our appbar title.
      title: title,
      centerTitle: true,
      bottom: bottom
    );
  }
  
  @override
  // TODO: implement preferredSize
  Size get preferredSize => Size.fromHeight(height);
}