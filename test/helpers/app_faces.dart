import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:flutter/services.dart' show FontLoader;

/// Loads the app's own faces — BIZ UDPGothic and 나눔고딕, both weights,
/// by the names and files `AppTypography` declares (the ones `pubspec.yaml`
/// ships) — so a test measures text the way the app lays it out.
///
/// ⚠️flutter_test does not load the app's fonts. Without this every glyph is
/// measured in the test font, and a box that clips in BIZ UDPGothic can pass
/// (the colour readout's hex did: 56.5 wide in the app's face, 54 in the
/// box). Three tests loaded a face by hand before this one existed.
Future<void> loadTheAppFaces() async {
  for (final (family, files) in _faces) {
    final loader = FontLoader(family);
    for (final path in [files.regular, files.bold]) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

final _faces = [
  (AppTypography.bundledFamily, AppTypography.bundledFiles),
  (AppTypography.bundledFallback.single, AppTypography.bundledFallbackFiles),
];

/// The icon font from the Flutter SDK running this test: the tester sits
/// in `artifacts/engine/<platform>/`, the font in `artifacts/material_fonts/`.
Future<void> loadIcons() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final bytes = File(
    '${artifacts.path}/material_fonts/materialicons-regular.otf',
  ).readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}
