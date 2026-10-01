@Tags(['benchmark'])
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// What an INVERSE costs on the wall of a 1920×1080 canvas — 5760×3240,
/// the box an inverse covers (I-23).
///
/// Two numbers, measured side by side in one run:
///
///   1. the ants: `pixelOutlineContours`, walked from each row's runs. It
///      used to allocate a mask over the selected box and read every byte
///      of it, and an inverse's box is the whole wall — ~18.7M bytes on
///      the paint thread before one ant was drawn.
///   2. `maskFor` over the same box — what a LIFT of the inverse still
///      pays, because the mask is the lift's input. This is the number the
///      ants no longer pay.
///
/// ⚠️READ THE RATIO, NOT THE MILLISECONDS: this machine runs other lanes'
/// gates, and only two things measured in one run compare.
///
/// Prints; asserts only that the work happened. Run it alone.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);
  final wall = canvas.pasteboardRect;

  /// A fresh inverse per call: the contours are memoised on the region, so
  /// timing one region twice would time a field read.
  CanvasSelectionRegion inverse() => CanvasSelectionRegion.invertedWithin(
    CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(
        left: 300.3,
        top: 200.7,
        right: 1500.4,
        bottom: 900.2,
      ),
    ),
    wall,
  )!;

  /// The median of [runs] timed calls, after one untimed warm-up.
  int medianMicros(void Function() body, {int runs = 5}) {
    body();
    final times = <int>[];
    for (var i = 0; i < runs; i += 1) {
      final watch = Stopwatch()..start();
      body();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return times[times.length ~/ 2];
  }

  test('the ants and the mask of an inverse over a 5760×3240 wall', () {
    final left = wall.left.toInt();
    final top = wall.top.toInt();
    final width = wall.width.toInt();
    final height = wall.height.toInt();

    var contours = 0;
    final outline = medianMicros(() {
      contours = inverse().pixelOutlineContours.length;
    });
    var cornerByte = 0;
    final mask = medianMicros(() {
      final bytes = inverse().maskFor(
        left: left,
        top: top,
        width: width,
        height: height,
      );
      cornerByte = bytes[0];
    });

    debugPrint(
      'inverse over ${width}x$height: ants ${outline / 1000} ms '
      '($contours contours) · maskFor ${mask / 1000} ms · '
      'ants/mask ${(outline / mask).toStringAsFixed(3)}',
    );
    expect(contours, greaterThan(0), reason: 'the walk ran');
    expect(cornerByte, isNonZero, reason: 'the mask was filled');
  });
}
