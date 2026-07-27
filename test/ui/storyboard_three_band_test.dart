import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';
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
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
}
