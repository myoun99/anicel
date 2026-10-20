import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../services/straight_rgba_image.dart' show uploadRawRgba;

/// A source of one level picture: an image and where its halved self lands
/// in the level — the origin for a cel's single image, a quadrant for each
/// of the four pictures under a level tile.
typedef LevelSource = ({ui.Image image, ui.Offset at});

/// One level of the display's pyramid: the picture that draws each of
/// [sources] at half size at its place, each level pixel the exact mean of
/// a 2×2 block of its source (render round, 안 1 「선명」, 2026-09-16).
///
/// 🚨★★★A HALVING, NEVER A ONE-STEP REDUCTION. Bilinear at exactly 0.5
/// samples the midpoint of every 2×2 block, which IS the box filter —
/// exact, on every engine. One bilinear step to a quarter samples 2×2 of
/// each 4×4 block and aliases; `FilterQuality.medium` mipmaps on Skia and,
/// on Impeller, only where the texture was uploaded with mip levels — a
/// deferred `toImageSync` image has none — so a picture reduced that way
/// is sharp on one machine and shimmers on another. Two halvings are the
/// same bytes everywhere. Deeper levels are made from the level above, one
/// halving at a time.
///
/// ONE PLACE for the cel images' levels (`LayerFrameImageCache`) and the
/// active layer's level tiles (`TilePyramid`, 4c): the same halving, so
/// the two cannot drift by a rounding. The caller rasterises: `toImageSync`
/// where the level is needed in the frame (a tile's), `toImage` where a
/// frame of latency is fine (a cel's).
ui.Picture halvingPicture(Iterable<LevelSource> sources) {
  final recorder = ui.PictureRecorder();
  drawHalvings(ui.Canvas(recorder), sources);
  return recorder.endRecording();
}

/// Draws each of [sources] onto [canvas] halved at its place — the body of
/// [halvingPicture], and the draw a cel's first level is made with straight
/// from its tiles (`composeHalvedSurfaceImage`). Open so a spy canvas can
/// read which draw each source took (no picture can: the two draws below
/// make the same bytes).
///
/// 🚨★★★AN EVEN IMAGE IS ONE TEXTURE DRAW, not a rect under an image shader
/// (2026-09-24, measured on the real Windows app, Impeller GLES): a bilinear
/// `drawImageRect` at exactly 0.5 IS the halving the shader rect was, the
/// same bytes on the device, the tester's Skia and its Vulkan alike — but
/// the shader rect is the dear way to draw it. A level tile rastered in
/// 2.43 ms against 4.25, and 70 halved tiles in one picture in 3.23 ms
/// against 111.8. Every tile is even, so every level tile goes this way.
///
/// ⛔AN IMAGE WITH AN ODD EDGE KEEPS THE SHADER RECT, for the render
/// round's reason (2026-09-16), which once held for every image: "An image
/// shader rather than `drawImageRect`, for the edge: the shader CLAMPS past
/// the source, so an odd edge's last texel fills its level pixel whole
/// ([halvedSize]) instead of leaving a half-covered column the pixel-centre
/// rule would drop — and a tile's quadrant never samples the tile beside
/// it." An even image has no such edge, and a tile is its own texture drawn
/// whole, so its quadrant cannot reach the tile beside it either. Drawing
/// an odd image as its even part plus the odd column, row and corner by
/// texture draws was tried on 2026-09-24 — the same bytes on the device and
/// on Skia, but up to 4/255 apart at the second level on the tester's
/// Vulkan, whose addressing of a sub-rectangle rounds differently from the
/// whole. An odd image is only ever a whole cel, one rect in its picture,
/// so the shader is paid once per level there, not once per tile.
void drawHalvings(ui.Canvas canvas, Iterable<LevelSource> sources) {
  // Bilinear: at exactly 0.5 the box mean. Never `medium` (above).
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;
  for (final source in sources) {
    final image = source.image;
    if (image.width.isOdd || image.height.isOdd) {
      _drawHalvedUnderShader(canvas, source);
      continue;
    }
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        source.at.dx,
        source.at.dy,
        image.width / 2,
        image.height / 2,
      ),
      paint,
    );
  }
}

void _drawHalvedUnderShader(ui.Canvas canvas, LevelSource source) {
  final half = Float64List(16)
    ..[0] = 0.5
    ..[5] = 0.5
    ..[10] = 1
    ..[12] = source.at.dx
    ..[13] = source.at.dy
    ..[15] = 1;
  final size = halvedSize(source.image.width, source.image.height);
  canvas.drawRect(
    ui.Rect.fromLTWH(
      source.at.dx,
      source.at.dy,
      size.width.toDouble(),
      size.height.toDouble(),
    ),
    ui.Paint()
      ..shader = ui.ImageShader(
        source.image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        half,
        filterQuality: ui.FilterQuality.low,
      )
      ..isAntiAlias = false,
  );
}

