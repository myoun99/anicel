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
import 'storyboard_cut_block_probe.dart';

/// The cut block is THREE BANDS: a thin one, the strip, a thin one. The
/// strip is the picture and nothing is written over it; the bands carry the
/// writing — the cut's number at the left end of the top one, its length at
/// the right end of the bottom one. That is the conte sheet's CUT and TIME
/// columns, which sit outside the picture cell, turned on their side.
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

/// A storyboard row divided into three panels at 0, 4 and 9.
Layer _dividedStoryboardLayer(String cutId) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
  frames: [
    for (final name in ['a', 'b', 'c'])
      Frame(id: FrameId('$cutId-$name'), duration: 1, strokes: const []),
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

/// Records every paragraph the painter lays down. An OUTLINED glyph is two
/// paragraphs at one offset (outline pass + fill pass); a plain one is a
/// single paragraph — so "two at the same spot" is the outline's
/// fingerprint, and the offset itself is the anchor contract.
class _ParagraphOffsetSpy implements Canvas {
  final List<Offset> offsets = [];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    offsets.add(offset);
  }

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

int _paragraphsAt(List<Offset> offsets, bool Function(Offset) where) =>
    offsets.where(where).length;

void main() {
  testWidgets('the block is three bands, and they tile it exactly', (
    tester,
  ) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.bandsFolded, isFalse);
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

  testWidgets('a short row FOLDS the bands: the strip takes the block and '
      'the writing falls back over the picture', (tester) async {
    await _pump(tester);
    final tall = requireCutBlock(tester, 'cut-1');
    expect(tall.bandsFolded, isFalse);

    // The painter answers for any row height — the fold is its rule, not
    // the panel's.
    final painter = cutBlocksPainter(tester);
    final short = StoryboardCutBlocksPainter(
      entries: painter.entries,
      storyboardLayerNames: painter.storyboardLayerNames,
      storyboardCellsByCut: painter.storyboardCellsByCut,
      geometry: painter.geometry,
      crossAxisExtent: StoryboardCutBlocksPainter.bandsMinBlockHeight - 1,
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

    expect(block.bandsFolded, isTrue);
    expect(block.strip, block.rect);
    expect(block.topBand, Rect.zero);
    expect(block.bottomBand, Rect.zero);
  });

  testWidgets('#15: each panel carries its frame NAME (or ○ unnamed — ● '
      'stays the inbetween mark\'s) and its own comma count — the timeline '
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
        0: TimelineExposure.drawing(const FrameId('cut-1-a'), length: 4),
        4: TimelineExposure.drawing(const FrameId('cut-1-b'), length: 5),
        9: TimelineExposure.drawing(const FrameId('cut-1-c'), length: 3),
      },
    );
    await _pump(tester, storyboardLayer: layer);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cellNames, ['LO', '○', '○']);
    expect(block.cellCommaLabels, ['4', '5', '3']);
  });

  testWidgets('#15: the no-row cut\'s single placeholder panel prints no '
      'writing at all', (tester) async {
    await _pump(tester);
    final block = requireCutBlock(tester, 'cut-1');

    expect(block.cellNames, ['']);
    expect(block.cellCommaLabels, ['']);
  });

  testWidgets('#15: a FOLDED block omits the panel writing at the source — '
      'folding that far means watching the cuts, not the panels', (
    tester,
  ) async {
    await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
    final painter = cutBlocksPainter(tester);
    final short = StoryboardCutBlocksPainter(
      entries: painter.entries,
      storyboardLayerNames: painter.storyboardLayerNames,
      storyboardCellsByCut: painter.storyboardCellsByCut,
      geometry: painter.geometry,
      crossAxisExtent: StoryboardCutBlocksPainter.bandsMinBlockHeight - 1,
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

    expect(block.bandsFolded, isTrue);
    expect(block.cells, hasLength(3), reason: 'the panels themselves stay');
    expect(block.cellNames, isEmpty);
    expect(block.cellCommaLabels, isEmpty);
  });

  group('#15 R3 — the writing anchors (user 2026-07-29)', () {
    testWidgets('a panel\'s frame name sits at its slot\'s TOP-LEFT — the '
        'cut block title\'s anchor — and is OUTLINED: two paragraphs share '
        'the offset', (tester) async {
      await _pump(
        tester,
        storyboardLayer: _dividedStoryboardLayer('cut-1'),
        thumbnailFor: (cut, frame, {tier = StoryboardThumbnailTier.strip}) =>
            null,
      );
      final block = requireCutBlock(tester, 'cut-1');
      final offsets = _paintedParagraphOffsets(tester);

      // Panel b starts at frame 4; 12 px/frame; the name's inset is half
      // the block padding (2) with 1px down — the title corner, not the
      // block-display centre it used to be.
      final expected = Offset(
        block.rect.left + 4 * 12.0 + 2,
        block.strip.top + 1,
      );
      expect(
        _paragraphsAt(offsets, (o) => (o - expected).distance < 0.01),
        greaterThanOrEqualTo(2),
        reason: 'outline pass + fill pass, one anchor',
      );
    });

    testWidgets('the cut TITLE is outlined too — the cells\' one writing '
        'rule on every label, no scrim anywhere', (tester) async {
      await _pump(tester, storyboardLayer: _dividedStoryboardLayer('cut-1'));
      final block = requireCutBlock(tester, 'cut-1');
      final offsets = _paintedParagraphOffsets(tester);

      // The title hangs at the top band's left end (padding 4). Its glyph
      // height floats with the theme — a glyph taller than the band
      // centres a hair ABOVE its top — so the pin is the column plus "two
      // paragraphs, one offset" in the band's neighbourhood over the strip.
      final titleHits = offsets
          .where(
            (o) =>
                (o.dx - (block.rect.left + 4)).abs() < 0.01 &&
                o.dy < block.strip.top,
          )
          .toList();
      expect(titleHits.length, greaterThanOrEqualTo(2));
      expect(
        titleHits.toSet().length,
        lessThan(titleHits.length),
        reason: 'at least one offset carries BOTH passes',
      );
    });
  });
}
