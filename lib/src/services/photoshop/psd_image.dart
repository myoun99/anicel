import 'dart:isolate';
import 'dart:typed_data';

import '../import/cel_picture.dart';
import 'psd_reader.dart';

/// The composite as a picture an import lays on cels: the pixels the reader
/// made, as they are ([PixelsPicture]) — never made one GPU image.
Future<CelPicture> decodePsdCompositePicture(Uint8List bytes) async {
  final composite = await readPsdComposite(bytes);
  return PixelsPicture(
    composite.rgba,
    width: composite.width,
    height: composite.height,
  );
}

/// The composite itself — the straight RGBA the reader produces, at the
/// document's own size: what an image entry point that asks
/// [looksLikePsdBytes] first reads a Photoshop document as — the cel bake
/// ([decodePsdCompositePicture]), the brush tip, the media viewer
/// ([PsdCompositeDocument]) — rather than a PSD branch in each.
///
/// The parse runs OFF the UI isolate. A layout PSD is routinely a hundred
/// megabytes and the walk over its channels is not fast; on the main isolate
/// that is a frozen window, and this app's bar is that a tablet must not
/// stutter. ↩️It was made a `ui.Image` for them too
/// (`decodePsdCompositeImage`, 「the bridge … to everything that already
/// knows what to do with a `ui.Image`」) until its last caller, the brush
/// tip, read these bytes as they are (관제 2026-11-11 18:47).
Future<({Uint8List rgba, int width, int height})> readPsdComposite(
  Uint8List bytes,
) async {
  final document = await Isolate.run(
    () => readPsdDocument(bytes, withLayers: false),
  );
  final composite = document.composite;
  if (composite == null) {
    // Photoshop only writes the composite when "Maximize Compatibility" is
    // on. Naming that is worth more than "could not open": the user can go
    // and re-save the file.
    throw const FormatException(
      'This Photoshop file was saved without a composite image.',
    );
  }
  return (rgba: composite, width: document.width, height: document.height);
}
