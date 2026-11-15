import 'package:flutter/material.dart';

/// The registration status chip ("Paid" / "Payment pending" / "You owe $X"
/// / "Covered" / "No charge"), shared by the status page and the registration list. Green
/// for settled, orange for owing, in light and dark mode.
class RegistrationStatusChip extends StatelessWidget {
  const RegistrationStatusChip(
      {super.key, required this.paid, required this.label});

  final bool paid;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color background = paid
        ? (dark ? Colors.green.shade900 : Colors.green.shade100)
        : (dark ? Colors.orange.shade900 : Colors.orange.shade100);
    final Color foreground = paid
        ? (dark ? Colors.green.shade100 : Colors.green.shade900)
        : (dark ? Colors.orange.shade100 : Colors.orange.shade900);
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: foreground),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }
}
