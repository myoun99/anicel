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

  /// The zoom a control may emit: [pixelsPerFrame] held inside the range —
  /// ANY value in it, so every percent the bar shows is a zoom of its own.
  ///
  /// 🚨ONE bound, asked by the slider and by the −/+ buttons. The slider
  /// once wrote 2px under a 2.4px floor and nothing brought it back (I-22
  /// ②-1); nothing can reach a zero cell either — what trips the grid's
  /// `frameCellWidth > 0` assert, the x-sheet's virtualization and the zoom
  /// anchor's division.
  ///
  /// 🗣️F-220 (유저 2026-09-29): 「1.7에서 2.8까지 이동하면 안바뀌고,
  /// 2.9까지 이동해야 … 바뀜 … 제대로 퍼센테이지 바뀔때마다 줌 상태가 바뀌지
  /// 않음 … 손을 뗄 때 값이 멋대로 살짝 바뀜」. ↩️The zoom landed on a GRID
  /// first — whole pixels per frame, whole FRAMES per pixel under one (R4 #5,
  /// 07-16: a sub-pixel drag rebuilt the entire grid for a visually identical
  /// step) — which left no zoom at all between 1/2 and 1 pixel a frame, and
  /// the bar, echoing the finger, jumped back to the grid on release. The
  /// user's ask then was a smooth drag, not the grid: a zoom step repaints
  /// the rows rather than rebuilding them since R28 #4, and every frame edge
  /// lands on a whole pixel at any zoom ([timelineFrameEdge]) — which is
  /// what the grid was keeping crisp.
  static double clamped(
    double pixelsPerFrame, {
    required int framesPerSecond,
  }) => pixelsPerFrame.clamp(
    minPixelsPerFrameAt(framesPerSecond),
    maxPixelsPerFrame,
  );

  /// One −/+ step (UI-R11 #11): ×1.25 like every editor zoom in the app, so
  /// a step feels equal at 4px and 96px.
  ///
  /// ↩️It fell back to the next grid value where ×1.25 rounded back onto
  /// the zoom it left (2026-09-16); with no grid, ×1.25 always moves, and
  /// only the bounds stop it.
  static double stepped(
    double pixelsPerFrame, {
    required bool zoomIn,
    required int framesPerSecond,
  }) => clamped(
    zoomIn ? pixelsPerFrame * 1.25 : pixelsPerFrame / 1.25,
    framesPerSecond: framesPerSecond,
  );
}
