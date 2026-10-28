import 'dart:async';
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
  _watchAwaitedUploads((_) => count += 1);
  return () => count;
}

/// The bytes of every upload AWAITED from here to the end of the test, in
/// the order they went up — each a copy, the upload still the engine's
/// ([countAwaitedUploads]). What a test reads of a picture it never holds:
/// a tile the store lets go before anything could ask for it.
List<Uint8List> keepAwaitedUploads() {
  final kept = <Uint8List>[];
  _watchAwaitedUploads((rgba) => kept.add(Uint8List.fromList(rgba)));
  return kept;
}

/// Holds every upload AWAITED from here to the end of the test until
/// [released] completes — each then carried out by the engine. Answers how
/// many have reached it so far: a raster a test needs in flight.
int Function() holdAwaitedUploads(Future<void> released) {
  var reached = 0;
  _watchAwaitedUploads((_) {
    reached += 1;
    return released;
  });
  return () => reached;
}

/// Stands in for the engine's upload until the end of the test: [seen]
/// hears each one's bytes — the upload waits for what it answers — and the
/// engine carries it out.
void _watchAwaitedUploads(FutureOr<void> Function(Uint8List rgba) seen) {
  late final Future<ui.Image> Function(
    Uint8List rgba, {
    required int width,
    required int height,
    int? targetWidth,
    int? targetHeight,
  })
  watching;
  watching =
      (rgba, {required width, required height, targetWidth, targetHeight}) async {
        await seen(rgba);
        // The engine's own upload, with the watch stood back in after it.
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
          debugRawRgbaUploader = watching;
        }
      };
  debugRawRgbaUploader = watching;
  addTearDown(() => debugRawRgbaUploader = null);
}
