import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/text/word_condensation.dart'
    show maxGapTightening;
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver;
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/theme/conte_ink.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show
        storyboardCutBandColor,
        storyboardCutBlockBackgroundColor,
        storyboardPanelPictureGroundColor,
        timelineSelectedFrameBorderColor,
        timelineStandingWashColor;
import '../helpers/fixed_thumbnails.dart';
import 'storyboard_conte_row_probe.dart';
import 'storyboard_cut_block_probe.dart';

/// The cut block is THREE BANDS, top to bottom: the CUT's, the strip, the
/// cut's. The strip is the picture and nothing is written over it; the
/// bands carry the writing — the cut's number at the left end of its top
/// band and its length at the right end of its bottom one (the conte
/// sheet's CUT and TIME columns, which sit outside the picture cell, turned
/// on their side).
///
/// ↩️FIVE bands from 2026-09-26: each panel's name and comma count stood in
/// a pair of the conte blocks' own, between the cut's and the strip (유저
/// 2026-09-25 · 2026-09-26). I-73 (유저 2026-10-08: 「우선 v행은 지금처럼
/// 보여주는건 그대로 보여줘 … 컷 선택만 되도록」 · 「띠 둘만 이사로 가자」)
/// moved that pair out to the conte row under the V row, where a panel is a
/// frame block and prints as one.
const _trackId = TrackId('band-track');

const _art = LayerMark(process: LayerProcess.art);
const _conte = LayerMark(process: LayerProcess.conte);

Cut _cut(
  String id,
  int duration, {
  Layer? storyboardLayer,
  LayerMark mark = LayerMark.none,
}) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  metadata: CutMetadata(mark: mark),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
    ?storyboardLayer,
  ],
);

/// A storyboard row divided into three panels at 0, 4 and 9 — [named]
/// gives their drawings the cel numbers `a`, `b`, `c`; without it they have
/// none, and show no name at all (유저 2026-09-26 — a storyboard drawing is
/// not an in-between).
Layer _dividedStoryboardLayer(
  String cutId, {
  bool named = false,
  LayerMark mark = LayerMark.none,
}) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
  mark: mark,
  frames: [
    for (final name in ['a', 'b', 'c'])
      Frame(
        id: FrameId('$cutId-$name'),
        duration: 1,
        strokes: const [],
        name: named ? name : null,
      ),
  ],
  timeline: {
    0: TimelineExposure.drawing(FrameId('$cutId-a'), length: 4),
    4: TimelineExposure.drawing(FrameId('$cutId-b'), length: 5),
    9: TimelineExposure.drawing(FrameId('$cutId-c'), length: 3),
  },
);

