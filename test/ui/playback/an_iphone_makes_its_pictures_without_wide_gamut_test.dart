import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★AN iPHONE OR iPAD MAKES ITS PICTURES WITHOUT WIDE GAMUT (F-509-Q7,
/// user 2026-10-30).
///
/// With the key absent its engine renders with wide gamut, every picture in
/// a format `flutter_gpu` cannot size — and every frame is drawn as it
/// stands, no step written into its picture
/// (`FlutterGpuFramePictures.sizes`). Nothing on this workstation renders
/// that format, so the plist is the one place a key let go can be caught.
void main() {
  test('the iOS Info.plist turns wide gamut off', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(RegExp(r'<key>FLTEnableWideGamut</key>\s*<false/>')),
    );
  });
}
