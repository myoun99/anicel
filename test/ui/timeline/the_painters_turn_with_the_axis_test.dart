import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// Every painter that serves both orientations is pinned on BOTH — the
/// characterisation the round-8 clone audit (C9) wrote before the
/// main/cross projection moved into `axis_turn.dart`.
///
/// 🚨The x-sheet is the timeline turned on its side, and the turn used to be
/// spelled by hand at the top of every `paint` (`horizontal ? size.width :
/// size.height`) — a fork per painter, each a place for one orientation to
/// lag the other. The horizontal side was pinned by the painters' own tests;
/// the VERTICAL side of most of them was not, which is how a projection
/// swapped in one painter would have shipped. These read the geometry off a
/// spy canvas where the drawing is lines and rects, and off pixels where it
/// is a filled path — a test on the painter's fields would pass while the
/// drawing moved.
class _CanvasSpy implements Canvas {
  final lines = <({Offset from, Offset to})>[];
  final rects = <Rect>[];
  final rrects = <Rect>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((from: p1, to: p2));

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect.outerRect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<Uint32List> _rasterize(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    try {
      final data = await image.toByteData();
      return data!.buffer.asUint32List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

bool _inked(Uint32List pixels, Size size, int x, int y) =>
    pixels[y * size.width.toInt() + x] != 0;

void main() {
  final scheme = buildAppTheme().colorScheme;

  group('TimelineBeatLinesPainter', () {
    // 16px cells: cadence 1, so every frame boundary carries a line.
    _CanvasSpy paint(Axis axis, Size size) {
      final spy = _CanvasSpy();
      TimelineBeatLinesPainter(
        frameCellExtent: 16,
        framesPerSecond: 24,
        colorScheme: scheme,
        ground: null,
        axis: axis,
        crossCellExtent: 10,
      ).paint(spy, size);
      return spy;
    }

    test('horizontal: frame lines stand up the height, seams lie across '
        'the width', () {
      final spy = paint(Axis.horizontal, const Size(48, 30));
      final frameLines = spy.lines.where((l) => l.from.dx == l.to.dx);
      final seams = spy.lines.where((l) => l.from.dy == l.to.dy);
      expect(frameLines.map((l) => l.from.dx), [16.5, 32.5, 48.5]);
      expect(
        frameLines.map((l) => (l.from.dy, l.to.dy)),
        everyElement((0, 30)),
      );
      expect(seams.map((l) => l.from.dy), [10, 20]);
      expect(seams.map((l) => (l.from.dx, l.to.dx)), everyElement((0, 48)));
    });

    test('vertical: frame lines lie across the width, seams stand up the '
        'height', () {
      final spy = paint(Axis.vertical, const Size(30, 48));
      final frameLines = spy.lines.where((l) => l.from.dy == l.to.dy);
      final seams = spy.lines.where((l) => l.from.dx == l.to.dx);
      expect(frameLines.map((l) => l.from.dy), [16.5, 32.5, 48.5]);
      expect(
        frameLines.map((l) => (l.from.dx, l.to.dx)),
        everyElement((0, 30)),
      );
      expect(seams.map((l) => l.from.dx), [10, 20]);
      expect(seams.map((l) => (l.from.dy, l.to.dy)), everyElement((0, 48)));
    });
  });

  group('TimelineOutsideCutWashPainter', () {
    _CanvasSpy paint(Axis axis, Size size, double outsideStart) {
      final spy = _CanvasSpy();
      TimelineOutsideCutWashPainter(
        outsideStart: outsideStart,
        colorScheme: scheme,
        axis: axis,
      ).paint(spy, size);
      return spy;
    }

    test('horizontal: the wash covers from the cut end to the right edge', () {
      expect(paint(Axis.horizontal, const Size(40, 24), 20).rects, [
        const Rect.fromLTWH(20, 0, 20, 24),
      ]);
    });

    test('vertical: the wash covers from the cut end to the bottom edge, '
        'and a cut end past the HEIGHT (not the width) paints nothing', () {
      expect(paint(Axis.vertical, const Size(24, 40), 20).rects, [
        const Rect.fromLTWH(0, 20, 24, 20),
      ]);
      expect(paint(Axis.vertical, const Size(24, 40), 30).rects, hasLength(1));
      expect(paint(Axis.vertical, const Size(24, 40), 40).rects, isEmpty);
    });
  });

  group('the instruction marks', () {
    const cellExtent = 48.0;
    const crossExtent = 30.0;
    const spanCells = 5;
    const mainExtent = cellExtent * spanCells;
    const midCross = 15;

    Layer layerWith(String instructionId, {String? valueA, String? valueB}) =>
        Layer(
          id: const LayerId('cam-1'),
          name: 'CAM 1',
          kind: LayerKind.instruction,
          frames: const [],
          timeline: const {},
          instructions: {
            0: InstructionEvent(
              instructionId: instructionId,
              length: spanCells,
              valueA: valueA,
              valueB: valueB,
            ),
          },
        );

    Size sizeFor(Axis axis) => axis == Axis.horizontal
        ? const Size(mainExtent, crossExtent)
        : const Size(crossExtent, mainExtent);

    /// The pixel at [along] the axis and [across] it.
    bool inkAt(Uint32List pixels, Axis axis, int along, int across) =>
        axis == Axis.horizontal
        ? _inked(pixels, sizeFor(axis), along, across)
        : _inked(pixels, sizeFor(axis), across, along);

    Future<Uint32List> markPixels(
      WidgetTester tester,
      Axis axis,
      String instructionId, {
      String? valueA,
      String? valueB,
    }) async {
      final size = sizeFor(axis);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: size.width,
            height: size.height,
            child: TimelineFixedFrameSpanLayer(
              geometry: const TimelineFrameGeometry(
                frameCellExtent: cellExtent,
                frameStartIndex: 0,
                frameEndIndexExclusive: spanCells,
              ),
              crossAxisExtent: crossExtent,
              axis: axis,
              children: timelineRowInstructionOverlays(
                layer: layerWith(instructionId, valueA: valueA, valueB: valueB),
                frameStartIndex: 0,
                frameEndIndexExclusive: spanCells,
                axis: axis,
                defById: CameraInstructionSet.standard.defById,
              ),
            ),
          ),
        ),
      );
      // Down a column the writing paints through its own CustomPaint, so
      // the mark's painter is picked by type rather than by position.
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-instruction-cam-1-0'),
              ),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((p) => p.painter)
          .singleWhere(
            (p) => p.runtimeType.toString() == '_InstructionMarkPainter',
          );
      final pixels = await tester.runAsync(() => _rasterize(painter!, size));
      return pixels!;
    }

    for (final axis in Axis.values) {
      testWidgets('$axis: a nameless bar wears caps wide on the span edges '
          'and tapered inward, with the line between', (tester) async {
        final pixels = await markPixels(tester, axis, 'pan');
        expect(inkAt(pixels, axis, 4, midCross), isTrue);
        expect(inkAt(pixels, axis, mainExtent ~/ 2, midCross), isTrue);
        expect(inkAt(pixels, axis, mainExtent.toInt() - 4, midCross), isTrue);
        expect(inkAt(pixels, axis, 2, midCross - 5), isTrue);
        expect(inkAt(pixels, axis, 22, midCross - 5), isFalse);
        expect(
          inkAt(pixels, axis, mainExtent.toInt() - 2, midCross - 5),
          isTrue,
        );
        expect(
          inkAt(pixels, axis, mainExtent.toInt() - 22, midCross - 5),
          isFalse,
        );
      });

      testWidgets('$axis: a named bar keeps the endpoint cells empty', (
        tester,
      ) async {
        final pixels = await markPixels(
          tester,
          axis,
          'pan',
          valueA: 'A',
          valueB: 'B',
        );
        expect(inkAt(pixels, axis, 4, midCross), isFalse);
        expect(inkAt(pixels, axis, mainExtent.toInt() - 4, midCross), isFalse);
        expect(inkAt(pixels, axis, mainExtent ~/ 2, midCross), isTrue);
      });

      testWidgets('$axis: FI opens narrow → wide, FO wide → narrow', (
        tester,
      ) async {
        final fi = await markPixels(tester, axis, 'fi');
        expect(inkAt(fi, axis, 10, midCross - 8), isFalse);
        expect(inkAt(fi, axis, mainExtent.toInt() - 10, midCross - 8), isTrue);
        final fo = await markPixels(tester, axis, 'fo');
        expect(inkAt(fo, axis, 10, midCross - 8), isTrue);
        expect(inkAt(fo, axis, mainExtent.toInt() - 10, midCross - 8), isFalse);
      });

      testWidgets('$axis: O.L is two triangles meeting at the span centre', (
        tester,
      ) async {
        final ol = await markPixels(tester, axis, 'ol');
        // Bases span the whole cross extent on both span edges…
        expect(inkAt(ol, axis, 3, 2), isTrue);
        expect(inkAt(ol, axis, mainExtent.toInt() - 3, 2), isTrue);
        // …and taper to the centre: a quarter of the way in, the triangle
        // is half its base, so the row's edge is bare and its middle inked.
        expect(inkAt(ol, axis, 60, 2), isFalse);
        expect(inkAt(ol, axis, 60, midCross), isTrue);
        expect(inkAt(ol, axis, mainExtent.toInt() - 60, 2), isFalse);
      });
    }
  });

  group('SePaperSpan dividers', () {
    Future<_CanvasSpy> paint(WidgetTester tester, Axis axis, Size size) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: SePaperSpan(axis: axis, frameCellExtent: 10),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(SePaperSpan),
          matching: find.byType(CustomPaint),
        ),
      );
      final spy = _CanvasSpy();
      paint.painter!.paint(spy, size);
      return spy;
    }

    testWidgets('horizontal: one divider per cell, standing up the height', (
      tester,
    ) async {
      final spy = await paint(tester, Axis.horizontal, const Size(40, 24));
      expect(spy.lines.map((l) => (l.from, l.to)), [
        (const Offset(10, 0), const Offset(10, 24)),
        (const Offset(20, 0), const Offset(20, 24)),
        (const Offset(30, 0), const Offset(30, 24)),
      ]);
    });

    testWidgets('vertical: one divider per cell, lying across the width', (
      tester,
    ) async {
      final spy = await paint(tester, Axis.vertical, const Size(24, 40));
      expect(spy.lines.map((l) => (l.from, l.to)), [
        (const Offset(0, 10), const Offset(24, 10)),
        (const Offset(0, 20), const Offset(24, 20)),
        (const Offset(0, 30), const Offset(24, 30)),
      ]);
    });
  });

  group('BlockEdgeGripBarPainter', () {
    Rect painted(Axis axis, Size size) {
      final spy = _CanvasSpy();
      BlockEdgeGripBarPainter(
        edge: TimelineBlockEdge.end,
        axis: axis,
        ink: BlockEdgeGripInk.rest,
      ).paint(spy, size);
      return spy.rrects.single;
    }

    test('the bar sits where the shared rect law puts it, on both axes', () {
      expect(
        painted(Axis.horizontal, const Size(40, 24)),
        blockEdgeGripBarRect(
          edge: TimelineBlockEdge.end,
          hitExtent: 40,
          crossAxisExtent: 24,
          axis: Axis.horizontal,
        ),
      );
      expect(
        painted(Axis.vertical, const Size(24, 40)),
        blockEdgeGripBarRect(
          edge: TimelineBlockEdge.end,
          hitExtent: 40,
          crossAxisExtent: 24,
          axis: Axis.vertical,
        ),
      );
      // The end grip is measured from the hit extent's far end — the
      // HEIGHT of a vertical strip, not its width.
      expect(
        painted(Axis.vertical, const Size(24, 40)).bottom,
        greaterThan(30),
      );
    });
  });

  group('DialogueFitText', () {
    Future<Uint32List> glyphs(WidgetTester tester, Axis axis, Size size) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: DialogueFitText(
                text: 'あいう',
                axis: axis,
                color: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(DialogueFitText),
          matching: find.byType(CustomPaint),
        ),
      );
      final pixels = await tester.runAsync(
        () => _rasterize(paint.painter!, size),
      );
      return pixels!;
    }

    testWidgets('horizontal: the glyphs are spread over the WIDTH', (
      tester,
    ) async {
      const size = Size(120, 20);
      final pixels = await glyphs(tester, Axis.horizontal, size);
      var farInk = 0;
      for (var x = 80; x < 120; x += 1) {
        for (var y = 0; y < 20; y += 1) {
          if (_inked(pixels, size, x, y)) farInk += 1;
        }
      }
      expect(farInk, greaterThan(0), reason: 'the last glyph sits past 2/3');
    });

    testWidgets('vertical: the glyphs are spread over the HEIGHT', (
      tester,
    ) async {
      const size = Size(20, 120);
      final pixels = await glyphs(tester, Axis.vertical, size);
      var farInk = 0;
      for (var y = 80; y < 120; y += 1) {
        for (var x = 0; x < 20; x += 1) {
          if (_inked(pixels, size, x, y)) farInk += 1;
        }
      }
      expect(farInk, greaterThan(0), reason: 'the last glyph sits past 2/3');
    });
  });

  group('the FieldSlider track', () {
    Future<_CanvasSpy> track(WidgetTester tester, Axis axis, Size size) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: FieldSlider(
                  value: 0.5,
                  min: 0,
                  max: 1,
                  axis: axis,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .singleWhere(
            (p) => p.runtimeType.toString() == '_FieldSliderTrackPainter',
          );
      final spy = _CanvasSpy();
      painter!.paint(spy, size);
      return spy;
    }

    testWidgets('horizontal: the fill grows rightward from the left, and it '
        'is the ONLY mark of the value', (tester) async {
      final spy = await track(tester, Axis.horizontal, const Size(100, 20));
      expect(spy.rects, [const Rect.fromLTWH(0, 0, 50, 20)]);
    });

    testWidgets('vertical: the fill grows upward from the bottom, and it is '
        'the ONLY mark of the value', (tester) async {
      final spy = await track(tester, Axis.vertical, const Size(20, 100));
      expect(spy.rects, [const Rect.fromLTWH(0, 50, 20, 50)]);
    });
  });

  group('TimelineFrameAxisBox', () {
    const childKey = ValueKey('child');
    const boxKey = ValueKey('box');

    Future<Offset> childOffset(WidgetTester tester, Axis axis) async {
      final geometry = TimelineFrameGeometryHandle(
        const TimelineFrameGeometry(
          frameCellExtent: 10,
          frameStartIndex: 0,
          frameEndIndexExclusive: 20,
        ).windowed(originPx: 30, extentPx: 100),
      );
      addTearDown(geometry.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: TimelineFrameAxisBox(
              key: boxKey,
              geometry: geometry,
              crossAxisExtent: 24,
              axis: axis,
              child: const SizedBox(key: childKey),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byKey(childKey)) -
          tester.getTopLeft(find.byKey(boxKey));
    }

    testWidgets('a windowed child sits at its origin ALONG the axis', (
      tester,
    ) async {
      expect(await childOffset(tester, Axis.horizontal), const Offset(30, 0));
      expect(await childOffset(tester, Axis.vertical), const Offset(0, 30));
    });
  });
}
