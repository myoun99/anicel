import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../../models/layer.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../text/word_condensation.dart';
import 'axis_turn.dart';
import 'timeline_beat_lines.dart' show timelineRowPaperExtent;
import 'timeline_cell_style.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_policy.dart'
    show timelineRunLengthLabel;
import 'timeline_frame_window.dart' show visibleFrameWindowFor;
import 'timeline_glyph_cache.dart';
import '../repaint_props.dart';
import 'memo_token.dart';

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

/// The koma number's type size — the same at every zoom (B, 2026-09-24).
const double timelineRunLabelFontSize = 9;

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
class TimelineRowRunLabelsPainter extends CustomPainter with RepaintOnProps {
  TimelineRowRunLabelsPainter({
    required this.layer,
    required this.geometry,
    required this.crossAxisExtent,
    required this.showSeconds,
    required this.countingBase,
    required this.baseTextStyle,
    this.axis = Axis.horizontal,
    this.windowBucket,
    this.viewportMainExtent = 0,
    // F-24: the labels no longer ask what they are sitting on, so this
    // painter no longer watches the cel-content revision either — the ink
    // is the block's ink whatever the block holds.
  }) : super(repaint: Listenable.merge([geometry, ?windowBucket]));

  final Layer layer;

  /// The row's scroll window, as its cells take it (UI-R15): a paint prints
  /// the labels of the blocks the window can show and repaints once per span
  /// crossing.
  ///
  /// 🚨I-22 ③: the labels ride the cells painter as its foreground, so they
  /// paint whenever the cells do — at every span crossing of a scroll — and
  /// they printed every block's number on the row while the cells drew what
  /// the window reaches (95ms of a 769ms scroll sample at 24px, profile).
  /// Null keeps the whole row, for a host that shows all of it.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The ambient text style the row sits in — the app's face. The number
  /// is printed the way the block's NAME is ([timelineBlockWordStyle]).
  final TextStyle baseTextStyle;

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
  /// 🚨F-24: the COLOR is real now. It used to be layout/cache identity
  /// only, because paint() ran the label through the ground law and
  /// whatever black-or-white that resolved to superseded this; the label
  /// takes the block's own ink instead ([timelineInBlockInk]), which is
  /// what the cel NAME inside the block has always worn.
  ///
  /// ⚠️The 0.72 stays. It is what separates a block's length from its
  /// name at a glance, it is what is on screen today wherever the ink was
  /// already dark, and the report was about the number turning WHITE —
  /// not about how strong it is.
  ///
  /// 🚨ONE SIZE AT EVERY ZOOM (유저 2026-09-24, B): the number narrows into
  /// its block instead ([paint]). ↩️It shrank with the cell and with a
  /// squeezed row (R26 #38 · #15), and it was set from a bare `TextStyle`,
  /// which named no face — so it drew in the OS's font while the name beside
  /// it drew in the app's.
  TextStyle get labelStyle => timelineBlockWordStyle(
    baseTextStyle,
    ink: timelineInBlockInk().withValues(alpha: 0.72),
    fontSize: timelineRunLabelFontSize,
    bold: true,
  );

  /// Every label this row would draw, in block order — THE probe surface.
  List<TimelineRunLabel> runLabels() =>
      _labelsIn(frameStartIndex, frameEndIndexExclusive);

  /// The labels a paint prints: those whose block reaches the frames the
  /// window can show ([windowBucket]).
  List<TimelineRunLabel> runLabelsInWindow() {
    final window = visibleFrameWindowFor(
      bucket: windowBucket,
      viewportMainExtent: viewportMainExtent,
      cellExtent: frameCellExtent,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
    );
    return _labelsIn(window.startIndex, window.endIndexExclusive);
  }

