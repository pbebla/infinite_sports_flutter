import 'package:flutter/material.dart';

typedef Callback = void Function(int index);

class BotNavBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedIndex = 0;
  final Callback onIndexSelect;

  const BotNavBar({super.key, required this.onIndexSelect});
  
  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/scores.png')),
          label: 'Live Scores'),
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/leagues.png')),
          label: 'Leagues'),
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/leagues.png')),
          label: 'Season 11'),
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/aroundyou.png')),
          label: 'Around You'),
      ],
      selectedItemColor: Theme.of(context).colorScheme.primary,
      currentIndex: selectedIndex,
      onTap: onIndexSelect,
      ); // This trailing comma makes auto-formatting nicer for build methods.
  }
  
  @override
  // TODO: implement preferredSize
  Size get preferredSize => throw UnimplementedError();
}