import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../../core/argb_channels.dart';

/// The grid-tile op stream (UI-R18 O7 / R18-T T1): the timeline frame
/// grids describe a tile's contents as a flat int32 word list — flat
/// rect fills, hairlines, rounded boxes and A8-atlas glyph blits, which
/// is the WHOLE post-O1 cell visual language — and the GPU engine's grid
/// pass draws it (packages/gpu_engine/rust/src/kernels/timeline/grid),
/// whose shader is the one source of truth for the semantics.
/// ↩️The C `qa_grid_raster_tile` rastered it, pinned byte for byte to a
/// Dart reference, until grid-on-the-engine ⑥.
///
/// OP colors pack as memory-order RGBA words (r | g<<8 | b<<16 | a<<24),
/// STRAIGHT alpha. A tile is drawn over clear, and kept straight
/// (`GpuGridPicture`).
abstract final class TimelineGridTileOp {
  static const int fillRect = 1;
  static const int hline = 2;
  static const int vline = 3;
  static const int glyph = 4;

  /// The rounded-rect fill (T2, the cell BLOCK chrome): every geometry field
  /// is 24.8 fixed point (pixels * 256 — [q8]) so fractional-zoom cell
  /// rects ride sub-pixel; corner mask bit0=TL, bit1=TR, bit2=BL,
  /// bit3=BR (unset corners square). AA from the rounded-box SDF.
  static const int rrectFill = 5;

  /// The rounded-rect RING (I-129, 2026-10-25: an EMPTY block's outline —
  /// the export Cels tab's hollow block, on the timeline's blocks): the
  /// [rrectFill] coverage of the box less that of the box a line width in
  /// from each side, its corners that much tighter. Its open mask names
  /// the sides it leaves OPEN ([sideLeft]…): a block a tile's span cuts
  /// runs on into the next tile, which must not see a seam there.
  ///
  /// ↩️6 was the per-cell block border's STROKE once: D32/D38 (2026-08-18)
  /// made that border transparent for good, and the op left the writer,
  /// the Dart reference and the C engine together with the substrate
  /// rewrite of 2026-09-24.
  static const int rrectRing = 6;

  static const int cornerTopLeft = 1;
  static const int cornerTopRight = 2;
  static const int cornerBottomLeft = 4;
  static const int cornerBottomRight = 8;

  static const int sideLeft = 1;
  static const int sideTop = 2;
  static const int sideRight = 4;
  static const int sideBottom = 8;
}

/// A rounded rect in PIXELS as the op stream states it: [cornerMask] picks
/// which corners take [radius] (bit0=TL, bit1=TR, bit2=BL, bit3=BR).
typedef TimelineGridRRect = ({
  double x,
  double y,
  double width,
  double height,
  double radius,
  int cornerMask,
});

/// Pixels → the op stream's 24.8 fixed-point word.
int timelineGridQ8(double pixels) => (pixels * 256).round();

/// A rounded box's [width], [height] and [radius] as the stream's q8 words.
///
/// ⛔A CORNER THE GPU ENGINE'S GRID PASS REFUSES IS REFUSED HERE, where the
/// op is written — the corner the box takes, its radius or half its
/// narrower side where that is less, past 64 pixels or below square
/// (`kernels/timeline/grid/mod.rs`, `MOST_RADIUS_Q9`: the pass refuses the
/// whole stream rather than draw a smaller corner, and asks the writer to
/// refuse first). Throws [ArgumentError].
(int, int, int) _cornered(double width, double height, double radius) {
  final (w, h, r) = (
    timelineGridQ8(width),
    timelineGridQ8(height),
    timelineGridQ8(radius),
  );
  // In q9, as the pass reads it.
  final corner = math.min(2 * r, math.min(w, h));
  if (r < 0 || corner > _mostCornerQ9) {
    throw ArgumentError(
      'a corner of $radius px on a box $width px wide and $height px high: '
      'the grid takes none below square and none past 64 px',
    );
  }
  return (w, h, r);
}

const int _mostCornerQ9 = 1 << 15;

/// Packs a straight-alpha color into the op stream's RGBA word.
int timelineGridPackRgba(Color color) {
  final argb = color.toARGB32();
  return argbRed(argb) |
      (argbGreen(argb) << 8) |
      (argbBlue(argb) << 16) |
      (argbAlpha(argb) << 24);
}

/// Grow-only builder for one tile's op stream.
class TimelineGridTileOpWriter {
  final List<int> _words = <int>[];

  int get wordCount => _words.length;

  void fillRect(int x, int y, int width, int height, int rgba) {
    _words
      ..add(TimelineGridTileOp.fillRect)
      ..add(x)
      ..add(y)
      ..add(width)
      ..add(height)
      ..add(rgba);
  }

  /// A horizontal line [length] long, [thickness] tall.
  void hline(int x, int y, int length, int thickness, int rgba) {
    _words
      ..add(TimelineGridTileOp.hline)
      ..add(x)
      ..add(y)
      ..add(length)
      ..add(thickness)
      ..add(rgba);
  }

  /// A vertical line [length] tall, [thickness] wide.
  void vline(int x, int y, int length, int thickness, int rgba) {
    _words
      ..add(TimelineGridTileOp.vline)
      ..add(x)
      ..add(y)
      ..add(length)
      ..add(thickness)
      ..add(rgba);
  }

  /// A filled rounded rect; geometry in PIXELS (converted to q8 here),
  /// [cornerMask] picks which corners round.
  void rrectFill(
    double x,
    double y,
    double width,
    double height,
    double radius,
    int cornerMask,
    int rgba,
  ) {
    final (w, h, r) = _cornered(width, height, radius);
    _words
      ..add(TimelineGridTileOp.rrectFill)
      ..add(timelineGridQ8(x))
      ..add(timelineGridQ8(y))
      ..add(w)
      ..add(h)
      ..add(r)
      ..add(cornerMask)
      ..add(rgba);
  }

  /// [box]'s ring [lineWidth] wide inside it (converted to q8 here),
  /// leaving open the sides [openMask] names
  /// ([TimelineGridTileOp.rrectRing]).
  void rrectRing(
    TimelineGridRRect box, {
    required double lineWidth,
    required int openMask,
    required int rgba,
  }) {
    final (w, h, r) = _cornered(box.width, box.height, box.radius);
    _words
      ..add(TimelineGridTileOp.rrectRing)
      ..add(timelineGridQ8(box.x))
      ..add(timelineGridQ8(box.y))
      ..add(w)
      ..add(h)
      ..add(r)
      ..add(box.cornerMask)
      ..add(timelineGridQ8(lineWidth))
      ..add(openMask)
      ..add(rgba);
  }

  /// Blits a [width]x[height] window of the A8 atlas at (atlasX, atlasY)
  /// to (destX, destY), tinted by [rgba] (atlas coverage scales its
  /// alpha).
  void glyph(
    int destX,
    int destY,
    int atlasX,
    int atlasY,
    int width,
    int height,
    int rgba,
  ) {
    _words
      ..add(TimelineGridTileOp.glyph)
      ..add(destX)
      ..add(destY)
      ..add(atlasX)
      ..add(atlasY)
      ..add(width)
      ..add(height)
      ..add(rgba);
  }

  /// The ops another writer built, written on after these.
  void append(Int32List ops) => _words.addAll(ops);

  Int32List build() => Int32List.fromList(_words);
}
