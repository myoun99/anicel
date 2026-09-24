import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
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
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingHeldColor;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🗣️유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
/// 두고싶어. 기본값은 있음으로」 — the frame lines on a block's paper are a
/// switch, on by default; I-44's paper-only block is the other position.
///
/// What has to hold: ON, a block carries EXACTLY the sheet's lines — the same
/// boundaries at every zoom, the same weights, inked onto its paper — at its
/// inner boundaries only; OFF, nothing crosses it. And both raster paths —
/// the canvas pass and the baked tile — draw the one answer.
void main() {
  final scheme = buildAppTheme().colorScheme;
  final host = scheme.surfaceContainerHighest;

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  /// Block A over 2..14, block B glued on at 14..30, empty after.
  final layer = Layer(
    id: const LayerId('draw'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('a'), duration: 1, strokes: const []),
      Frame(id: const FrameId('b'), duration: 1, strokes: const []),
    ],
    timeline: {
      2: const TimelineExposure.drawing(FrameId('a'), length: 12),
      14: const TimelineExposure.drawing(FrameId('b'), length: 16),
    },
  );

  TimelineRowCellsPainter painterFor({
    required bool lines,
    double cell = 24,
    Axis axis = Axis.horizontal,
    Color? paperGround,
    bool worked = true,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: cell,
      frameEndIndexExclusive: 40,
    ),
    crossAxisExtent: 28,
    exposureStateForLayer: stateFor,
    colorScheme: scheme,
    baseTextStyle: const TextStyle(fontSize: 11),
    axis: axis,
    celContent: TimelineCelContentSource(
      hasContent: (_, _) => worked,
      revision: ValueNotifier<int>(0),
    ),
    paperGround: paperGround ?? host,
    blockFrameLines: lines,
    framesPerSecond: 24,
  );

  /// The line the sheet's law draws on [painter]'s paper at [frame].
  ({Rect rect, Color color})? lawLineAt(
    TimelineRowCellsPainter painter,
    int frame,
  ) {
    final paper = painter.paperRectFor(frame);
    final horizontal = painter.axis == Axis.horizontal;
    return timelineBlockFrameLine(
      axis: painter.axis,
      frameIndex: frame,
      boundary: horizontal ? paper.left : paper.top,
      across: horizontal
          ? (from: paper.top, to: paper.bottom)
          : (from: paper.left, to: paper.right),
      frameCellExtent: painter.frameCellExtent,
      framesPerSecond: 24,
      colorScheme: scheme,
      paper: painter.resolvedCellStyleFor(frame).background,
    );
  }

  group('the substrate', () {
    test('OFF: a block is ONE piece of paper and nothing crosses it', () {
      final painter = painterFor(lines: false);
      final substrate = painter.substrateIn(0, 40);
      expect(substrate.lines, isEmpty);
      expect(substrate.paper.map((piece) => piece.rect).toList(), [
        painter.paperRectFor(2).expandToInclude(painter.paperRectFor(13)),
        painter.paperRectFor(14).expandToInclude(painter.paperRectFor(29)),
      ], reason: 'one box per block — two glued blocks stay two');
      for (final piece in substrate.paper) {
        final radius = piece.radius!;
        expect(radius.topLeft.x, greaterThan(0), reason: 'a block\'s start');
        expect(radius.topRight.x, greaterThan(0), reason: 'a block\'s end');
      }
    });

    test('ON: exactly the sheet\'s lines on the paper, at the blocks\' INNER '
        'boundaries — never a block\'s own edge, never the ground', () {
      final painter = painterFor(lines: true);
      final substrate = painter.substrateIn(0, 40);
      expect(substrate.lines, [
        for (var frame = 3; frame < 30; frame += 1)
          if (frame != 14) lawLineAt(painter, frame)!,
      ], reason: 'a block\'s first boundary is its edge (2, and 14 where B '
          'is glued on), and the ground (30 on) is the sheet\'s');
      expect(
        substrate.lines.map((line) => line.rect.width).toSet(),
        {timelineGridBaseLineStroke, timelineGridSecondLineInk().strokeWidth},
        reason: 'the law\'s weights come along — 24 is a second',
      );
    });

    test('zoomed out, a block keeps exactly the boundaries the sheet keeps',
        () {
      for (final cell in [3.0, 5.0, 8.0, 12.0]) {
        final painter = painterFor(lines: true, cell: cell);
        final drawn = painter.substrateIn(0, 40).lines.length;
        var kept = 0;
        for (var frame = 3; frame < 30; frame += 1) {
          if (frame == 14) {
            continue;
          }
          if (timelineFrameBoundaryLineInk(
                frameIndex: frame,
                frameCellExtent: cell,
                framesPerSecond: 24,
                colorScheme: scheme,
              ) !=
              null) {
            kept += 1;
          }
        }
        expect(drawn, kept, reason: 'cell $cell');
      }
    });

    test('see-through paper carries no second line — the sheet\'s own shows '
        'through it (F-7)', () {
      // The folded row lies on the artwork: no ground to pre-blend an
      // unworked block onto, so its paper stays translucent.
      final painter = TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        celContent: TimelineCelContentSource(
          hasContent: (_, _) => false,
          revision: ValueNotifier<int>(0),
        ),
        blockFrameLines: true,
        framesPerSecond: 24,
      );
      expect(
        painter.resolvedCellStyleFor(5).background.a,
        lessThan(1),
        reason: 'fixture premise: see-through paper',
      );
      expect(painter.substrateIn(0, 40).lines, isEmpty);
    });

    test('the X-sheet: the same lines, turned', () {
      final painter = painterFor(lines: true, axis: Axis.vertical);
      final line = painter.substrateIn(0, 40).lines.first;
      expect(line.rect.width, greaterThan(line.rect.height));
      expect(line, lawLineAt(painter, 3));
    });

    test('a stretch that stops on a second line owns the sliver that leans '
        'back into it', () {
      final painter = painterFor(lines: true);
      final tile = painter.substrateIn(0, 24).lines;
      expect(tile.last, lawLineAt(painter, 24));
      expect(
        tile.last.rect.left,
        lessThan(painter.cellRectFor(24).left),
        reason: 'fixture premise: the second line leans back',
      );
    });
  });

  group('both raster paths draw the one answer', () {
    test('the canvas pass paints the substrate — paper, then its lines', () {
      final painter = painterFor(lines: true);
      final spy = _PaintSpy();
      painter.paint(spy, const Size(960, 28));
      final substrate = painter.substrateIn(0, 40);
      // The canvas keeps a paint's colour in 8 bits a channel, so that is
      // the width the two are compared at.
      expect(spy.fills, [
        for (final piece in substrate.paper)
          (rect: piece.rect, argb: piece.color.toARGB32()),
        for (final line in substrate.lines)
          (rect: line.rect, argb: line.color.toARGB32()),
      ]);
    });

    test('the tile bakes the substrate: its stream rasters to the pixels the '
        'pieces and lines make through the field', () {
      const dpr = 1.5;
      for (final lines in [false, true]) {
        final painter = painterFor(lines: lines);
        const start = 8;
        const end = 32;
        final baked = timelineGridSubstrateOps(
          painter: painter,
          spanStartIndex: start,
          spanEndIndexExclusive: end,
          devicePixelRatio: dpr,
        );
        final origin = painter.cellRectFor(start).left;
        final field = TimelineGridTileOpWriter();
        final substrate = painter.substrateIn(start, end);
        for (final piece in substrate.paper) {
          final radius = piece.radius;
          var mask = 0;
          var value = 0.0;
          if (radius != null) {
            for (final (corner, bit) in [
              (radius.topLeft, TimelineGridTileOp.cornerTopLeft),
              (radius.topRight, TimelineGridTileOp.cornerTopRight),
              (radius.bottomLeft, TimelineGridTileOp.cornerBottomLeft),
              (radius.bottomRight, TimelineGridTileOp.cornerBottomRight),
            ]) {
              if (corner.x > 0) {
                mask |= bit;
                value = corner.x;
              }
            }
          }
          field.rrectFill(
            (piece.rect.left - origin) * dpr,
            piece.rect.top * dpr,
            piece.rect.width * dpr,
            piece.rect.height * dpr,
            value * dpr,
            mask,
            timelineGridPackRgba(piece.color),
          );
        }
        for (final line in substrate.lines) {
          field.rrectFill(
            (line.rect.left - origin) * dpr,
            line.rect.top * dpr,
            line.rect.width * dpr,
            line.rect.height * dpr,
            0,
            0,
            timelineGridPackRgba(line.color),
          );
        }
        final width = ((end - start) * 24 * dpr).ceil();
        final height = (28 * dpr).ceil();
        Uint8List raster(Int32List ops) {
          final pixels = Uint8List(width * height * 4);
          expect(
            timelineGridRasterTileReference(
              pixels: pixels,
              tileWidth: width,
              tileHeight: height,
              backgroundRgba: 0,
              ops: ops,
            ),
            0,
          );
          return pixels;
        }

        expect(
          raster(baked),
          equals(raster(field.build())),
          reason: 'lines $lines',
        );
        if (lines) {
          expect(substrate.lines, isNotEmpty, reason: 'fixture premise');
        }
      }
    });
  });

  group('the law carries the switch', () {
    setUp(() => AppFrameGridSettings.settings.value =
        const AppFrameGridSettings());
    tearDown(() => AppFrameGridSettings.settings.value =
        const AppFrameGridSettings());

    testWidgets('a host\'s law reads the switch itself, and a flip reaches '
        'every reader under it', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        TimelineGridLaw(
          ground: host,
          framesPerSecond: 30,
          child: Builder(
            builder: (context) {
              inner = context;
              TimelineGridLaw.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(TimelineGridLaw.maybeOf(inner)!.blockFrameLines, isTrue,
          reason: 'on by default');
      AppFrameGridSettings.settings.value =
          const AppFrameGridSettings(blockFrameLines: false);
      await tester.pump();
      expect(TimelineGridLaw.maybeOf(inner)!.blockFrameLines, isFalse);
    });

    testWidgets('the SE paper span draws the law\'s lines where the switch '
        'is on, and none where it is off', (tester) async {
      Future<List<({Rect rect, int argb})>> linesOn(bool shown) async {
        AppFrameGridSettings.settings.value =
            AppFrameGridSettings(blockFrameLines: shown);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: TimelineGridLaw(
              ground: host,
              framesPerSecond: 24,
              child: const Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 8 * 24,
                  height: 28,
                  child: SePaperSpan(
                    axis: Axis.horizontal,
                    frameCellExtent: 24,
                    startFrame: 20,
                  ),
                ),
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
        final spy = _PaintSpy();
        paint.painter!.paint(spy, const Size(8 * 24, 28));
        return [
          for (final fill in spy.fills)
            if (fill.rect.width < 24) fill,
        ];
      }

      expect(await linesOn(false), isEmpty);
      final lines = await linesOn(true);
      expect(lines, hasLength(7), reason: 'frames 21..27 at 24px');
      expect(
        lines[3].rect.width,
        timelineGridSecondLineInk().strokeWidth,
        reason: 'frame 24 is a second — the span counts from where it is',
      );
    });
  });

  test('the flip window: its grid crosses a body where the switch is on, '
      'and lies under it where it is off', () {
    List<String> order({required bool lines}) {
      final painter = FlipHudPainter(
        snapshot: const FlipHudSnapshot(
          rows: [
            FlipHudRow(
              name: 'A',
              kind: LayerKind.animation,
              runs: [FlipHudRun(startIndex: 0, length: 6, label: '1')],
            ),
          ],
          rowIndex: 0,
          frameIndex: 2,
          frameCount: 8,
        ),
        axis: FlipHudAxis.frame,
        frameStep: true,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        blockFrameLines: lines,
      );
      final spy = _OrderSpy();
      painter.paint(spy, FlipHudMetrics.sizeFor(FlipHudAxis.frame));
      return spy.order;
    }

    final on = order(lines: true);
    expect(on, contains('body'), reason: 'fixture premise: a body');
    expect(on.lastIndexOf('line'), greaterThan(on.indexOf('body')));
    final off = order(lines: false);
    expect(off, contains('line'), reason: 'the grid is still there');
    expect(
      off.lastIndexOf('line'),
      lessThan(off.indexOf('body')),
      reason: 'every line goes down before the body covers it',
    );
  });
}

/// What the flip window lays down, in order: `body` for a block's body,
/// `line` for a grid line.
class _OrderSpy implements Canvas {
  final order = <String>[];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.style == PaintingStyle.fill &&
        paint.color.toARGB32() == timelineDrawingHeldColor.toARGB32()) {
      order.add('body');
    }
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => order.add('line');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PaintSpy implements Canvas {
  final fills = <({Rect rect, int argb})>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.style == PaintingStyle.fill) {
      fills.add((rect: rect, argb: paint.color.toARGB32()));
    }
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.style == PaintingStyle.fill) {
      fills.add((rect: rrect.outerRect, argb: paint.color.toARGB32()));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
