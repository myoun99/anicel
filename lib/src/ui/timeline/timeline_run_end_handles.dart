import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_repeat.dart';
import 'axis_turn.dart' show extentAlong;
import 'timeline_cell_style.dart'
    show timelineDrawingHeldColor, timelineTextOnColor;
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_span_layout.dart';
import 'timeline_glyph_cache.dart';

/// Session-level hooks for the run-edge affordances (UI-R9 #10, TVP
/// style): [+] adds NEW one-frame drawings by dragging (one-undo drag
/// previewing through the session's drag channel); the edge property TAG
/// sets the edge's None/Hold/Repeat mode through a flyout (immediate
/// one-undo commit).
class TimelineRunEditCallbacks {
  const TimelineRunEditCallbacks({
    required this.onAddBegin,
    required this.onAddUpdate,
    required this.onAddEnd,
    required this.onAddCancel,
    required this.onEdgeModeSelected,
    this.canScopeToSelection,
  });

  final bool Function(
    LayerId layerId,
    int blockStartIndex, {
    required bool atEnd,
  })
  onAddBegin;
  final void Function(int count) onAddUpdate;
  final VoidCallback onAddEnd;
  final VoidCallback onAddCancel;

  /// The tag flyout picked a mode for the run edge; null clears it
  /// (None). [scopeToSelection] carries the flyout's EXPLICIT choice
  /// (UI-R19 #2): "Repeat" = the whole run even while a selection is
  /// live; "Repeat selection" = the selection scopes the pattern.
  final void Function(
    LayerId layerId,
    int blockStartIndex,
    TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode, {
    bool scopeToSelection,
  })
  onEdgeModeSelected;

  /// Whether the LIVE frame-range selection can scope a repeat pattern
  /// on this edge — gates the flyout's "Repeat selection" entry. Null =
  /// the entry never shows (hosts without selection support).
  final bool Function(
    LayerId layerId,
    int blockStartIndex,
    TimelineRunEdgeSide side,
  )?
  canScopeToSelection;
}

/// The cluster's main-axis extent: half a frame cell, zoom-scaled and
/// clamped (UI-R11 #13 replaced the old fixed 14px chips).
double timelineRunClusterMainExtent(double frameCellExtent) =>
    (frameCellExtent / 2).clamp(7.0, 24.0);

/// The glyph size the property letter uses; [+] draws two points larger.
double timelineRunClusterGlyphSize(double frameCellExtent) =>
    (frameCellExtent * 0.5).clamp(7.0, 12.0);

/// One run edge's affordance cluster, resolved but not yet drawn.
///
/// Identity vs display (UI-R11 #1/#2): [blockStartIndex] and [runKey]
/// come from the COMMITTED run (stable across drags — R12-③), while
/// [run] is the DISPLAY run, so the cluster rides block moves and live [+]
/// adds.
class TimelineRunEdgeCluster {
  const TimelineRunEdgeCluster({
    required this.side,
    required this.blockStartIndex,
    required this.runKey,
    required this.mode,
    required this.hasPattern,
    required this.run,
  });

  final TimelineRunEdgeSide side;
  final int blockStartIndex;

  /// The COMMITTED run's key: its start index, which no preview moves.
  ///
  /// F-134: this was the frame id of the run's first block, and linked
  /// blocks share one — two runs opening on the same drawing wore the same
  /// target ids.
  final String runKey;

  /// The edge's current mode; null = None. Display stays quiet either
  /// way — the letter changes, never an accent (UI-R10 #1).
  final TimelineRunEdgeMode? mode;

  /// A selection-scoped repeat pattern is live on this edge (UI-R19 #2):
  /// the flyout's "Repeat selection" entry reads checked from it.
  final bool hasPattern;

  /// The DISPLAY run, in frames: the edge the cluster stands beside, and
  /// the room its size is measured against ([timelineRunClusterRect]).
  final ({int startIndex, int endIndexExclusive}) run;

  /// The letter the property tag prints.
  String get modeLetter => switch (mode) {
    TimelineRunEdgeMode.hold => 'H',
    TimelineRunEdgeMode.repeat => 'R',
    null => 'N',
  };

