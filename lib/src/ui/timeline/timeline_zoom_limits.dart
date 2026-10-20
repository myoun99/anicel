import 'dart:math' as math;

/// How far the timeline's frame axis may zoom, in pixels per frame — the
/// one place the panel, its view cluster and anything else that clamps a
/// zoom read the same numbers.
///
/// A leaf on purpose: the view cluster used to read these off
/// `TimelinePanel`, which builds the cluster, and the two files imported
/// each other (Round 4 of the audit, 2026-09-03).
abstract final class TimelineZoomLimits {
  /// The closest zoom.
  ///
  /// 🗣️F-403 (유저 2026-10-19): 「우선 200%이상의 값은 필요없어보임. 그러니
  /// 지금의 최소값부터 200%까지만 살리도록」 — 200% of the 24-pixel frame the
  /// bar read as 100% then, which reads 250% now that the 100% moved under
  /// it ([referencePixelsPerFrame]). ↩️96 — 400% then.
  static const double maxPixelsPerFrame = 48;

  /// The zoom the bar reads as 100%, and the one a cut nobody zoomed opens
  /// at — the zoom to work at.
  ///
  /// 🗣️F-403 (유저 2026-10-19): 「50%이 작업하기 최적한 줌 상태라고
  /// 생각함. 그래서 50%을 100%으로서 두도록」 · (23:12) 「50은 너무 블록이
  /// 작으니 80%를 100%로 잡도록」 — 80% of the 24-pixel frame.
  static const double referencePixelsPerFrame = 19.2;

  /// The frame a panel is laid out at when its host names no zoom — the
  /// classic cell, which the block-edge grip is sized by. The app's hosts
  /// always name one. ↩️It was the 100% too, until F-403
  /// ([referencePixelsPerFrame]).
  static const double defaultPixelsPerFrame = 24;

  /// How many steps a zoom takes per [referencePixelsPerFrame]: a step is
  /// 0.1% — the last digit the bar writes.
  ///
  /// 🗣️F-403 (유저 2026-10-19): 「0.9%에서 숫자 안바뀌는데 줌이 바뀌는걸
  /// 발견. 내가 분명 이런 슬라이더에서 조절되는 숫자까지 다 슬라이더에
  /// 보여주라고 하지않았나? … 소수점 두번째부터는 작동안하도록 … 그로 인해
  /// 줌이 딱딱해진다거나 다 알고 말하는것임」 — no zoom lies between two
  /// numbers the bar writes. ↩️Any zoom in the range was one (F-220).
  static const int _stepsPerReference = 1000;

  /// The zoom [steps] steps make.
  static double _zoomOf(int steps) =>
      steps * referencePixelsPerFrame / _stepsPerReference;

  /// The step nearest [pixelsPerFrame]. The range is its callers' to hold
  /// ([clamped], [stepped]), each after its own arithmetic.
  static int _stepsOf(double pixelsPerFrame) =>
      (pixelsPerFrame *
              _stepsPerReference /
              referencePixelsPerFrame)
          .round();

  static int get _maxSteps => _stepsOf(maxPixelsPerFrame);

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

  /// The widest zoom for a project counting [framesPerSecond]: the closest
  /// step that keeps a second at [_widestPixelsPerSecond] pixels or under
  /// (24fps → 0.6%, 30 → 0.5%, 60 → 0.2%), and never under one step.
  ///
  /// ↩️It was one pixel for a whole number of frames (24fps → 1/8), until
  /// F-403 put every zoom on a step.
  static double minPixelsPerFrameAt(int framesPerSecond) =>
      _zoomOf(_minStepsAt(framesPerSecond));

  static int _minStepsAt(int framesPerSecond) => math.max(
    1,
    (_widestPixelsPerSecond /
            framesPerSecond *
            _stepsPerReference /
            referencePixelsPerFrame)
        .floor(),
  );

  /// The zoom a control may emit: [pixelsPerFrame] on its nearest step
  /// inside the range ([_stepsPerReference]).
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
  /// what the grid was keeping crisp. The steps of F-403 are the numbers the
  /// bar writes, so every number it reaches is still a zoom of its own.
  static double clamped(
    double pixelsPerFrame, {
    required int framesPerSecond,
  }) => _zoomOf(
    _stepsOf(
      pixelsPerFrame,
    ).clamp(_minStepsAt(framesPerSecond), _maxSteps),
  );

  /// The closest zoom at which [frames] frames stand inside [extent]
  /// pixels — on a step, inside the range: the zoom fit (I-111).
  static double fitting(
    double extent, {
    required int frames,
    required int framesPerSecond,
  }) {
    final steps =
        extent /
        math.max(1, frames) *
        _stepsPerReference /
        referencePixelsPerFrame;
    return _zoomOf(
      steps.floor().clamp(_minStepsAt(framesPerSecond), _maxSteps),
    );
  }

  /// One −/+ step (UI-R11 #11): ×1.25 like every editor zoom in the app, so
  /// a step feels equal at the widest zoom and the closest — and at least
  /// one step ([_stepsPerReference]), so a press moves the zoom wherever
  /// ×1.25 rounds back onto the step it left.
  ///
  /// ↩️It fell back to the next grid value where ×1.25 rounded back onto
  /// the zoom it left (2026-09-16); with no grid, ×1.25 always moved, until
  /// the steps of F-403.
  static double stepped(
    double pixelsPerFrame, {
    required bool zoomIn,
    required int framesPerSecond,
  }) {
    final from = _stepsOf(pixelsPerFrame);
    final to = zoomIn
        ? math.max(from + 1, _stepsOf(pixelsPerFrame * 1.25))
        : math.min(from - 1, _stepsOf(pixelsPerFrame / 1.25));
    return _zoomOf(to.clamp(_minStepsAt(framesPerSecond), _maxSteps));
  }
}
