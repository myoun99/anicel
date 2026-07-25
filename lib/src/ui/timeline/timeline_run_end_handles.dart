import 'package:flutter/material.dart';

import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_repeat.dart';
import '../theme/app_theme.dart' show AppColors;
import 'timeline_frame_coordinate_policy.dart';
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
/// Identity vs display (UI-R11 #1/#2): [blockStartIndex] and [anchorValue]
/// come from the COMMITTED run (stable across drags — R12-③), while
/// [edgeOffset] follows the DISPLAY run, so the cluster rides block moves
/// and live [+] adds.
class TimelineRunEdgeCluster {
  const TimelineRunEdgeCluster({
    required this.side,
    required this.blockStartIndex,
    required this.anchorValue,
    required this.mode,
    required this.hasPattern,
    required this.edgeOffset,
  });

  final TimelineRunEdgeSide side;
  final int blockStartIndex;
  final String anchorValue;

  /// The edge's current mode; null = None. Display stays quiet either
  /// way — the letter changes, never an accent (UI-R10 #1).
  final TimelineRunEdgeMode? mode;

  /// A selection-scoped repeat pattern is live on this edge (UI-R19 #2):
  /// the flyout's "Repeat selection" entry reads checked from it.
  final bool hasPattern;

  /// Main-axis offset of the DISPLAY run edge.
  final double edgeOffset;

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
      other.anchorValue == anchorValue &&
      other.mode == mode &&
      other.hasPattern == hasPattern &&
      other.edgeOffset == edgeOffset;

  @override
  int get hashCode =>
      Object.hash(side, blockStartIndex, anchorValue, mode, hasPattern, edgeOffset);
}

/// A selection-scoped repeat pattern's span (UI-R10 #5 / UI-R19 #2).
class TimelineRunPatternSpan {
  const TimelineRunPatternSpan({
    required this.anchorValue,
    required this.side,
    required this.mainStart,
    required this.mainExtent,
  });

  final String anchorValue;
  final TimelineRunEdgeSide side;
  final double mainStart;
  final double mainExtent;

  @override
  bool operator ==(Object other) =>
      other is TimelineRunPatternSpan &&
      other.anchorValue == anchorValue &&
      other.side == side &&
      other.mainStart == mainStart &&
      other.mainExtent == mainExtent;

  @override
  int get hashCode => Object.hash(anchorValue, side, mainStart, mainExtent);
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
  final displayStartByFrameId = <FrameId, int>{};
  for (final entry in layer.timeline.entries) {
    final frameId = entry.value.frameId;
    if (entry.value.ghost || frameId == null) {
      continue;
    }
    // Lowest non-ghost display start wins (a cross-layer move preview can
    // leave the block absent entirely — then it simply never lands here).
    displayStartByFrameId.putIfAbsent(frameId, () => entry.key);
  }

  double edgeX(int frameIndex) => frameVisibleX(
    frameIndex: frameIndex,
    frameStartIndex: frameStartIndex,
    frameCellWidth: frameCellExtent,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
  );

  int? displayStartOf(FrameId frameId) => displayStartByFrameId[frameId];

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
    final displayAnchorStart = displayStartOf(baseRun.anchorFrameId);
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

    // A selection-scoped repeat pattern shows its span (UI-R10 #5).
    for (final behavior in [endBehavior, startBehavior]) {
      if (behavior == null ||
          behavior.mode != TimelineRunEdgeMode.repeat ||
          behavior.patternAnchorFrameId == null) {
        continue;
      }
      final anchorStart = displayStartOf(behavior.patternAnchorFrameId!);
      if (anchorStart == null ||
          anchorStart < run.startIndex ||
          anchorStart >= run.endIndexExclusive) {
        continue;
      }
      final (spanStart, spanEnd) = behavior.side == TimelineRunEdgeSide.end
          ? (anchorStart, run.endIndexExclusive)
          : (
              run.startIndex,
              anchorStart + layer.timeline[anchorStart]!.length!,
            );
      final start = edgeX(spanStart);
      patterns.add(
        TimelineRunPatternSpan(
          anchorValue: behavior.anchorFrameId.value,
          side: behavior.side,
          mainStart: start,
          mainExtent: edgeX(spanEnd) - start,
        ),
      );
    }

    // END cluster on the display run edge.
    clusters.add(
      TimelineRunEdgeCluster(
        side: TimelineRunEdgeSide.end,
        blockStartIndex: baseRun.startIndex,
        anchorValue: baseRun.anchorFrameId.value,
        mode: endBehavior?.mode,
        hasPattern: endBehavior?.patternAnchorFrameId != null,
        edgeOffset: edgeX(run.endIndexExclusive),
      ),
    );

    // START cluster mirror.
    if (run.startIndex > 0) {
      clusters.add(
        TimelineRunEdgeCluster(
          side: TimelineRunEdgeSide.start,
          blockStartIndex: baseRun.startIndex,
          anchorValue: baseRun.anchorFrameId.value,
          mode: startBehavior?.mode,
          hasPattern: startBehavior?.patternAnchorFrameId != null,
          edgeOffset: edgeX(run.startIndex),
        ),
      );
    }
  }
  return TimelineRunEdgeChrome(clusters: clusters, patterns: patterns);
}

/// The cluster's box in row-local coordinates, given its display edge.
Rect timelineRunClusterRect({
  required TimelineRunEdgeCluster cluster,
  required double frameCellExtent,
  required double crossAxisExtent,
  required Axis axis,
}) {
  final mainExtent = timelineRunClusterMainExtent(frameCellExtent);
  final mainStart = cluster.side == TimelineRunEdgeSide.end
      ? cluster.edgeOffset
      : cluster.edgeOffset - mainExtent;
  return axis == Axis.horizontal
      ? Rect.fromLTWH(mainStart, 0, mainExtent, crossAxisExtent)
      : Rect.fromLTWH(0, mainStart, crossAxisExtent, mainExtent);
}

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

/// Draws one cluster glyph centred in its half.
void paintTimelineRunGlyph(
  Canvas canvas, {
  required String text,
  required Rect slot,
  required double fontSize,
  required Color color,
}) {
  final glyph = timelineGlyphPainter(
    text,
    TextStyle(
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
  glyph.paint(
    canvas,
    Offset(
      slot.center.dx - glyph.width / 2,
      slot.center.dy - glyph.height / 2,
    ),
  );
}

/// The pattern span's wash + outline (UI-R19 #2, ACCENT 2 per UI-R22 #5).
void paintTimelineRunPatternSpan(Canvas canvas, Rect rect) {
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
  canvas
    ..drawRRect(
      rrect,
      Paint()..color = AppColors.accent2.withValues(alpha: 0.10),
    )
    ..drawRRect(
      rrect.deflate(1),
      Paint()
        ..color = AppColors.accent2.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
}
