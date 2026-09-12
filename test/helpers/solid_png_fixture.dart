import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Writes a [width]×[height] PNG filled with one [rgba] colour into
/// [directory] and returns its path: a real picture on disk for the import
/// doors to take.
///
/// 🚨★★★THE ONE PNG FIXTURE. Fourteen test files each ran this same encode —
/// build RGBA bytes · `decodeImageFromPixels` · `toByteData(png)` · write —
/// and they differed only in the three things named here.
///
/// ⛔THE PARAMETERS EXIST SO THE DIFFERENCE STAYS VISIBLE AT THE CALL SITE.
/// Folding a fixture's size or colour into one default is how a test quietly
/// stops measuring what it was written for — 실측 2026-09-09: a bulk
/// conversion that collapsed per-case coordinates onto one helper compiled
/// green and measured the wrong thing. A caller that needs 16×16 says 16×16.
///
/// ⚠️Call it inside `tester.runAsync` — the encoder is real async work.
/// ⚠️[rgba] packs ALL FOUR channels, alpha last: `0xAAAAAAAA` is the
/// half-transparent grey the import windows use, `0x000000FF` opaque black,
/// `0x00000000` the fully open pixel the preview's checker test needs.
Future<String> writeSolidPng(
  Directory directory,
  String name, {
  int width = 8,
  int height = 8,
  int rgba = 0x3366FFFF,
}) async {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = (rgba >> 24) & 0xFF;
    pixels[i + 1] = (rgba >> 16) & 0xFF;
    pixels[i + 2] = (rgba >> 8) & 0xFF;
    pixels[i + 3] = rgba & 0xFF;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  // Some callers name a nested path; creating an existing directory is a
  // no-op, so this costs the others nothing.
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}