  @override
  bool operator ==(Object other) =>
      other is TimelineRunEdgeCluster &&
      other.side == side &&
      other.blockStartIndex == blockStartIndex &&
      other.runKey == runKey &&
      other.mode == mode &&
      other.hasPattern == hasPattern &&
      other.run == run;

  @override
  int get hashCode =>
      Object.hash(side, blockStartIndex, runKey, mode, hasPattern, run);
}

/// A selection-scoped repeat pattern's span (UI-R10 #5 / UI-R19 #2).
class TimelineRunPatternSpan {
  const TimelineRunPatternSpan({
    required this.runKey,
    required this.side,
    required this.mainStart,
    required this.mainExtent,
  });

  /// The committed run's key ([TimelineRunEdgeCluster.runKey]).
  final String runKey;
  final TimelineRunEdgeSide side;
  final double mainStart;
  final double mainExtent;

  @override
  bool operator ==(Object other) =>
      other is TimelineRunPatternSpan &&
      other.runKey == runKey &&
      other.side == side &&
      other.mainStart == mainStart &&
      other.mainExtent == mainExtent;

  @override
  int get hashCode => Object.hash(runKey, side, mainStart, mainExtent);
}

/// The run-edge chrome one row shows: a cluster per glued run edge plus any
/// pattern spans.
class TimelineRunEdgeChrome {
  const TimelineRunEdgeChrome({required this.clusters, required this.patterns});

  static const TimelineRunEdgeChrome none = TimelineRunEdgeChrome(
    clusters: [],
    patterns: [],
  );

  final List<TimelineRunEdgeCluster> clusters;
  final List<TimelineRunPatternSpan> patterns;
}

/// Resolves the run-edge clusters hugging each glued run (UI-R11 #13).
///
/// Ghost runs themselves get no clusters (their timing is derived).
TimelineRunEdgeChrome timelineRunEdgeChrome({
  required Layer layer,
  Layer? baseLayer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required double leadingFrameSpacerWidth,
  required double frameCellExtent,
}) {
  final identity = baseLayer ?? layer;
  final clusters = <TimelineRunEdgeCluster>[];
  final patterns = <TimelineRunPatternSpan>[];
  final seenRunStarts = <int>{};

  // ONE pass each for the two things this loop used to ask per block. Both
  // helpers scan the whole timeline, and asking them inside the loop made
  // resolving a row's chrome O(n²) — which is what a zoom step pays, since
  // the geometry moved and the model has to come out again.
  final identityRuns = gluedRunsByBlockStart(identity);
  final displayRuns = identical(layer, identity)
      ? identityRuns
      : gluedRunsByBlockStart(layer);
  final identityStarts = _startsByFrameId(identity);
  final displayStarts = identical(layer, identity)
      ? identityStarts
      : _startsByFrameId(layer);

  double edgeX(int frameIndex) => frameVisibleX(
    frameIndex: frameIndex,
    frameStartIndex: frameStartIndex,
    frameCellWidth: frameCellExtent,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
  );

  // Where a committed block sits in the DISPLAY row: at the SAME occurrence
  // of its drawing — the k-th block showing a drawing in the committed row is
  // the k-th showing it in the preview. Without a preview the two rows are
  // one and the answer is exact; a cross-layer move preview can leave the
  // block absent entirely, and then it simply never lands. 🚨F-134: the
  // lowest occurrence alone sent a linked copy's run to the FIRST run showing
  // its drawing, so the copy had no [+] or property tag of its own.
  int? displayStartOf(int identityBlockStart) {
    final frameId = identity.timeline[identityBlockStart]!.frameId!;
    final ordinal = identityStarts[frameId]!.indexOf(identityBlockStart);
    final candidates = displayStarts[frameId];
    return candidates == null || ordinal >= candidates.length
        ? null
        : candidates[ordinal];
  }

  for (final key in identity.timeline.keys) {
    final entry = identity.timeline[key]!;
    if (!entry.isDrawing || entry.ghost) {
      continue;
    }
    final baseRun = identityRuns[key];
    if (baseRun == null || !seenRunStarts.add(baseRun.startIndex)) {
      continue;
    }
    // Resolve the LIVE display run for positions/modes: previews shift
    // the anchor block, the glued run containing it is the visual unit.
    final displayAnchorStart = displayStartOf(baseRun.startIndex);
    if (displayAnchorStart == null) {
      continue;
    }
    final run = displayRuns[displayAnchorStart];
    if (run == null ||
        run.endIndexExclusive < frameStartIndex ||
        run.startIndex > frameEndIndexExclusive) {
      continue;
    }

    final endBehavior = runEdgeBehaviorIn(layer, run, TimelineRunEdgeSide.end);
    final startBehavior = runEdgeBehaviorIn(
      layer,
      run,
      TimelineRunEdgeSide.start,
    );
    final runKey = '${baseRun.startIndex}';

    // A selection-scoped repeat pattern shows its span (UI-R10 #5).
    for (final (side, behavior) in [
      (TimelineRunEdgeSide.end, endBehavior),
      (TimelineRunEdgeSide.start, startBehavior),
    ]) {
      final bound = behavior?.patternBlockStart;
      if (bound == null) {
        continue;
      }
      final (spanStart, spanEnd) = side == TimelineRunEdgeSide.end
          ? (bound, run.endIndexExclusive)
          : (run.startIndex, bound + layer.timeline[bound]!.length!);
      final start = edgeX(spanStart);
      patterns.add(
        TimelineRunPatternSpan(
          runKey: runKey,
          side: side,
          mainStart: start,
          mainExtent: edgeX(spanEnd) - start,
        ),
      );
    }

    // END cluster on the display run edge.
    final displayRun = (
      startIndex: run.startIndex,
      endIndexExclusive: run.endIndexExclusive,
    );
    clusters.add(
      TimelineRunEdgeCluster(
        side: TimelineRunEdgeSide.end,
        blockStartIndex: baseRun.startIndex,
        runKey: runKey,
        mode: endBehavior?.mode,
        hasPattern: endBehavior?.patternBlockStart != null,
        run: displayRun,
      ),
    );

    // START cluster mirror.
    if (run.startIndex > 0) {
      clusters.add(
        TimelineRunEdgeCluster(
          side: TimelineRunEdgeSide.start,
          blockStartIndex: baseRun.startIndex,
          runKey: runKey,
          mode: startBehavior?.mode,
          hasPattern: startBehavior?.patternBlockStart != null,
          run: displayRun,
        ),
      );
    }
  }
  return TimelineRunEdgeChrome(clusters: clusters, patterns: patterns);
}

