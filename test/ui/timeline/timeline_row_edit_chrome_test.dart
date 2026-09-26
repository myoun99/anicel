import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show
        TimelineRowEditChromePainter,
        TimelineRowRunAddTarget,
        TimelineRowRunTagTarget;
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';

import '../../helpers/app_faces.dart';
import 'timeline_frame_geometry_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// R28 #4 tier 2: a dense row's grips and run clusters are ONE painter plus
/// ONE gesture layer. The point of the change is the cost of a zoom step, so
/// these pin the properties that make the collapse safe:
///
///  * the row mounts no per-affordance widgets at all (the regression guard —
///    re-adding one silently brings the zoom cost back),
///  * a press ON an affordance still belongs to it (UI-R10 #12), and
///  * a press anywhere ELSE still falls through to the cells, which a
///    row-wide layer would otherwise swallow whole.
void main() {
  /// Blocks [0,2) and [4,6): two separate glued runs with a gap between.
  Layer twoRunLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      4: const TimelineExposure.drawing(FrameId('f2'), length: 2),
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

  Widget harness({
    required List<int> seeks,
    List<(LayerId, int, TimelineBlockEdge)>? gripBegins,
    List<(LayerId, int, bool)>? addBegins,
    TextStyle face = const TextStyle(),
    Layer? layer,
    double frameCellExtent = 48,
    int frameEndIndexExclusive = 8,
  }) => MaterialApp(
    home: Scaffold(
      body: Material(
        child: DefaultTextStyle.merge(
          style: face,
          child: TimelineFrameCellsRow(
            layer: layer ?? twoRunLayer(),
            playbackFrameCount: 24,
            // Classic geometry: 48px cells put the grips at [0,12] / [84,96]
            // and run 0's end cluster at [96,120].
            geometry: testFrameGeometry(
              frameCellExtent: frameCellExtent,
              frameEndIndexExclusive: frameEndIndexExclusive,
            ),
            crossAxisExtent: 52,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: seeks.add,
            commaDrag: TimelineCommaDragCallbacks(
              onBegin: (layerId, start, edge) {
                gripBegins?.add((layerId, start, edge));
                return true;
              },
              onUpdate: (_) {},
              onEnd: () {},
              onCancel: () {},
            ),
            runEdit: TimelineRunEditCallbacks(
              onAddBegin: (layerId, start, {required atEnd}) {
                addBegins?.add((layerId, start, atEnd));
                return true;
              },
              onAddUpdate: (_) {},
              onAddEnd: () {},
              onAddCancel: () {},
              onEdgeModeSelected: (_, _, _, _, {scopeToSelection = false}) {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('the row draws its whole edit chrome and mounts NO widget per '
      'grip or run edge', (tester) async {
    await tester.pumpWidget(harness(seeks: []));

    expect(
      find.byType(BlockEdgeGrip),
      findsNothing,
      reason: 'the dense rows paint their grips; a widget here is the '
          'zoom-step cost coming back',
    );
    expect(timelineRowChromeIds(tester, 'layer-a'), [
      // Grips lead: the block edges keep comma-drag priority over a
      // neighbouring run cluster, exactly as the old Stack order gave them.
      'block-edge-grip-start-layer-a-0',
      'block-edge-grip-end-layer-a-0',
      'block-edge-grip-start-layer-a-1',
      'block-edge-grip-end-layer-a-1',
      'run-add-end-layer-a-0',
      'run-edge-tag-layer-a-0-end',
      'run-add-end-layer-a-4',
      'run-edge-tag-layer-a-4-end',
      'run-add-start-layer-a-4',
      'run-edge-tag-layer-a-4-start',
    ]);
  });

  testWidgets('a press on empty cells still seeks — the row-wide layer only '
      'accepts pointers that land on an affordance', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(harness(seeks: seeks));

    // x = 140 is frame 2, clear of block 0's end grip [84,96], of run 0's
    // end cluster [96,120] and of run 1's start cluster [168,192].
    await tester.tapAt(const Offset(140, 26));
    await tester.pump();

    expect(seeks, [2]);
  });

  testWidgets('a press ON a grip or a run cluster never seeks the playhead '
      'under it (UI-R10 #12)', (tester) async {
    final seeks = <int>[];
    final gripBegins = <(LayerId, int, TimelineBlockEdge)>[];
    final addBegins = <(LayerId, int, bool)>[];
    await tester.pumpWidget(
      harness(seeks: seeks, gripBegins: gripBegins, addBegins: addBegins),
    );

    // The end grip of block 0: a comma drag, not a seek.
    final gripCentre = timelineRowChromeCenter(
      tester,
      'layer-a',
      'block-edge-grip-end-layer-a-0',
    );
    final drag = await tester.startGesture(gripCentre);
    await drag.moveBy(const Offset(60, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(gripBegins, [
      (const LayerId('layer-a'), 0, TimelineBlockEdge.end),
    ]);

    // The [+] half of run 0's end cluster: an add, not a seek.
    await tester.tapAt(
      timelineRowChromeCenter(tester, 'layer-a', 'run-add-end-layer-a-0'),
    );
    await tester.pumpAndSettle();
    expect(addBegins, [(const LayerId('layer-a'), 0, true)]);

    expect(seeks, isEmpty, reason: 'a near-miss must not move the playhead');
  });

  testWidgets('hover lights ONLY the pointed affordance and picks its cursor', (
    tester,
  ) async {
    await tester.pumpWidget(harness(seeks: []));

    MouseCursor cursor() => tester
        .widget<MouseRegion>(
          find.descendant(
            of: timelineRowChromeFinder('layer-a'),
            matching: find.byType(MouseRegion),
          ),
        )
        .cursor;
    String? hovered() => timelineRowChromePainter(tester, 'layer-a')!.hoveredId;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // Parked clear of every affordance — the origin is inside block 0's
    // START grip.
    await mouse.addPointer(location: const Offset(400, 300));
    addTearDown(mouse.removePointer);
    await tester.pump();

    expect(hovered(), isNull);
    expect(cursor(), MouseCursor.defer);

    await mouse.moveTo(
      timelineRowChromeCenter(
        tester,
        'layer-a',
        'block-edge-grip-end-layer-a-0',
      ),
    );
    await tester.pump();
    expect(hovered(), 'block-edge-grip-end-layer-a-0');
    expect(cursor(), SystemMouseCursors.resizeColumn);

    // The property tag is a click target, not a resize one.
    await mouse.moveTo(
      timelineRowChromeCenter(tester, 'layer-a', 'run-edge-tag-layer-a-0-end'),
    );
    await tester.pump();
    expect(hovered(), 'run-edge-tag-layer-a-0-end');
    expect(cursor(), SystemMouseCursors.click);

    // Off every affordance the row hands the cursor back to the cells.
    await mouse.moveTo(const Offset(140, 26));
    await tester.pump();
    expect(hovered(), isNull);
    expect(cursor(), MouseCursor.defer);
  });

  testWidgets('the run glyphs are set in the app\'s face, taken from the '
      'ambient style (「앱은 한 글꼴」, 08-28)', (tester) async {
    await loadTheAppFaces();
    const face = TextStyle(fontFamily: 'BIZ UDPGothic');
    await tester.pumpWidget(harness(seeks: [], face: face));
    final painter = timelineRowChromePainter(tester, 'layer-a')!;

    // What each [+] and tag is written as, in the order they are painted.
    final glyph = timelineRunClusterGlyphSize(48);
    final written = [
      for (final target in painter.targets)
        if (target is TimelineRowRunAddTarget)
          ('+', glyph + 2)
        else if (target is TimelineRowRunTagTarget)
          (target.letter, glyph),
    ];
    List<double> widthsIn(TextStyle style) => [
      for (final (text, size) in written)
        (TextPainter(
          text: TextSpan(
            text: text,
            style: style.copyWith(
              fontSize: size,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout()).maxIntrinsicWidth,
    ];
    expect(written, hasLength(6), reason: 'the premise: three clusters');
    expect(
      widthsIn(face),
      isNot(widthsIn(const TextStyle())),
      reason: 'the premise: the two faces set the glyphs at different widths',
    );

    final painted = _PaintedWidths();
    painter.paint(painted, const Size(8 * 48, 52));
    expect(painted.widths, hasLength(written.length));
    final expected = widthsIn(face);
    for (var i = 0; i < written.length; i += 1) {
      expect(
        painted.widths[i],
        closeTo(expected[i], 0.5),
        reason: '`${written[i].$1}` — set from scratch it named no face and '
            'wrote in the OS\'s',
      );
    }
  });

  testWidgets('🗣️Q3: where a run is too short to hold its buttons they take '
      'one cell, and what they write keeps to it — at the ten-minute floor '
      'they all but vanish instead of covering the cells beside them', (
    tester,
  ) async {
    const cell = 1 / 8;
    await tester.pumpWidget(
      harness(
        seeks: [],
        // Ten frames at 400: a pixel and a quarter, and the buttons are 7.
        layer: Layer(
          id: const LayerId('layer-a'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            400: const TimelineExposure.drawing(FrameId('f1'), length: 10),
          },
        ),
        frameCellExtent: cell,
        frameEndIndexExclusive: 2000,
      ),
    );
    final painter = timelineRowChromePainter(tester, 'layer-a')!;
    final boxes = [
      for (final target in painter.targets)
        if (target is TimelineRowRunAddTarget)
          target.rect
        else if (target is TimelineRowRunTagTarget)
          target.rect,
    ];
    expect(boxes, hasLength(4), reason: 'the premise: two edges, two each');
    for (final box in boxes) {
      expect(box.width, closeTo(cell, 1e-9));
    }

    final painted = _PaintedWidths();
    painter.paint(painted, const Size(2000 * cell, 52));
    expect(painted.widths, hasLength(boxes.length));
    for (final width in painted.widths) {
      expect(width, lessThan(1), reason: 'a glyph the size of its box');
    }
  });

  testWidgets('a changed face repaints the run glyphs — the face turns with '
      'the language', (tester) async {
    Future<TimelineRowEditChromePainter> writtenIn(String family) async {
      await tester.pumpWidget(
        harness(seeks: [], face: TextStyle(fontFamily: family)),
      );
      return timelineRowChromePainter(tester, 'layer-a')!;
    }

    final first = await writtenIn('First');
    expect(
      (await writtenIn('First')).shouldRepaint(first),
      isFalse,
      reason: 'the premise: a rebuild with the same inputs does not repaint',
    );
    expect((await writtenIn('Second')).shouldRepaint(first), isTrue);
  });
}

/// The natural width of every paragraph painted, in painting order.
class _PaintedWidths implements Canvas {
  final widths = <double>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      widths.add(paragraph.maxIntrinsicWidth);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
