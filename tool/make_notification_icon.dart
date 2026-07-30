// One-off generator: builds the Android notification small icon from the
// transparent app logo. Android renders only the alpha channel (white tint),
// so the colored logo becomes a white silhouette in the status bar.
// Run: dart run tool/make_notification_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/infinitelarge_dark.png').readAsBytesSync())!;
  final corner = src.getPixel(0, 0);
  stdout.writeln('source ${src.width}x${src.height}, corner alpha=${corner.a} (0 = transparent: good)');
  if (corner.a != 0) {
    stderr.writeln('ERROR: background is not transparent — need a transparent logo.');
    exit(1);
  }
  // Trim the transparent margins so the glyph fills the icon box — the raw
  // logo has large built-in padding that made the status-bar icon look tiny.
  final trimmed = img.trim(src, mode: img.TrimMode.transparent);
  final side = trimmed.width > trimmed.height ? trimmed.width : trimmed.height;
  final square = img.Image(width: side, height: side, numChannels: 4);
  img.compositeImage(square, trimmed,
      dstX: (side - trimmed.width) ~/ 2, dstY: (side - trimmed.height) ~/ 2);
  // 96x96 = 24dp small icon at xxhdpi; Android scales for other densities.
  final resized = img.copyResize(square, width: 96, height: 96, interpolation: img.Interpolation.cubic);
  final out = File('android/app/src/main/res/drawable/ic_notification.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(resized));
  stdout.writeln('wrote ${out.path}');

  // Large icons: the full-color logo on a solid square (Robinhood-style),
  // shown as the big image on the right side of notifications. Two variants —
  // white square for light mode, black square for dark mode; the app picks
  // one at display time from the phone's theme.
  const largeSide = 256;
  final glyph = img.copyResize(trimmed, width: (largeSide * 0.78).round());
  for (final (suffix, r, g, b) in [('light', 255, 255, 255), ('dark', 0, 0, 0)]) {
    final large = img.Image(width: largeSide, height: largeSide, numChannels: 4);
    img.fill(large, color: img.ColorRgba8(r, g, b, 255));
    img.compositeImage(large, glyph,
        dstX: (largeSide - glyph.width) ~/ 2, dstY: (largeSide - glyph.height) ~/ 2);
    final out = File('android/app/src/main/res/drawable/ic_notification_large_$suffix.png')
      ..writeAsBytesSync(img.encodePng(large));
    stdout.writeln('wrote ${out.path}');
  }
}
