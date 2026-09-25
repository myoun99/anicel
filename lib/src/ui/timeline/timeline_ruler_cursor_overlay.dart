import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';

import 'timeline_cell_style.dart' show timelineSelectedFrameBorderColor;
import 'timeline_frame_window.dart';
import '../repaint_props.dart';
import 'memo_token.dart';

/// A frame ruler's MOVING layer: the current-frame tint and the green
/// cached-range bar, painted OVER the static header cells and driven by
/// [CustomPainter.repaint] — so a playhead tick, a warming frame or a cel
/// edit repaints this thin strip instead of re-recording the ruler's
/// labels and grid lines.
///
/// The split matters twice over:
///
/// - **Cost.** The static strip lays out a glyph per labeled frame. Keeping
///   the cursor tint in it meant every seek re-recorded all of that; here a
///   seek draws two rects.
/// - **Correctness.** Whether a frame is READY is DERIVED state — the
///   playback composite self-validates against a signature, so nothing
///   raises an "invalidated" event when a cel is edited. There is no token
///   a gated painter could compare. The only honest answer is to keep the
///   read cheap and re-read it on every signal that can change it, which is
///   what [repaintSignal] carries (warm progress + pixel edits) alongside
///   the playhead — and to REPAINT only when what it read differs from what
///   it drew ([TimelineRulerCursorOverlay]'s gate, F-166).
///
/// Shared by the storyboard ruler and the timeline ruler (it was the
/// storyboard's private painter first).
class TimelineRulerCursorOverlayPainter extends CustomPainter
    with RepaintOnProps {
  TimelineRulerCursorOverlayPainter({
    required this.playhead,
    required Listenable? repaintSignal,
    required this.windowBucket,
    required this.viewportMainExtent,
    required this.renderedFrames,
    required this.cellWidth,
    required this.isFrameReady,
    this.axis = Axis.horizontal,
    this.onPaintedRuns,
  }) : super(
         repaint: Listenable.merge([?playhead, ?repaintSignal, windowBucket]),
       );

  /// Told the ready runs each paint drew — what the overlay's gate compares
  /// a signal's answer against.
  final void Function(List<({int startIndex, int endIndexExclusive})> runs)?
  onPaintedRuns;

  /// The FRAME axis. Horizontal rulers (timeline, storyboard) run frames
  /// left-to-right and hug the bar to the bottom edge; the X-sheet rail runs
  /// them top-to-bottom with the cells to its right, so the bar hugs the
  /// right edge instead. One widget, both orientations (the Axis policy the
  /// rest of the timeline follows).
  final Axis axis;

  /// The frame the tint follows; a null VALUE draws no tint (the
  /// storyboard's "no playhead" state).
  final ValueListenable<int?>? playhead;

  /// UI-R15→R16 self-windowing: paint covers the bucket-derived slice of
  /// the full-bounds strip (repaint once per span crossing).
  final ValueListenable<int> windowBucket;
  final double viewportMainExtent;
  final int renderedFrames;
  final double cellWidth;
  final bool Function(int globalFrame)? isFrameReady;

  /// The AE-style ready-range green (the header cells' own strip color).
  static const Color readyBarColor = Color(0xFF54B435);

  /// The strip's thickness along the ruler's bottom edge.
  static const double readyBarThickness = 3;

  ({int startIndex, int endIndexExclusive}) _visibleWindow() =>
      visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: cellWidth,
        frameStartIndex: 0,
        frameEndIndexExclusive: renderedFrames,
      );

  /// The ready RUNS this overlay would draw — the probe surface tests read
  /// instead of scraping the canvas.
  ///
  /// B1: the runs cover the whole RENDERED window — there is no
  /// content-end clamp, deliberately (유저 2026-08-16: 「왜 콘텐츠끝너머가
  /// 초록이되면 안되는거지? 재생가능한거잖아」). Past the drawings the
  /// predicate answers "ready by definition", and clamping the bar here
  /// would repaint that answer as "not ready" — the exact lie the
  /// two-kind law retired.
  List<({int startIndex, int endIndexExclusive})> readyRuns() {
    final ready = isFrameReady;
    final runs = <({int startIndex, int endIndexExclusive})>[];
    if (ready == null) {
      return runs;
    }
    final window = _visibleWindow();
    final end = window.endIndexExclusive;
    var runStart = -1;
    for (var frame = window.startIndex; frame <= end; frame += 1) {
      if (frame < end && ready(frame)) {
        runStart = runStart < 0 ? frame : runStart;
        continue;
      }
      if (runStart >= 0) {
        runs.add((startIndex: runStart, endIndexExclusive: frame));
        runStart = -1;
      }
    }
    return runs;
  }

  /// The frame the tint marks, or null when it is outside the window (the
  /// probe surface for "which frame does the ruler show as current").
  int? tintedFrame() {
    final frame = playhead?.value;
    if (frame == null) {
      return null;
    }
    return frameWindowContains(_visibleWindow(), frame) ? frame : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = axis == Axis.horizontal;
    final barPaint = Paint()..color = readyBarColor;
    final runs = readyRuns();
    onPaintedRuns?.call(runs);
    for (final run in runs) {
      final start = run.startIndex * cellWidth;
      final extent = (run.endIndexExclusive - run.startIndex) * cellWidth;
      canvas.drawRect(
        horizontal
            ? Rect.fromLTWH(
                start,
                size.height - readyBarThickness,
                extent,
                readyBarThickness,
              )
            : Rect.fromLTWH(
                size.width - readyBarThickness,
                start,
                readyBarThickness,
                extent,
              ),
        barPaint,
      );
    }

    final frame = tintedFrame();
    if (frame != null) {
      // Matches the header cell's selected fill: the same tint over the
      // same surface the cell would have blended it onto.
      canvas.drawRect(
        horizontal
            ? Rect.fromLTWH(frame * cellWidth, 0, cellWidth, size.height)
            : Rect.fromLTWH(0, frame * cellWidth, size.width, cellWidth),
        Paint()
          ..color = timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
      );
    }
  }

  @override
  Object get props => (
    ByIdentity(windowBucket),
    viewportMainExtent,
    renderedFrames,
    cellWidth,
    axis,
    ByIdentity(playhead),
    // VALUE-compared, not identity: a method tear-off (`session.isCached`)
    // is a fresh object every build but compares EQUAL, so `identical`
    // here would repaint on every unrelated rebuild — the churn that hid
    // in the ruler painters.
    isFrameReady,
  );
}

