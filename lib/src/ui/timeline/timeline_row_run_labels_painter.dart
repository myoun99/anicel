import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../../models/layer.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_policy.dart' show timelineDurationLabel;
import 'timeline_glyph_cache.dart';

/// One block's printed length and where it sits — the probe surface tests
/// read instead of hunting for a widget key.
class TimelineRunLabel {
  const TimelineRunLabel({
    required this.startIndex,
    required this.endIndexExclusive,
    required this.text,
    required this.anchor,
  });

  final int startIndex;
  final int endIndexExclusive;

  /// The printed number ('48' or '2+0' — never an `f` suffix).
  final String text;

  /// The point the glyph centres on: the block's LAST cell, bottom-centre
  /// (R27 #3), in row-local coordinates.
  final Offset anchor;
}

/// R26 #7 / R27 #3: every frame block prints ITS OWN length — one label per
/// block, not the glued run's total. The shared display toggle picks frames
/// (`48`) or seconds+frames (`2+00`).
///
/// PAINTED, not a widget per block (R28 #4). These used to be a `Positioned`
/// per run, which made a zoom step re-lay-out rows x runs boxes: measured at
/// ~869ms per step on 29 rows, and the run count was the multiplier (4x the
/// runs cost 2.7x). Painting them collapses that to one draw pass per row.
///
/// It rides ABOVE the cells painter rather than inside it, which is what the
/// widget overlay was protecting: the cells painter bakes span TILES through
/// a native rasterizer, and a label that flips with the frames/seconds toggle
/// would otherwise have to join every bake key on both paths. A separate
/// painter keeps the toggle a plain repaint and leaves the tile keys alone.
///
/// Ghost blocks stay unlabeled: their timing is derived, the same rule the
/// run-edge clusters follow.
class TimelineRowRunLabelsPainter extends CustomPainter {
  TimelineRowRunLabelsPainter({
    required this.layer,
    required this.geometry,
    required this.crossAxisExtent,
    required this.showSeconds,
    required this.countingBase,
    this.axis = Axis.horizontal,
  }) : super(repaint: geometry);

  final Layer layer;

  /// The LIVE frame-axis geometry (R28 #4): a zoom step repaints this
  /// painter rather than rebuilding the row that built it.
  final TimelineFrameGeometryHandle geometry;

  final double crossAxisExtent;
  final bool showSeconds;
  final int countingBase;
  final Axis axis;

  int get frameStartIndex => geometry.value.frameStartIndex;
  int get frameEndIndexExclusive => geometry.value.frameEndIndexExclusive;
  double get frameCellExtent => geometry.value.frameCellExtent;

  double _edge(int frameIndex) => geometry.value.edgeAt(frameIndex);

  /// The resolved label style — public so the bold/scale contract stays
  /// assertable now that there is no `Text` widget to read it off.
  TextStyle get labelStyle => TextStyle(
    fontSize: timelineFittedGlyphFontSize(9, frameCellExtent),
    fontWeight: FontWeight.w700,
    color: timelineDrawingInkColor.withValues(alpha: 0.72),
  );

  /// Every label this row would draw, in block order — THE probe surface.
  List<TimelineRunLabel> runLabels() {
    final labels = <TimelineRunLabel>[];
    for (final key in layer.timeline.keys) {
      final entry = layer.timeline[key]!;
      if (!entry.isDrawing || entry.ghost) {
        continue;
      }
      final startIndex = key;
      final endIndexExclusive = key + (entry.length ?? 1);
      if (endIndexExclusive <= frameStartIndex ||
          startIndex >= frameEndIndexExclusive) {
        continue;
      }
      final start = _edge(startIndex);
      final end = _edge(endIndexExclusive);
      // The centre of the block's LAST cell, row-local.
      final lastCellCentre = end - frameCellExtent / 2;
      labels.add(
        TimelineRunLabel(
          startIndex: startIndex,
          endIndexExclusive: endIndexExclusive,
          text: timelineDurationLabel(
            endIndexExclusive - startIndex,
            showSeconds: showSeconds,
            countingBase: countingBase,
          ),
          anchor: axis == Axis.horizontal
              ? Offset(lastCellCentre, crossAxisExtent)
              : Offset(crossAxisExtent / 2, lastCellCentre),
        ),
      );
      assert(!start.isNaN);
    }
    return labels;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final style = labelStyle;
    for (final label in runLabels()) {
      final glyph = timelineGlyphPainter(label.text, style);
      // Clipped to its OWN block: a number wider than one cell spills back
      // over its own block, never into the neighbour's.
      final blockStart = _edge(label.startIndex);
      final blockEnd = _edge(label.endIndexExclusive);
      final blockRect = axis == Axis.horizontal
          ? Rect.fromLTRB(blockStart, 0, blockEnd, crossAxisExtent)
          : Rect.fromLTRB(0, blockStart, crossAxisExtent, blockEnd);
      canvas.save();
      canvas.clipRect(blockRect);
      // Bottom-aligned, 1px inset — the widget overlay's `bottom: 1`.
      final offset = axis == Axis.horizontal
          ? Offset(
              label.anchor.dx - glyph.width / 2,
              crossAxisExtent - glyph.height - 1,
            )
          : Offset(
              (crossAxisExtent - glyph.width) / 2,
              label.anchor.dy - glyph.height / 2,
            );
      glyph.paint(canvas, offset);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant TimelineRowRunLabelsPainter oldDelegate) =>
      // Geometry is absent on purpose — it arrives through `repaint`.
      !identical(oldDelegate.layer, layer) ||
      oldDelegate.crossAxisExtent != crossAxisExtent ||
      oldDelegate.showSeconds != showSeconds ||
      oldDelegate.countingBase != countingBase ||
      oldDelegate.axis != axis;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    // One node per label — the `Text` widgets these replaced carried their
    // own, and dropping them would take the surface away from screen readers
    // and from every test that reads the row by semantics.
    final nodes = <CustomPainterSemantics>[];
    for (final label in runLabels()) {
      final blockStart = _edge(label.startIndex);
      final blockEnd = _edge(label.endIndexExclusive);
      nodes.add(
        CustomPainterSemantics(
          rect: axis == Axis.horizontal
              ? Rect.fromLTRB(blockStart, 0, blockEnd, crossAxisExtent)
              : Rect.fromLTRB(0, blockStart, crossAxisExtent, blockEnd),
          properties: SemanticsProperties(
            label: label.text,
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };
}
