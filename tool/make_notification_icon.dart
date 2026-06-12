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
  // 96x96 = 24dp small icon at xxhdpi; Android scales for other densities.
  final resized = img.copyResize(src, width: 96, height: 96, interpolation: img.Interpolation.cubic);
  final out = File('android/app/src/main/res/drawable/ic_notification.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(resized));
  stdout.writeln('wrote ${out.path}');
}
