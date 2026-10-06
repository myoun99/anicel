import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/drags/frame_range_move_drag.dart';
import 'package:anicel/src/ui/session/frame_range_move_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// A RIGID GROUP HAS ONE DELTA.
///
/// A frame-range move of several rows slides them 「together … as one rigid
/// group」 (UI-R18 #1), and two things let the group come apart, both
/// measured on 2026-10-07 while the folder's block learned to be dragged
/// (F-311, 유저: 「내부 전체적으로 이동하는 느낌」):
///
///  · every row was planned with the delta the hand asked for and landed
///    where it could. A row stops at contact with a neighbour and takes the
///    seat beyond only once it reaches it, so in the frames between, that
///    row stood still while the others went on;
///  · a step the group could not take dropped the riders of the step before
///    it and kept that step's blocks, so a release there moved the blocks
///    and left the camera's keys.
///
/// The gesture's two halves, named so `tool/mutation_run.dart` runs this
/// file for them.
FrameRangeMoveDragVerbs moveOf(EditorSessionManager s) => s.rangeMove;

/// What a step shows of [id], or null when the step shows nothing of it.
Map<int, int>? shownBlocks(EditorSessionManager s, String id) {
  final preview = s.dragPreview.value;
  final row = preview is BlockMoveDragPreview
      ? preview.previewLayers[LayerId(id)]
      : null;
  return row == null ? null : _blocksOf(row);
}

/// The move's own casting, asked of the drag itself: what the span carries
/// besides its rows — none here, where no folder row is swept.
List<Layer> heldBeside(EditorSessionManager s) => rowsHeldByFolderRowsOf(
  s.frameRangeSelection.value!,
  project: s,
  rangeSelections: s.rangeSelections,
);

Map<int, int> _blocksOf(Layer layer) => {
  for (final entry in layer.timeline.entries)
    if (!entry.value.ghost) entry.key: entry.value.length!,
};