  /// The row's blocks as `(start, length)`, in order — whatever the row.
  ///
  /// 🗣️F-228 (유저 2026-09-29): 「디렉션레이어나 트랜지션레이어만
  /// 코마텍스트가 없는데, 블록이라면 전부 코마텍스트가 존재해야함.
  /// 통일해서 적용」. A transition row has no timeline of its own — its
  /// blocks are the spans it stores ([LayerKind.bandIsInstructionsOnly]);
  /// every other row keeps its blocks on the timeline, the direction row's
  /// included (R27: its spans ride its blocks). Ghosts stay unlabeled.
  Iterable<(int, int)> get _blocks sync* {
    if (layer.kind.bandIsInstructionsOnly) {
      for (final MapEntry(:key, :value) in layer.instructions.entries) {
        yield (key, value.length);
      }
      return;
    }
    for (final MapEntry(:key, :value) in layer.timeline.entries) {
      if (value.isDrawing && !value.ghost) {
        yield (key, value.length ?? 1);
      }
    }
  }

  /// The labels of the blocks that reach frames [from, to), in block order.
  List<TimelineRunLabel> _labelsIn(int from, int to) {
    final labels = <TimelineRunLabel>[];
    for (final (startIndex, length) in _blocks) {
      final endIndexExclusive = startIndex + length;
      if (!frameRangesOverlap(startIndex, endIndexExclusive, from, to)) {
        continue;
      }
      // D23: a 1-comma block prints nothing — paint and semantics fall
      // silent together (the semantics builder iterates these labels).
      final text = timelineRunLengthLabel(
        endIndexExclusive - startIndex,
        showSeconds: showSeconds,
        countingBase: countingBase,
      );
      if (text == null) {
        continue;
      }
      final start = _edge(startIndex);
      final end = _edge(endIndexExclusive);
      // The centre of the block's LAST cell, row-local — the cell the law
      // laid (F-220), not the zoom's nominal width.
      final lastCellCentre = (_edge(endIndexExclusive - 1) + end) / 2;
      labels.add(
        TimelineRunLabel(
          startIndex: startIndex,
          endIndexExclusive: endIndexExclusive,
          text: text,
          // Frame axis: the last cell's centre. Cross axis: the far end
          // (R10).
          anchor: offsetAlong(
            axis,
            along: lastCellCentre,
            across: crossAxisExtent,
          ),
        ),
      );
      assert(!start.isNaN);
    }
    return labels;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final style = labelStyle;
    for (final label in runLabelsInWindow()) {
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
      // pushed to the far end of the cross axis — the paper's far edge, a
      // seam short of the row's (I-44): the timeline's bottom, the X-sheet's
      // right. The cross axis is what keeps the badge clear of the cel
      // name, which centres in the cell.
      // ↩️F-96: centred while it fits; a number wider than the cell ends at
      // the cell and grows back into its block — and (B) narrows only once
      // it would leave the block ([timelineBlockWordLayout]).
      final paper = timelineRowPaperExtent(crossAxisExtent);
      final lastCellStart = _edge(label.endIndexExclusive - 1);
      final layout = timelineBlockWordLayout(glyph.size, (
        axis: axis,
        room: axis == Axis.horizontal
            ? Rect.fromLTRB(blockStart, 0, blockEnd, paper)
            : Rect.fromLTRB(0, blockStart, paper, blockEnd),
        cellStart: lastCellStart,
        cellExtent: blockEnd - lastCellStart,
        growth: TimelineBlockWordGrowth.towardBlockStart,
        acrossAlignment: 1,
      ));
      // 🚨F-24: the block's OWN ink, the one the cel name inside the block
      // already wears — not the ground law. The number and the name sit on
      // the same paper and now say so in the same colour.
      paintFittedText(canvas, glyph, layout.origin, layout.fit);
      canvas.restore();
    }
  }

  @override
  // Geometry is absent on purpose — it arrives through `repaint`.
  Object get props =>
      (
        ByIdentity(layer),
        crossAxisExtent,
        showSeconds,
        countingBase,
        baseTextStyle,
        axis,
        ByIdentity(windowBucket),
        viewportMainExtent,
      );
  // ⛔The cel-content comparison went with F-24. It was here because a
  // moved revision was a moved GROUND (the empty-cel blend) and the ink
  // read that ground; the ink is the block's own now, so what a block
  // holds is no longer a reason to repaint its number.

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
