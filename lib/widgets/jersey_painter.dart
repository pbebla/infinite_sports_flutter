import 'package:flutter/material.dart';

/// Jersey silhouette used by the team pages' jersey-color swatches
/// (tournament team page and the league team page — P2.1 Task A3 shared it
/// out of tournamentteamdetail.dart).
class JerseyPainter extends CustomPainter {
  final Color color;
  const JerseyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h * 0.2);
    path.lineTo(w * 0.25, h * 0.08);
    path.lineTo(w * 0.35, 0);
    path.lineTo(w * 0.5, h * 0.12);
    path.lineTo(w * 0.65, 0);
    path.lineTo(w * 0.75, h * 0.08);
    path.lineTo(w, h * 0.2);
    path.lineTo(w * 0.75, h * 0.38);
    path.lineTo(w * 0.75, h);
    path.lineTo(w * 0.25, h);
    path.lineTo(w * 0.25, h * 0.38);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant JerseyPainter old) => old.color != color;
}
