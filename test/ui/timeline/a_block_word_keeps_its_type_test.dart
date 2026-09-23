import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart' show FlipHudAxis;
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🚨B (유저 2026-09-24, `block-word-size-at-zoom-Q1`): 「글자크기 그냥
/// 유지하고 블록의 모든 공간 쓸수있게하고, 블록보다 작아지면 가로크기만
/// 줄인다」 — 「이름은 블록안에서만」 — 「법같은거 최대한 통일하면서.
/// 컷블록의 텍스트든 se텍스트든 뭐든」.
///
/// Every word a block writes keeps its type at every zoom, stays inside its
/// block, and narrows — each axis on its own — only where the block runs
/// short. These pin it on every surface that writes one: the frame block's
/// name and length, a lane key's name, an SE name, an instruction's
/// writing, the flip window and the folded row's fallback strip. (The
/// storyboard's labels are pinned in `storyboard_three_band_test`.)
///
/// ⚠️`flutter test` sets every glyph a full em wide, so words here are much
/// wider than on screen — which is what makes them run past their blocks.
void main() {
  const base = TextStyle(fontSize: 14, fontFamily: 'Face');
  const rowExtent = 28.0;
  // Blocks (start, length) and their names.
  const blocks = <(int, int)>[(0, 1), (1, 3), (4, 6)];
  const names = {0: 'A1234', 1: '12', 4: '1234567'};

  final layer = Layer(
    id: const LayerId('words'),
    name: 'A',
    frames: [
      for (final start in names.keys)
        Frame(id: FrameId('f$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final (start, length) in blocks)
        start: TimelineExposure.drawing(FrameId('f$start'), length: length),
    },
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  TimelineRowCellsPainter cellsPainter(
    double cell, {
    double crossExtent = rowExtent,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: cell,
      frameEndIndexExclusive: 16,
    ),
    crossAxisExtent: crossExtent,
    exposureStateForLayer: stateFor,
    frameNameForLayer: (_, frameIndex) => names[frameIndex],
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: base,
  );

  Size naturalName(TimelineRowCellsPainter painter, int start) {
    final model = painter.cellModelAt(start);
    return timelineGlyphPainter(model.glyph, painter.glyphStyleFor(model)).size;
  }

  const zooms = [48.0, 24.0, 12.0, 6.0, 2.4];

  group('a frame block\'s NAME', () {
    test('keeps one type size at every zoom', () {
      for (final cell in zooms) {
        final painter = cellsPainter(cell);
        for (final (start, _) in blocks) {
          expect(
            painter.glyphStyleFor(painter.cellModelAt(start)).fontSize,
            base.fontSize,
            reason: '$cell px cell, block at $start — ↩️it shrank below 14px '
                'cells (R26 #38)',
          );
        }
      }
    });

    test('stays inside its block and narrows only past it', () {
      for (final cell in zooms) {
        final painter = cellsPainter(cell);
        for (final (start, length) in blocks) {
          final word = naturalName(painter, start);
          final layout = painter.cellWordLayoutFor(start, word);
          final left = layout.origin.dx;
          final right = left + word.width * layout.fit.x;
          final blockLeft = painter.cellRectFor(start).left;
          final blockRight = blockLeft + length * cell;
          final what = '$cell px cell, block at $start';
          expect(left, greaterThanOrEqualTo(blockLeft - 1e-6), reason: what);
          expect(
            right,
            lessThanOrEqualTo(blockRight + 1e-6),
            reason: '$what: 「이름은 블록안에서만」',
          );
          expect(
            layout.fit.x < 1,
            word.width > length * cell,
            reason: '$what: narrowed exactly when the block runs short',
          );
          expect(
            layout.fit.y,
            1.0,
            reason: '$what: the row is tall enough — the height is kept',
          );
        }
      }
    });

    test('the painted word is that layout, not a word of its own', () {
      const cell = 6.0;
      final painter = cellsPainter(cell);
      final spy = _PaintedBoxes();
      painter.paint(spy, const Size(cell * 16, rowExtent));
      for (final (start, length) in blocks) {
        final blockLeft = painter.cellRectFor(start).left;
        final box = spy.boxes.firstWhere(
          (box) => (box.left - blockLeft).abs() < 0.5,
          orElse: () => fail('nothing painted at the block at $start'),
        );
        expect(
          box.right,
          lessThanOrEqualTo(blockLeft + length * cell + 0.5),
          reason: 'the block at $start',
        );
      }
    });

    test('a squeezed row narrows it ACROSS instead of shrinking the type', () {
      final painter = cellsPainter(24, crossExtent: 8);
      final word = naturalName(painter, 1);
      final layout = painter.cellWordLayoutFor(1, word);
      expect(painter.glyphStyleFor(painter.cellModelAt(1)).fontSize, 14);
      expect(layout.fit.y, lessThan(1));
      expect(
        word.height * layout.fit.y,
        lessThanOrEqualTo(7 + 1e-6),
        reason: 'inside the paper, a seam short of the 8px row',
      );
    });
  });

  group('a frame block\'s LENGTH (koma)', () {
    TimelineRowRunLabelsPainter runLabels(double cell) =>
        TimelineRowRunLabelsPainter(
          layer: layer,
          geometry: testFrameGeometry(
            frameCellExtent: cell,
            frameEndIndexExclusive: 16,
          ),
          crossAxisExtent: rowExtent,
          showSeconds: false,
          countingBase: 24,
          baseTextStyle: base,
        );

    test('keeps one size at every zoom, in the app\'s face', () {
      for (final cell in zooms) {
        final style = runLabels(cell).labelStyle;
        expect(style.fontSize, timelineRunLabelFontSize, reason: '$cell');
        expect(
          style.fontFamily,
          'Face',
          reason: 'a bare TextStyle named no face and drew in the OS\'s',
        );
      }
    });

    test('stays inside its block and narrows only past it', () {
      for (final cell in zooms) {
        final painter = runLabels(cell);
        final spy = _PaintedBoxes();
        painter.paint(spy, Size(cell * 16, rowExtent));
        final labels = painter.runLabels();
        expect(spy.boxes, hasLength(labels.length), reason: 'fixture');
        for (var i = 0; i < labels.length; i += 1) {
          final label = labels[i];
          final blockLeft = label.startIndex * cell;
          final blockRight = label.endIndexExclusive * cell;
          expect(
            spy.boxes[i].left,
            greaterThanOrEqualTo(blockLeft - 1e-6),
            reason: '$cell px, block at ${label.startIndex}',
          );
          expect(
            spy.boxes[i].right,
            lessThanOrEqualTo(blockRight + 1e-6),
            reason: '$cell px, block at ${label.startIndex}',
          );
          expect(
            spy.boxes[i].height,
            moreOrLessEquals(timelineRunLabelFontSize, epsilon: 1e-6),
            reason: 'the height is kept',
          );
        }
      }
    });
  });

  test('the glyph cache tells two faces of one word apart', () {
    const first = TextStyle(fontSize: 9, fontFamily: 'First');
    const second = TextStyle(fontSize: 9, fontFamily: 'Second');
    timelineGlyphPainter('12', first);
    expect(
      timelineGlyphPainter('12', second).text!.style!.fontFamily,
      'Second',
      reason: '↩️the cache keyed on colour, weight and size alone, so a '
          'number laid out in one face was served in another',
    );
  });

  group('a lane key\'s NAME', () {
    Future<void> pumpLane(
      WidgetTester tester, {
      required double cell,
      required Axis axis,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TimelineLaneFrameRow(
                layer: layer,
                lane: const PropertyLaneRow(
                  laneId: 'position',
                  label: 'Position',
                  keyedFrames: {2},
                  keyNames: {2: 'Walk'},
                ),
                frameStartIndex: 0,
                frameEndIndexExclusive: 12,
                leadingFrameSpacerWidth: 0,
                trailingFrameSpacerWidth: 0,
                metrics: TimelineGridMetrics.defaults.copyWith(
                  frameCellWidth: cell,
                ),
                axis: axis,
              ),
            ),
          ),
        ),
      );
    }

    for (final axis in Axis.values) {
      testWidgets('shows below 14px cells too, inside its cell ($axis)', (
        tester,
      ) async {
        const cell = 6.0;
        await pumpLane(tester, cell: cell, axis: axis);
        final word = find.text('Walk');
        expect(
          word,
          findsOneWidget,
          reason: '↩️it was dropped below 14px cells and on the X-sheet — '
              'both mine (2026-08-11), from when the name stood beside the '
              'diamond',
        );
        expect(
          find.ancestor(of: word, matching: find.byType(TimelineBlockWord)),
          findsOneWidget,
        );
        final origin = tester.getTopLeft(find.byType(TimelineLaneFrameRow));
        final painted = tester.getRect(word).shift(-origin);
        final along = axis == Axis.horizontal
            ? (painted.left, painted.right)
            : (painted.top, painted.bottom);
        expect(along.$1, greaterThanOrEqualTo(2 * cell - 1e-6));
        expect(along.$2, lessThanOrEqualTo(3 * cell + 1e-6));
      });
    }
  });

  testWidgets('an SE name narrows into its chip instead of shrinking whole', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 12,
              height: rowExtent,
              child: SeSpanVisual(
                axis: Axis.horizontal,
                dialogue: '',
                seName: 'ドアー',
              ),
            ),
          ),
        ),
      ),
    );
    final chip = find.bySemanticsLabel('SE name ドアー');
    expect(chip, findsOneWidget, reason: 'fixture');
    expect(
      find.descendant(of: chip, matching: find.byType(FittedBox)),
      findsNothing,
      reason: '↩️FittedBox.scaleDown shrank the name height with width',
    );
    final word = find.descendant(
      of: chip,
      matching: find.byType(TimelineBlockWord),
    );
    expect(word, findsOneWidget);
    final room = tester.getRect(word);
    final child = tester.renderObject<RenderBox>(
      find.descendant(of: word, matching: find.byType(ExcludeSemantics)).first,
    );
    final painted = MatrixUtils.transformRect(
      child.getTransformTo(null),
      Offset.zero & child.size,
    );
    expect(painted.left, greaterThanOrEqualTo(room.left - 1e-6));
    expect(painted.right, lessThanOrEqualTo(room.right + 1e-6));
    expect(painted.top, greaterThanOrEqualTo(room.top - 1e-6));
    expect(painted.bottom, lessThanOrEqualTo(room.bottom + 1e-6));
  });

  testWidgets('an instruction\'s writing stays inside its span', (
    tester,
  ) async {
    const cell = 12.0;
    const cells = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: cell * 8,
            height: rowExtent,
            child: TimelineFixedFrameSpanLayer(
              geometry: const TimelineFrameGeometry(
                frameCellExtent: cell,
                frameStartIndex: 0,
                frameEndIndexExclusive: 8,
              ),
              crossAxisExtent: rowExtent,
              axis: Axis.horizontal,
              children: timelineRowInstructionOverlays(
                layer: Layer(
                  id: const LayerId('cam'),
                  name: 'CAM',
                  kind: LayerKind.instruction,
                  frames: const [],
                  timeline: const {},
                  instructions: {
                    0: const InstructionEvent(
                      instructionId: 'pan',
                      length: cells,
                      valueA: 'FROMHERE',
                      valueB: 'TOTHERE',
                    ),
                  },
                ),
                frameStartIndex: 0,
                frameEndIndexExclusive: 8,
                axis: Axis.horizontal,
                defById: CameraInstructionSet.standard.defById,
              ),
            ),
          ),
        ),
      ),
    );
    final span = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-instruction-cam-0')),
    );
    for (final text in ['FROMHERE', 'TOTHERE']) {
      final painted = tester.getRect(find.text(text));
      expect(
        painted.left,
        greaterThanOrEqualTo(span.left - 1e-6),
        reason: '$text: ↩️it ran onto the neighbours\' cells (2026-07-09)',
      );
      expect(painted.right, lessThanOrEqualTo(span.right + 1e-6));
    }
  });

  test('the flip window\'s name keeps its type and narrows into its slot', () {
    const painter = FlipHudPainter(
      snapshot: FlipHudSnapshot(
        rows: [
          FlipHudRow(
            name: 'A',
            kind: LayerKind.animation,
            runs: [FlipHudRun(startIndex: 0, length: 1, label: 'LONGNAME')],
          ),
        ],
        rowIndex: 0,
        frameIndex: 0,
        frameCount: 8,
      ),
      axis: FlipHudAxis.frame,
      frameStep: true,
      colorScheme: ColorScheme.dark(),
      baseTextStyle: base,
    );
    final spy = _PaintedBoxes();
    painter.paint(spy, FlipHudMetrics.sizeFor(FlipHudAxis.frame));
    // The name is the one word at the block's type: 14px tall, as painted.
    final named = spy.boxes.where(
      (box) => (box.height - 14).abs() < 1e-6,
    );
    expect(named, isNotEmpty, reason: 'the name keeps its type');
    for (final box in named) {
      expect(
        box.width,
        lessThanOrEqualTo(FlipHudMetrics.frameCellWidth - 4 + 1e-6),
        reason: 'narrowed into its slot — ↩️it was cut to an ellipsis, '
            'whose paragraph still measured the whole name',
      );
    }
  });

  testWidgets('the folded row\'s fallback strip never drops a word', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: CollapsedRowOverlay(
              snapshot: FlipHudSnapshot(
                rows: [
                  FlipHudRow(
                    name: 'A',
                    kind: LayerKind.animation,
                    runs: [
                      FlipHudRun(startIndex: 0, length: 2, label: 'LONGNAME'),
                    ],
                  ),
                ],
                rowIndex: 0,
                frameIndex: 0,
                frameCount: 40,
              ),
              rail: null,
              naturalRailWidth: 100,
              pixelsPerFrame: 3,
              framesPerSecond: 24,
            ),
          ),
        ),
      ),
    );
    final strip = find.byKey(const ValueKey<String>('collapsed-strip'));
    final spy = _PaintedBoxes();
    tester.widget<CustomPaint>(strip).painter!.paint(
      spy,
      tester.getSize(strip),
    );
    // The block covers frames 0-1 (6px); the empty stretch's `x` opens at 2.
    final name = spy.boxes.where((box) => box.left < 2 * 3);
    expect(
      name,
      isNotEmpty,
      reason: '↩️a word whose room was under 10px was not drawn at all',
    );
    for (final box in name) {
      expect(
        box.right,
        lessThanOrEqualTo(2 * 3 + 1e-6),
        reason: 'and it stays inside its block',
      );
    }
  });
}

/// Every paragraph's box as PAINTED, following the transforms — a narrowed
/// word is drawn at the origin of a scaled canvas.
class _PaintedBoxes implements Canvas {
  final boxes = <Rect>[];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void saveLayer(Rect? bounds, Paint paint) => save();

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void rotate(double radians) =>
      _transform = _transform.multiplied(Matrix4.rotationZ(radians));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => boxes.add(
    MatrixUtils.transformRect(
      _transform,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
