import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';

/// Counts the uploads that are AWAITED from here to the end of the test —
/// the decode round a tile waits when its picture is not made through the
/// door — each still carried out by the engine. Answers how many so far.
///
/// What tells the two roads of a compose apart: they make the same picture,
/// and only one of them waits for it.
int Function() countAwaitedUploads() {
  var count = 0;
  late final Future<ui.Image> Function(
    Uint8List rgba, {
    required int width,
    required int height,
    int? targetWidth,
    int? targetHeight,
  })
  counting;
  counting =
      (rgba, {required width, required height, targetWidth, targetHeight}) async {
        count += 1;
        // The engine's own upload, with the count stood back in after it.
        debugRawRgbaUploader = null;
        try {
          return await uploadRawRgba(
            rgba,
            width: width,
            height: height,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
          );
        } finally {
          debugRawRgbaUploader = counting;
        }
      };
  debugRawRgbaUploader = counting;
  addTearDown(() => debugRawRgbaUploader = null);
  return () => count;
}
