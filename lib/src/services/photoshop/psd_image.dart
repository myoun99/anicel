import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/straight_rgba_image.dart';
import 'psd_reader.dart';

/// The bridge between the document reader and everything in the app that
/// already knows what to do with a `ui.Image`.
///
/// Every image entry point asks [looksLikePsdBytes] first and comes here if
/// the answer is yes, which is what makes a PSD behave like a PNG
/// everywhere — the cel bake, the brush tip, the media viewer, thumbnails.
/// The alternative was a PSD branch in each of them.
///
/// The parse runs OFF the UI isolate. A layout PSD is routinely a hundred
/// megabytes and the walk over its channels is not fast; on the main isolate
/// that is a frozen window, and this app's bar is that a tablet must not
/// stutter.
Future<ui.Image> decodePsdCompositeImage(Uint8List bytes) async {
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
  final completer = Completer<ui.Image>();
  decodeStraightRgbaImage(
    rgba: composite,
    width: document.width,
    height: document.height,
    onDecoded: completer.complete,
  );
  return completer.future;
}
