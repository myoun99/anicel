import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/drags/frame_range_move_drag.dart';
import 'package:anicel/src/ui/session/folder_bands.dart';
import 'package:anicel/src/ui/session/layer_stack.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineGridGroundOver;
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart'
    show timelineHoldDashGlyph;

import '../timeline/timeline_frame_geometry_probe.dart';

/// F-311 (유저 2026-10-06): 「일반 폴더의 블록, 왜 이 경우 일부만 회색인지?
/// 폴더 블록이 그림 없는구간 회색하는건 아이디어 좋다고 하니 개선해서 채용.
/// 그리고 추가로 폴더의 블록 드래그로 이동할 수 있게. 내부 전체적으로
/// 이동하는 느낌. 그리고 지금 성질 홀드로하면 폴더에서 콘티블록마냥 블록 꽉
/// 채워지는데, 그거말고 홀드면 홀드 점선 그대로 사용하도록. 왜냐하면 홀드면
/// 사실 뒤가 빈공간인데 블록 드래그 이동하기 번거로우니까. 그래서 실제
/// 존재하는 블록만 제대로 하고싶은것. 리피트의 고스트프레임도 마찬가지」.
///
/// The collaborators the three halves live in, named so
/// `tool/mutation_run.dart` runs this file for them.
FolderBands bandsOf(EditorSessionManager s) => s.folderBands;
LayerStack stackOf(EditorSessionManager s) => s.layerStack;

/// The move's own casting of a folder row, asked directly.
List<String> heldRowsOf(EditorSessionManager s) => [
  for (final row in rowsHeldByFolderRowsOf(
    s.frameRangeSelection.value!,
    project: s,
    rangeSelections: s.rangeSelections,
  ))
    row.id.value,
];

const _cutId = CutId('f311-cut');
const _canvas = CanvasSize(width: 320, height: 180);
const _folder = LayerId('F');

