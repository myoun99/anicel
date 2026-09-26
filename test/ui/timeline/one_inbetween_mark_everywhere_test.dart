// ONE IN-BETWEEN MARK, DRAWN ONE WAY ON EVERY SURFACE.
//
// 🗣️유저 2026-09-24: 「지금 블록 이름 없을때의 헤드에 있는 점이랑 노출부분에
// 넣는 중간나누기 점이랑 다른게 느껴지거든? 타임시트에 점 마크는 작고 헤드 점
// 마크는 크단말야. 그래서 같은취급으로 통일하고싶고, 지금 타임시트패널에서
// 동그라미는 작은걸로 통일하고, 타임라인쪽 점 마크도 지금 너무 크니까
// 작게하고싶어. 지금의 절반?」 — then 「데이터적으로도 같은 취급시키는거
// 맞지? 중간나누기 마크1로서 작동했으면」.
//
// An unnamed drawing's head printed ● as TEXT — in its cel number's type,
// twice the sheet's dot, at a size and a baseline of the face's own — while
// the dot inside a block was a mark. These pins look at what each surface
// lays down: the same circle for both, one size per surface. (A storyboard
// panel draws no mark at all since 2026-09-26 — 「콘티레이어는 이름 없으면
// 진짜 이름 없도록」 — pinned in `storyboard_cut_block_bands_test`.)
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart' show FlipHudAxis;
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/inbetween_mark_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/run_edge_fixtures.dart';
import 'timeline_frame_geometry_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const font = 14.0;
  const rowExtent = 28.0;
  const frames = 8;

  // An UNNAMED block over 0-3 with a dot at 2, then a named one over 4-7 —
  // on the layer, which is where a row reads where its cells change (I-22).
  final cels = [
    Frame(id: const FrameId('unnamed'), duration: 1, strokes: const []),
    Frame(id: const FrameId('named'), duration: 1, strokes: const []),
  ];
  const blocks = {
    0: TimelineExposure.drawing(
      FrameId('unnamed'),
      length: 4,
      breakdownOffsets: [2],
    ),
    4: TimelineExposure.drawing(FrameId('named'), length: 4),
  };
  const stateFor = exposureOf;

  final layer = Layer(
    id: const LayerId('row'),
    name: 'A',
    frames: cels,
    timeline: blocks,
  );

  TimelineRowCellsPainter rowPainter(
    Axis axis, {
    double cell = 24,
    double crossExtent = rowExtent,
    Layer? row,
  }) => TimelineRowCellsPainter(
        layer: row ?? layer,
        geometry: testFrameGeometry(
          frameCellExtent: cell,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: crossExtent,
        exposureStateForLayer: stateFor,
        frameNameForLayer: (_, frame) => frame == 4 ? 'A1' : null,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: font),
        axis: axis,
      );

  Size rowSize(Axis axis, {double cell = 24}) => axis == Axis.horizontal
      ? Size(cell * frames, rowExtent)
      : Size(rowExtent, cell * frames);

  final roomy = timelineInbetweenMarkRadius(
    font,
    cellExtent: 100,
    crossExtent: 100,
  );

  for (final axis in Axis.values) {
    test('the row draws an unnamed head and a block\'s dot as ONE circle — '
        'one size, one ink, at the centre of the cell\'s paper ($axis)', () {
      final painter = rowPainter(axis);
      final laid = _Laid();
      painter.paint(laid, rowSize(axis));

      expect(laid.circles, hasLength(2));
      final [head, dot] = laid.circles;
      expect(head.center, painter.paperRectFor(0).center);
      expect(dot.center, painter.paperRectFor(2).center);
      expect(head.radius, dot.radius, reason: 'one mark, one size');
      expect(head.color, dot.color, reason: 'one mark, one ink');
      expect(
        head.radius * 2,
        closeTo(font * 0.45, 1e-9),
        reason:
            '🗣️「지금의 절반?」 — half the ● a 14px cell word inked '
            '(0.89em, measured in the app\'s face)',
      );
      for (var frame = 0; frame < 4; frame += 1) {
        final cell = painter.cellRectFor(frame);
        expect(
          laid.paragraphs.where((box) => box.overlaps(cell)),
          isEmpty,
          reason: 'frame $frame: no text stands in for the mark',
        );
      }
      expect(
        laid.paragraphs,
        isNotEmpty,
        reason: '⛔전제: the named block still writes its name',
      );
    });
  }

  test('a repeat GHOST wears the same marks — its unnamed head and its '
      'dot, text-only like every ghost (UI-R10 #11)', () {
    final repeated = rederiveRunBehaviors(
      Layer(
        id: const LayerId('ghosts'),
        name: 'G',
        frames: [
          Frame(id: const FrameId('g1'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(
            FrameId('g1'),
            length: 2,
            endEdge: repeatMark,
          ),
        },
      ),
      cutFrameCount: 8,
    );
    final painter = TimelineRowCellsPainter(
      layer: repeated,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: frames,
      ),
      crossAxisExtent: rowExtent,
      // The ghost chain restarts the block at 2; its dot rides at 3.
      exposureStateForLayer: (_, frame) => switch (frame) {
        0 || 2 => TimelineCellExposureState.drawingStart,
        3 => TimelineCellExposureState.markHeld,
        _ => TimelineCellExposureState.held,
      },
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: font),
    );

    final head = painter.cellModelAt(2);
    final dot = painter.cellModelAt(3);
    expect(head.ghost && dot.ghost, isTrue, reason: '⛔전제: ghost cells');
    expect(head.mark, unnamedDrawingMark);
    expect(dot.mark, breakdownMark);
    expect(head.glyph, isEmpty);
    expect(dot.glyph, isEmpty);
  });

  test('the mark shrinks with a tight cell or a squeezed row as every mark '
      'does (D39-2), and never leaves its cell — the tile that holds the '
      'cell is the only one that draws it', () {
    for (final crossExtent in [rowExtent, 12.0, 8.0]) {
      for (
        var cell = TimelineZoomLimits.minPixelsPerFrameAt(24);
        cell <= TimelineZoomLimits.maxPixelsPerFrame;
        cell += 0.6
      ) {
        for (final axis in Axis.values) {
          final painter = rowPainter(
            axis,
            cell: cell,
            crossExtent: crossExtent,
          );
          for (final frame in [0, 2]) {
            final place = painter.inbetweenMarkLayoutFor(frame);
            final disc = Rect.fromCircle(
              center: place.center,
              radius: place.radius,
            );
            final paper = painter.paperRectFor(frame);
            final where = 'cell $cell, row $crossExtent, $axis, frame $frame';
            expect(
              paper.inflate(1e-9).contains(disc.topLeft) &&
                  paper.inflate(1e-9).contains(disc.bottomRight),
              isTrue,
              reason: '$where: $disc leaves $paper',
            );
            final roomyCell = cell >= 14 && crossExtent == rowExtent;
            expect(
              place.radius,
              roomyCell ? roomy : lessThan(roomy),
              reason: where,
            );
          }
        }
      }
    }
  });

  test('a tile bakes each mark where the row draws it — a disc in the '
      'cell\'s ink, in the tile\'s own pixels — and no glyph for it', () async {
    for (final axis in Axis.values) {
      final painter = rowPainter(axis);
      for (final dpr in [1.0, 1.5, 2.0]) {
        for (final (start, end) in [(0, 4), (1, 4)]) {
          final ops = await TimelineGridTileStore.instance.debugForegroundOps(
            painter: painter,
            spanStartIndex: start,
            spanEndIndexExclusive: end,
            devicePixelRatio: dpr,
          );
          // The tile starts at its first cell, along the frame axis.
          final first = painter.cellRectFor(start);
          final origin = axis == Axis.horizontal
              ? Offset(first.left, 0)
              : Offset(0, first.top);
          final expected = TimelineGridTileOpWriter();
          for (final frame in [0, 2]) {
            if (frame < start) {
              continue;
            }
            final place = painter.inbetweenMarkLayoutFor(frame);
            final disc = Rect.fromCircle(
              center: (place.center - origin) * dpr,
              radius: place.radius * dpr,
            );
            expected.rrectFill(
              disc.left,
              disc.top,
              disc.width,
              disc.height,
              disc.width / 2,
              TimelineGridTileOp.cornerTopLeft |
                  TimelineGridTileOp.cornerTopRight |
                  TimelineGridTileOp.cornerBottomLeft |
                  TimelineGridTileOp.cornerBottomRight,
              timelineGridPackRgba(
                painter.foregroundInkFor(painter.cellModelAt(frame)),
              ),
            );
          }
          expect(
            ops,
            expected.build(),
            reason: '$axis, span [$start, $end) at $dpr',
          );
        }
      }
    }
  });

  FlipHudPainter flipWindow(
    String label, {
    LayerKind kind = LayerKind.animation,
  }) => FlipHudPainter(
    snapshot: FlipHudSnapshot(
      rows: [
        FlipHudRow(
          name: 'A',
          kind: kind,
          runs: [FlipHudRun(startIndex: 0, length: 2, label: label)],
        ),
      ],
      rowIndex: 0,
      frameIndex: 0,
      frameCount: 8,
    ),
    axis: FlipHudAxis.frame,
    frameStep: true,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: font),
  );

  test('the flip window wears the mark on an unnamed block — drawn where '
      'its name would stand, at the size of that name', () {
    final size = FlipHudMetrics.sizeFor(FlipHudAxis.frame);
    final unnamed = _Laid();
    flipWindow('').paint(unnamed, size);
    final named = _Laid();
    flipWindow('A1').paint(named, size);

    expect(named.circles, isEmpty, reason: 'a name is written, not marked');
    expect(unnamed.circles, hasLength(1));
    final mark = unnamed.circles.single;
    expect(
      mark.radius,
      roomy,
      reason: 'the head word\'s 14px, the row\'s mark at the row\'s type',
    );
    final name = named.paragraphs.where(
      (box) => (box.height - font).abs() < 1e-6,
    );
    expect(name, hasLength(1), reason: '⛔전제: the name is in the slot');
    expect(
      (mark.center - name.single.center).distance,
      lessThan(1e-6),
      reason: 'the mark stands at the slot\'s centre, where the name is set',
    );
  });

  Future<_Laid> foldedStrip(
    WidgetTester tester,
    String label, {
    LayerKind kind = LayerKind.animation,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: CollapsedRowOverlay(
              snapshot: FlipHudSnapshot(
                rows: [
                  FlipHudRow(
                    name: 'A',
                    kind: kind,
                    runs: [FlipHudRun(startIndex: 0, length: 2, label: label)],
                  ),
                ],
                rowIndex: 0,
                frameIndex: 5,
                frameCount: 40,
              ),
              rail: null,
              naturalRailWidth: 100,
              pixelsPerFrame: 12,
              framesPerSecond: 24,
            ),
          ),
        ),
      ),
    );
    final strip = find.byKey(const ValueKey<String>('collapsed-strip'));
    final laid = _Laid()..size = tester.getSize(strip);
    tester.widget<CustomPaint>(strip).painter!.paint(laid, laid.size!);
    return laid;
  }

  testWidgets('the folded row\'s strip wears the mark on an unnamed block, '
      'in its first cell, at the size of the strip\'s type', (tester) async {
    final named = await foldedStrip(tester, 'A1');
    expect(named.circles, isEmpty, reason: 'a name is written, not marked');

    final unnamed = await foldedStrip(tester, '');
    expect(unnamed.circles, hasLength(1));
    final mark = unnamed.circles.single;
    // The block's room: frames 0-1 at 12px, inset 1 along and 4 across.
    final room = Rect.fromLTRB(1, 4, 24 - 1, unnamed.size!.height - 4);
    expect(mark.center, Offset(room.left + 12 / 2, room.center.dy));
    expect(
      mark.radius,
      timelineInbetweenMarkRadius(9.5, cellExtent: 12, crossExtent: room.height),
      reason: 'the strip\'s 9.5px type, fitted to its 12px cell',
    );
  });

  // 🗣️유저 2026-09-25: 「이미지레이어는 프레임 이름 없으면 중간나누기 마크가
  // 아니라 이름을 안보이게 하는 상태로」 — the layer IS the picture there,
  // so its unnamed head is neither a mark nor a word, on every surface.
  group('an IMAGE row\'s unnamed head wears NOTHING', () {
    final image = Layer(
      id: const LayerId('bg'),
      name: 'BG',
      kind: LayerKind.image,
      frames: cels,
      timeline: blocks,
    );

    for (final axis in Axis.values) {
      test('on its row: no mark and no word — a dot INSIDE the block is '
          'still a mark ($axis)', () {
        final painter = rowPainter(axis, row: image);
        final laid = _Laid();
        painter.paint(laid, rowSize(axis));

        expect(
          laid.circles.map((circle) => circle.center),
          [painter.paperRectFor(2).center],
          reason: 'the dot at 2 is the only circle',
        );
        expect(
          laid.paragraphs.where(
            (box) => box.overlaps(painter.cellRectFor(0)),
          ),
          isEmpty,
        );
      });
    }

    test('in the flip window', () {
      final size = FlipHudMetrics.sizeFor(FlipHudAxis.frame);
      final unnamed = _Laid();
      flipWindow('', kind: LayerKind.image).paint(unnamed, size);
      expect(unnamed.circles, isEmpty);
      final named = _Laid();
      flipWindow('BG1', kind: LayerKind.image).paint(named, size);
      expect(
        named.paragraphs.where((box) => (box.height - font).abs() < 1e-6),
        hasLength(1),
        reason: '⛔전제: a NAMED image cel still writes its name',
      );
      expect(
        unnamed.paragraphs.where((box) => (box.height - font).abs() < 1e-6),
        isEmpty,
      );
    });

    testWidgets('on the folded row\'s strip', (tester) async {
      final unnamed = await foldedStrip(tester, '', kind: LayerKind.image);
      expect(unnamed.circles, isEmpty);
      // The block holds frames 0-1 at 12px: no word of any width there.
      expect(
        unnamed.paragraphs.where((box) => box.center.dx < 24),
        isEmpty,
      );
    });
  });

  test('the sheet draws an unnamed head and a block\'s dot as ONE small '
      'circle — 「타임시트패널에서 동그라미는 작은걸로 통일」', () {
    final document = TimesheetDocument.fromCut(
      cut: Cut(
        id: const CutId('cut-1'),
        name: '1',
        duration: 12,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        layers: [
          Layer(
            id: const LayerId('a'),
            name: 'A',
            frames: [
              Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
            ],
            timeline: const {
              0: TimelineExposure.drawing(
                FrameId('f1'),
                length: 3,
                breakdownOffsets: [1],
              ),
            },
          ),
        ],
      ),
      projectName: 'P',
      fps: 24,
    );
    final layout = TimesheetDocumentLayout(document: document);
    final laid = _Laid();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: document,
      layout: layout,
      layers: const {SheetPaintLayer.content},
    ).paint(laid, layout.documentSize);

    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(0);
    final width = layout.columnWidthFor(document.columns[0].kind);
    Rect cellAt(int row) => Rect.fromLTWH(
      left,
      layout.halfRowsTop(0) + row * TimesheetDocumentLayout.rowHeight,
      width,
      TimesheetDocumentLayout.rowHeight,
    );
    final marks = laid.circles
        .where((circle) => cellAt(0).contains(circle.center) ||
            cellAt(1).contains(circle.center))
        .toList();
    expect(marks, hasLength(2));
    final [head, dot] = marks;
    expect(head.center, cellAt(0).center);
    expect(dot.center, cellAt(1).center);
    expect(head.radius, 2.8, reason: 'the small one — the sheet\'s dot');
    expect(dot.radius, head.radius);
    expect(
      laid.paragraphs.where((box) => box.overlaps(cellAt(0))),
      isEmpty,
      reason: '↩️the head printed ● as its 10px cel number',
    );
  });
}

/// What a painter lays down — its circles, and the boxes of its paragraphs
/// — following the transforms.
class _Laid implements Canvas {
  final circles = <({Offset center, double radius, Color color})>[];
  final paragraphs = <Rect>[];
  Size? size;
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
  void drawCircle(Offset c, double radius, Paint paint) => circles.add((
    center: MatrixUtils.transformPoint(_transform, c),
    radius: radius,
    color: paint.color,
  ));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs.add(
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