/// The size of [width] × [height] halved: ⌈w/2⌉ × ⌈h/2⌉.
///
/// An odd edge keeps its last texel as a whole level pixel (the mean of
/// that texel and its clamped neighbour), so the level maps back onto the
/// artwork at EXACTLY half — twice its own size, one texel past an odd
/// edge. A level of ⌊w/2⌋ would map at w/(2⌊w/2⌋) instead, a hair off 1:1,
/// and nearest sampling of it would double a column somewhere in every
/// row.
({int width, int height}) halvedSize(int width, int height) =>
    (width: (width + 1) ~/ 2, height: (height + 1) ~/ 2);

/// THE ENGINE'S HALVING, MEASURED: what [halvingPicture] makes of a 2×2
/// block, by the sum of its four values (0 to 1020) — read off THIS device's
/// engine once, then the table a halving on the CPU looks the sum up in
/// ([halveRgbaWords]). Null where the engine's halving is not a function of
/// the sum alone: there nothing is halved but by the engine.
///
/// 🗣️유저 2026-10-18 (a-big-reference-picture-still-costs-when-zoomed-out-Q1):
/// 「엔진과 같은 바이트를 내는 CPU 반감을 찾는다」 · 「최대한 반감 한곳으로. 법
/// 통일하고싶음.」 — so the law stays [halvingPicture]'s, and the table is
/// MEASURED from it, never written down. 🔬On the Surface Pro 11 (Impeller
/// GLES, profile build, 2026-10-21, a throwaway probe over 2048×2048 random
/// pictures, opaque and translucent, `toImage` and `toImageSync`) the engine
/// gave the nearest value of the four's sum, a tie rounded down but for
/// 127.5, rounded up — 0 of 4,194,304 values apart from that rule, where
/// 「ties down」written by hand was 0.39% apart, every one a 127.5. Another
/// GPU may round another way; its own table says how.
///
/// Measured over premultiplied texels, as every texel the compose halves is:
/// the four channels of a calibration texel are its alpha, so no value
/// exceeds its alpha ([_calibrationStrip]).
Future<Uint8List?> measuredHalving() =>
    _halving ??= _measureHalving().then((table) {
      _measured = table;
      return table;
    });

/// [measuredHalving]'s table once it has been read — null before, and where
/// the engine's halving is not the sum's.
Uint8List? get measuredHalvingIfRead => _measured;

Future<Uint8List?>? _halving;
Uint8List? _measured;

/// A test's engine for the measure: what it makes of a calibration strip
/// ([width] × [height] premultiplied texels), halved — the test runner's
/// own engine halves one way only.
@visibleForTesting
Future<Uint8List?> Function(Uint8List bytes, int width, int height)?
debugEngineHalving;

/// Forgets the table, so the next [measuredHalving] reads it again.
@visibleForTesting
void debugForgetMeasuredHalving() {
  _halving = null;
  _measured = null;
}

/// The sums a calibration strip holds — every one, four ways each.
const int _halvingSums = 4 * 255 + 1;

/// A 2×2 block of [sum] the [way]th of four ways: spread evenly, packed
/// towards the first texel, towards the last, and in two diagonal pairs.
List<int> _calibrationBlock(int sum, int way) {
  List<int> packed() {
    final values = <int>[];
    var left = sum;
    for (var i = 0; i < 4; i += 1) {
      final value = left > 255 ? 255 : left;
      values.add(value);
      left -= value;
    }
    return values;
  }

  switch (way) {
    case 0:
      final q = sum ~/ 4;
      final r = sum % 4;
      return [for (var i = 0; i < 4; i += 1) q + (r > i ? 1 : 0)];
    case 1:
      return packed();
    case 2:
      return packed().reversed.toList();
    default:
      final half = sum ~/ 2;
      final a = half > 255 ? 255 : half;
      final rest = sum - half;
      final c = rest > 255 ? 255 : rest;
      return [a, c, rest - c, half - a];
  }
}

/// How many blocks a calibration strip runs along its length: 4096 texels,
/// a side every engine holds — so a sum is halved near the origin and far
/// from it, where a sample's place is least exact.
const int _stripBlocks = 2048;

/// Where the [block]th block of a calibration strip lies, in blocks — two
/// blocks across a strip, [_stripBlocks] along it, running [across] the
/// picture or down it.
({int x, int y}) _stripPlace(int block, {required bool across}) {
  final along = block % _stripBlocks;
  final side = block ~/ _stripBlocks;
  return across ? (x: along, y: side) : (x: side, y: along);
}

