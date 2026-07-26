import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/brush_tip_mask.dart';

// `maxBrushTipMaskSide` moved to the mask model so the pure-Dart importers
// can honour the same cap without pulling `dart:ui` in behind it.
export '../models/brush_tip_mask.dart' show maxBrushTipMaskSide;

/// Reads a PNG (or any format the engine decodes) as a brush tip mask.
///
/// Coverage is alpha shaped by darkness: a black-on-transparent tip resolves
/// to its own alpha, a black-on-white opaque scan resolves to inverted
/// luminance. If that yields nothing at all — a white-on-transparent tip —
/// the alpha channel alone stands in. The result is downscaled past
/// [maxBrushTipMaskSide] and padded to the centered square the engine's
/// samplers require.
///
/// Shared by Clip Studio import and by the tip library, so a tip the user
/// registers by hand and one that arrives inside a `.sut` are read by the
/// same rules.
Future<BrushTipMask> decodeBrushTipImage(
  Uint8List bytes, {
  required String id,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (byteData == null) {
      throw const FormatException('image pixels unavailable');
    }
    final rgba = byteData.buffer.asUint8List();
    final width = image.width;
    final height = image.height;

    var gray = Uint8List(width * height);
    var sum = 0;
    for (var index = 0; index < gray.length; index += 1) {
      final r = rgba[index * 4];
      final g = rgba[index * 4 + 1];
      final b = rgba[index * 4 + 2];
      final a = rgba[index * 4 + 3];
      final luminance = (r * 299 + g * 587 + b * 114) ~/ 1000;
      final value = a * (255 - luminance) ~/ 255;
      gray[index] = value;
      sum += value;
    }
    if (sum == 0) {
      for (var index = 0; index < gray.length; index += 1) {
        gray[index] = rgba[index * 4 + 3];
      }
    }

    var maskWidth = width;
    var maskHeight = height;
    final longSide = math.max(width, height);
    if (longSide > maxBrushTipMaskSide) {
      final scale = maxBrushTipMaskSide / longSide;
      final scaledWidth = math.max(1, (width * scale).round());
      final scaledHeight = math.max(1, (height * scale).round());
      gray = _resizeGray(
        gray,
        width: width,
        height: height,
        newWidth: scaledWidth,
        newHeight: scaledHeight,
      );
      maskWidth = scaledWidth;
      maskHeight = scaledHeight;
    }

    final side = math.max(maskWidth, maskHeight);
    final alpha = Uint8List(side * side);
    final offsetX = (side - maskWidth) ~/ 2;
    final offsetY = (side - maskHeight) ~/ 2;
    for (var y = 0; y < maskHeight; y += 1) {
      alpha.setRange(
        (offsetY + y) * side + offsetX,
        (offsetY + y) * side + offsetX + maskWidth,
        gray,
        y * maskWidth,
      );
    }
    return BrushTipMask(id: id, size: side, alpha: alpha);
  } finally {
    image.dispose();
  }
}

/// Writes a tip mask as a PNG whose ALPHA channel carries the coverage over
/// black.
///
/// Two reasons for that shape rather than an opaque grayscale image. It
/// round-trips through [decodeBrushTipImage] exactly — black gives
/// inverted luminance of 1, so coverage comes back as the alpha it went in
/// as — and it is what a tip looks like to a human opening the file: the
/// silhouette, on transparency.
///
/// It also sidesteps the premultiply trap. `rgba8888` pixels are
/// PREMULTIPLIED going into the engine, and premultiplying black is black,
/// so no rounding can creep into the round trip.
Future<Uint8List> encodeBrushTipImage(BrushTipMask mask) async {
  final rgba = Uint8List(mask.size * mask.size * 4);
  for (var index = 0; index < mask.alpha.length; index += 1) {
    rgba[index * 4 + 3] = mask.alpha[index];
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    mask.size,
    mask.size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw StateError('Could not encode the brush tip "${mask.id}".');
    }
    return png.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Bilinear grayscale resize.
Uint8List _resizeGray(
  Uint8List source, {
  required int width,
  required int height,
  required int newWidth,
  required int newHeight,
}) {
  final output = Uint8List(newWidth * newHeight);
  for (var y = 0; y < newHeight; y += 1) {
    final sourceY = (y + 0.5) * height / newHeight - 0.5;
    final y0 = sourceY.floor().clamp(0, height - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final fy = (sourceY - y0).clamp(0.0, 1.0);
    for (var x = 0; x < newWidth; x += 1) {
      final sourceX = (x + 0.5) * width / newWidth - 0.5;
      final x0 = sourceX.floor().clamp(0, width - 1);
      final x1 = (x0 + 1).clamp(0, width - 1);
      final fx = (sourceX - x0).clamp(0.0, 1.0);
      final top =
          source[y0 * width + x0] * (1 - fx) + source[y0 * width + x1] * fx;
      final bottom =
          source[y1 * width + x0] * (1 - fx) + source[y1 * width + x1] * fx;
      output[y * newWidth + x] = (top * (1 - fy) + bottom * fy).round();
    }
  }
  return output;
}

/// A tiny preview of [mask], [side]x[side] alpha bytes, averaged from the
/// full-resolution mask.
///
/// The tip library stores one of these inline in its index so the picker
/// grid can paint on the first frame — decoding a folder of PNGs is
/// asynchronous, and a grid of empty squares that fills in later is exactly
/// the kind of UI that moves under the user's hand.
Uint8List brushTipThumbnailAlpha(BrushTipMask mask, {int side = 16}) {
  final thumbnail = Uint8List(side * side);
  for (var row = 0; row < side; row += 1) {
    final startY = row * mask.size ~/ side;
    final endY = math.max(startY + 1, (row + 1) * mask.size ~/ side);
    for (var column = 0; column < side; column += 1) {
      final startX = column * mask.size ~/ side;
      final endX = math.max(startX + 1, (column + 1) * mask.size ~/ side);
      var total = 0;
      var count = 0;
      for (var y = startY; y < endY && y < mask.size; y += 1) {
        for (var x = startX; x < endX && x < mask.size; x += 1) {
          total += mask.alpha[y * mask.size + x];
          count += 1;
        }
      }
      thumbnail[row * side + column] = count == 0 ? 0 : total ~/ count;
    }
  }
  return thumbnail;
}
