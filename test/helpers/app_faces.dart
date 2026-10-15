import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:flutter/services.dart' show FontLoader, rootBundle;

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

/// The icon font as this test's own asset bundle carries it — the copy the
/// tool puts there for `uses-material-design`, by the name the tool gives
/// it.
///
/// ↩️It was read from the SDK's cache beside the tester, as
/// `artifacts/material_fonts/materialicons-regular.otf`: Windows and macOS
/// found it, and Linux CI had no such file (PR #1481, 10-15).
Future<void> loadIcons() async {
  final loader = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await loader.load();
}
