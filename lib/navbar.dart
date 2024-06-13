import 'package:flutter/material.dart';
import 'package:flutter_application/login.dart';


class NavBar extends StatelessWidget {
  const NavBar({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        children: [
          ListTile(
            title: Center(child: Text("Log Out")),
            textColor: Colors.white,
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginPage()))
          ),
        ],
      ),
    );
  }
}