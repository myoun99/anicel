import '../core/floor_math.dart';
import 'canvas_size.dart';

/// How many whole canvases of pasteboard sit beyond EACH edge.
///
/// 🚨H2 (유저 확정 2026-08-22): 「페이스트보드 **최대치 3x3으로 두는건 일단
/// 하는거야. 자동확장만 아이디어로서 남기고**」 — one canvas past every edge
/// is a 3×3 footprint.
///
/// ⛔It was TWO, i.e. 5×5. Nothing measured said it had to be; the number
/// was chosen when the pasteboard was first bounded, and the user has now
/// named the one they want. Every other pasteboard fact derives from the
/// four getters below, so this constant is the whole knob.
///
/// 💡STILL AN IDEA, deliberately not built: growing the pasteboard to
/// follow where material actually sits, the way Adobe Animate does. The
/// user asked for the fixed 3×3 first and kept the rest as a thought —
/// 「자동확장만 아이디어로서 남기고」. ⚠️I first read their original note as
/// "both halves are only a thought"; the 「이건」 in it points at the second
/// half alone.
const int pasteboardCanvasesPerEdge = 1;

/// The pasteboard: the finite drawable rectangle AROUND the canvas
/// (Flash's gray stage surround). It extends [pasteboardCanvasesPerEdge]
/// canvas sizes beyond every canvas edge — a 3×3 canvas footprint — so
/// strokes, fills and selection drops are bounded, storage worst cases stay
/// finite, and the "fill outside the canvas" option has a hard wall. (The
/// fill apron stays its own capped size — see pasteboardFillMarginCap — so
/// changing the pasteboard never changes the flood raster.)
///
/// The canvas keeps its [0, width) × [0, height) pixel space; the
/// pasteboard adds negative space to the left/top and overflow to the
/// right/bottom. Composite/export raster at canvas size, which crops
/// pasteboard content for free.
extension PasteboardBounds on CanvasSize {
  int get pasteboardLeft => -pasteboardCanvasesPerEdge * width;

  int get pasteboardTop => -pasteboardCanvasesPerEdge * height;

  int get pasteboardRightExclusive => (1 + pasteboardCanvasesPerEdge) * width;

  int get pasteboardBottomExclusive => (1 + pasteboardCanvasesPerEdge) * height;

  bool containsPasteboardPixel({required int x, required int y}) {
    return x >= pasteboardLeft &&
        x < pasteboardRightExclusive &&
        y >= pasteboardTop &&
        y < pasteboardBottomExclusive;
  }

  /// [containsPasteboardPixel] for continuous canvas-space positions
  /// (pointer input, stroke segment clipping).
  bool containsPasteboardPoint({required double x, required double y}) {
    return x >= pasteboardLeft &&
        x < pasteboardRightExclusive &&
        y >= pasteboardTop &&
        y < pasteboardBottomExclusive;
  }

  /// First tile column that intersects the pasteboard.
  int pasteboardTileXMin(int tileSize) => floorDiv(pasteboardLeft, tileSize);

  /// First tile row that intersects the pasteboard.
  int pasteboardTileYMin(int tileSize) => floorDiv(pasteboardTop, tileSize);

  /// One past the last tile column that intersects the pasteboard.
  int pasteboardTileXEndExclusive(int tileSize) =>
      ceilDiv(pasteboardRightExclusive, tileSize);

  /// One past the last tile row that intersects the pasteboard.
  int pasteboardTileYEndExclusive(int tileSize) =>
      ceilDiv(pasteboardBottomExclusive, tileSize);
}