/// The overlay, mounted the way both rulers want it: pointer-transparent
/// and on its own raster layer, so its repaints never touch the static
/// strip underneath.
///
/// 🚨ITS [repaintSignal] IS GATED (F-166, 2026-09-26). Warm progress
/// fires once per frame the prerender finishes, and between two strokes it
/// walks the whole cut, nearly every frame of it already green — yet every
/// tick repainted this strip, and a repaint anywhere in the timeline dock
/// throws the dock's still image away. Measured on the real app (cut 301):
/// the overlay repainted every ~0.1 s between strokes, the dock's wait for
/// stillness backed off to its ceiling, and the next stroke then painted
/// the whole timeline on every frame (17–21 ms of raster against 4–5).
/// Each tick now re-reads the runs and asks for a paint only when they
/// differ from the runs last DRAWN — not the runs last read, or a read
/// that no paint followed would leave the screen stale.
class TimelineRulerCursorOverlay extends StatefulWidget {
  const TimelineRulerCursorOverlay({
    super.key,
    required this.keyValue,
    required this.playhead,
    required this.repaintSignal,
    required this.windowBucket,
    required this.viewportMainExtent,
    required this.renderedFrames,
    required this.cellWidth,
    required this.isFrameReady,
    this.axis = Axis.horizontal,
  });

  final Axis axis;
  final String keyValue;
  final ValueListenable<int?>? playhead;
  final Listenable? repaintSignal;
  final ValueListenable<int> windowBucket;
  final double viewportMainExtent;
  final int renderedFrames;
  final double cellWidth;
  final bool Function(int globalFrame)? isFrameReady;

  @override
  State<TimelineRulerCursorOverlay> createState() =>
      _TimelineRulerCursorOverlayState();
}

class _TimelineRulerCursorOverlayState
    extends State<TimelineRulerCursorOverlay> {
  late final _ReadyRunsGate _gate = _ReadyRunsGate(() => _painter);
  late TimelineRulerCursorOverlayPainter _painter;

  @override
  void initState() {
    super.initState();
    widget.repaintSignal?.addListener(_gate.recheck);
  }

  @override
  void didUpdateWidget(covariant TimelineRulerCursorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repaintSignal != widget.repaintSignal) {
      oldWidget.repaintSignal?.removeListener(_gate.recheck);
      widget.repaintSignal?.addListener(_gate.recheck);
    }
  }

  @override
  void dispose() {
    widget.repaintSignal?.removeListener(_gate.recheck);
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _painter = TimelineRulerCursorOverlayPainter(
      playhead: widget.playhead,
      repaintSignal: _gate,
      windowBucket: widget.windowBucket,
      viewportMainExtent: widget.viewportMainExtent,
      renderedFrames: widget.renderedFrames,
      cellWidth: widget.cellWidth,
      isFrameReady: widget.isFrameReady,
      axis: widget.axis,
      onPaintedRuns: _gate.drew,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>(widget.keyValue),
          painter: _painter,
        ),
      ),
    );
  }
}

/// The overlay's [TimelineRulerCursorOverlay.repaintSignal], passed on
/// only when the ready runs the current painter reads differ from the runs
/// it last drew.
class _ReadyRunsGate extends ChangeNotifier {
  _ReadyRunsGate(this._painter);

  final TimelineRulerCursorOverlayPainter Function() _painter;
  List<({int startIndex, int endIndexExclusive})>? _drawn;

  void drew(List<({int startIndex, int endIndexExclusive})> runs) =>
      _drawn = runs;

  void recheck() {
    final drawn = _drawn;
    if (drawn != null && listEquals(drawn, _painter().readyRuns())) {
      return;
    }
    notifyListeners();
  }
}
