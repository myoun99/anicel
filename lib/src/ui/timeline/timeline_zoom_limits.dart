import 'dart:math' as math;

/// How far the timeline's frame axis may zoom, in pixels per frame — the
/// one place the panel, its view cluster and anything else that clamps a
/// zoom read the same numbers.
///
/// A leaf on purpose: the view cluster used to read these off
/// `TimelinePanel`, which builds the cluster, and the two files imported
/// each other (Round 4 of the audit, 2026-09-03).
abstract final class TimelineZoomLimits {
  static const double maxPixelsPerFrame = 96;
  static const double defaultPixelsPerFrame = 24;

  /// The most pixels a SECOND takes at the widest zoom — the floor said in
  /// time, because the ask was in time (I-22, 유저 09-12 「프로급이면
  /// 10분까지 보여야」 · 09-17 「줌 최대로 줄이면 프리미어 프로급으로
  /// 10분까지 보이게」 · 09-26 「타임라인 10분정도로 보이게 축소가능하게」).
  /// On the user's screen a maximized timeline's frame area measured
  /// ~2,350px (41 s at the old 2.4px floor); at 3px a second, ten minutes
  /// take 1,800px at most, at every rate.
  ///
  /// ↩️The floor was 4 px per FRAME, then 2.4 (UI-R18 #11: 10% of the
  /// default density across all three frame panels) — a floor in frames,
  /// which puts a 60fps project's ten minutes two and a half times as far
  /// away as a 24fps one's.
  static const int _widestPixelsPerSecond = 3;

  /// The widest zoom for a project counting [framesPerSecond]: one pixel
  /// for a WHOLE number of frames — the fewest that keep a second at
  /// [_widestPixelsPerSecond] pixels or under (24fps → 1/8, 25 → 1/9,
  /// 30 → 1/10, 60 → 1/20).
  static double minPixelsPerFrameAt(int framesPerSecond) =>
      1 / math.max(1, (framesPerSecond / _widestPixelsPerSecond).ceil());

  /// The zoom values a control may emit — the GRID: whole pixels per frame
  /// from one pixel up (R4 #5: a sub-pixel drag rebuilt the entire grid for
  /// a visually identical step), and under one pixel the same rule turned
  /// over, whole FRAMES per pixel (1/2, 1/3, …), so every step still moves
  /// some frame boundary by a whole pixel.
  ///
  /// 🚨ONE quantizer, asked by the slider and by the −/+ buttons, and it
  /// lands on the grid BEFORE it clamps. The slider rounded without
  /// clamping at all, so the bottom of its track wrote 2px where the floor
  /// was 2.4 and the value was never brought back (I-22 ②-1). Both bounds
  /// are grid values, so a clamped value is still on the grid, and nothing
  /// can reach a zero cell — what trips the grid's `frameCellWidth > 0`
  /// assert, the x-sheet's virtualization and the zoom anchor's division.
  static double quantize(
    double pixelsPerFrame, {
    required int framesPerSecond,
  }) {
    final floor = minPixelsPerFrameAt(framesPerSecond);
    return _onGrid(pixelsPerFrame).clamp(floor, maxPixelsPerFrame);
  }

  /// One −/+ step (UI-R11 #11): ×1.25 like every editor zoom in the app, so
  /// a step feels equal at 4px and 96px — landed on the grid, and where
  /// that lands back on the zoom it left, the next grid value over.
  ///
  /// ↩️That fallback went on 2026-09-16 because nothing could reach it: on
  /// whole pixels over a 2.4px floor, ×1.25 stood still only AT the two
  /// bounds, where the clamp answered first. The finer grid under one
  /// pixel reaches it — ÷1.25 of 2 rounds back to 2, of 1 back to 1, and
  /// ×1.25 of 1/2 back to 1/2 — so without it both buttons would stick
  /// there with nothing on screen saying why.
  static double stepped(
    double pixelsPerFrame, {
    required bool zoomIn,
    required int framesPerSecond,
  }) {
    final target = quantize(
      zoomIn ? pixelsPerFrame * 1.25 : pixelsPerFrame / 1.25,
      framesPerSecond: framesPerSecond,
    );
    if (target != pixelsPerFrame) {
      return target;
    }
    return quantize(
      _gridNeighbour(pixelsPerFrame, zoomIn: zoomIn),
      framesPerSecond: framesPerSecond,
    );
  }

  static double _onGrid(double pixelsPerFrame) {
    if (pixelsPerFrame >= 1) {
      return pixelsPerFrame.roundToDouble();
    }
    return 1 / (1 / pixelsPerFrame).roundToDouble();
  }

  /// The grid value next to [pixelsPerFrame] (itself on the grid).
  static double _gridNeighbour(double pixelsPerFrame, {required bool zoomIn}) {
    if (pixelsPerFrame > 1 || (pixelsPerFrame == 1 && zoomIn)) {
      return zoomIn ? pixelsPerFrame + 1 : pixelsPerFrame - 1;
    }
    final framesPerPixel = (1 / pixelsPerFrame).roundToDouble();
    return 1 / (zoomIn ? framesPerPixel - 1 : framesPerPixel + 1);
  }
}
