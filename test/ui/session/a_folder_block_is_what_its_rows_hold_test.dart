import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show isSyncedAttachedLayer;
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show LayerFolderQueries;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/drags/frame_range_move_drag.dart';
import 'package:anicel/src/ui/session/folder_bands.dart';
import 'package:anicel/src/ui/session/layer_stack.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_block_look.dart'
    show timelineEmptyBlockGrey;
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart'
    show timelineHoldGlyph;

import '../timeline/timeline_frame_geometry_probe.dart';
import '../../helpers/a_folder_made_by_hand.dart';
import '../timeline/tile_store_idle.dart';

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

EditorSessionManager _session(
  List<Layer> layers, {
  List<MediaAsset> pool = const [],
}) {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('f311'),
      name: 'F-311',
      createdAt: DateTime.utc(2026, 10, 7),
      mediaAssets: pool,
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

/// [rows] put in the cut, in one edit, each in place of the row of its id.
void _put(EditorSessionManager s, List<Layer> rows) {
  final byId = {for (final row in rows) row.id: row};
  s.repository.updateProject(
    (project) => project.copyWith(
      tracks: [
        for (final track in project.tracks)
          track.copyWith(
            cuts: [
              for (final cut in track.cuts)
                cut.copyWith(
                  layers: [
                    for (final layer in cut.layers) byId[layer.id] ?? layer,
                  ],
                ),
            ],
          ),
      ],
    ),
  );
}

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

/// The cel [frame] of [layer] as one whose picture data could not be read —
/// the record its making keeps (`a_cel_the_file_does_not_hold_is_red_test`
/// has the making).
void _cannotRead(EditorSessionManager s, String layer, String frame) =>
    s.renderCaches.layerFrameImageCache.unreadable.note(
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        LayerId(layer),
        FrameId(frame),
      ),
    );

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
/// grids ask it — baking its spans in [store] where one is given.
TimelineRowCellsPainter _painter(
  EditorSessionManager s,
  Layer layer, {
  TimelineGridTileStore? store,
  int frames = 40,
}) =>
    TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: frames,
      ),
      tileStore: store,
      substrateGeneration: 'p:cut',
      crossAxisExtent: 28,
      exposureStateForLayer: s.exposureStateForLayer,
      celContent: TimelineCelContentSource(
        hasContent: stackOf(s).celHasContentForLayer,
        cannotRead: stackOf(s).celCannotBeReadForLayer,
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
  setUpAll(openAppGpuEngine);
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
      expect(onFolder.cellModelAt(12).glyph, timelineHoldGlyph);
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
        onFolder.resolvedCellStyleFor(9).border,
        isNot(onFolder.resolvedCellStyleFor(30).border),
        reason: 'CONTROL: a block is drawn — here with no picture yet, over '
            'no ground, as its outline (I-129)',
      );
      expect(onFolder.resolvedCellStyleFor(12).border, Colors.transparent);
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
        reason: 'one block, 0..6: white where a drew, hollow past it',
      );
      expect(
        painter.resolvedCellStyleFor(4).background,
        painter.resolvedCellStyleFor(9).background,
      );
      expect(
        painter.resolvedCellStyleFor(4).border,
        timelineEmptyBlockGrey,
        reason: 'the empty block\'s outline, over no known ground (I-129)',
      );
    });

    // 🗣️F-561 (유저 2026-11-04): 「G행의 프레임쪽보면 중간까지밖에 색이
    // 안칠해져있음. 3 직전까지 색이 있으면 그런 기능인가보다 하겠는데 중간에
    // 걸쳐있으니까 버그인가?」 — the folder's block wore what its first cell
    // in the window showed, so a tile begun past a row's drawn block showed
    // the rest as empty, and one begun on it showed it all as drawn.
    test('🎯the block is LAID grey where the answer is, whatever window '
        'lays it — the edges of its rows\' blocks are its edges too', () {
      final s = _session(_stack());
      _draw(s, 'a', 'a0');
      final painter = _painter(s, _band(s));
      bool covers(Rect rect, int frame) =>
          rect.contains(painter.paperRectFor(frame).center);
      for (final from in [0, 1, 3, 4, 5, 8]) {
        final laid = painter.substrateIn(from, 12);
        for (var frame = from; frame < 12; frame += 1) {
          final style = painter.resolvedCellStyleFor(frame);
          expect(
            [
              for (final piece in laid.paper)
                if (covers(piece.rect, frame)) piece.color,
            ],
            [if (style.background.a > 0) style.background],
            reason: 'the paper at $frame, laid from $from',
          );
          expect(
            [
              for (final ring in laid.rings)
                if (covers(ring.rect, frame)) ring.color,
            ],
            [if (style.border.a > 0) style.border],
            reason: 'the outline at $frame, laid from $from',
          );
        }
      }
    });

    test('a row\'s block that moves inside the folder\'s gives the folder '
        'a row to lay again, though its blocks did not move', () {
      final s = _session(_stack());
      final before = _band(s);
      s.repository.updateProject(
        (project) => project.copyWith(
          tracks: [
            for (final track in project.tracks)
              track.copyWith(
                cuts: [
                  for (final cut in track.cuts)
                    cut.copyWith(
                      layers: [
                        for (final layer in cut.layers)
                          if (layer.id == const LayerId('b'))
                            _row('b', const {2: 1, 3: 3}, inside: 'F')
                          else
                            layer,
                      ],
                    ),
                ],
              ),
          ],
        ),
      );
      final after = _band(s);
      expect(_blocks(after), _blocks(before), reason: '⛔전제: 0..6, 8..10');
      expect(
        identical(after, before),
        isFalse,
        reason: 'b\'s blocks meet at 3 now, where its grey can change',
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

  // 유저 2026-10-16 (frame-picture-indicator-Q1 b): 「a + 그 셀이 있는
  // 타임라인 칸에도 빨간 표시」 — and the band shows what its rows hold.
  group('red is where a row shows a cel that cannot be read', () {
    test('🚨the folder\'s frame is red where a row in it shows one, and '
        'nowhere else; the row itself is red over its block', () {
      final s = _session(_stack());
      _cannotRead(s, 'a', 'a0');
      List<int> redOf(Layer layer) => [
        for (var frame = 0; frame < 12; frame += 1)
          if (stackOf(s).celCannotBeReadForLayer(layer, frame)) frame,
      ];

      expect(
        redOf(_band(s)),
        [0, 1, 2, 3],
        reason: 'a0 stands 0..4 — under b\'s block too, which reads; past it '
            'b alone, and a8 reads',
      );
      expect(redOf(_layer(s, 'a')), [0, 1, 2, 3]);
      expect(redOf(_layer(s, 'b')), isEmpty);
    });

    test('the painter paints the folder\'s block red by that answer', () {
      final s = _session(_stack());
      _draw(s, 'b', 'b2');
      _cannotRead(s, 'a', 'a0');
      final painter = _painter(s, _band(s));

      expect(
        painter.resolvedCellStyleFor(1).background,
        timelineUnreadableCelPaperColor,
      );
      expect(
        painter.resolvedCellStyleFor(5).background,
        isNot(timelineUnreadableCelPaperColor),
        reason: 'the same block past a0 shows b alone, and b reads',
      );
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

      expect(
        s.dragPreview.value,
        isA<BlockMoveDragPreview>(),
        reason: 'the group goes as far as every row can — a step that asks '
            'for more is still a step',
      );
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

    // 🐛folder-band-lags-a-comma-drag (10-27): the band followed a MOVE
    // alone — a comma drag and a file held over a row drew the folder as
    // it stood, and it caught up on the release.
    test('a row\'s comma drag shows on the folder it stands in', () {
      final s = _session(_stack());
      expect(
        s.edgeDrag.beginExposureEdgeDrag(
          layerId: const LayerId('b'),
          blockStartIndex: 2,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );

      s.edgeDrag.updateExposureEdgeDrag(3);

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
        {0: 10},
        reason: 'b ends at 9 under the hand, and meets a\'s 8..10',
      );
      s.edgeDrag.cancelExposureEdgeDrag();
      expect(s.dragPreview.value, isNull);
    });

    test('a file held over a row shows on the folder it stands in', () {
      const path = '/pool/walk_0001.png';
      final s = _session(
        _stack(),
        pool: [
          MediaAsset(
            path: path,
            name: 'walk',
            kind: MediaAssetKind.image,
            frameCount: 4,
          ),
        ],
      );

      s.showMediaPlacement(const LayerId('b'), 12, path);

      expect(
        (s.dragPreview.value as MediaPlacementPreview?)?.silhouette,
        (layerId: const LayerId('b'), startIndex: 12, endIndexExclusive: 16),
        reason: '⛔전제: the four cells it would make on b',
      );
      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
        {0: 6, 8: 2, 12: 4},
        reason: 'the cells the drop would make are what b would hold',
      );
      s.mediaPlacement.clear();
    });

    test('a folder over an edit that left its blocks as they were is read '
        'from its rows as they are now', () {
      final s = _session(_stack());
      final before = _band(s);
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('a'),
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      s.edgeDrag.updateExposureEdgeDrag(-1);
      s.edgeDrag.endExposureEdgeDrag();
      expect(
        [
          _blocks(_layer(s, 'a')),
          _blocks(_band(s)),
          identical(_band(s), before),
        ],
        [
          {0: 3, 8: 2},
          _blocks(before),
          false,
        ],
        reason: '⛔전제: a ends at 3 under b\'s 2..6 — the band\'s blocks as '
            'they were, a row\'s end moved inside them where its grey can '
            'change, so a band of its own (F-561). ↩️The band was kept',
      );

      s.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('b'),
        blockStartIndex: 2,
        edge: TimelineBlockEdge.end,
      );
      s.edgeDrag.updateExposureEdgeDrag(-3);

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
        {0: 3, 8: 2},
        reason: 'b ends at 3 under the hand, over the a that ends at 3 now',
      );
      s.edgeDrag.cancelExposureEdgeDrag();
    });

    // The folder's OWN form in a drag is no band: it holds no block, so
    // the row read as that form alone went blank while its keys moved.
    test('a folder\'s block moved with its own keys shows its rows where '
        'they go, and its keys with them', () {
      final s = _session([
        for (final layer in _stack())
          if (layer.id == _folder)
            layer.copyWith(
              transformTrack: TransformTrack.empty().copyWith(
                position: PropertyTrack<CanvasPoint>.empty().withKey(
                  1,
                  CanvasPoint(x: 5, y: 5),
                ),
              ),
            )
          else
            layer,
      ]);
      s.updateFrameRangeSelectionDrag(
        layerId: _folder,
        anchorIndex: 1,
        headIndex: 1,
        spanRows: const [
          LayerRowAddress(_folder),
          LaneRowAddress(_folder, 'position'),
        ],
      );
      expect(s.rangeMove.beginFrameRangeMoveDrag(_folder), isTrue);

      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 12);

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
        {8: 2, 12: 6},
        reason: 'a\'s 0..4 and b\'s 2..6 went 12 on',
      );
      expect(folder?.transformTrack.position.keys.keys.toList(), [13]);
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('a folder\'s own keys scrubbed leave its row holding what its rows '
        'hold', () {
      final s = _session(_stack());
      s.laneVerbs.previewLayerTransformAtPlayhead(
        _folder,
        (track, frame) => track.withKeyframe(
          frame,
          TransformPose(center: CanvasPoint(x: 12, y: 34)),
        ),
      );
      final scrubbed = (s.dragPreview.value as LaneEditPreview?)?.row;
      expect(scrubbed?.id, _folder, reason: '⛔전제: the scrub is on F');

      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(folder == null ? null : _blocks(folder), {0: 6, 8: 2});
      expect(folder?.transformTrack, scrubbed?.transformTrack);
      s.laneVerbs.endLaneEditPreview();
    });

    group('🐛F-467 (유저 2026-10-25): 「폴더의 블록을 잡고 이동시킬때, 원래 '
        '위치에 블록이 남아있는 버그. 이동끝나면 사라짐」 — a synced attach '
        'row in it is read as its row shows it, by its base', () {
      /// `a` standing 0..4 in F, and its mirror under it.
      (EditorSessionManager, LayerId) mirrored() {
        final s = _session([
          _row('a', const {0: 4}, inside: 'F'),
          _folderRow('F'),
        ]);
        s.selectLayer(const LayerId('a'));
        s.folders.addAttachedLayer(AttachedPlacement.below);
        final mirror = s.activeLayer!;
        expect(
          [isSyncedAttachedLayer(mirror), mirror.folderId, _blocks(mirror)],
          [true, _folder, {0: 4}],
          reason: '⛔전제: a mirror of a, in F, standing where a stands',
        );
        _selectFolderBlockAt(s, 1);
        s.rangeMove.beginFrameRangeMoveDrag(_folder);
        return (s, mirror.id);
      }

      test('the folder\'s block goes where the hand has it, and nowhere '
          'else', () {
        final (s, mirror) = mirrored();

        s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 6);

        final preview = s.dragPreview.value;
        expect(
          _blocks(timelineRowPreviewLayer(preview, _layer(s, mirror.value))!),
          {6: 4},
          reason: 'CONTROL: the mirror\'s own row follows its base',
        );
        expect(
          _blocks(timelineRowPreviewLayer(preview, _band(s))!),
          {6: 4},
          reason: 'read off the mirror where it stood, the folder held the '
              'block at 0..4 too until the release',
        );
        s.rangeMove.endFrameRangeMoveDrag();
        expect(_blocks(_band(s)), {6: 4});
      });

      test('its picture greys and whitens the folder where the mirror goes',
          () {
        final (s, mirror) = mirrored();
        final cel = _layer(s, mirror.value).timeline[0]!.frameId!;
        _draw(s, mirror.value, cel.value);

        s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 6);

        final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s))!;
        bool drawn(int frame) =>
            stackOf(s).celHasContentForLayer(folder, frame);
        expect(
          [drawn(1), drawn(7)],
          [false, true],
          reason: 'the mirror\'s picture rides to 6..10 with it — read where '
              'it stood, the white stayed at 0..4',
        );
        s.rangeMove.cancelFrameRangeMoveDrag();
      });

      // A band kept across an edit stands for its rows as they are now: let
      // go of its base, the mirror stands where it stood as it did, and the
      // band is the one it was — so it must not read the mirror as before.
      test('a mirror let go of its base stays where it stands while the base '
          'is carried', () {
        final s = _session([
          _row('a', const {0: 4}, inside: 'F'),
          _folderRow('F'),
        ]);
        s.selectLayer(const LayerId('a'));
        s.folders.addAttachedLayer(AttachedPlacement.below);
        final mirror = s.activeLayer!.id;
        final band = _band(s);

        s.folders.detachActiveLayer();

        final let = _layer(s, mirror.value);
        expect(
          [isSyncedAttachedLayer(let), let.folderId, _blocks(let)],
          [false, _folder, {0: 4}],
          reason: '⛔전제: let go, in F, standing where it stood',
        );
        expect(identical(_band(s), band), isTrue, reason: '⛔전제: kept');
        _selectFolderBlockAt(s, 1, const LayerId('a'));
        s.rangeMove.beginFrameRangeMoveDrag(const LayerId('a'));
        s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 6);

        expect(
          _blocks(timelineRowPreviewLayer(s.dragPreview.value, _band(s))!),
          {0: 4, 6: 4},
          reason: 'read as the mirror it was, it went with its old base',
        );
        s.rangeMove.cancelFrameRangeMoveDrag();
      });

      test('an organizer holding the mirrors of a row outside it follows that '
          'row\'s drag', () {
        final s = _session([_row('a', const {0: 4})]);
        s.selectLayer(const LayerId('a'));
        s.folders.addAttachedLayer(AttachedPlacement.above);
        groupTheActiveAttachIntoAFolder(s);
        final organizer = s.requireActiveCut.layers.folderLayers.single.id;
        expect(
          [_layer(s, 'a').folderId, _blocks(_band(s, organizer))],
          [null, {0: 4}],
          reason: '⛔전제: a stands outside the organizer its mirror is in',
        );
        s.updateFrameRangeSelectionDrag(
          layerId: const LayerId('a'),
          anchorIndex: 1,
          headIndex: 1,
        );
        s.rangeMove.beginFrameRangeMoveDrag(const LayerId('a'));

        s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 6);

        final shown = timelineRowPreviewLayer(
          s.dragPreview.value,
          _band(s, organizer),
        );
        expect(
          shown == null ? null : _blocks(shown),
          {6: 4},
          reason: 'no row of the organizer\'s own is in the drag\'s hand, so '
              'asked by id the organizer stood still until the release',
        );
        s.rangeMove.cancelFrameRangeMoveDrag();
      });
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

      final preview = s.dragPreview.value;
      expect(
        (preview! as BlockMoveDragPreview).previewLayers.keys,
        [const LayerId('a')],
        reason: 'the drag carries the rows it moves, and no band: a band is '
            'read off its rows where the folder\'s row shows it',
      );
      expect(
        timelineRowPreviewLayer(preview, _band(s)),
        isNotNull,
        reason: '⛔전제: F holds a',
      );
      expect(
        timelineRowPreviewLayer(preview, _band(s, const LayerId('H'))),
        isNull,
        reason: 'a step rebuilds the rows it moves: H holds none of them, '
            'and a band made anew every step would rebuild its row',
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
      final folder = timelineRowPreviewLayer(s.dragPreview.value, _band(s));
      expect(
        folder == null ? null : _blocks(folder),
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

  // 🐛F-561 ② (서피스 실기 2026-11-07): a row's block end dragged 3 → 7
  // under a folder of 1..10, and the folder's row stayed white to 3 — its
  // tiles were kept, for the folder's own blocks had not moved.
  group('a tile of the folder\'s block shows its rows as they are', () {
    final store = TimelineGridTileStore.instance;

    setUp(store.clear);

    tearDown(store.clear);

    // 24px cells: the spans are [0, span) and [span, 2 * span).
    final span = timelineFrameWindowSpanFor(24);

    /// a, a row of [kind]: 0..4 on a0, and [length] cells from `span + 2` on
    /// [cel] — a1 holds the picture, a2 none; b: `span` to `span + 8`, bare.
    /// The folder's blocks are 0..4 and `span` to `span + 8` either way.
    Layer a({
      int length = 4,
      String cel = 'a1',
      LayerKind kind = LayerKind.animation,
    }) => Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: kind,
      folderId: _folder,
      frames: [
        for (final id in ['a0', 'a1', 'a2'])
          Frame(id: FrameId(id), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('a0'), length: 4),
        span + 2: TimelineExposure.drawing(FrameId(cel), length: length),
      },
    );

    EditorSessionManager session({List<Layer> beside = const []}) {
      final s = _session([
        a(),
        _row('b', {span: 8}, inside: 'F'),
        ...beside,
        _folderRow('F'),
      ]);
      _draw(s, 'a', 'a1');
      return s;
    }

    /// The folder's tiles of the two spans, as its row asks them now.
    List<TimelineGridTilePicture?> tiles(EditorSessionManager s) {
      final painter = _painter(s, _band(s), store: store, frames: 2 * span);
      return [
        for (final from in [0, span])
          store.tileFor(
            painter: painter,
            spanStartIndex: from,
            spanEndIndexExclusive: from + span,
            devicePixelRatio: 1,
          ),
      ];
    }

    /// The folder's tiles once both have landed.
    Future<List<TimelineGridTilePicture?>> landed(
      EditorSessionManager s,
    ) async {
      tiles(s);
      await tileStoreIdle(store);
      final both = tiles(s);
      expect(both, everyElement(isNotNull), reason: '⛔전제: baked');
      return both;
    }

    List<Uint8List> pixelsOf(List<TimelineGridTilePicture?> tiles) => [
      for (final tile in tiles)
        tile!.picture.read(),
    ];

    /// Puts the rows [edited] in at once, and holds the folder's tiles to what
    /// a bake from nothing paints of its rows as they are now — the span
    /// before the edit keeping its tile where [keepsTheSpanBefore] (F-244).
    Future<void> expectTheTilesShowTheRowsAsTheyAre(
      EditorSessionManager s,
      List<Layer> edited, {
      bool keepsTheSpanBefore = true,
    }) async {
      final before = await landed(s);
      final paintedBefore = pixelsOf(before);
      final blocks = _blocks(_band(s));

      _put(s, edited);

      expect(_blocks(_band(s)), blocks, reason: '⛔전제: its blocks stayed');
      final after = tiles(s);
      expect(after, everyElement(isNotNull), reason: '⛔전제: shown');
      final shown = pixelsOf(after);
      store.clear();
      final painted = pixelsOf(await landed(s));
      expect(
        listEquals(paintedBefore.last, painted.last),
        isFalse,
        reason: '⛔전제: the grey moved in the paint',
      );
      if (keepsTheSpanBefore) {
        expect(
          identical(after.first, before.first),
          isTrue,
          reason: 'CONTROL: the span before the edit keeps its tile',
        );
      }
      for (final i in [0, 1]) {
        expect(
          listEquals(shown[i], painted[i]),
          isTrue,
          reason: 'the tile of span $i shows the rows as they were',
        );
      }
    }

    test('🚨a row\'s block that ends elsewhere inside the folder\'s', () async {
      await expectTheTilesShowTheRowsAsTheyAre(session(), [a(length: 5)]);
    });

    test('🚨a row\'s block that shows another cel, its edges where they '
        'were', () async {
      await expectTheTilesShowTheRowsAsTheyAre(session(), [a(cel: 'a2')]);
    });

    // A row more is asked from frame 0: the band's rows are paired in order.
    test('🚨a row put in the folder, its block inside the folder\'s', () async {
      final s = session(beside: [_row('c', {span + 6: 2})]);
      _draw(s, 'c', 'c${span + 6}');
      await expectTheTilesShowTheRowsAsTheyAre(
        s,
        [_row('c', {span + 6: 2}, inside: 'F')],
        keepsTheSpanBefore: false,
      );
    });

    // A row of no cels holds no picture, whatever it stands; its kind is
    // asked before its blocks, so the band is asked anew from frame 0.
    test('🚨a row turned to a kind that holds no cels', () async {
      await expectTheTilesShowTheRowsAsTheyAre(
        session(),
        [a(kind: LayerKind.se)],
        keepsTheSpanBefore: false,
      );
    });

    // One row of the folder's taken out and another put in standing as it
    // stood, on cels of the same names: what they hold is the other row's.
    test('🚨a row put in the folder in place of one taken out, standing as '
        'it stood', () async {
      final cel = 'b$span';
      Layer c({String? inside}) => Layer(
        id: const LayerId('c'),
        name: 'c',
        kind: LayerKind.animation,
        folderId: inside == null ? null : LayerId(inside),
        frames: [Frame(id: FrameId(cel), duration: 1, strokes: const [])],
        timeline: {span: TimelineExposure.drawing(FrameId(cel), length: 8)},
      );
      final s = session(beside: [c()]);
      _draw(s, 'c', cel);
      await expectTheTilesShowTheRowsAsTheyAre(
        s,
        [_row('b', {span: 8}), c(inside: 'F')],
        keepsTheSpanBefore: false,
      );
    });
  });
}