/// Every non-ghost block start of [layer], grouped by the drawing it shows,
/// in timeline order — the occurrences [timelineRunEdgeChrome] pairs up.
Map<FrameId, List<int>> _startsByFrameId(Layer layer) {
  final starts = <FrameId, List<int>>{};
  for (final entry in layer.timeline.entries) {
    final frameId = entry.value.frameId;
    if (entry.value.ghost || frameId == null) {
      continue;
    }
    (starts[frameId] ??= []).add(entry.key);
  }
  return starts;
}

/// The cluster's box in row-local coordinates: its extent
/// ([timelineRunClusterMainExtent]) beside the run's edge — after its end,
/// before its start — and ONE CELL where the run is shorter than that.
///
/// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q3, 「삼각형과 같은 법」): at
/// I-22's ten-minute floor the 7px cluster covered 56 frames, and a row of
/// short runs laid its buttons over one another and over the cells a press
/// was meant for. It keeps its size while its run holds it and takes one
/// cell where it does not — the block edge's law
/// (`timelineBlockEdgeGripPlacement`), asked through the same resolution.
Rect timelineRunClusterRect({
  required TimelineRunEdgeCluster cluster,
  required TimelineFrameGeometry geometry,
  required double crossAxisExtent,
  required Axis axis,
}) {
  final end = cluster.side == TimelineRunEdgeSide.end;
  return timelineFrameSpanRect(
    TimelineFrameSpanPlacement(
      startIndex: end ? cluster.run.endIndexExclusive : cluster.run.startIndex,
      mainExtent: timelineRunClusterMainExtent(geometry.frameCellExtent),
      anchorAtTrailingEdge: !end,
      fitsIn: cluster.run,
    ),
    geometry,
    crossAxisExtent: crossAxisExtent,
    axis: axis,
  );
}