Layer _row(String id, Map<int, int> blocks) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  frames: [
    for (final start in blocks.keys)
      Frame(id: FrameId('$id$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final MapEntry(key: start, value: length) in blocks.entries)
      start: TimelineExposure.drawing(FrameId('$id$start'), length: length),
  },
);

/// Two rows, bottom → top, in a cut of 24 frames:
///
///     b      ·  ·  [b2 ······]  ·  ·  ·  ·         2..6
///     a      [a0 ······]  ·  ·  ·  ·  [a8]         0..4, 8..10
EditorSessionManager _twoRows() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('rigid'),
      name: 'rigid',
      createdAt: DateTime.utc(2026, 10, 7),
      tracks: [
        Track(
          id: const TrackId('rigid-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('rigid-cut'),
              name: 'c1',
              duration: 24,
              canvasSize: const CanvasSize(width: 320, height: 180),
              layers: [
                _row('a', const {0: 4, 8: 2}),
                _row('b', const {2: 4}),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

Map<int, int> _blocks(EditorSessionManager s, String id) =>
    _blocksOf(s.layerById(LayerId(id))!);

/// The default cut with one block at frame 4 of its drawing row and the
/// camera's Position keyed at frame 2 — the session, that row, the camera's.
(EditorSessionManager, LayerId row, LayerId camera) _aBlockAndACameraKey() {
  final base = createDefaultProject();
  final cut = base.tracks.first.cuts.first;
  final empty = CutCamera().track;
  final s = EditorSessionManager(
    initialProject: base.copyWith(
      tracks: [
        base.tracks.first.copyWith(
          cuts: [
            cut.copyWith(
              camera: CutCamera.fromTrack(
                empty.copyWith(
                  position: empty.position.withKey(
                    2,
                    CanvasPoint(x: 10, y: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(s.dispose);
  s.selectFrameIndex(4);
  s.createDrawingAtCurrentFrame();
  return (
    s,
    s.activeLayer!.id,
    s.layers.firstWhere((l) => l.kind == LayerKind.camera).id,
  );
}

/// Sweeps both rows over the blocks under frame 1 and picks them up by a.
void _pickUpBothRows(EditorSessionManager s) {
  s.updateFrameRangeSelectionDrag(
    layerId: const LayerId('a'),
    anchorIndex: 1,
    headIndex: 1,
    headLayerId: const LayerId('b'),
  );
  final span = s.frameRangeSelection.value!;
  expect(
    (span.startIndex, span.endIndexExclusive, span.spanLayerIds.length),
    (0, 6, 2),
    reason: 'the premise: both rows, over a\'s first block and b\'s',
  );
  expect(heldBeside(s), isEmpty);
  expect(moveOf(s).beginFrameRangeMoveDrag(const LayerId('a')), isTrue);
}

void main() {
  test('rows asked to go where one of them cannot stop where that one '
      'stops — all of them, and the outline with them', () {
    final s = _twoRows();
    _pickUpBothRows(s);

    // a's block would stand on its own next one, 8..10: it stops at 4.
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: 5);

    expect(shownBlocks(s, 'a'), {4: 4, 8: 2});
    expect(
      shownBlocks(s, 'b'),
      {6: 4},
      reason: 'b has nothing in its way and went on to 7 — the two rows a '
          'frame apart from how they were picked up',
    );
    final outline = s.frameRangeSelection.value!;
    expect((outline.startIndex, outline.endIndexExclusive), (4, 10));

    moveOf(s).endFrameRangeMoveDrag();
    expect(_blocks(s, 'a'), {4: 4, 8: 2});
    expect(_blocks(s, 'b'), {6: 4});
    final landed = s.frameRangeSelection.value!;
    expect((landed.startIndex, landed.endIndexExclusive), (4, 10));
  });

  test('…and take the seat beyond once every one of them reaches it', () {
    final s = _twoRows();
    _pickUpBothRows(s);

    moveOf(s).updateFrameRangeMoveDrag(frameDelta: 6);
    moveOf(s).endFrameRangeMoveDrag();

    expect(
      _blocks(s, 'a'),
      {4: 2, 6: 4},
      reason: 'a\'s block is past its neighbour, which closed up behind it',
    );
    expect(_blocks(s, 'b'), {8: 4});
  });

  test('a step short of contact is the step asked for', () {
    final s = _twoRows();
    _pickUpBothRows(s);

    moveOf(s).updateFrameRangeMoveDrag(frameDelta: 3);
    moveOf(s).endFrameRangeMoveDrag();

    expect(_blocks(s, 'a'), {3: 4, 8: 2});
    expect(_blocks(s, 'b'), {5: 4});
  });

  test('a group one of whose rows has nowhere to go that way is home, '
      'and shows it', () {
    final s = _twoRows();
    _pickUpBothRows(s);
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: 2);
    expect(shownBlocks(s, 'b'), {4: 4}, reason: 'the premise: a step shown');

    // a's block stands at the head of the axis.
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: -1);

    expect(
      s.dragPreview.value,
      isNull,
      reason: 'the step before stayed on screen, two frames from the hand',
    );
    final outline = s.frameRangeSelection.value!;
    expect((outline.startIndex, outline.endIndexExclusive), (0, 6));
    moveOf(s).endFrameRangeMoveDrag();
    expect(_blocks(s, 'a'), {0: 4, 8: 2});
    expect(_blocks(s, 'b'), {2: 4});
  });

  test('a step the keys riding cannot take leaves the step before it '
      'whole: released there, the blocks AND the keys land', () {
    final (s, row, camera) = _aBlockAndACameraKey();
    List<int> cameraKeys() =>
        s.requireActiveCut.camera.track.position.keys.keys.toList();
    Map<int, int> blocks() => _blocksOf(s.layerById(row)!);
    expect(blocks(), {4: 1}, reason: 'the premise');
    expect(cameraKeys(), [2], reason: 'the premise');

    s.updateFrameRangeSelectionDrag(
      layerId: row,
      anchorIndex: 2,
      headIndex: 4,
      headLayerId: camera,
    );
    expect(moveOf(s).beginFrameRangeMoveDrag(row), isTrue);
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: -2);
    // The key would land in front of the axis; the block has room.
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: -3);
    moveOf(s).endFrameRangeMoveDrag();

    expect(blocks(), {2: 1}, reason: 'the last step the group could take');
    expect(
      cameraKeys(),
      [0],
      reason: 'the held step had dropped the keys\' shift and kept the '
          'block\'s: the block went to 2 and the key stayed at 2',
    );
  });

  test('the keys that rode a row hop die with it: a slide that cannot land '
      'after it commits nothing, not the keys alone', () {
    final (s, row, camera) = _aBlockAndACameraKey();
    // A second row for the block to hop to.
    s.layerStack.addLayer();
    final other = s.activeLayer!.id;
    List<int> cameraKeys() =>
        s.requireActiveCut.camera.track.position.keys.keys.toList();
    Map<int, int> blocks(LayerId id) => _blocksOf(s.layerById(id)!);

    s.updateFrameRangeSelectionDrag(
      layerId: row,
      anchorIndex: 2,
      headIndex: 4,
      headLayerId: camera,
    );
    expect(moveOf(s).beginFrameRangeMoveDrag(row), isTrue);
    // The block hops to the other row, two frames back; the key rides.
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: -2, targetLayerId: other);
    expect(
      shownBlocks(s, other.value),
      {2: 1},
      reason: 'the premise: the hop landed, and the key rode it',
    );
    // Home on its own row, three frames back: the block could, the key
    // would stand in front of the axis. The hop is no longer what the hand
    // asks for, and this step has no landing.
    moveOf(s).updateFrameRangeMoveDrag(frameDelta: -3, targetLayerId: row);
    moveOf(s).endFrameRangeMoveDrag();

    expect(blocks(row), {4: 1});
    expect(blocks(other), isEmpty);
    expect(
      cameraKeys(),
      [2],
      reason: 'a shift left over from the hop lands alone: the key moved '
          'and the block it rode with stayed home',
    );
  });
}