/// A row named [id] standing the blocks [blocks] — `start: length`, each on
/// a cel of its own named `<id><start>`.
Layer _row(String id, Map<int, int> blocks, {String? inside}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  folderId: inside == null ? null : LayerId(inside),
  frames: [
    for (final start in blocks.keys)
      Frame(id: FrameId('$id$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final MapEntry(key: start, value: length) in blocks.entries)
      start: TimelineExposure.drawing(FrameId('$id$start'), length: length),
  },
);

Layer _folderRow(String id, {String? inside}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.folder,
  folderId: inside == null ? null : LayerId(inside),
  frames: const [],
  timeline: const {},
);

/// The stack this file stands on, bottom → top, in a cut of 24 frames:
///
///     over            ·  ·  ·  ·  ·  ·  ·  ·  ·  ·
///     F ─┬─ b         ·  ·  [b2 ······]  ·  ·  ·  ·     2..6
///        └─ a         [a0 ······]  ·  ·  ·  ·  [a8]     0..4, 8..10
///     under
///
/// so the folder's blocks are 0..6 and 8..10.
List<Layer> _stack({Map<int, int> over = const {}}) => [
  _row('under', const {}),
  _row('a', const {0: 4, 8: 2}, inside: 'F'),
  _row('b', const {2: 4}, inside: 'F'),
  _folderRow('F'),
  _row('over', over),
];

EditorSessionManager _session(List<Layer> layers) {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('f311'),
      name: 'F-311',
      createdAt: DateTime.utc(2026, 10, 7),
      tracks: [
        Track(
          id: const TrackId('f311-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: _cutId,
              name: 'c1',
              duration: 24,
              canvasSize: _canvas,
              layers: layers,
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

Layer _layer(EditorSessionManager s, String id) => s.layerById(LayerId(id))!;

/// The folder's row as the grids are handed it.
Layer _band(EditorSessionManager s, [LayerId id = _folder]) =>
    bandsOf(s).folderBandLayerFor(s.layerById(id)!);

/// `start: length` of every block a row stands — its ghosts left out.
Map<int, int> _blocks(Layer layer) => {
  for (final entry in layer.timeline.entries)
    if (!entry.value.ghost) entry.key: entry.value.length!,
};

/// `start: length` of the ghosts of [mode] a row shows.
Map<int, int> _ghosts(Layer layer, TimelineRunEdgeMode mode) => {
  for (final entry in layer.timeline.entries)
    if (entry.value.ghostOf?.mode == mode) entry.key: entry.value.length!,
};

/// Puts a picture in the cel [frame] of [layer].
void _draw(EditorSessionManager s, String layer, String frame) {
  s.renderCaches.brushFrameStore.storeBakedSurface(
    s.brushFrameKeyForCut(s.requireActiveCut, LayerId(layer), FrameId(frame)),
    BitmapSurface(
      canvasSize: _canvas,
      tileSize: 4,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: 4,
          pixels: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0xFF),
        ),
      },
    ),
  );
}

void _setEdge(
  EditorSessionManager s,
  String layer,
  int blockStart,
  TimelineRunEdgeMode mode,
) => s.rangeMove.setRunEdgeBehavior(
  layerId: LayerId(layer),
  blockStartIndex: blockStart,
  side: TimelineRunEdgeSide.end,
  mode: mode,
  scopeToSelection: false,
);

/// The shared cells painter over [layer], asking the session what the
/// grids ask it.
TimelineRowCellsPainter _painter(EditorSessionManager s, Layer layer) =>
    TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: s.exposureStateForLayer,
      celContent: TimelineCelContentSource(
        hasContent: stackOf(s).celHasContentForLayer,
        revision: stackOf(s).celTintRevision,
      ),
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );

/// Selects the folder's block under [frame] by a press on the folder's row.
void _selectFolderBlockAt(EditorSessionManager s, int frame, [LayerId? id]) =>
    s.updateFrameRangeSelectionDrag(
      layerId: id ?? _folder,
      anchorIndex: frame,
      headIndex: frame,
    );

void main() {
  group('the band is the blocks its rows stand', () {
    test('a ghost is no block of the union: the runs are the blocks, and '
        'the ghosts stand beside them — a hold\'s before a repeat\'s, and '
        'neither where a block stands', () {
      const hold = TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      const repeat = TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.repeat,
      );
      Layer member(String id, Map<int, TimelineExposure> timeline) => Layer(
        id: LayerId(id),
        name: id,
        kind: LayerKind.animation,
        frames: [Frame(id: FrameId(id), duration: 1, strokes: const [])],
        timeline: timeline,
      );
      final members = [
        // A block 0..2, then its hold to 12.
        member('h', {
          0: const TimelineExposure.drawing(FrameId('h'), length: 2),
          2: const TimelineExposure.drawing(
            FrameId('h'),
            length: 10,
            ghostOf: hold,
          ),
        }),
        // A block 4..6 — under the hold above — then its repeats to 16.
        member('r', {
          4: const TimelineExposure.drawing(FrameId('r'), length: 2),
          6: const TimelineExposure.drawing(
            FrameId('r'),
            length: 2,
            ghostOf: repeat,
          ),
          8: const TimelineExposure.drawing(
            FrameId('r'),
            length: 8,
            ghostOf: repeat,
          ),
        }),
      ];

      final runs = folderAggregateRuns(members);
      expect(
        runs,
        [(start: 0, endExclusive: 2), (start: 4, endExclusive: 6)],
        reason: '「실제 존재하는 블록만」 — the hold ran the block to 12 and '
            'the repeats to 16',
      );
      expect(folderGhostRuns(members, runs), [
        (start: 2, endExclusive: 4, mode: TimelineRunEdgeMode.hold),
        (start: 6, endExclusive: 12, mode: TimelineRunEdgeMode.hold),
        (start: 12, endExclusive: 16, mode: TimelineRunEdgeMode.repeat),
      ]);
    });

    test('a hold set on a row draws on the folder as the hold\'s dash, '
        'past the block that ends where the row\'s does', () {
      final s = _session(_stack());
      final resting = _band(s);
      expect(_blocks(resting), {0: 6, 8: 2});

      _setEdge(s, 'a', 8, TimelineRunEdgeMode.hold);

      final band = _band(s);
      expect(
        _blocks(band),
        {0: 6, 8: 2},
        reason: '「홀드면 사실 뒤가 빈공간」 — it filled the folder\'s block '
            'to the end of the cut, 8..24',
      );
      expect(_ghosts(band, TimelineRunEdgeMode.hold), {10: 14});
      expect(
        identical(band, resting),
        isFalse,
        reason: 'the blocks did not move and the band did: a cache keyed on '
            'the blocks alone hands back the band from before the hold',
      );
      expect(bandsOf(s).folderBandRunsOf(_folder), [
        (start: 0, endExclusive: 6),
        (start: 8, endExclusive: 10),
      ]);

      // …and what the shared painter makes of it is what it makes of the
      // row's own hold.
      final onFolder = _painter(s, band);
      final onRow = _painter(s, _layer(s, 'a'));
      expect(onFolder.cellModelAt(12).glyph, timelineHoldDashGlyph);
      expect(onFolder.cellModelAt(12).glyph, onRow.cellModelAt(12).glyph);
      expect(onFolder.cellModelAt(12).ghost, isTrue);
      expect(
        onFolder.resolvedCellStyleFor(12).background,
        onFolder.resolvedCellStyleFor(30).background,
        reason: 'a ghost wears no paper — the cell past the cut is the '
            'empty one it must match',
      );
      expect(onFolder.cellModelAt(9).ghost, isFalse);
      expect(
        onFolder.resolvedCellStyleFor(9).background,
        isNot(onFolder.resolvedCellStyleFor(30).background),
        reason: 'CONTROL: a block does wear paper',
      );
    });

    test('a repeat\'s ghosts are no block either, and stand where no hold '
        'does', () {
      final s = _session(_stack());
      _setEdge(s, 'a', 8, TimelineRunEdgeMode.hold);
      _setEdge(s, 'b', 2, TimelineRunEdgeMode.repeat);
      expect(
        _ghosts(_layer(s, 'b'), TimelineRunEdgeMode.repeat),
        isNotEmpty,
        reason: 'the premise: the row repeats to the end of the cut',
      );

      final band = _band(s);

      expect(_blocks(band), {0: 6, 8: 2}, reason: '「리피트의 고스트프레임도」');
      expect(_ghosts(band, TimelineRunEdgeMode.repeat), {6: 2});
      expect(_ghosts(band, TimelineRunEdgeMode.hold), {10: 14});
      expect(_painter(s, band).cellModelAt(6).ghost, isTrue);
    });

    test('a press on the folder\'s row takes the block, not the hold '
        'behind it', () {
      final s = _session(_stack());
      _setEdge(s, 'a', 8, TimelineRunEdgeMode.hold);

      _selectFolderBlockAt(s, 9);

      final selection = s.frameRangeSelection.value!;
      expect(
        (selection.startIndex, selection.endIndexExclusive),
        (8, 10),
        reason: 'the snap lane is the blocks: it took 8..24',
      );
      expect(selection.spanLayerIds, [_folder]);
    });
  });

  group('grey is where no row holds a picture', () {
    test('a block of one row beside bare cells of another is grey until a '
        'row draws there — it read the bare cells as drawn', () {
      final s = _session(_stack());
      _draw(s, 'a', 'a0');
      final folder = _band(s);
      bool drawn(int frame) => stackOf(s).celHasContentForLayer(folder, frame);

      expect(
        [for (var frame = 0; frame < 4; frame += 1) drawn(frame)],
        everyElement(isTrue),
        reason: 'a holds a picture at 0..4',
      );
      expect(
        [drawn(4), drawn(5)],
        [false, false],
        reason: '「왜 이 경우 일부만 회색인지」 — only b stands a block here '
            'and it is empty; a\'s bare cells answered 「no tint」, which '
            'the union read as a picture',
      );
      expect(
        [drawn(8), drawn(9)],
        [false, false],
        reason: 'a\'s second block is empty and b is bare here',
      );

      _draw(s, 'b', 'b2');
      expect([drawn(4), drawn(5)], [true, true]);
      expect([drawn(8), drawn(9)], [false, false]);
    });

    test('…and a row of its own still wears no tint on a bare cell', () {
      final s = _session(_stack());
      final a = _layer(s, 'a');
      expect(stackOf(s).celHasContentForLayer(a, 6), isTrue);
      expect(stackOf(s).celHasContentForLayer(a, 0), isFalse);
      expect(
        stackOf(s).celHasContentForLayer(
          s.layers.firstWhere((layer) => layer.kind == LayerKind.folder),
          6,
        ),
        isFalse,
        reason: 'no row of the folder stands a block at 6',
      );
    });

    test('the painter greys the folder\'s block by that answer', () {
      final s = _session(_stack());
      _draw(s, 'a', 'a0');
      final painter = _painter(s, _band(s));

      expect(
        painter.resolvedCellStyleFor(4).background,
        isNot(painter.resolvedCellStyleFor(1).background),
        reason: 'one block, 0..6: white where a drew, grey past it',
      );
      expect(
        painter.resolvedCellStyleFor(4).background,
        painter.resolvedCellStyleFor(9).background,
      );
      expect(
        painter.resolvedCellStyleFor(4).background,
        timelineGridGroundOver(
          under: null,
          painted: timelineEmptyCelPaperColor(timelineDrawingHeldColor),
        ),
      );
    });

    test('a folder inside it is no row that drew: what it holds is asked, '
        'the folder\'s own row answers nothing', () {
      final s = _session([
        _row('c', const {1: 2}, inside: 'G'),
        _folderRow('G', inside: 'F'),
        _folderRow('F'),
      ]);
      bool drawn(int frame) =>
          stackOf(s).celHasContentForLayer(_band(s), frame);

      expect(
        [drawn(1), drawn(2)],
        [false, false],
        reason: 'c\'s block is empty — and G, a row of F that holds no cel, '
            'is not a picture',
      );
      _draw(s, 'c', 'c1');
      expect([drawn(1), drawn(2)], [true, true]);
    });
  });

  group('a drag on the folder\'s block carries the rows it holds', () {
    test('the block is picked up by its folder row, and the rows inside '
        'go with it — one undo brings them back', () {
      final s = _session(_stack());
      _selectFolderBlockAt(s, 1);
      expect(heldRowsOf(s), unorderedEquals(['a', 'b']));

      expect(
        s.rangeMove.beginFrameRangeMoveDrag(_folder),
        isTrue,
        reason: '「폴더의 블록 드래그로 이동할 수 있게」 — the folder row '
            'stands no block of its own, and the move found nothing to move',
      );
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(
        _blocks(_layer(s, 'a')),
        {2: 4, 8: 2},
        reason: '「내부 전체적으로 이동하는 느낌」 — what the run 0..6 held '
            'moved; a\'s block at 8 is another run',
      );
      expect(_blocks(_layer(s, 'b')), {4: 4});
      expect(_blocks(_band(s)), {2: 8});
      final landed = s.frameRangeSelection.value!;
      expect((landed.startIndex, landed.endIndexExclusive), (2, 8));
      expect(landed.spanLayerIds, [_folder]);

      s.undo();
      expect(_blocks(_layer(s, 'a')), {0: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {2: 4});
    });

    test('the hand shows it as it goes: the rows, and the folder\'s own '
        'row with its grey', () {
      final s = _session(_stack());
      _draw(s, 'a', 'a0');
      _selectFolderBlockAt(s, 1);
      s.rangeMove.beginFrameRangeMoveDrag(_folder);

      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);

      final preview = s.dragPreview.value;
      expect(preview, isA<BlockMoveDragPreview>());
      final shown = (preview! as BlockMoveDragPreview).previewLayers;
      expect(_blocks(shown[const LayerId('a')]!), {2: 4, 8: 2});
      expect(_blocks(shown[const LayerId('b')]!), {4: 4});
      final folder = timelineRowPreviewLayer(preview, _band(s));
      expect(
        folder,
        isNotNull,
        reason: 'the folder\'s row is the one the hand is on: it stood '
            'still until the release',
      );
      expect(_blocks(folder!), {2: 8});
      expect(
        _blocks(_layer(s, 'a')),
        {0: 4, 8: 2},
        reason: 'CONTROL: nothing is written before the release',
      );
      bool drawn(int frame) => stackOf(s).celHasContentForLayer(folder, frame);
      expect(
        [for (var frame = 2; frame < 10; frame += 1) drawn(frame)],
        [true, true, true, true, false, false, false, false],
        reason: 'a\'s picture rides to 2..6 with its block — read off the '
            'rows where they stood, the white stayed at 0..4',
      );

      s.rangeMove.cancelFrameRangeMoveDrag();
      expect(s.dragPreview.value, isNull);
      expect(_blocks(_layer(s, 'a')), {0: 4, 8: 2});
    });

    test('it stops where its first row stops, as one — and takes the seat '
        'beyond once every row reaches it', () {
      final s = _session(_stack());
      _selectFolderBlockAt(s, 1);
      s.rangeMove.beginFrameRangeMoveDrag(_folder);

      // a's block would stand on its own next one, 8..10: it stops at 4,
      // touching it. b has nothing in its way.
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 5);

      final shown =
          (s.dragPreview.value! as BlockMoveDragPreview).previewLayers;
      expect(_blocks(shown[const LayerId('a')]!), {4: 4, 8: 2});
      expect(
        _blocks(shown[const LayerId('b')]!),
        {6: 4},
        reason: '「내부 전체적으로 이동하는 느낌」 — each row landed where IT '
            'could, so b went on to 7 and the rows came apart by a frame',
      );
      final outline = s.frameRangeSelection.value!;
      expect(
        (outline.startIndex, outline.endIndexExclusive),
        (4, 10),
        reason: 'the outline is where the blocks are, not where the hand is',
      );

      // Six frames along a's block has room past its neighbour: it takes
      // the seat beyond, and the rest go with it.
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 6);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'a')), {4: 2, 6: 4});
      expect(_blocks(_layer(s, 'b')), {8: 4});
    });

    test('a group with nowhere to go that way stays where it started', () {
      final s = _session(_stack());
      _selectFolderBlockAt(s, 1);
      s.rangeMove.beginFrameRangeMoveDrag(_folder);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);

      // a's block stands at the head of the axis: nothing is in front.
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: -1);

      expect(
        s.dragPreview.value,
        isNull,
        reason: 'b could go a frame back and a could not: the group is home, '
            'and the step before must not stay on screen',
      );
      final outline = s.frameRangeSelection.value!;
      expect((outline.startIndex, outline.endIndexExclusive), (0, 6));
      s.rangeMove.endFrameRangeMoveDrag();
      expect(_blocks(_layer(s, 'a')), {0: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {2: 4});
    });

    test('the folder\'s row has no row to go to: a hand that wanders onto '
        'another row still moves along the frames', () {
      final s = _session(_stack());
      _selectFolderBlockAt(s, 1);
      s.rangeMove.beginFrameRangeMoveDrag(_folder);

      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 2,
        targetLayerId: const LayerId('over'),
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'a')), {2: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {4: 4});
      expect(_blocks(_layer(s, 'over')), isEmpty);
    });

    test('a row swept along with its folder is moved once', () {
      final s = _session(_stack());
      s.updateFrameRangeSelectionDrag(
        layerId: _folder,
        anchorIndex: 1,
        headIndex: 1,
        headLayerId: const LayerId('b'),
      );
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        unorderedEquals([_folder, const LayerId('b')]),
        reason: 'the premise: the span covers the folder and b, the row '
            'under it',
      );
      expect(heldRowsOf(s), ['a'], reason: 'b is a row of the span itself');

      s.rangeMove.beginFrameRangeMoveDrag(_folder);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'a')), {2: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {4: 4});
    });

    test('a row outside swept with the folder slides with what it holds', () {
      final s = _session(_stack(over: const {1: 2}));
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('over'),
        anchorIndex: 1,
        headIndex: 1,
        headLayerId: _folder,
      );
      final span = s.frameRangeSelection.value!;
      expect(
        (span.startIndex, span.endIndexExclusive),
        (0, 6),
        reason: 'the premise: the span grew to the folder\'s whole block',
      );

      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('over'));
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'over')), {2: 2});
      expect(_blocks(_layer(s, 'a')), {1: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {3: 4});
    });

    test('a folded folder moves what it holds all the same, and a folder '
        'inside one moves only its own', () {
      final s = _session([
        _row('a', const {0: 4}, inside: 'F'),
        _row('c', const {1: 2}, inside: 'G'),
        _folderRow('G', inside: 'F'),
        _folderRow('F'),
      ]);
      s.folders.toggleLayerCollapsed(_folder);
      expect(_band(s).collapsed, isTrue, reason: 'the premise');

      _selectFolderBlockAt(s, 1, const LayerId('G'));
      expect(heldRowsOf(s), ['c']);
      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('G'));
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
      s.rangeMove.endFrameRangeMoveDrag();
      expect(_blocks(_layer(s, 'c')), {2: 2});
      expect(_blocks(_layer(s, 'a')), {0: 4});

      _selectFolderBlockAt(s, 1);
      s.rangeMove.beginFrameRangeMoveDrag(_folder);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
      s.rangeMove.endFrameRangeMoveDrag();
      expect(_blocks(_layer(s, 'c')), {5: 2});
      expect(_blocks(_layer(s, 'a')), {3: 4});
    });

    test('a hold goes on holding from where its block was put', () {
      final s = _session(_stack());
      _setEdge(s, 'a', 8, TimelineRunEdgeMode.hold);
      _selectFolderBlockAt(s, 9);

      s.rangeMove.beginFrameRangeMoveDrag(_folder);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
      final shown = timelineRowPreviewLayer(s.dragPreview.value, _band(s))!;
      expect(_blocks(shown), {0: 6, 11: 2});
      expect(_ghosts(shown, TimelineRunEdgeMode.hold), {13: 11});
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'a')), {0: 4, 11: 2});
      expect(_ghosts(_layer(s, 'a'), TimelineRunEdgeMode.hold), {13: 11});
      expect(_ghosts(_band(s), TimelineRunEdgeMode.hold), {13: 11});
    });

    test('a folder row over cells no row stands a block in moves nothing', () {
      final s = _session(_stack());
      s.updateFrameRangeSelectionDrag(
        layerId: _folder,
        anchorIndex: 14,
        headIndex: 16,
      );
      expect(s.frameRangeSelection.value, isNotNull, reason: 'the premise');
      expect(heldRowsOf(s), isEmpty);
      expect(s.rangeMove.beginFrameRangeMoveDrag(_folder), isFalse);
    });

    test('a row\'s own drag shows on the folder it stands in', () {
      final s = _session(_stack());
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('b'),
        anchorIndex: 3,
        headIndex: 3,
      );
      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('b'));

      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 9);

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
        {0: 4, 8: 2, 11: 4},
        reason: 'b went to 11..15, and the folder shows what its rows hold',
      );
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('…and on no folder whose rows stand still', () {
      final s = _session([
        _row('a', const {0: 4}, inside: 'F'),
        _folderRow('F'),
        _row('h', const {0: 4}, inside: 'H'),
        _folderRow('H'),
      ]);
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('a'),
        anchorIndex: 1,
        headIndex: 1,
      );
      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('a'));

      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);

      final shown =
          (s.dragPreview.value! as BlockMoveDragPreview).previewLayers;
      expect(
        shown.keys,
        unorderedEquals([const LayerId('a'), _folder]),
        reason: 'a step rebuilds the rows it moves: H holds none of them, '
            'and a band handed to it every step would rebuild its row',
      );
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('a hop to another row shows on the folder the rows stand in', () {
      final s = _session(_stack());
      // b and a, the two rows under the folder's own.
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('b'),
        anchorIndex: 3,
        headIndex: 3,
        headLayerId: const LayerId('a'),
      );
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        unorderedEquals([const LayerId('a'), const LayerId('b')]),
        reason: 'the premise',
      );
      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('b'));

      // One row down: b's block onto a's row, a's onto the row under it.
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: const LayerId('a'),
      );

      final shown =
          (s.dragPreview.value! as BlockMoveDragPreview).previewLayers;
      expect(_blocks(shown[const LayerId('under')]!), {0: 4}, reason: 'a\'s');
      expect(_blocks(shown[const LayerId('a')]!), {2: 4, 8: 2}, reason: 'b\'s');
      expect(
        shown[_folder] == null ? null : _blocks(shown[_folder]!),
        {2: 4, 8: 2},
        reason: 'a\'s block left the folder: its band is what stays in it',
      );
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('a direction row carried to another shows on the folder they '
        'stand in', () {
      Layer direction(String id, Map<int, InstructionEvent> spans) => Layer(
        id: LayerId(id),
        name: id,
        kind: LayerKind.instruction,
        folderId: _folder,
        frames: const [],
        timeline: const {},
        instructions: spans,
      );
      final s = _session([
        direction('d2', const {}),
        direction('d1', const {
          1: InstructionEvent(instructionId: 'pan', length: 2),
        }),
        _folderRow('F'),
      ]);
      expect(
        _blocks(_band(s)),
        {1: 2},
        reason: 'the premise: a span is a block',
      );
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('d1'),
        anchorIndex: 1,
        headIndex: 2,
      );
      expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);

      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 2,
        targetLayerId: const LayerId('d2'),
      );

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(folder == null ? null : _blocks(folder), {3: 2});
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('a row hop the rows riding cannot go the frames of does not '
        'happen: the folder\'s rows go as far as the hop or not at all', () {
      final s = _session([
        ..._stack(over: const {1: 2}),
        _row('top', const {}),
      ]);
      s.updateFrameRangeSelectionDrag(
        layerId: const LayerId('over'),
        anchorIndex: 1,
        headIndex: 1,
        headLayerId: _folder,
      );
      expect(heldRowsOf(s), unorderedEquals(['a', 'b']), reason: 'the premise');
      s.rangeMove.beginFrameRangeMoveDrag(const LayerId('over'));

      // Up a row and five frames along: over's block can; a's stops at 4.
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 5,
        targetLayerId: const LayerId('top'),
      );
      expect(
        s.dragPreview.value,
        isNull,
        reason: 'a rider that lands short of the hop tears the group: the '
            'step has no landing, and the first step leaves nothing shown',
      );

      // Four frames along every row can go.
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 4,
        targetLayerId: const LayerId('top'),
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(_blocks(_layer(s, 'top')), {5: 2});
      expect(_blocks(_layer(s, 'over')), isEmpty);
      expect(_blocks(_layer(s, 'a')), {4: 4, 8: 2});
      expect(_blocks(_layer(s, 'b')), {6: 4});
    });
  });
}
