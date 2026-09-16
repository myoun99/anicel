/// How far the timeline's frame axis may zoom, in pixels per frame — the
/// one place the panel, its view cluster and anything else that clamps a
/// zoom read the same numbers.
///
/// A leaf on purpose: the view cluster used to read these off
/// `TimelinePanel`, which builds the cluster, and the two files imported
/// each other (Round 4 of the audit, 2026-09-03).
abstract final class TimelineZoomLimits {
  static const double minPixelsPerFrame = 2.4;
  static const double maxPixelsPerFrame = 96;
  static const double defaultPixelsPerFrame = 24;

  /// The zoom values a control may emit: WHOLE pixels per frame (the grid
  /// the slider has quantized to since R4 #5 — a sub-pixel drag rebuilt the
  /// entire grid for a visually identical step), and then the range's own
  /// bounds.
  ///
  /// 🚨ONE quantizer, asked by the slider and by the −/+ buttons, and it
  /// rounds BEFORE it clamps. The slider rounded without clamping at all,
  /// so the bottom of its track wrote 2px where the floor is 2.4 and the
  /// value was never brought back (I-22 ②-1); the buttons clamped a value
  /// they had already rounded, which is the same answer only while whole
  /// pixels are the whole grid. Rounding a value below the floor can no
  /// longer reach zero here, and a zero cell is what trips the grid's
  /// `frameCellWidth > 0` assert, the x-sheet's virtualization and the zoom
  /// anchor's division.
  static double quantize(double pixelsPerFrame) => pixelsPerFrame
      .roundToDouble()
      .clamp(minPixelsPerFrame, maxPixelsPerFrame);
}
