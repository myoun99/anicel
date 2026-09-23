import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// Loads the app UI's own faces — BIZ UDPGothic and 나눔고딕, both weights,
/// exactly as `pubspec.yaml` declares them — from the files the bundle
/// ships, so a test measures text the way the app lays it out.
///
/// ⚠️flutter_test does not load the app's fonts. Without this every glyph is
/// measured in the test font, and a box that clips in BIZ UDPGothic can pass
/// (the colour readout's hex did: 56.5 wide in the app's face, 54 in the
/// box). Three tests loaded a face by hand before this one existed.
Future<void> loadTheAppFaces() async {
  for (final (family, files) in _faces) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

const _faces = [
  ('BIZ UDPGothic', ['BIZUDPGothic-Regular.ttf', 'BIZUDPGothic-Bold.ttf']),
  ('Nanum Gothic', ['NanumGothic-Regular.ttf', 'NanumGothic-Bold.ttf']),
];
