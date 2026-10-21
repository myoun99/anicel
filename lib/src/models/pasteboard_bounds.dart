import 'dart:ui' as ui;

import '../core/floor_math.dart';
import 'canvas_size.dart';
import 'dirty_region.dart';
import 'tile_coord.dart';

/// How big a project's pasteboard is: the whole stage's side — paper and
/// pasteboard together — as a multiple of the paper's.
///
/// 🗣️I-109 (유저 2026-10-20): 「페이스트보드 크기,사용함 안함 기능필요」, sized
/// 「용지 대비 … 단계 심플하게」 (Q1) in the three steps of Q3 (2026-10-21:
/// 「1.5x · 2x · 3x」). [three] is one paper past every edge — the 3×3 the
/// pasteboard was fixed at until then.
///
/// 🚨H2 (유저 확정 2026-08-22): 「페이스트보드 **최대치 3x3으로 두는건 일단
/// 하는거야. 자동확장만 아이디어로서 남기고**」 — so 3x is the largest step.
/// ⛔It was 5×5 before H2. Nothing measured said it had to be.
///
/// 💡STILL AN IDEA, deliberately not built: growing the pasteboard to
/// follow where material actually sits, the way Adobe Animate does —
/// 「자동확장만 아이디어로서 남기고」. ⚠️I first read the user's note as
/// "both halves are only a thought"; the 「이건」 in it points at the second
/// half alone.
enum PasteboardSize {
  oneAndAHalf('1.5x', PasteboardReach.quarter),
  two('2x', PasteboardReach.half),
  three('3x', PasteboardReach.whole);

  const PasteboardSize(this.label, this.reach);

  /// What the step is called where it is picked.
  final String label;

  /// How far past the paper this size reaches, while it is in use.
  final PasteboardReach reach;
}

/// How far past the paper the pasteboard reaches on EVERY edge, in quarters
/// of the paper's own side: the one value every wall is drawn from.
///
/// It is a project's [PasteboardSize] while its pasteboard is in use, and
/// [none] while it is not ([PasteboardReach.of]) — the wall is then the
/// paper itself (I-109: 「페이스트보드 사용안함시 근본/구조적으로 사용
/// 안하도록」).
///
/// ⛔Two project values, one reach: the size is kept while the pasteboard
/// is off, so turning it back on finds the size it had. Asking the size
/// alone 「is there a pasteboard」 would make one value answer two
/// questions.
enum PasteboardReach {
  none(0),
  quarter(1),
  half(2),
  whole(4);

  const PasteboardReach(this.quartersPerEdge);

  /// The reach of a pasteboard of [size], [inUse] or not.
  static PasteboardReach of({
    required PasteboardSize size,
    required bool inUse,
  }) => inUse ? size.reach : none;

  final int quartersPerEdge;

  /// The pixels this reach puts past an edge of a paper [side] long —
  /// ROUNDED UP, so the wall never stands inside the size picked: a 1.5x
  /// pasteboard round a paper 1919 wide reaches 480 past each side, not
  /// 479.
  int pastEdgeOf(int side) => ceilDiv(side * quartersPerEdge, 4);
}

/// The pasteboard of a [canvas] at a [reach]: the finite drawable rectangle
/// AROUND the canvas (Flash's gray stage surround) — the wall every stroke,
/// fill, paste, text and selection stops at, and that a picture keeps its
/// tiles inside.
///
/// The canvas keeps its [0, width) × [0, height) pixel space; the
/// pasteboard adds negative space to the left/top and overflow to the
/// right/bottom. Composite/export raster at canvas size, which crops
/// pasteboard content for free.
///
/// ⛔ONE WALL (I-109). Every wall in the editor is read from this type, and
/// it cannot be built without a reach: the walls were four getters on
/// [CanvasSize] reading one constant, so a pasteboard of another size could
/// not be spelled without a second rule beside the first.
final class PasteboardWall {
  const PasteboardWall(this.canvas, this.reach);

  final CanvasSize canvas;
  final PasteboardReach reach;

  int get left => -reach.pastEdgeOf(canvas.width);

  int get top => -reach.pastEdgeOf(canvas.height);

  int get rightExclusive => canvas.width + reach.pastEdgeOf(canvas.width);

  int get bottomExclusive => canvas.height + reach.pastEdgeOf(canvas.height);

  /// The whole pasteboard as a rect — the wall every stroke, stamp and
  /// stroke-blend landing clips against ([DirtyRegion.intersection]).
  DirtyRegion get region => DirtyRegion(
    left: left,
    top: top,
    rightExclusive: rightExclusive,
    bottomExclusive: bottomExclusive,
  );

  /// The same wall as a canvas-space [ui.Rect], for everything that clips
  /// or bounds in doubles: a painter's clip, the display extent, a float's
  /// preview, a text or raster placement.
  ///
  /// ⛔ONE CONVERSION (F-85, 2026-09-15). This rect was typed out from the
  /// four getters above in seven places, and an eighth — the knee's flat
  /// projection, gone since 2026-09-16 — typed the 3×3 NUMBERS instead, so
  /// it would have kept the old wall the day the pasteboard's size moved.
  ui.Rect get rect => ui.Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    rightExclusive.toDouble(),
    bottomExclusive.toDouble(),
  );

  bool containsPixel({required int x, required int y}) =>
      x >= left && x < rightExclusive && y >= top && y < bottomExclusive;

  /// [containsPixel] for continuous canvas-space positions (pointer input,
  /// stroke segment clipping).
  bool containsPoint({required double x, required double y}) =>
      x >= left && x < rightExclusive && y >= top && y < bottomExclusive;

  /// Every tile that intersects the pasteboard, as a range.
  TileRange tileRange(int tileSize) => (
    firstX: floorDiv(left, tileSize),
    lastX: ceilDiv(rightExclusive, tileSize) - 1,
    firstY: floorDiv(top, tileSize),
    lastY: ceilDiv(bottomExclusive, tileSize) - 1,
  );

  @override
  bool operator ==(Object other) =>
      other is PasteboardWall && other.canvas == canvas && other.reach == reach;

  @override
  int get hashCode => Object.hash(canvas, reach);

  @override
  String toString() => 'PasteboardWall($canvas, $reach)';
}

/// The paper's own rects, and its pasteboard at a reach.
extension PasteboardBounds on CanvasSize {
  /// This canvas's pasteboard at [reach].
  PasteboardWall pasteboardAt(PasteboardReach reach) =>
      PasteboardWall(this, reach);

  /// The canvas itself as a rect: [0, width) × [0, height) — the wall the
  /// fill's settling bounds clip against.
  DirtyRegion get canvasRegion => DirtyRegion(
    left: 0,
    top: 0,
    rightExclusive: width,
    bottomExclusive: height,
  );

  /// The canvas itself as a canvas-space [ui.Rect], [0, width) ×
  /// [0, height) — what a paper plate fills, a fit frames and a backdrop
  /// paints.
  ///
  /// ⛔ONE CONVERSION (audit, 2026-09-15), for [PasteboardWall.rect]'s
  /// reason: this rect was typed out from the size in eleven places across
  /// seven files. `one_canvas_rect_test` keeps it at one.
  ui.Rect get canvasRect =>
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
}
