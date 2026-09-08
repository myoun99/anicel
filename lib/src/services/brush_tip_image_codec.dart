import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/brush_tip_mask.dart';
import 'brush_tip_coverage.dart';
import 'photoshop/psd_image.dart';
import 'photoshop/psd_reader.dart';
import 'resample/coverage_resample.dart';
import 'straight_rgba_image.dart';

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
  // A Photoshop document reaches the tip library the same way a PNG does,
  // so it takes the same detour every image entry point takes.
  final image = looksLikePsdBytes(bytes)
      ? await decodePsdCompositeImage(bytes)
      : (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
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

    final gray = Uint8List(width * height);
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

    return brushTipMaskFromCoverage(
      gray,
      size: (width: width, height: height),
      id: id,
    );
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
  // 🚨Through [uploadRawRgba], not `ui.decodeImageFromPixels`: the SDK
  // function drops every failure into a future nobody holds, so the
  // `Completer` that stood here could only ever succeed. Encoding a tip that
  // the engine refuses would have hung this `await` instead of throwing —
  // and the caller is a SAVE, which would then never finish and never say
  // why. The bytes are already premultiplied (see the paragraph above), so
  // this is the same upload with an answer on the failing side.
  final image = await uploadRawRgba(rgba, width: mask.size, height: mask.size);
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

/// A tiny preview of [mask], [side]x[side] alpha bytes, averaged from the
/// full-resolution mask.
///
/// The tip library stores one of these inline in its index so the picker
/// grid can paint on the first frame — decoding a folder of PNGs is
/// asynchronous, and a grid of empty squares that fills in later is exactly
/// the kind of UI that moves under the user's hand.
///
/// 🚨THROUGH THE SAME FILTER THE MASK ITSELF CAME DOWN THROUGH. A preview
/// is a minification of a coverage map, which is the one question
/// [resampleCoverage] answers, so it is not a second question and does not
/// get a second filter (ARCH-audit-Q7, 2026-09-07).
Uint8List brushTipThumbnailAlpha(BrushTipMask mask, {int side = 16}) =>
    resampleCoverage(
      mask.alpha,
      width: mask.size,
      height: mask.size,
      newWidth: side,
      newHeight: side,
    );
