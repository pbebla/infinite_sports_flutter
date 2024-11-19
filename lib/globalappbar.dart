import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/table.dart';

class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final double height;
  final PreferredSizeWidget? bottom;
  final Widget tableWidget;
  final Widget leaderboardWidget;
  const GlobalAppBar({super.key, required this.title, required this.height, this.bottom, required this.tableWidget, required this.leaderboardWidget});
  
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
        tableWidget,
        leaderboardWidget
      ],
      backgroundColor: Theme.of(context).colorScheme.primary,
      // Here we take the value from the MyHomePage object that was created by
      // the App.build method, and use it to set our appbar title.
      title: title,
      centerTitle: true,
      foregroundColor: Colors.white,
      bottom: bottom
    );
  }
  
  @override
  // TODO: implement preferredSize
  Size get preferredSize => Size.fromHeight(height);
}