/// How much of its size a cluster's glyph is drawn at in [slot]: all of it
/// while the cluster keeps its extent, and the share its box kept where a
/// short run gave it one cell — the triangle fills its box the same way.
double timelineRunClusterGlyphFit(
  Rect slot, {
  required Axis axis,
  required double frameCellExtent,
}) => math.min(
  1,
  extentAlong(axis, slot.size) / timelineRunClusterMainExtent(frameCellExtent),
);

/// [+] takes the first half of the CROSS axis, the property letter the
/// second, so the very next frame stays visible beside them (UI-R11 #13).
(Rect add, Rect tag) timelineRunClusterHalves(Rect cluster, Axis axis) =>
    axis == Axis.horizontal
    ? (
        Rect.fromLTRB(
          cluster.left,
          cluster.top,
          cluster.right,
          cluster.center.dy,
        ),
        Rect.fromLTRB(
          cluster.left,
          cluster.center.dy,
          cluster.right,
          cluster.bottom,
        ),
      )
    : (
        Rect.fromLTRB(
          cluster.left,
          cluster.top,
          cluster.center.dx,
          cluster.bottom,
        ),
        Rect.fromLTRB(
          cluster.center.dx,
          cluster.top,
          cluster.right,
          cluster.bottom,
        ),
      );

/// The 3-state TEXT color (UI-R11 #13: no chrome — the glyph carries every
/// state): rest dim, hover white, operating accent.
Color timelineRunGlyphColor(
  ColorScheme colorScheme, {
  required bool hovered,
  required bool operating,
}) {
  if (operating) {
    return colorScheme.primary;
  }
  if (hovered) {
    return Colors.white;
  }
  return colorScheme.onSurfaceVariant.withValues(alpha: 0.65);
}

/// Draws one cluster glyph centred in its half, bold on one line of [type]
/// — the size, the ink and the app's face are the caller's. Set from
/// scratch here, the glyphs named no face and wrote in the OS's font
/// (「앱은 한 글꼴」, 08-28).
void paintTimelineRunGlyph(
  Canvas canvas, {
  required String text,
  required Rect slot,
  required TextStyle type,
}) {
  final glyph = timelineGlyphPainter(
    text,
    type.copyWith(height: 1, fontWeight: FontWeight.w700),
  );
  glyph.paint(
    canvas,
    Offset(
      slot.center.dx - glyph.width / 2,
      slot.center.dy - glyph.height / 2,
    ),
  );
}

/// The pattern span's outline (UI-R19 #2).
///
/// This used to be the app's only production use of a second accent hue,
/// whose whole job was to read differently from a plain selection. The hue is
/// gone — and it must NOT be replaced by the accent, because the accent is
/// what "selected" means: a frame-range selection on this very row is accent
/// at 0.18 behind a 2px solid accent border, so an accent span would be
/// impersonating the thing it exists to differ from.
///
/// A pattern span is a MARK ON PAPER, so it wears the ground law's ink,
/// the way the block-edge grips beside it already do — [ground] is the
/// color of what it sits on, not the theme's brightness. And it is DASHED,
/// because a repeat pattern should say what it is rather than merely that
/// it is not a selection. It now differs from a selection in ink and in
/// edge, where it used to differ in hue and nothing.
///
/// [corner] is the blocks' own (`timelineBlockCornerRadiusAt`) — the span
/// outlines a run of them, so it rounds as they do at every zoom.
void paintTimelineRunPatternSpan(
  Canvas canvas,
  Rect rect, {
  required Radius corner,
  Color ground = timelineDrawingHeldColor,
}) {
  final ink = timelineTextOnColor(ground);
  final rrect = RRect.fromRectAndRadius(rect, corner);
  canvas.drawRRect(rrect, Paint()..color = ink.withValues(alpha: 0.06));
  final stroke = Paint()
    ..color = ink.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final path = Path()..addRRect(rrect.deflate(1));
  for (final metric in path.computeMetrics()) {
    var start = 0.0;
    while (start < metric.length) {
      final end = math.min(start + _patternDashLength, metric.length);
      canvas.drawPath(metric.extractPath(start, end), stroke);
      start = end + _patternDashGap;
    }
  }
}

const double _patternDashLength = 5;
const double _patternDashGap = 4;