/// Every [_halvingSums] sum four ways in a strip, a 2×2 block each, its four
/// channels the block's value — premultiplied, as no value exceeds its
/// alpha.
({Uint8List bytes, int width, int height}) _calibrationStrip({
  required bool across,
}) {
  final width = across ? _stripBlocks * 2 : 4;
  final height = across ? 4 : _stripBlocks * 2;
  final bytes = Uint8List(width * height * 4);
  for (var block = 0; block < _halvingSums * 4; block += 1) {
    final values = _calibrationBlock(block ~/ 4, block % 4);
    final (:x, :y) = _stripPlace(block, across: across);
    for (var texel = 0; texel < 4; texel += 1) {
      final at = ((y * 2 + texel ~/ 2) * width + x * 2 + texel % 2) * 4;
      bytes.fillRange(at, at + 4, values[texel]);
    }
  }
  return (bytes: bytes, width: width, height: height);
}

/// A calibration strip halved by the engine ([_engineHalving]), read back.
Future<Uint8List?> _halvedStrip({required bool across}) {
  final (:bytes, :width, :height) = _calibrationStrip(across: across);
  return (debugEngineHalving ?? _engineHalving)(bytes, width, height);
}

/// [halvingPicture]'s halving of [bytes], read back. (An engine that held
/// them smaller halves a sum two ways across the strips, and so has no
/// table: [_measureHalving] needs no check of its own for that.)
Future<Uint8List?> _engineHalving(
  Uint8List bytes,
  int width,
  int height,
) async {
  final image = await uploadRawRgba(bytes, width: width, height: height);
  final ui.Image half;
  try {
    final picture = halvingPicture([(image: image, at: ui.Offset.zero)]);
    try {
      half = await picture.toImage(width ~/ 2, height ~/ 2);
    } finally {
      picture.dispose();
    }
  } finally {
    image.dispose();
  }
  try {
    return (await half.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))?.buffer.asUint8List();
  } finally {
    half.dispose();
  }
}

/// Reads the table off two strips, one across and one down: every sum, four
/// ways, both strips, every channel must halve to one value.
Future<Uint8List?> _measureHalving() async {
  final table = Uint16List(_halvingSums)..fillRange(0, _halvingSums, 0xFFFF);
  for (final across in [true, false]) {
    final Uint8List? halved;
    try {
      halved = await _halvedStrip(across: across);
    } on Object catch (_) {
      // An engine that cannot make the strip halves alone, as it always did.
      return null;
    }
    if (halved == null) {
      return null;
    }
    final halfWidth = across ? _stripBlocks : 2;
    for (var block = 0; block < _halvingSums * 4; block += 1) {
      final sum = block ~/ 4;
      final (:x, :y) = _stripPlace(block, across: across);
      final at = (y * halfWidth + x) * 4;
      for (var channel = 0; channel < 4; channel += 1) {
        final value = halved[at + channel];
        if (table[sum] == 0xFFFF) {
          table[sum] = value;
        } else if (table[sum] != value) {
          // Not the sum's alone: one sum halved two ways.
          return null;
        }
      }
    }
  }
  return Uint8List.fromList(table);
}

/// Halves premultiplied rgba8888 words through the engine's measured
/// halving ([measuredHalving]): each of [width] × [height] (both even)
/// texels of [from], a row every [fromStride] words from [fromStart], halved
/// into [into] at [intoStart], a row every [intoStride] words — each value
/// [table]'s for the sum of its 2×2 block's four.
///
/// Two channels a lane: a word's alternate bytes masked apart sum without
/// carrying into each other (four values sum to at most 1020), and land
/// back where they came from — whichever end of the word a channel is.
void halveRgbaWords(
  Uint8List table,
  Uint32List from, {
  required int fromStart,
  required int fromStride,
  required int width,
  required int height,
  required Uint32List into,
  required int intoStart,
  required int intoStride,
}) {
  assert(width.isEven && height.isEven, 'a halving of whole blocks');
  const mask = 0x00FF00FF;
  for (var y = 0; y < height ~/ 2; y += 1) {
    var top = fromStart + 2 * y * fromStride;
    var bottom = top + fromStride;
    var out = intoStart + y * intoStride;
    for (var x = 0; x < width ~/ 2; x += 1) {
      final a = from[top];
      final b = from[top + 1];
      final c = from[bottom];
      final d = from[bottom + 1];
      top += 2;
      bottom += 2;
      final even = (a & mask) + (b & mask) + (c & mask) + (d & mask);
      final odd =
          ((a >> 8) & mask) +
          ((b >> 8) & mask) +
          ((c >> 8) & mask) +
          ((d >> 8) & mask);
      into[out] =
          table[even & 0xFFFF] |
          table[odd & 0xFFFF] << 8 |
          table[even >> 16] << 16 |
          table[odd >> 16] << 24;
      out += 1;
    }
  }
}
