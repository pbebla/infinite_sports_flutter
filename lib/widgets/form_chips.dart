import 'package:flutter/material.dart';

/// W/D/L form chips, oldest → newest (feed from teamLeagueForm). Fixed
/// shades under white text — reads identically in light and dark mode.
class FormChips extends StatelessWidget {
  final List<String> form;
  final double size;

  const FormChips({super.key, required this.form, this.size = 20});

  Color _color(String result) {
    switch (result) {
      case 'W':
        return const Color(0xFF0A7D2C); // the live-clock green
      case 'L':
        return const Color(0xFFC62828); // material red 800
      default:
        return const Color(0xFF757575); // material grey 600
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final result in form)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _color(result),
                shape: BoxShape.circle,
              ),
              child: Text(
                result,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
