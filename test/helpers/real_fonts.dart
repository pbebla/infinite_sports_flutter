// Real text metrics for widget tests. The test environment draws every glyph
// as an Ahem square, which says nothing about whether a label really fits
// (and renders captured images as blocks). These register the Flutter SDK's
// own Roboto (as 'RobotoReal', so a test opts in without disturbing Ahem
// layouts elsewhere) and Material Icons. Each returns false when the SDK's
// material_fonts folder can't be found (the caller then skips).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

const String kRealFont = 'RobotoReal';
bool? _realFontLoaded;
bool? _iconsLoaded;

Directory? _materialFontsDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) candidates.add('$root/bin/cache/artifacts/material_fonts');
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    candidates.add('${dir.path}/material_fonts');
    dir = dir.parent;
  }
  for (final path in candidates) {
    final d = Directory(path);
    if (File('${d.path}/roboto-regular.ttf').existsSync()) return d;
  }
  return null;
}

Future<bool> loadRealFont() async {
  if (_realFontLoaded != null) return _realFontLoaded!;
  final dir = _materialFontsDir();
  if (dir == null) return _realFontLoaded = false;
  final loader = FontLoader(kRealFont);
  for (final file in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf'
  ]) {
    final bytes = File('${dir.path}/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  return _realFontLoaded = true;
}

/// Registers the SDK's Material Icons font so Icon glyphs render in captured
/// images (otherwise they are Ahem boxes too).
Future<bool> loadMaterialIconsFont() async {
  if (_iconsLoaded != null) return _iconsLoaded!;
  final dir = _materialFontsDir();
  final file =
      dir == null ? null : File('${dir.path}/materialicons-regular.otf');
  if (file == null || !file.existsSync()) return _iconsLoaded = false;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
  return _iconsLoaded = true;
}

/// A system font with the symbol glyphs Roboto lacks here (▲ ▼ →), for
/// faithful image previews — registered as [kSymbolsFallbackFont]. On a
/// phone the OS supplies these; the test engine has no fallback of its own.
const String kSymbolsFallbackFont = 'SymbolsFallback';
bool? _symbolsLoaded;

Future<bool> loadSymbolsFallbackFont() async {
  if (_symbolsLoaded != null) return _symbolsLoaded!;
  const candidates = [
    'C:/Windows/Fonts/seguisym.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Apple Symbols.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader(kSymbolsFallbackFont)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
    return _symbolsLoaded = true;
  }
  return _symbolsLoaded = false;
}
