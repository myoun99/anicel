import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver, StoryboardThumbnailTier;
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/inbetween_mark_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_marker.dart'
    show timelineCellWritesNothing;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineTextOnColor;
import 'storyboard_cut_block_probe.dart';

/// The cut block is THREE BANDS: a thin one, the strip, a thin one. The
/// strip is the picture and nothing is written over it; the bands carry the
/// writing — the cut's number at the left end of the top one, its length at
/// the right end of the bottom one (the conte sheet's CUT and TIME columns,
/// which sit outside the picture cell, turned on their side), and each
/// panel's name and comma count beside them (유저 2026-09-25).
const _trackId = TrackId('band-track');

Cut _cut(String id, int duration, {Layer? storyboardLayer}) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
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
/// none, and wear the in-between mark.
Layer _dividedStoryboardLayer(String cutId, {bool named = false}) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
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

Project _project({Layer? storyboardLayer}) => Project(
  id: const ProjectId('band-project'),
  name: 'Bands',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 12, storyboardLayer: storyboardLayer)],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  Layer? storyboardLayer,
  double pixelsPerFrame = 12,
  StoryboardThumbnailResolver? thumbnailFor,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoryboardPanel(
          project: _project(storyboardLayer: storyboardLayer),
          activeCutId: const CutId('cut-1'),
          pixelsPerFrame: pixelsPerFrame,
          thumbnailFor: thumbnailFor,
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

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Offset> _paintedParagraphOffsets(WidgetTester tester) {
  final spy = _ParagraphOffsetSpy();
  cutBlocksPainter(tester).paint(
    spy,
    tester.getSize(
      find.byKey(const ValueKey<String>('storyboard-cut-blocks-band-track')),
    ),
  );
  return spy.offsets;
}

void main() {
  testWidgets('the block is three bands, and they tile it exactly', (
    tester,
  ) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.topBand.top, block.rect.top);
    expect(block.strip.top, block.topBand.bottom);
    expect(block.bottomBand.top, block.strip.bottom);
    expect(block.bottomBand.bottom, block.rect.bottom);
    // The bands are thin; the strip keeps the rest.
    expect(block.strip.height, greaterThan(block.topBand.height));
  });

  testWidgets('the strip fills the block edge to edge — x IS the frame '
      'axis, so a horizontal inset would break the alignment with the '
      'ruler and the S rows', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.strip.left, block.rect.left);
    expect(block.strip.right, block.rect.right);
    expect(block.topBand.width, block.rect.width);
    expect(block.bottomBand.width, block.rect.width);
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
      activeCutId: painter.activeCutId,
      selectedRange: painter.selectedRange,
      rowAddress: painter.rowAddress,
      hoveredCutId: painter.hoveredCutId,
      colorScheme: painter.colorScheme,
      brightness: painter.brightness,
      baseTextStyle: painter.baseTextStyle,
      showSeconds: painter.showSeconds,
      countingBase: painter.countingBase,
    );
    final block = short.blocks().single;

    const band = StoryboardCutBlocksPainter.bandHeight;
    expect(block.topBand.height, band);
    expect(block.bottomBand.height, band);
    expect(block.strip.top, block.topBand.bottom);
    expect(block.strip.height, floor - band * 2);
    expect(
      block.cellHeads,
      hasLength(3),
      reason: '↩️under 44px the bands folded and the panel writing went',
    );
    expect(block.cellCommaLabels, ['4', '5', '3']);
  });

  testWidgets('#15: each panel carries its frame NAME (or the in-between '
      'mark when unnamed — F-149) and its own comma count — the timeline '
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
      (word: '', mark: unnamedDrawingMark),
      (word: '', mark: unnamedDrawingMark),
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
    // 「띠로 옮긴다 — 이름은 윗 띠, 코마는 아랫 띠」. ↩️D29-2 carried them
    // over the picture on plates of the band's fill, and the plates covered
    // the pictures. 24 px a frame: the test face prints a letter as wide as
    // its type, so a narrower panel would sit under the cut's title.
    const cell = 24.0;

    Future<(StoryboardCutBlockVisual, _ParagraphOffsetSpy)> painted(
      WidgetTester tester, {
      required bool named,
    }) async {
      await _pump(
        tester,
        storyboardLayer: _dividedStoryboardLayer('cut-1', named: named),
        pixelsPerFrame: cell,
        thumbnailFor: (cut, frame, {tier = StoryboardThumbnailTier.strip}) =>
            null,
      );
      final spy = _ParagraphOffsetSpy();
      cutBlocksPainter(tester).paint(
        spy,
        tester.getSize(
          find.byKey(
            const ValueKey<String>('storyboard-cut-blocks-band-track'),
          ),
        ),
      );
      return (requireCutBlock(tester, 'cut-1'), spy);
    }

    List<Rect> wordsIn(Rect band, _ParagraphOffsetSpy spy) =>
        spy.rects.where((rect) => band.contains(rect.center)).toList()
          ..sort((a, b) => a.left.compareTo(b.left));

    testWidgets('a panel\'s name stands in the TOP band from the panel\'s '
        'left — the cut title\'s anchor — the first one after the title, and '
        'nothing is written over the picture', (tester) async {
      final (block, spy) = await painted(tester, named: true);
      final top = wordsIn(block.topBand, spy);

      expect(top, hasLength(4), reason: 'the title, then a, b and c');
      final [title, a, b, c] = top;
      expect(title.left, closeTo(block.rect.left + 4, 0.01));
      expect(
        a.left,
        greaterThanOrEqualTo(title.right + 4 - 0.01),
        reason: 'the band is shared: panel a\'s name stands after the title',
      );
      // Panels b and c start at frames 4 and 9; the band's word inset is 4.
      expect(b.left, closeTo(block.rect.left + 4 * cell + 4, 0.01));
      expect(c.left, closeTo(block.rect.left + 9 * cell + 4, 0.01));
      expect(
        wordsIn(block.strip, spy),
        isEmpty,
        reason: '🗣️nothing rides the picture',
      );
    });

    testWidgets('a panel\'s comma count stands in the BOTTOM band under the '
        'panel\'s last cell, and the last one ends before the cut\'s length',
        (tester) async {
      final (block, spy) = await painted(tester, named: true);
      final bottom = wordsIn(block.bottomBand, spy);

      expect(bottom, hasLength(4), reason: '4, 5 and 3, then the length');
      final [a, b, c, length] = bottom;
      expect(length.right, closeTo(block.rect.right - 4, 0.01));
      // F-96: centred on the panel's last cell while it fits.
      expect(a.center.dx, closeTo(block.rect.left + 3.5 * cell, 0.01));
      expect(b.center.dx, closeTo(block.rect.left + 8.5 * cell, 0.01));
      expect(
        c.right,
        lessThanOrEqualTo(length.left - 4 + 0.01),
        reason: 'the band is shared: the last comma ends before the length',
      );
    });

    testWidgets('🗣️a panel whose drawing has no cel number wears the '
        'in-between mark where its name would stand — DRAWN, the timeline\'s '
        'mark, on the band itself (유저 2026-09-24: 「같은취급으로 통일」)', (
      tester,
    ) async {
      final (block, spy) = await painted(tester, named: false);
      final painter = cutBlocksPainter(tester);
      final panelB = block.rect.left + 4 * cell;

      expect(
        wordsIn(block.topBand, spy),
        hasLength(1),
        reason: 'the title only — no glyph stands in for the mark',
      );
      final mark = spy.circles.singleWhere(
        (circle) =>
            circle.center.dx > panelB && circle.center.dx < 9 * cell,
      );
      expect(mark.center.dy, closeTo(block.topBand.center.dy, 0.01));
      expect(mark.center.dx - panelB, lessThan(4 + 13 + 0.01));
      expect(
        mark.radius,
        timelineInbetweenMarkRadius(
          11,
          cellExtent: 5 * cell,
          crossExtent: StoryboardCutBlocksPainter.bandHeight,
        ),
        reason: 'the timeline\'s mark at the band\'s type, fitted to its room',
      );
      expect(
        mark.color,
        timelineTextOnColor(
          storyboardCarriedWritingGround(block, painter.colorScheme),
        ),
        reason: 'the ground law resolves the mark as it resolves a name',
      );
      expect(
        spy.plates.where(
          (plate) =>
              plate.rect.contains(mark.center) &&
              // A plate was a word's own size; the block's outline and the
              // panels' silhouettes are the row's.
              plate.rect.height <= StoryboardCutBlocksPainter.bandHeight + 4,
        ),
        isEmpty,
        reason: '↩️D29-2\'s plate is gone — the band is the ground',
      );
    });

    testWidgets('the cut TITLE follows the ground law too — the cells\' one '
        'writing rule on every label, no scrim anywhere', (tester) async {
      await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
      final block = requireCutBlock(tester, 'cut-1');
      final offsets = _paintedParagraphOffsets(tester);

      // The title hangs at the top band's left end (padding 4). Its glyph
      // height floats with the theme — a glyph taller than the band
      // centres a hair ABOVE its top — so the pin is the column plus "one
      // paragraph, one offset" in the band's neighbourhood over the strip.
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
    final spy = _ParagraphOffsetSpy();
    cutBlocksPainter(tester).paint(
      spy,
      tester.getSize(
        find.byKey(const ValueKey<String>('storyboard-cut-blocks-band-track')),
      ),
    );
    final band = block.topBand;
    final title = spy.rects
        .where(
          (rect) =>
              (rect.left - (band.left + 4)).abs() < 0.01 &&
              rect.center.dy < block.strip.top,
        )
        .toList();
    expect(title, hasLength(1), reason: 'the title is painted');
    expect(
      title.single.right,
      lessThanOrEqualTo(band.right - 4 + 0.01),
      reason: 'narrowed into its band — ↩️an ellipsis cut its end, and its '
          'paragraph still measured the whole name',
    );
  });
}
