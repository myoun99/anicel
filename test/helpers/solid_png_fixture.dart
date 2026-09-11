import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Writes an 8×8 opaque PNG of one colour into [directory] and returns its
/// path: a real picture on disk for the import doors to take.
///
/// ⚠️Call it inside `tester.runAsync` — the encoder is real async work.
Future<String> writeSolidPng(Directory directory, String name) async {
  const side = 8;
  final pixels = Uint8List(side * side * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0x33;
    pixels[i + 1] = 0x66;
    pixels[i + 2] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}
