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
import 'package:anicel/src/models/track.dart';
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
import 'package:anicel/src/ui/timeline/timeline_cell_marker.dart'
    show timelineCellWritesNothing;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show
        storyboardCutBlockBackgroundColor,
        storyboardPanelPictureGroundColor,
        timelineStandingWashColor;
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart'
    show timelineFrameEdge;
import '../helpers/fixed_thumbnails.dart';
import 'storyboard_cut_block_probe.dart';

/// The cut block is FIVE BANDS, top to bottom: the CUT's, the CONTE
/// BLOCKS', the strip, the conte blocks', the cut's. The strip is the
/// picture and nothing is written over it; the bands carry the writing —
/// the cut's number at the left end of its top band and its length at the
/// right end of its bottom one (the conte sheet's CUT and TIME columns,
/// which sit outside the picture cell, turned on their side), and each
/// panel's name and comma count in the conte blocks' pair between (유저
/// 2026-09-25 · 2026-09-26). ↩️Three bands — one each side, shared by the
/// cut's writing and the panels' — until 2026-09-26.
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

/// The words laid in [band], left to right.
List<Rect> _wordsIn(Rect band, _ParagraphOffsetSpy spy) =>
    spy.rects.where((rect) => band.contains(rect.center)).toList()
      ..sort((a, b) => a.left.compareTo(b.left));

