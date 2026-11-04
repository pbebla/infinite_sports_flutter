// Paint-pattern helpers for the rank chart's end point.
//
// `paints..circle(...)` insists that the FIRST drawCircle call it meets match
// its arguments, so asking "is there a ring somewhere?" with it fails on the
// chart's solid dots that come first — and `isNot(paints..circle(...))` would
// pass for the wrong reason. These scan instead (`something`), so both the
// positive and the negated form say exactly what they mean.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isCircle(Symbol method) => method == #drawCircle;

bool _near(Offset a, Offset b) => (a - b).distance < 0.01;

/// The chart painted a HOLLOW ring: a stroked circle of [strokeWidth] with
/// the given [radius] — optionally at [center] and in [color].
PaintPattern paintsHollowRing({
  double radius = 5,
  double strokeWidth = 2,
  Offset? center,
  Color? color,
}) =>
    paints
      ..something((Symbol method, List<dynamic> args) {
        if (!_isCircle(method)) return false;
        final paint = args[2] as Paint;
        return paint.style == PaintingStyle.stroke &&
            paint.strokeWidth == strokeWidth &&
            (args[1] as double) == radius &&
            (center == null || _near(args[0] as Offset, center)) &&
            (color == null || paint.color.toARGB32() == color.toARGB32());
      });

/// The chart painted a SOLID (filled) circle at [center].
PaintPattern paintsSolidDotAt(Offset center, {double? radius}) => paints
  ..something((Symbol method, List<dynamic> args) {
    if (!_isCircle(method)) return false;
    final paint = args[2] as Paint;
    return paint.style == PaintingStyle.fill &&
        _near(args[0] as Offset, center) &&
        (radius == null || (args[1] as double) == radius);
  });

/// The chart painted NO stroked circle at all (nothing hollow).
Matcher paintsNoRing() => isNot(paints
  ..something((Symbol method, List<dynamic> args) =>
      _isCircle(method) && (args[2] as Paint).style == PaintingStyle.stroke));
