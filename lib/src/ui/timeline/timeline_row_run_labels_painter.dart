import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../../models/layer.dart';
import '../theme/app_theme.dart' show AppColors;
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_cel_content_source.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_policy.dart'
    show timelineCommaLabelVisibleFor, timelineDurationLabel;
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

  /// Where the glyph sits, in row-local coordinates — ONE rule for both
  /// orientations (R27 #3, restored by R10):
  ///
  /// * the FRAME axis: the centre of the block's LAST cell;
  /// * the CROSS axis: the far end, 1px in — the timeline's bottom, the
  ///   X-sheet's right. A literal pixel, not a fraction of the extent.
  ///
  /// R9 #5 moved the frame axis to the block's END corner as well, to
  /// keep a one-frame block's badge off its cel name. The user read the
  /// result as the number falling off the block, and the cross-axis
  /// inset already separates the two: the name centres in the cell, the
  /// badge hangs under it.
  ///
  /// This is also what the storyboard's panel writing has always done,
  /// so the three surfaces are back to one rule.
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
    this.celContent,
    this.backdropColor = AppColors.surface,
  }) : super(repaint: Listenable.merge([geometry, ?celContent?.revision]));

  final Layer layer;

  /// The unworked-block tint's source (R26 #44), shared with the cells
  /// painter: a block whose cel holds no picture is the 43%-alpha paper
  /// over [backdropColor], and its label's GROUND is that blend — over the
  /// dark lane it lands on the light-ink side of [timelineTextOnColor]
  /// where the opaque paper takes the dark one. Null = every block reads
  /// as full paper (rows the tint never applies to).
  final TimelineCelContentSource? celContent;

  /// What an empty-cel block's translucent paper composites over — the
  /// row's underlay (`colorScheme.surface` in production).
  final Color backdropColor;

  /// Read LIVE like the cells painter's: the row repaints on a revision
  /// bump rather than rebuilding, so a captured value would hold
  /// yesterday's tint forever.
  int get celContentRevision => celContent?.revision.value ?? 0;

  bool Function(Layer layer, int frameIndex)? get celHasContent =>
      celContent?.hasContent;

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
  ///
  /// The COLOR is layout/cache identity only: paint() draws the label
  /// through the ground law ([paintTimelineGlyphOnGround]), whose resolved
  /// black/white solid supersedes any style color.
  TextStyle get labelStyle => TextStyle(
    fontSize: timelineFittedGlyphFontSize(
      9,
      frameCellExtent,
      // The vertical half of the fit rule (#15): a squeezed row shrinks
      // its numbers like a squeezed cell does.
      crossExtent: crossAxisExtent,
    ),
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
      // D23: a 1-comma block prints nothing — paint and semantics fall
      // silent together (the semantics builder iterates these labels).
      if (!timelineCommaLabelVisibleFor(endIndexExclusive - startIndex)) {
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
          // Frame axis: the last cell's centre. Cross axis: the far end
          // (R10).
          anchor: axis == Axis.horizontal
              ? Offset(lastCellCentre, crossAxisExtent)
              : Offset(crossAxisExtent, lastCellCentre),
        ),
      );
      assert(!start.isNaN);
    }
    return labels;
  }

  /// The COMPOSITED color under the block's label — THE ground the text
  /// law reads ([timelineTextOnColor]). A worked block is its layer's
  /// paper (⑲: the color label); an unworked one is that paper at the
  /// empty-cel alpha over the row's backdrop, blended here because
  /// luminance is a property of the pixels, not of a translucent color.
  Color groundForBlockAt(int startIndex) {
    final paper = layerMarkColor(layer.mark);
    if (celContent?.hasContent(layer, startIndex) ?? true) {
      return paper;
    }
    return Color.alphaBlend(timelineEmptyCelPaperColor(paper), backdropColor);
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
      // R10: CENTRED on the block's last cell along the frame axis, and
      // pushed to the far end of the cross axis with a 1px inset — the
      // timeline's bottom, the X-sheet's right. The cross axis is what
      // keeps the badge clear of the cel name, which centres in the cell.
      final offset = axis == Axis.horizontal
          ? Offset(
              label.anchor.dx - glyph.width / 2,
              crossAxisExtent - glyph.height - 1,
            )
          : Offset(
              crossAxisExtent - glyph.width - 1,
              label.anchor.dy - glyph.height / 2,
            );
      // The ground law (2026-08-17, one rule on every surface — the
      // difference blend replaced after it read navy on purple blocks):
      // solid black or white by the luminance of the block this label
      // sits on, which this painter KNOWS — the same layer paper the
      // cells painter fills beneath it.
      paintTimelineGlyphOnGround(
        canvas,
        offset,
        label.text,
        style,
        ground: groundForBlockAt(label.startIndex),
      );
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
      oldDelegate.axis != axis ||
      // Value-compared like the cells painter's: the tear-off bundle is a
      // fresh-but-equal object per build, but a moved REVISION is a moved
      // ground (the empty-cel blend) and must repaint the label's ink.
      oldDelegate.celHasContent != celHasContent ||
      oldDelegate.celContentRevision != celContentRevision ||
      oldDelegate.backdropColor != backdropColor;

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