void main() {
  testWidgets('the block is FIVE bands, and they tile it exactly', (
    tester,
  ) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final block = requireCutBlock(tester, 'cut-1');
    const band = StoryboardCutBlocksPainter.bandHeight;

    expect(block.topBand.top, block.rect.top);
    expect(block.innerTopBand.top, block.topBand.bottom);
    expect(block.strip.top, block.innerTopBand.bottom);
    expect(block.innerBottomBand.top, block.strip.bottom);
    expect(block.bottomBand.top, block.innerBottomBand.bottom);
    expect(block.bottomBand.bottom, block.rect.bottom);
    for (final each in [
      block.topBand,
      block.innerTopBand,
      block.innerBottomBand,
      block.bottomBand,
    ]) {
      expect(each.height, band);
    }
    // 🗣️유저 2026-09-26: 「기본높이는 96으로 가자」 — the strip keeps what the
    // four bands leave of it.
    expect(block.rect.height, StoryboardPanel.defaultTrackLaneHeight);
    expect(block.strip.height, block.rect.height - band * 4);
  });

  testWidgets('the strip fills the block edge to edge — x IS the frame '
      'axis, so a horizontal inset would break the alignment with the '
      'ruler and the S rows', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.strip.left, block.rect.left);
    expect(block.strip.right, block.rect.right);
    for (final band in [
      block.topBand,
      block.innerTopBand,
      block.innerBottomBand,
      block.bottomBand,
    ]) {
      expect(band.width, block.rect.width);
    }
  });

  testWidgets('🗣️the conte blocks\' bands stand on EVERY cut — one with no '
      'storyboard layer keeps them in the same place (유저 2026-09-26: 「처음'
      '부터 콘티블록 생각해서 띠 위치 잡아두는게 콘티블록 있는거랑 없는거랑 ui'
      '차이 안날거같은데」)', (tester) async {
    await _pump(tester);
    final bare = requireCutBlock(tester, 'cut-1');
    expect(bare.hasStoryboardLayer, isFalse, reason: '⛔전제');
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final divided = requireCutBlock(tester, 'cut-1');

    expect(bare.innerTopBand, divided.innerTopBand);
    expect(bare.strip, divided.strip);
    expect(bare.innerBottomBand, divided.innerBottomBand);
  });

  testWidgets('a cut with NO storyboard row still has one panel over the '
      'whole cut — the empty case is the general rule degenerating', (
    tester,
  ) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.hasStoryboardLayer, isFalse);
    expect(block.cells, hasLength(1));
    expect(block.cells.single.startIndex, 0);
    expect(block.cells.single.endIndexExclusive, 12);
  });

  testWidgets('a divided row shows its panels, tiling the cut', (tester) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.hasStoryboardLayer, isTrue);
    expect(block.cells.map((cell) => cell.startIndex), [0, 4, 9]);
    // The last panel runs to the cut end, whatever its stored length said.
    expect(block.cells.map((cell) => cell.endIndexExclusive), [4, 9, 12]);
  });

  testWidgets('🗣️a short row KEEPS its bands and their writing — the strip '
      'gives up the room (유저 2026-09-25: 「띠는 v행 세로 줄어도 고정으로 그 '
      '자리에 두자」)', (tester) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    // The painter answers for any row height — at the V row's floor too.
    final painter = cutBlocksPainter(tester);
    const floor = StoryboardPanel.minTrackLaneHeight;
    final short = StoryboardCutBlocksPainter(
      entries: painter.entries,
      storyboardLayerNames: painter.storyboardLayerNames,
      storyboardCellsByCut: painter.storyboardCellsByCut,
      geometry: painter.geometry,
      crossAxisExtent: floor,
      minBlockWidth: painter.minBlockWidth,
      selectedRange: painter.selectedRange,
      rowAddress: painter.rowAddress,
      hoveredCutId: painter.hoveredCutId,
      colorScheme: painter.colorScheme,
      baseTextStyle: painter.baseTextStyle,
      showSeconds: painter.showSeconds,
      countingBase: painter.countingBase,
      devicePixelRatio: painter.devicePixelRatio,
    );
    final block = short.blocks().single;

    const band = StoryboardCutBlocksPainter.bandHeight;
    expect(
      floor,
      band * 4,
      reason: 'the floor is the four bands alone (유저 2026-09-26: 「최솟값 ok」)',
    );
    for (final each in [
      block.topBand,
      block.innerTopBand,
      block.innerBottomBand,
      block.bottomBand,
    ]) {
      expect(each.height, band);
    }
    expect(block.strip.height, 0);
    expect(
      block.cellHeads,
      hasLength(3),
      reason: '↩️under 44px the bands folded and the panel writing went',
    );
    expect(block.cellCommaLabels, ['4', '5', '3']);
  });

  testWidgets('🗣️the cut\'s pair of bands wears the cut\'s 색 라벨 and the '
      'conte blocks\' pair the storyboard layer\'s (유저 2026-09-26: 「블록도 '
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
    expect(spy.fillOf(block.innerTopBand), layerMarkColor(_conte).toARGB32());
    expect(
      spy.fillOf(block.innerBottomBand),
      layerMarkColor(_conte).toARGB32(),
    );
  });

  testWidgets('with no storyboard layer the conte blocks\' bands are the '
      'PLATE — no layer, no label to wear', (tester) async {
    await _pump(tester, cutMark: _art);
    final block = requireCutBlock(tester, 'cut-1');
    final spy = _painted(tester);
    final plate = spy.plates.single.color.toARGB32();

    expect(spy.fillOf(block.topBand), layerMarkColor(_art).toARGB32());
    expect(spy.fillOf(block.innerTopBand), plate);
    expect(spy.fillOf(block.innerBottomBand), plate);
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
      {
        block.topBand,
        block.innerTopBand,
        block.innerBottomBand,
        block.bottomBand,
      },
      reason: 'the bands and nothing else: no panel silhouette (↩️#15), no '
          'create box (↩️D30), no gap',
    );
  });

  testWidgets('🗣️F-248: the cut under the playhead wears the standing wash '
      'in its plate, under its pictures — 「외곽라인말고 블럭을 바탕색으로서 '
      '강조색 표시. 전처럼 연하게」', (tester) async {
    final under = ValueNotifier<CutId?>(const CutId('cut-1'));
    addTearDown(under.dispose);
    await _pump(
      tester,
      storyboardLayer: _dividedStoryboardLayer('cut-1'),
      cutUnderPlayhead: under,
    );
    int plate() => _painted(tester).plates.single.color.toARGB32();

    expect(
      plate(),
      Color.alphaBlend(timelineStandingWashColor, conteSheetInk).toARGB32(),
    );
    under.value = null;
    expect(
      tester.renderObject(cutBlocksFinder()).debugNeedsPaint,
      isTrue,
      reason: 'the crossing repaints the row',
    );
    await tester.pump();
    expect(plate(), conteSheetInk.toARGB32(), reason: 'it goes with the cut');
  });

  test('a hovered cut under the playhead lifts its washed plate, not the '
      'bare ink', () {
    final scheme = ThemeData.dark().colorScheme;
    expect(
      storyboardCutBlockBackgroundColor(scheme, hovered: true, standing: true),
      Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.10),
        Color.alphaBlend(timelineStandingWashColor, conteSheetInk),
      ),
    );
  });

  testWidgets('a range selection tints all FOUR bands and never the plate — '
      'the selection colours what is not the picture', (tester) async {
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
    final selected = StoryboardCutBlocksPainter(
      entries: painter.entries,
      storyboardLayerNames: painter.storyboardLayerNames,
      storyboardCellsByCut: painter.storyboardCellsByCut,
      geometry: painter.geometry,
      crossAxisExtent: painter.crossAxisExtent,
      minBlockWidth: painter.minBlockWidth,
      selectedRange: range,
      rowAddress: painter.rowAddress,
      hoveredCutId: painter.hoveredCutId,
      colorScheme: painter.colorScheme,
      baseTextStyle: painter.baseTextStyle,
      showSeconds: painter.showSeconds,
      countingBase: painter.countingBase,
      devicePixelRatio: painter.devicePixelRatio,
    );
    final block = selected.blocks().single;
    expect(block.isRangeSelected, isTrue, reason: '⛔전제');

    final spy = _ParagraphOffsetSpy();
    selected.paint(spy, Size(block.rect.right, block.rect.bottom));
    Color tint(StoryboardBand band) =>
        storyboardCarriedWritingGround(block, painter.colorScheme, band: band);
    expect(tint(StoryboardBand.cut), isNot(block.cutLabel));
    expect(tint(StoryboardBand.conte), isNot(block.conteLabel));
    expect(spy.fillOf(block.topBand), tint(StoryboardBand.cut).toARGB32());
    expect(spy.fillOf(block.bottomBand), tint(StoryboardBand.cut).toARGB32());
    expect(
      spy.fillOf(block.innerTopBand),
      tint(StoryboardBand.conte).toARGB32(),
    );
    expect(
      spy.fillOf(block.innerBottomBand),
      tint(StoryboardBand.conte).toARGB32(),
    );
    expect(
      spy.plates.single.color.toARGB32(),
      storyboardCutBlockBackgroundColor(
        painter.colorScheme,
        hovered: false,
        standing: false,
      ).toARGB32(),
      reason: 'the block keeps its resting plate around the picture',
    );
  });

  testWidgets('🗣️a cut with no storyboard layer: its WHOLE inner top band is '
      'the create button, the + where a conte block\'s name would stand '
      '(유저 2026-09-26: 「콘티블록 상단띠 전면을 생성버튼으로」)', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');
    final spy = _painted(tester);

    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(block),
      block.innerTopBand,
    );
    final plus = _wordsIn(block.innerTopBand, spy);
    expect(plus, hasLength(1), reason: 'the + and nothing else');
    expect(plus.single.left, closeTo(block.rect.left + 4, 0.01));
    expect(
      _wordsIn(block.strip, spy),
      isEmpty,
      reason: '↩️D30 stood it in a box centred in the strip',
    );

    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(
        requireCutBlock(tester, 'cut-1'),
      ),
      isNull,
      reason: 'a cut with a storyboard layer has conte blocks there instead',
    );
  });

  testWidgets('#15: each panel carries its frame NAME (nothing when unnamed — '
      '유저 09-26, ↩️F-149\'s mark) and its own comma count — the timeline '
      'row conventions carried over', (tester) async {
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
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cellHeads, [
      (word: 'LO', mark: null),
      (word: '', mark: null),
      (word: '', mark: null),
    ]);
    expect(block.cellCommaLabels, ['4', '5', '3']);
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
    final block = requireCutBlock(tester, 'cut-1');

    expect(
      block.cellCommaLabels,
      ['11', ''],
      reason: 'length 1 is silent (2코마부터만 표시); length 11 still counts',
    );
  });

  testWidgets('#15: the no-row cut\'s single placeholder panel prints no '
      'writing at all', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cellHeads, [timelineCellWritesNothing]);
    expect(block.cellCommaLabels, ['']);
  });

  group('#15 R3 — the writing anchors (user 2026-07-29), in the BANDS', () {
    // 🗣️유저 2026-09-25, to 「패널의 이름·코마 글씨가 썸네일을 가린다」:
    // 「띠로 옮긴다 — 이름은 윗 띠, 코마는 아랫 띠」 — and since 2026-09-26 the
    // conte blocks' own pair of bands, inside the cut's. ↩️D29-2 carried
    // them over the picture on plates of the band's fill, and the plates
    // covered the pictures.
    const cell = 24.0;

    Future<(StoryboardCutBlockVisual, _ParagraphOffsetSpy)> painted(
      WidgetTester tester, {
      required bool named,
      double pixelsPerFrame = cell,
    }) async {
      await _pump(
        tester,
        storyboardLayer: _dividedStoryboardLayer('cut-1', named: named),
        pixelsPerFrame: pixelsPerFrame,
        thumbnailFor: (cut, frame, {required shownHeight, region}) =>
            null,
      );
      return (requireCutBlock(tester, 'cut-1'), _painted(tester));
    }

    testWidgets('a panel\'s name stands in the conte blocks\' TOP band from '
        'the panel\'s left — the cut title\'s anchor — the title alone in '
        'the cut\'s, and nothing over the picture', (tester) async {
      final (block, spy) = await painted(tester, named: true);

      final title = _wordsIn(block.topBand, spy);
      expect(title, hasLength(1), reason: 'the title alone');
      expect(title.single.left, closeTo(block.rect.left + 4, 0.01));
      final names = _wordsIn(block.innerTopBand, spy);
      expect(names, hasLength(3), reason: 'a, b and c');
      final [a, b, c] = names;
      // Panels a, b and c start at frames 0, 4 and 9; the word inset is 4.
      expect(a.left, closeTo(block.rect.left + 4, 0.01));
      expect(b.left, closeTo(block.rect.left + 4 * cell + 4, 0.01));
      expect(c.left, closeTo(block.rect.left + 9 * cell + 4, 0.01));
      expect(
        _wordsIn(block.strip, spy),
        isEmpty,
        reason: '🗣️nothing rides the picture',
      );
    });

    testWidgets('a name wider than its panel is narrowed into the panel — '
        'never gone (R26 #38: 「절대 안 사라지도록」)', (tester) async {
      const narrow = 4.0;
      final (block, spy) = await painted(
        tester,
        named: true,
        pixelsPerFrame: narrow,
      );
      final [a, ...] = _wordsIn(block.innerTopBand, spy);
      final panelAEnd = block.rect.left + 4 * narrow;
      expect(a.left, closeTo(block.rect.left + 4, 0.01));
      expect(
        a.right,
        lessThanOrEqualTo(panelAEnd - 4 + 0.01),
        reason: 'panel a\'s own name, narrowed into its own panel',
      );
    });

    testWidgets('a panel\'s comma count stands in the conte blocks\' BOTTOM '
        'band under the panel\'s last cell, and the cut\'s length alone in '
        'the cut\'s', (tester) async {
      final (block, spy) = await painted(tester, named: true);

      final length = _wordsIn(block.bottomBand, spy);
      expect(length, hasLength(1), reason: 'the length alone');
      expect(length.single.right, closeTo(block.rect.right - 4, 0.01));
      final commas = _wordsIn(block.innerBottomBand, spy);
      expect(commas, hasLength(3), reason: '4, 5 and 3');
      final [a, b, c] = commas;
      // F-96: centred on the panel's last cell while it fits — and on the
      // band's middle across it.
      expect(a.center.dx, closeTo(block.rect.left + 3.5 * cell, 0.01));
      expect(b.center.dx, closeTo(block.rect.left + 8.5 * cell, 0.01));
      expect(
        c.center.dx,
        closeTo(block.rect.left + 11.5 * cell, 0.01),
        reason: '↩️it ended before the cut\'s length while the two shared a '
            'band',
      );
      expect(a.center.dy, closeTo(block.innerBottomBand.center.dy, 0.01));
    });

    // 🧪F-220: the zoom follows every percent, and the law lays cells a
    // pixel apart in width — 14 and 15 at 14.6. A count centred on a cell
    // of the zoom's nominal width sat a fraction off the panel's last cell.
    testWidgets('at a zoom that is not whole pixels the comma count centres '
        'on the panel\'s last cell as the law laid it', (tester) async {
      const zoom = 14.6;
      double edge(int frame) => timelineFrameEdge(frame, zoom);
      final (block, spy) = await painted(
        tester,
        named: true,
        pixelsPerFrame: zoom,
      );

      final commas = _wordsIn(block.innerBottomBand, spy);
      expect(commas, hasLength(3), reason: '4, 5 and 3');
      // The panels end at frames 4, 9 and 12.
      for (final (comma, end) in [
        (commas[0], 4),
        (commas[1], 9),
        (commas[2], 12),
      ]) {
        expect(
          comma.center.dx,
          closeTo(block.rect.left + (edge(end - 1) + edge(end)) / 2, 0.01),
          reason: 'the panel ending at $end',
        );
      }
    });

    // 🗣️유저 2026-09-26: 「콘티레이어는 이름 없으면 진짜 이름 없도록 … 그리고
    // 이름없다고해서 띠까지 썸네일 차지한다던가 이런거없이 ui는 안바뀌게」.
    // ↩️It wore the timeline's in-between mark, drawn on the band, since
    // 2026-09-24 (「같은취급으로 통일」) — F-149's rule, now animation's alone.
    testWidgets('🗣️a panel whose drawing has no cel number writes NOTHING '
        'where its name would stand — no word, no mark — and the bands keep '
        'their place', (tester) async {
      final (block, spy) = await painted(tester, named: false);

      expect(
        _wordsIn(block.innerTopBand, spy),
        isEmpty,
        reason: 'no name at all',
      );
      expect(
        spy.circles,
        isEmpty,
        reason: 'no in-between mark on a storyboard panel',
      );
      final named = (await painted(tester, named: true)).$1;
      expect(block.innerTopBand, named.innerTopBand, reason: 'the band stays');
      expect(block.strip, named.strip, reason: 'the picture does not grow');
    });

    // 🗣️F-234 (유저 2026-09-29): 「코마텍스트가 위아래 정렬이 중앙이아니라
    // 살짝위라던가 … 특히 컷블록의 코마텍스트. 관련 텍스트 통일」.
    testWidgets('🚨F-234: every word in the four bands keeps its whole '
        'height — the block word\'s box, which the band holds — on the '
        'band\'s middle', (tester) async {
      final (block, spy) = await painted(tester, named: true);

      for (final band in [
        block.topBand,
        block.innerTopBand,
        block.innerBottomBand,
        block.bottomBand,
      ]) {
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
      await painted(tester, named: true);

      expect(
        cutBlocksPainter(tester).baseTextStyle,
        DefaultTextStyle.of(
          tester.element(find.byType(StoryboardPanel)),
        ).style,
        reason: '↩️it was the theme\'s labelSmall, a style no other block '
            'word reads',
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
                o.dy < block.innerTopBand.top,
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

  // 🗣️F-234-Q1 (유저 2026-09-29): 「글자 사이부터 줄이기」. Each word is
  // first painted at a roomy zoom, where it runs its natural length.
  group('a word a few pixels long gives up its letter gaps and is not '
      'narrowed', () {
    final onePanel = Layer(
      id: const LayerId('cut-1-sb'),
      name: 'SB',
      kind: LayerKind.storyboard,
      frames: [
        Frame(id: const FrameId('cut-1-a'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('cut-1-a'), length: 12),
      },
    );
    Future<({double width, double xScale})> wordIn(
      WidgetTester tester,
      Rect Function(StoryboardCutBlockVisual block) band, {
      required double pixelsPerFrame,
    }) async {
      await _pump(
        tester,
        pixelsPerFrame: pixelsPerFrame,
        storyboardLayer: onePanel,
      );
      final block = requireCutBlock(tester, 'cut-1');
      final spy = _painted(tester);
      final at = spy.rects.indexWhere(
        (rect) => band(block).contains(rect.center),
      );
      return (width: spy.rects[at].width, xScale: spy.xScales[at]);
    }

    testWidgets('the cut\'s title', (tester) async {
      Rect title(StoryboardCutBlockVisual block) => block.topBand;
      final natural = await wordIn(tester, title, pixelsPerFrame: 12);
      final tight = await wordIn(tester, title, pixelsPerFrame: 5.25);
      final room = requireCutBlock(tester, 'cut-1').topBand.width - 8;
      expect(
        natural.width - room,
        inExclusiveRange(0, 4 * maxGapTightening),
        reason: '⛔전제: longer than its room by less than its four gaps give',
      );
      expect(tight.xScale, 1, reason: 'its gaps gave the pixels');
    });

    testWidgets('a panel\'s comma count', (tester) async {
      Rect commas(StoryboardCutBlockVisual block) => block.innerBottomBand;
      final natural = await wordIn(tester, commas, pixelsPerFrame: 12);
      // Twelve frames of 22/12px: 22px of panel.
      final tight = await wordIn(tester, commas, pixelsPerFrame: 22 / 12);
      expect(
        natural.width - 22,
        inExclusiveRange(0, maxGapTightening),
        reason: '⛔전제: 「12」 is longer than its panel by less than its gap',
      );
      expect(tight.xScale, 1, reason: 'its gap gave the pixel');
      expect(tight.width, lessThanOrEqualTo(22), reason: 'set that tight');
    });
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

  test('🗣️the V row\'s heights are the user\'s: 96 by default and the four '
      'bands at the floor (유저 2026-09-26: 「기본높이는 96으로 가자. 최솟값 '
      'ok. 최대값은 최대한 키울수있으면 좋아」)', () {
    expect(StoryboardPanel.defaultTrackLaneHeight, 96);
    expect(
      StoryboardPanel.minTrackLaneHeight,
      StoryboardCutBlocksPainter.bandHeight * 4,
    );
  });

  testWidgets('🗣️what an edge stands on is read off the block — its four '
      'bands in their fills, and each picture where it is drawn, on its '
      'paper (유저 2026-09-26: 「2여도 흰종이부분에 엣지는 1처럼 제대로 보이게 '
      '가능하지?」)', (tester) async {
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

    expect(grounds.take(4).map((ground) => ground.rect), [
      block.topBand,
      block.innerTopBand,
      block.innerBottomBand,
      block.bottomBand,
    ]);
    expect(grounds.take(4).map((ground) => ground.color), [
      layerMarkColor(_art),
      layerMarkColor(_conte),
      layerMarkColor(_conte),
      layerMarkColor(_art),
    ]);
    // Panel a (4 frames) is wider than its picture, which is drawn the
    // strip's height tall from the panel's left: past it, the plate.
    final strip = block.strip;
    final drawnWidth = 160 * strip.height / 90;
    expect(drawnWidth, lessThan(4 * cell), reason: '⛔전제');
    expect(
      grounds[4].rect,
      Rect.fromLTWH(block.rect.left, strip.top, drawnWidth, strip.height),
    );
    expect(grounds[4].color, storyboardPanelPictureGroundColor);
    expect(
      grounds.skip(5).map((ground) => (ground.rect, ground.color)),
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

  testWidgets('each edge reads the grounds of the block it stands in, moved '
      'into its own chrome layer', (tester) async {
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
    const band = StoryboardCutBlocksPainter.bandHeight;
    final grounds = StoryboardPlateGrounds(painter, crossOffset: band);
    final blocks = painter.blocks();
    expect(blocks, hasLength(3), reason: '⛔전제');

    // A triangle hanging from each block's conte top band, as a chrome
    // layer mounted a band down the row sees it.
    for (final (index, block) in blocks.indexed) {
      final box = Rect.fromLTWH(block.rect.right - 8, 0, 8, 20);
      final under = grounds.under(box);
      expect(
        under.map((ground) => ground.rect),
        [block.innerTopBand.shift(const Offset(0, -band))],
        reason: 'block $index',
      );
      expect(
        under.single.color,
        [
          layerMarkColor(_conte),
          // No storyboard layer: the plate, at rest.
          conteSheetInk,
          layerMarkColor(LayerMark.none),
        ][index],
        reason: 'block $index',
      );
    }
    expect(
      grounds.under(const Rect.fromLTWH(-40, 0, 8, 20)),
      isEmpty,
      reason: 'nothing under a box before the first block',
    );
  });
}
