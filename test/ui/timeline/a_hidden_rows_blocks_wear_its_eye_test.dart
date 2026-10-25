import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/rail_eyes.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineGridGroundOver;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineInBlockInk;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart'
    show timelineGridSubstrateOps;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker, TimelineLaneKeysLine;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🗣️I-129 (유저 2026-10-25): 「레이어 비지블 껐을때, 블록도 그걸
/// 표시하고싶음. 같은 비활성화색으로」 · 「이 비지블시 비활성화색은 키던
/// 프레임블록이던 동일하게 법통일해서」 · 「꺼진 행의 빈블록은 말한
/// 빈블록이랑 동일하게」 — a hidden row's blocks, their words and its keys
/// wear the rail's switched-off look ([AppColors.offAlpha]); an empty block
/// is an empty block on any row.
void main() {
  const ground = Color(0xFF202124);
  final row = Layer(
    id: const LayerId('row'),
    name: 'row',
    mark: const LayerMark(process: LayerProcess.finish),
    frames: const [],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
    },
  );
  final paper = layerMarkColor(row.mark);
  final ink = timelineInBlockInk();

  /// [painted] switched off over [under] — the alpha the rail's plate and
  /// name wear, laid onto what is under it.
  Color off(Color painted, {required Color? under}) => timelineGridGroundOver(
    under: under,
    painted: painted.withValues(alpha: painted.a * AppColors.offAlpha),
  )!;

  final dimmed = off(paper, under: ground);

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      switch (frameIndex) {
        0 || 2 => TimelineCellExposureState.drawingStart,
        1 || 3 => TimelineCellExposureState.held,
        _ => TimelineCellExposureState.uncovered,
      };

  TimelineCelContentSource drawnFrom(int frame) => TimelineCelContentSource(
    hasContent: (_, at) => at >= frame,
    cannotRead: (_, _) => false,
    revision: CelContentRevision.everyRow(ValueNotifier<int>(0)),
  );

  TimelineRowCellsPainter cells({
    bool shown = true,
    TimelineCelContentSource? celContent,
  }) => TimelineRowCellsPainter(
    layer: row,
    geometry: testFrameGeometry(
      frameCellExtent: 24,
      frameEndIndexExclusive: 8,
    ),
    crossAxisExtent: 28,
    exposureStateForLayer: stateFor,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    paperGround: ground,
    celContent: celContent,
    shown: shown,
  );

  TimelineRowRunLabelsPainter labels({
    bool shown = true,
  }) => TimelineRowRunLabelsPainter(
    baseTextStyle: const TextStyle(fontSize: 11),
    layer: row,
    geometry: testFrameGeometry(
      frameCellExtent: 24,
      frameEndIndexExclusive: 8,
    ),
    crossAxisExtent: 28,
    showSeconds: false,
    countingBase: 24,
    paperGround: ground,
    shown: shown,
  );

  group('a frame block', () {
    test('on a hidden row wears the switched-off paper — opaque over the '
        'ground it knows — and its words dim with it', () {
      expect(dimmed, isNot(paper), reason: '⛔전제: the look moves');
      final shownCells = cells();
      final hiddenCells = cells(shown: false);
      for (final frame in [0, 1, 3]) {
        expect(shownCells.resolvedCellStyleFor(frame).background, paper);
        expect(
          hiddenCells.resolvedCellStyleFor(frame).background,
          dimmed,
          reason: '@$frame',
        );
      }
      expect(dimmed.a, 1, reason: 'baked: 「투명말고」');
      expect(
        hiddenCells.foregroundInkFor(hiddenCells.cellModelAt(0)),
        off(ink, under: dimmed),
      );
      expect(shownCells.foregroundInkFor(shownCells.cellModelAt(0)), ink);
      final shownNumbers = labels();
      final numberInk = shownNumbers.inkFor(shownNumbers.runLabels().first);
      final numbers = labels(shown: false);
      expect(
        numbers.inkFor(numbers.runLabels().first),
        off(numberInk, under: dimmed),
        reason: 'the 코마 number is the block\'s word as its name is',
      );
    });

    test('an EMPTY block on a hidden row is an empty block — hollow, the '
        'ground behind it, the grey outline and words', () {
      final painter = cells(shown: false, celContent: drawnFrom(2));
      final grey = timelineGridGroundOver(
        under: ground,
        painted: timelineEmptyBlockGrey,
      );
      for (final frame in [0, 1]) {
        final style = painter.resolvedCellStyleFor(frame);
        expect(style.background, ground, reason: '@$frame');
        expect(style.border, grey, reason: '@$frame');
      }
      expect(painter.foregroundInkFor(painter.cellModelAt(0)), grey);
      expect(
        painter.resolvedCellStyleFor(2).background,
        dimmed,
        reason: 'the drawn block beside it is hidden as its row is',
      );
    });

    test('its substrate is laid in the look — a hidden run\'s paper, an '
        'empty run\'s ground and a ring of its grey', () {
      final substrate = cells(
        shown: false,
        celContent: drawnFrom(2),
      ).substrateIn(0, 4);
      expect([for (final piece in substrate.paper) piece.color], [
        ground,
        dimmed,
      ]);
      expect(substrate.rings, hasLength(1), reason: 'the empty block alone');
      final ring = substrate.rings.single;
      expect(
        ring.color,
        timelineGridGroundOver(under: ground, painted: timelineEmptyBlockGrey),
      );
      expect(ring.width, timelineBlockLineWidth);
      expect(ring.open, (
        left: false,
        top: false,
        right: false,
        bottom: false,
      ), reason: 'the span holds the whole block: every side is drawn');
      final cut = cells(
        shown: false,
        celContent: drawnFrom(2),
      ).substrateIn(1, 4).rings.single;
      expect(
        cut.open.left,
        isTrue,
        reason: 'a block that runs in from before the span leaves that side '
            'open, so a tile cut draws no line down its middle',
      );
    });

    test('an empty block BAKES as its ground and a ring of its grey — the '
        'stream the tile is rastered from', () {
      final painter = cells(celContent: drawnFrom(2));
      final substrate = painter.substrateIn(0, 2);
      final piece = substrate.paper.single;
      final ring = substrate.rings.single;
      const corners =
          TimelineGridTileOp.cornerTopLeft |
          TimelineGridTileOp.cornerTopRight |
          TimelineGridTileOp.cornerBottomLeft |
          TimelineGridTileOp.cornerBottomRight;
      TimelineGridTileOpWriter paperAlone() => TimelineGridTileOpWriter()
        ..rrectFill(
          piece.rect.left,
          piece.rect.top,
          piece.rect.width,
          piece.rect.height,
          piece.radius!.topLeft.x,
          corners,
          timelineGridPackRgba(piece.color),
        );
      final field = paperAlone()
        ..rrectRing(
          (
            x: ring.rect.left,
            y: ring.rect.top,
            width: ring.rect.width,
            height: ring.rect.height,
            radius: ring.radius!.topLeft.x,
            cornerMask: corners,
          ),
          lineWidth: ring.width,
          openMask: 0,
          rgba: timelineGridPackRgba(ring.color),
        );
      Uint8List raster(Int32List ops) {
        final pixels = Uint8List(4 * 2 * 24 * 28);
        expect(
          timelineGridRasterTileReference(
            pixels: pixels,
            tileWidth: 2 * 24,
            tileHeight: 28,
            backgroundRgba: 0,
            ops: ops,
          ),
          0,
        );
        return pixels;
      }

      final baked = timelineGridSubstrateOps(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 2,
        devicePixelRatio: 1.0,
      );
      expect(raster(baked), equals(raster(field.build())));
      expect(
        raster(baked),
        isNot(equals(raster(paperAlone().build()))),
        reason: '⛔전제: the ring is in the stream, not the paper alone',
      );
    });
  });

  group('a key', () {
    Future<void> pumpUnder(
      WidgetTester tester,
      RailEye eye,
      Widget child,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 28,
            child: RailEyes(eyes: {row.id: eye}, child: child),
          ),
        ),
      ),
    );

    Finder painted(Type type) => find.descendant(
      of: find.byType(type),
      matching: find.byType(CustomPaint),
    );

    for (final (name, eye) in [
      ('its own eye off', (on: false, hiddenAbove: false)),
      ('a folder above it hiding it', (on: true, hiddenAbove: true)),
    ]) {
      testWidgets('dims as its row\'s blocks do — $name', (tester) async {
        final marker = TimelineLaneKeyMarker(
          mark: KeyMark.linear,
          axis: Axis.horizontal,
          markerSize: const Size.square(12),
          layer: row,
        );
        await pumpUnder(tester, (on: true, hiddenAbove: false), marker);
        expect(painted(TimelineLaneKeyMarker), paints..path(color: paper));

        await pumpUnder(tester, eye, marker);
        expect(
          painted(TimelineLaneKeyMarker),
          paints..path(color: off(paper, under: null)),
          reason: 'no ground known here: the off paper laid as it is',
        );

        await pumpUnder(
          tester,
          eye,
          TimelineLaneKeysLine(axis: Axis.horizontal, cells: 4, layer: row),
        );
        expect(
          painted(TimelineLaneKeysLine),
          paints..line(color: off(paper, under: null)),
          reason: 'the line between the keys wears it too',
        );
      });
    }
  });
}