Project _project({
  Layer? storyboardLayer,
  LayerMark cutMark = LayerMark.none,
}) => Project(
  id: const ProjectId('band-project'),
  name: 'Bands',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        _cut('cut-1', 12, storyboardLayer: storyboardLayer, mark: cutMark),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  Layer? storyboardLayer,
  LayerMark cutMark = LayerMark.none,
  CutId? activeCutId = const CutId('cut-1'),
  double pixelsPerFrame = 12,
  StoryboardThumbnailResolver? thumbnailFor,
  ValueListenable<CutId?>? cutUnderPlayhead,
  TimelineRowAddress? selectedRow,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoryboardPanel(
          project: _project(storyboardLayer: storyboardLayer, cutMark: cutMark),
          activeCutId: activeCutId,
          cutUnderPlayhead: cutUnderPlayhead,
          selectedRow: selectedRow,
          pixelsPerFrame: pixelsPerFrame,
          thumbnails: thumbnailFor == null
              ? null
              : fixedThumbnails(thumbnailFor),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Records every paragraph the painter lays down. A SELF-INVERTING glyph
/// (2026-08-17, the outline's successor) is exactly ONE paragraph — two
/// paragraphs at one offset was the retired outline's fingerprint
/// (stroke pass + fill pass), so "one at the spot, never two" is both the
/// anchor contract and the outline-gone proof.
/// Where each paragraph LANDS, following the transforms: a label narrowed
/// into its band (B, 2026-09-24) is drawn at the origin of a scaled canvas.
class _ParagraphOffsetSpy implements Canvas {
  final List<Offset> offsets = [];
  final List<Rect> rects = [];

  /// How far each paragraph was narrowed across, beside [rects].
  final List<double> xScales = [];
  final List<({Offset center, double radius, Color color})> circles = [];
  final List<({Rect rect, Color color})> plates = [];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    offsets.add(MatrixUtils.transformPoint(_transform, offset));
    rects.add(
      MatrixUtils.transformRect(
        _transform,
        offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
      ),
    );
    xScales.add(_transform.storage[0]);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add((
    center: MatrixUtils.transformPoint(_transform, c),
    radius: radius,
    color: paint.color,
  ));

  @override
  void drawRRect(RRect rrect, Paint paint) => plates.add((
    rect: MatrixUtils.transformRect(_transform, rrect.outerRect),
    color: paint.color,
  ));

  /// The plain rectangles laid down, with their fill — the bands.
  final List<({Rect rect, Color color})> fills = [];

  @override
  void drawRect(Rect rect, Paint paint) => fills.add((
    rect: MatrixUtils.transformRect(_transform, rect),
    color: paint.color,
  ));

  /// The fill laid on exactly [rect], as ARGB: a [Paint] keeps its colour in
  /// 32 bits, so a colour read back off one is not `==` the double-precision
  /// one it was handed.
  int fillOf(Rect rect) =>
      fills.singleWhere((fill) => fill.rect == rect).color.toARGB32();

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

_ParagraphOffsetSpy _painted(WidgetTester tester) {
  final spy = _ParagraphOffsetSpy();
  cutBlocksPainter(tester).paint(
    spy,
    tester.getSize(
      find.byKey(const ValueKey<String>('storyboard-cut-blocks-band-track')),
    ),
  );
  return spy;
}

/// What the conte row's create buttons lay down — their plates and their
/// `+`.
_ParagraphOffsetSpy _paintedCreate(WidgetTester tester) {
  final spy = _ParagraphOffsetSpy();
  final create = conteCreateFinder(_trackId.value);
  tester
      .widget<CustomPaint>(create)
      .painter!
      .paint(spy, tester.getSize(create));
  return spy;
}

/// The words laid in [band], left to right.
List<Rect> _wordsIn(Rect band, _ParagraphOffsetSpy spy) =>
    spy.rects.where((rect) => band.contains(rect.center)).toList()
      ..sort((a, b) => a.left.compareTo(b.left));

/// A copy of [painter] at another height, or under another selection — the
/// painter answers for any row, not only the one mounted.
StoryboardCutBlocksPainter _painterLike(
  StoryboardCutBlocksPainter painter, {
  double? crossAxisExtent,
  ValueListenable<TrackFrameRangeSelection?>? selectedRange,
}) => StoryboardCutBlocksPainter(
  entries: painter.entries,
  storyboardCellsByCut: painter.storyboardCellsByCut,
  geometry: painter.geometry,
  crossAxisExtent: crossAxisExtent ?? painter.crossAxisExtent,
  minBlockWidth: painter.minBlockWidth,
  selectedRange: selectedRange ?? painter.selectedRange,
  rowAddress: painter.rowAddress,
  hoveredCutId: painter.hoveredCutId,
  colorScheme: painter.colorScheme,
  baseTextStyle: painter.baseTextStyle,
  showSeconds: painter.showSeconds,
  countingBase: painter.countingBase,
  devicePixelRatio: painter.devicePixelRatio,
);

void main() {
  testWidgets('the block is THREE bands, and they tile it exactly', (
    tester,
  ) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final block = requireCutBlock(tester, 'cut-1');
    const band = StoryboardCutBlocksPainter.bandHeight;

    expect(block.topBand.top, block.rect.top);
    expect(block.strip.top, block.topBand.bottom);
    expect(block.bottomBand.top, block.strip.bottom);
    expect(block.bottomBand.bottom, block.rect.bottom);
    for (final each in [block.topBand, block.bottomBand]) {
      expect(each.height, band);
    }
    // I-73 (the drawn proposal 유저 took on 2026-10-08: 「높이 70 + 30」):
    // the strip keeps what the cut's two bands leave of the row — the 44px
    // it had under four.
    expect(block.rect.height, StoryboardPanel.defaultTrackLaneHeight);
    expect(block.strip.height, block.rect.height - band * 2);
    expect(block.strip.height, 44);
  });

  testWidgets('the strip fills the block edge to edge — x IS the frame '
      'axis, so a horizontal inset would break the alignment with the '
      'ruler and the S rows', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.strip.left, block.rect.left);
    expect(block.strip.right, block.rect.right);
    for (final band in [block.topBand, block.bottomBand]) {
      expect(band.width, block.rect.width);
    }
  });

  // ↩️유저 2026-09-26: 「처음부터 콘티블록 생각해서 띠 위치 잡아두는게
  // 콘티블록 있는거랑 없는거랑 ui차이 안날거같은데」 — said of the conte
  // blocks' bands, which stood on every cut. They are a row of their own now,
  // and the cut block has nothing of a conte layer's to be different by.
  testWidgets('🗣️a cut block is the same three bands with a conte layer or '
      'without one', (tester) async {
    await _pump(tester);
    final bare = requireCutBlock(tester, 'cut-1');
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final divided = requireCutBlock(tester, 'cut-1');

    expect(bare.topBand, divided.topBand);
    expect(bare.strip, divided.strip);
    expect(bare.bottomBand, divided.bottomBand);
  });

  testWidgets('a cut with NO storyboard row still has one panel over the '
      'whole cut — the empty case is the general rule degenerating', (
    tester,
  ) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cells, hasLength(1));
    expect(block.cells.single.startIndex, 0);
    expect(block.cells.single.endIndexExclusive, 12);
  });

  testWidgets('a divided row shows its panels, tiling the cut', (tester) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cells.map((cell) => cell.startIndex), [0, 4, 9]);
    // The last panel runs to the cut end, whatever its stored length said.
    expect(block.cells.map((cell) => cell.endIndexExclusive), [4, 9, 12]);
  });

  testWidgets('🗣️a short row KEEPS its bands and their writing — the strip '
      'gives up the room (유저 2026-09-25: 「띠는 v행 세로 줄어도 고정으로 그 '
      '자리에 두자」)', (tester) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    // The painter answers for any row height — at the V row's floor too.
    const floor = StoryboardPanel.minTrackLaneHeight;
    final block = _painterLike(
      cutBlocksPainter(tester),
      crossAxisExtent: floor,
    ).blocks().single;

    const band = StoryboardCutBlocksPainter.bandHeight;
    expect(
      floor,
      band * 2,
      reason: 'the floor is the bands alone (유저 2026-09-26: 「최솟값 ok」)',
    );
    for (final each in [block.topBand, block.bottomBand]) {
      expect(each.height, band);
    }
    expect(block.strip.height, 0);
    expect(block.title, 'cut-1');
    expect(block.total, '12', reason: 'every word stays whole');
  });

  testWidgets('🗣️the cut\'s bands wear the cut\'s 색 라벨, and the conte '
      'row\'s blocks the storyboard layer\'s (유저 2026-09-26: 「블록도 '
      '색라벨에맞춰서 프레임블록 칠하는거마냥」 · 「안쪽띠, 콘티블록 라벨 반영」)', (
    tester,
  ) async {
    await _pump(
      tester,
      storyboardLayer: _dividedStoryboardLayer('cut-1', mark: _conte),
      cutMark: _art,
    );
    final block = requireCutBlock(tester, 'cut-1');
    final spy = _painted(tester);

    expect(spy.fillOf(block.topBand), layerMarkColor(_art).toARGB32());
    expect(spy.fillOf(block.bottomBand), layerMarkColor(_art).toARGB32());
    // ↩️The conte blocks' pair of bands, inside the cut block.
    final conteRow = conteRowPainter(tester, _trackId.value);
    for (final frame in [0, 4, 9, 11]) {
      expect(
        conteRow.resolvedCellStyleFor(frame).background,
        layerMarkColor(_conte),
        reason: 'frame $frame',
      );
    }
  });

  testWidgets('with no storyboard layer the conte row wears the PLATE — no '
      'layer, no label to wear — and its + reads against it', (tester) async {
    await _pump(tester, cutMark: _art);
    final block = requireCutBlock(tester, 'cut-1');
    final cut = _painted(tester);
    final cutPlate = cut.plates.single.color.toARGB32();
    final create = _paintedCreate(tester);
    final plate = conteCreatePlates(tester, _trackId.value).single;

    expect(cut.fillOf(block.topBand), layerMarkColor(_art).toARGB32());
    expect(
      create.plates.map((each) => (each.rect, each.color.toARGB32())),
      [(plate.outerRect, cutPlate)],
      reason: 'the cut block\'s own plate, over the cut\'s whole stretch',
    );
    // The + where a panel's name would stand: at the stretch's left, the
    // band word's inset in.
    expect(create.rects, hasLength(1), reason: 'the + and nothing else');
    expect(create.rects.single.left, closeTo(plate.left + 4, 0.01));
    expect(
      conteRowBlocks(tester, _trackId.value),
      isEmpty,
      reason: 'and the row holds no block there',
    );
  });

  testWidgets('🗣️the plate is the conte sheet\'s ink, and nothing outlines '
      'it — 「바탕색을 콘티프리뷰패널의 픽쳐의 실루엣이랑 똑같이 검정색」 · 「패딩/'
      '실루엣선 이런거 싹 없도록 심플하게만」 (유저 2026-09-26)', (tester) async {
    // The ACTIVE cut, on purpose: being active colours no plate. What does
    // is the playhead standing in it (F-248, below) — none is wired here.
    // ↩️F-212 had taken the active cut's accent plate away.
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final block = requireCutBlock(tester, 'cut-1');
    final spy = _painted(tester);

    expect(
      spy.plates.map((plate) => (plate.rect, plate.color.toARGB32())),
      [(block.rect, conteSheetInk.toARGB32())],
      reason: 'ONE rounded shape — the plate, filled — and no outline round '
          'it (↩️R26 #8\'s light edge)',
    );
    expect(
      spy.fills.map((fill) => fill.rect).toSet(),
      {block.topBand, block.bottomBand},
      reason: 'the bands and nothing else: no panel silhouette (↩️#15), no '
          'create box (↩️D30), no gap',
    );
  });

  group('🗣️F-248: the cut you stand on wears the standing wash on its bands '
      '— 「썸네일 제외한 띠 부분」', () {
    Future<ValueNotifier<CutId?>> stand(
      WidgetTester tester, {
      TimelineRowAddress? on,
    }) async {
      final under = ValueNotifier<CutId?>(const CutId('cut-1'));
      addTearDown(under.dispose);
      await _pump(
        tester,
        storyboardLayer: _dividedStoryboardLayer('cut-1', mark: _conte),
        cutMark: _art,
        cutUnderPlayhead: under,
        selectedRow: on,
      );
      return under;
    }

    ({List<int> bands, int plate}) painted(WidgetTester tester) {
      final block = requireCutBlock(tester, 'cut-1');
      final spy = _painted(tester);
      return (
        bands: [
          for (final band in [block.topBand, block.bottomBand])
            spy.fillOf(band),
        ],
        plate: spy.plates.single.color.toARGB32(),
      );
    }

    int washed(Color label) =>
        Color.alphaBlend(timelineStandingWashColor, label).toARGB32();

    testWidgets('on the V row: the bands, never the plate around its '
        'pictures — and they go with the cut', (tester) async {
      final under = await stand(tester, on: const TrackRowAddress(_trackId));
      final cut = layerMarkColor(_art);
      final stood = painted(tester);
      expect(stood.bands, [washed(cut), washed(cut)]);
      expect(stood.plate, conteSheetInk.toARGB32());

      under.value = null;
      expect(
        tester.renderObject(cutBlocksFinder()).debugNeedsPaint,
        isTrue,
        reason: 'the crossing repaints the row',
      );
      await tester.pump();
      expect(painted(tester).bands.first, cut.toARGB32());
    });

    testWidgets('standing nowhere on this rail, none', (tester) async {
      await stand(tester);
      expect(
        painted(tester).bands.first,
        layerMarkColor(_art).toARGB32(),
      );
    });

    // One standing place: the conte row is a row of its own, and standing
    // on it is not standing on the cut above it.
    testWidgets('standing on the CONTE row under it, none', (tester) async {
      await stand(tester, on: LayerRowAddress(trackConteRowId(_trackId)));
      expect(painted(tester).bands, [
        layerMarkColor(_art).toARGB32(),
        layerMarkColor(_art).toARGB32(),
      ]);
    });
  });

  test('a selected band you stand on wears both — the wash under the '
      'selection\'s tint', () {
    const label = Color(0xFF406080);
    expect(
      storyboardCutBandColor(label, rangeSelected: true, standing: true),
      Color.alphaBlend(
        timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
        Color.alphaBlend(timelineStandingWashColor, label),
      ),
    );
  });

  testWidgets('a range selection tints BOTH bands and never the plate — the '
      'selection colours what is not the picture', (tester) async {
    await _pump(
      tester,
      storyboardLayer: _dividedStoryboardLayer('cut-1', mark: _conte),
      cutMark: _art,
    );
    final painter = cutBlocksPainter(tester);
    final range = ValueNotifier<TrackFrameRangeSelection?>(
      TrackFrameRangeSelection(
        trackId: _trackId,
        anchorRow: painter.rowAddress,
        startFrame: 0,
        endFrameExclusive: 12,
      ),
    );
    addTearDown(range.dispose);
    final selected = _painterLike(painter, selectedRange: range);
    final block = selected.blocks().single;
    expect(block.isRangeSelected, isTrue, reason: '⛔전제');

    final spy = _ParagraphOffsetSpy();
    selected.paint(spy, Size(block.rect.right, block.rect.bottom));
    final tint = storyboardCarriedWritingGround(block);
    expect(tint, isNot(block.cutLabel));
    expect(spy.fillOf(block.topBand), tint.toARGB32());
    expect(spy.fillOf(block.bottomBand), tint.toARGB32());
    expect(
      spy.plates.single.color.toARGB32(),
      storyboardCutBlockBackgroundColor(
        painter.colorScheme,
        hovered: false,
      ).toARGB32(),
      reason: 'the block keeps its resting plate around the picture',
    );
  });

  // The panels' writing is the conte row's, printed by the timeline's own
  // row: a name at its block's head and a length at its end — the frame
  // block's print, where the cut block's inner bands carried them (#15, 유저
  // 2026-09-25: 「이름은 윗 띠, 코마는 아랫 띠」).
  group('the panels\' writing is the conte row\'s', () {
    testWidgets('#15: each panel carries its frame NAME (nothing when '
        'unnamed — 유저 09-26, ↩️F-149\'s mark) and its own comma count', (
      tester,
    ) async {
      final layer = Layer(
        id: const LayerId('cut-1-sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          Frame(
            id: const FrameId('cut-1-a'),
            duration: 1,
            strokes: const [],
            name: 'LO',
          ),
          Frame(id: const FrameId('cut-1-b'), duration: 1, strokes: const []),
          Frame(id: const FrameId('cut-1-c'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('cut-1-a'), length: 4),
          4: const TimelineExposure.drawing(FrameId('cut-1-b'), length: 5),
          9: const TimelineExposure.drawing(FrameId('cut-1-c'), length: 3),
        },
      );
      await _pump(tester, storyboardLayer: layer);
      final row = conteRowPainter(tester, _trackId.value);

      expect(
        [
          for (final start in [0, 4, 9])
            (row.cellModelAt(start).glyph, row.cellModelAt(start).mark),
        ],
        [('LO', null), ('', null), ('', null)],
      );
      expect(conteRowRunLabels(tester, _trackId.value), [
        (0, '4'),
        (4, '5'),
        (9, '3'),
      ]);
    });

    testWidgets('D23: a ONE-comma panel prints no comma count — the shared '
        'predicate, same gate as the timeline run labels', (tester) async {
      final layer = Layer(
        id: const LayerId('cut-1-sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          Frame(id: const FrameId('cut-1-a'), duration: 1, strokes: const []),
          Frame(id: const FrameId('cut-1-b'), duration: 1, strokes: const []),
        ],
        timeline: {
          // Panels are the cut's coverage projection — the last one runs to
          // the cut's end, so the 1-comma panel goes LAST to stay 1 comma.
          0: const TimelineExposure.drawing(FrameId('cut-1-a'), length: 11),
          11: const TimelineExposure.drawing(FrameId('cut-1-b'), length: 1),
        },
      );
      await _pump(tester, storyboardLayer: layer);

      expect(
        conteRowRunLabels(tester, _trackId.value),
        [(0, '11')],
        reason: 'length 1 is silent (2코마부터만 표시); length 11 still counts',
      );
    });

    testWidgets('the last panel runs to the cut\'s end, whatever its stored '
        'length said — and counts what it shows', (tester) async {
      // Stored 0·4, 4·5, 9·3 over a cut of 12: the row tiles the cut.
      await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));

      expect(conteRowBlocks(tester, _trackId.value), {0: 4, 4: 5, 9: 3});
    });
  });

  group('#15 R3 — the writing anchors (user 2026-07-29), in the BANDS', () {
    const cell = 24.0;

    Future<(StoryboardCutBlockVisual, _ParagraphOffsetSpy)> painted(
      WidgetTester tester, {
      double pixelsPerFrame = cell,
    }) async {
      await _pump(
        tester,
        storyboardLayer: _dividedStoryboardLayer('cut-1', named: true),
        pixelsPerFrame: pixelsPerFrame,
        thumbnailFor: (cut, frame, {required shownHeight, region}) =>
            null,
      );
      return (requireCutBlock(tester, 'cut-1'), _painted(tester));
    }

    testWidgets('the cut\'s title stands alone in its top band from the '
        'block\'s left, its length alone in its bottom band at the right — '
        'and nothing over the picture', (tester) async {
      final (block, spy) = await painted(tester);

      final title = _wordsIn(block.topBand, spy);
      expect(title, hasLength(1), reason: 'the title alone');
      expect(title.single.left, closeTo(block.rect.left + 4, 0.01));
      final length = _wordsIn(block.bottomBand, spy);
      expect(length, hasLength(1), reason: 'the length alone');
      expect(length.single.right, closeTo(block.rect.right - 4, 0.01));
      expect(
        _wordsIn(block.strip, spy),
        isEmpty,
        reason: '🗣️nothing rides the picture — a panel\'s name and length '
            'are the conte row\'s (↩️in bands of their own here)',
      );
      expect(spy.circles, isEmpty, reason: 'no mark either');
    });

    // 🗣️F-234 (유저 2026-09-29): 「코마텍스트가 위아래 정렬이 중앙이아니라
    // 살짝위라던가 … 특히 컷블록의 코마텍스트. 관련 텍스트 통일」.
    testWidgets('🚨F-234: every word in the bands keeps its whole height — '
        'the block word\'s box, which the band holds — on the band\'s '
        'middle', (tester) async {
      final (block, spy) = await painted(tester);

      for (final band in [block.topBand, block.bottomBand]) {
        final words = _wordsIn(band, spy);
        expect(words, isNotEmpty, reason: 'fixture: $band writes');
        for (final word in words) {
          expect(
            word.height,
            closeTo(11, 0.01),
            reason: '↩️a 1.45 line made a 16px box, narrowed to 81% of its '
                'height to fit a 13px band its ink never overflowed',
          );
          expect(word.center.dy, closeTo(band.center.dy, 0.01));
        }
      }
    });

    testWidgets('F-234: the words are printed from the row\'s own ambient '
        'style — the one every block word is printed from', (tester) async {
      await painted(tester);
      final ambient = DefaultTextStyle.of(
        tester.element(find.byType(StoryboardPanel)),
      ).style;

      expect(
        cutBlocksPainter(tester).baseTextStyle,
        ambient,
        reason: '↩️it was the theme\'s labelSmall, a style no other block '
            'word reads',
      );
      expect(
        conteRowPainter(tester, _trackId.value).baseTextStyle,
        ambient,
        reason: 'and the conte row\'s words with them',
      );
    });

    testWidgets('the cut TITLE follows the ground law too — the cells\' one '
        'writing rule on every label, no scrim anywhere', (tester) async {
      await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
      final block = requireCutBlock(tester, 'cut-1');
      final offsets = _painted(tester).offsets;

      // The title hangs at the top band's left end (padding 4): one
      // paragraph, one offset — the fill pass and nothing under it.
      final titleHits = offsets
          .where(
            (o) =>
                (o.dx - (block.rect.left + 4)).abs() < 0.01 &&
                o.dy < block.strip.top,
          )
          .toList();
      expect(titleHits.length, 1, reason: 'the fill pass and nothing under it');
    });
  });

  testWidgets('B (유저 2026-09-24): a title longer than its band keeps its '
      'type and narrows into the band — never cut to an ellipsis', (
    tester,
  ) async {
    await _pump(tester, pixelsPerFrame: 2);
    final block = requireCutBlock(tester, 'cut-1');
    final band = block.topBand;
    final title = _wordsIn(band, _painted(tester));
    expect(title, hasLength(1), reason: 'the title is painted');
    expect(title.single.left, closeTo(band.left + 4, 0.01));
    expect(
      title.single.right,
      lessThanOrEqualTo(band.right - 4 + 0.01),
      reason: 'narrowed into its band — ↩️an ellipsis cut its end, and its '
          'paragraph still measured the whole name',
    );
  });

  // 🗣️F-234-Q1 (유저 2026-09-29): 「글자 사이부터 줄이기」. The word is first
  // painted at a roomy zoom, where it runs its natural length.
  testWidgets('a title a few pixels long gives up its letter gaps and is '
      'not narrowed', (tester) async {
    Future<({double width, double xScale})> titleAt(
      double pixelsPerFrame,
    ) async {
      await _pump(tester, pixelsPerFrame: pixelsPerFrame);
      final block = requireCutBlock(tester, 'cut-1');
      final spy = _painted(tester);
      final at = spy.rects.indexWhere(
        (rect) => block.topBand.contains(rect.center),
      );
      return (width: spy.rects[at].width, xScale: spy.xScales[at]);
    }

    final natural = await titleAt(12);
    final tight = await titleAt(5.25);
    final room = requireCutBlock(tester, 'cut-1').topBand.width - 8;
    expect(
      natural.width - room,
      inExclusiveRange(0, 4 * maxGapTightening),
      reason: '⛔전제: longer than its room by less than its four gaps give',
    );
    expect(tight.xScale, 1, reason: 'its gaps gave the pixels');
  });

  testWidgets('🗣️the row asks its pictures at the strip\'s height in DEVICE '
      'pixels — the conte cell\'s law — so a V row may grow as tall as it '
      'likes without stretching a small picture (유저 2026-09-26: 「최대값은 '
      '최대한 키울수있으면 좋아」)', (tester) async {
    final asked = <double>{};
    Future<void> pumpAt(double laneHeight) async {
      asked.clear();
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryboardPanel(
              project: _project(
                storyboardLayer: _dividedStoryboardLayer('cut-1'),
              ),
              activeCutId: const CutId('cut-1'),
              pixelsPerFrame: 12,
              trackLaneHeight: laneHeight,
              thumbnails: fixedThumbnails((
                cut,
                frame, {
                required shownHeight,
                region,
              }) {
                asked.add(shownHeight);
                return null;
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final laneHeight in [
      StoryboardPanel.defaultTrackLaneHeight,
      StoryboardPanel.defaultTrackLaneHeight * 4,
    ]) {
      await pumpAt(laneHeight);
      expect(asked, {
        StoryboardCutBlocksPainter.stripBandOf(laneHeight).height * 2,
      }, reason: 'a $laneHeight row, at twice the density');
    }

    // 🚨And at the floor, where the strip has no room, it asks for none: it
    // shows none, and every ask is a render that thaws its cut at the
    // canvas's full size (유저 2026-09-28: V행을 키우다 튕겼다 — measured on
    // the user's film, 26 pictures nobody could see took +570MB).
    await pumpAt(StoryboardPanel.minTrackLaneHeight);
    expect(asked, isEmpty, reason: 'a row at its floor shows no picture');
  });

  test('the V row\'s heights: 70 by default — the cut\'s two bands and the '
      '44px its picture had — and the two bands at the floor (I-73, the '
      'proposal 유저 took on 2026-10-08: 「높이 70 + 30」; ↩️96 and four '
      'bands, 유저 2026-09-26: 「기본높이는 96으로 가자. 최솟값 ok」)', () {
    expect(StoryboardPanel.defaultTrackLaneHeight, 70);
    expect(
      StoryboardPanel.minTrackLaneHeight,
      StoryboardCutBlocksPainter.bandHeight * 2,
    );
  });

  testWidgets('🗣️what an edge stands on is read off the block — its bands in '
      'their fill, and each picture where it is drawn, on its paper (유저 '
      '2026-09-26: 「2여도 흰종이부분에 엣지는 1처럼 제대로 보이게 가능하지?」)', (
    tester,
  ) async {
    final picture = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 160, 90),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      return recorder.endRecording().toImage(160, 90);
    }))!;
    const cell = 24.0;
    await _pump(
      tester,
      storyboardLayer: _dividedStoryboardLayer('cut-1', mark: _conte),
      cutMark: _art,
      pixelsPerFrame: cell,
      // Panel a's picture is there; b's and c's are still being made.
      thumbnailFor: (cut, frame, {required shownHeight, region}) =>
          frame == 0 ? picture : null,
    );
    final block = requireCutBlock(tester, 'cut-1');
    final grounds = cutBlocksPainter(tester).groundsOf(block);

    expect(grounds.take(2).map((ground) => ground.rect), [
      block.topBand,
      block.bottomBand,
    ]);
    expect(grounds.take(2).map((ground) => ground.color), [
      layerMarkColor(_art),
      layerMarkColor(_art),
    ]);
    // Panel a (4 frames) is wider than its picture, which is drawn the
    // strip's height tall from the panel's left: past it, the plate.
    final strip = block.strip;
    final drawnWidth = 160 * strip.height / 90;
    expect(drawnWidth, lessThan(4 * cell), reason: '⛔전제');
    expect(
      grounds[2].rect,
      Rect.fromLTWH(block.rect.left, strip.top, drawnWidth, strip.height),
    );
    expect(grounds[2].color, storyboardPanelPictureGroundColor);
    expect(
      grounds.skip(3).map((ground) => (ground.rect, ground.color)),
      [
        (
          Rect.fromLTRB(
            block.rect.left + 4 * cell,
            strip.top,
            block.rect.left + 9 * cell,
            strip.bottom,
          ),
          AppColors.washUp,
        ),
        (
          Rect.fromLTRB(
            block.rect.left + 9 * cell,
            strip.top,
            block.rect.left + 12 * cell,
            strip.bottom,
          ),
          AppColors.washUp,
        ),
      ],
      reason: 'a picture still being made is its placeholder\'s shade',
    );
  });

  testWidgets('each edge reads the grounds of the block it stands in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: Project(
              id: const ProjectId('band-project'),
              name: 'Bands',
              createdAt: DateTime.utc(2026, 7, 27),
              tracks: [
                Track(
                  id: _trackId,
                  name: 'Video',
                  cuts: [
                    _cut(
                      'cut-1',
                      12,
                      storyboardLayer: _dividedStoryboardLayer(
                        'cut-1',
                        mark: _conte,
                      ),
                      mark: _art,
                    ),
                    _cut(
                      'cut-2',
                      8,
                      mark: const LayerMark(process: LayerProcess.key),
                    ),
                    _cut(
                      'cut-3',
                      10,
                      storyboardLayer: _dividedStoryboardLayer('cut-3'),
                    ),
                  ],
                ),
              ],
            ),
            activeCutId: const CutId('cut-1'),
            pixelsPerFrame: 12,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painter = cutBlocksPainter(tester);
    final grounds = StoryboardPlateGrounds(painter);
    final blocks = painter.blocks();
    expect(blocks, hasLength(3), reason: '⛔전제');

    // A triangle hanging in each block's top band, at its end.
    for (final (index, block) in blocks.indexed) {
      final box = Rect.fromLTWH(block.rect.right - 8, 0, 8, 10);
      final under = grounds.under(box);
      expect(
        under.map((ground) => ground.rect),
        [block.topBand],
        reason: 'block $index',
      );
      expect(
        under.single.color,
        [
          layerMarkColor(_art),
          layerMarkColor(const LayerMark(process: LayerProcess.key)),
          layerMarkColor(LayerMark.none),
        ][index],
        reason: 'block $index: its own cut\'s label',
      );
    }
    expect(
      grounds.under(const Rect.fromLTWH(-40, 0, 8, 10)),
      isEmpty,
      reason: 'nothing under a box before the first block',
    );
  });
}
