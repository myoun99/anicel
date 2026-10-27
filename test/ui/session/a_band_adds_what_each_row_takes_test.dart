import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️ONE BAND (유저 2026-10-25, conte-sweep-leaves-the-lanes-out-Q1: 「띠
/// 하나로 — 레인 선택을 따로 세우지 않는다(타임라인도)」), on the ＋: a band
/// swept from a row's cells into its own lanes fills the cells' gaps AND keys
/// the lanes it swept, in one undo — 08-12's 「선택 객체 하나가 종류 섞인
/// 행들을 담고, 각 동사가 행 종류별로 알아서 처리」.
///
/// 🧪Measured on master (2026-10-27, a real mouse on the rail): ↩️the sweep
/// stood a lane selection beside the band, and ＋ keyed that alone — the
/// band's gap stayed empty.
const _a = LayerId('add-a');
const _s1 = LayerId('add-s1');

/// A row holding one three-frame block from frame 0, and a Position key at 0.
Layer _row(LayerId id, {LayerKind kind = LayerKind.animation}) => Layer(
  id: id,
  name: id.value,
  kind: kind,
  transformTrack: TransformTrack.empty().copyWith(
    position: PropertyTrack<CanvasPoint>.empty().withKey(
      0,
      CanvasPoint(x: 1, y: 1),
    ),
  ),
  frames: [
    Frame(
      id: FrameId('${id.value}-f'),
      duration: 3,
      name: '',
      strokes: const [],
    ),
  ],
  timeline: {
    0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 3),
  },
);

EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('add-project'),
      name: 'Add',
      createdAt: DateTime.utc(2026, 10, 27),
      tracks: [
        Track(
          id: const TrackId('add-track'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('add-cut'),
              name: '1',
              duration: 12,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [_row(_a)],
            ),
          ],
          seLayers: [_row(_s1, kind: LayerKind.se)],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

Layer _cutRow(EditorSessionManager session) =>
    session.layers.firstWhere((layer) => layer.id == _a);

Layer _seRow(EditorSessionManager session) => session.repository
    .requireProject()
    .tracks
    .single
    .seLayers
    .firstWhere((layer) => layer.id == _s1);

List<int> _positionKeys(Layer layer) =>
    layer.transformTrack.position.keys.keys.toList()..sort();

List<int> _starts(Layer layer) => layer.timeline.keys.toList()..sort();

void main() {
  test('a band over a row and its Position lane fills the row\'s gap and '
      'keys the lane — one undo', () {
    final session = _session();
    session.updateFrameRangeSelectionDrag(
      layerId: _a,
      anchorIndex: 0,
      headIndex: 5,
      spanRows: const [
        LayerRowAddress(_a),
        LaneRowAddress(_a, 'anchor-point'),
        LaneRowAddress(_a, 'position'),
      ],
    );
    expect(session.cellInstances.canCreateInstanceForSelection, isTrue);

    session.cellInstances.createInstancesForSelection();

    expect(_starts(_cutRow(session)), [0, 3], reason: 'the gap 3..5 filled');
    expect(
      _positionKeys(_cutRow(session)),
      [0, 1, 2, 3, 4, 5],
      reason: 'every unkeyed frame of the band, on the lane it swept',
    );
    expect(
      _cutRow(session).transformTrack.anchorPoint.keys.keys,
      hasLength(6),
      reason: 'and on every lane it swept',
    );

    session.historyManager.undo();
    expect(_starts(_cutRow(session)), [0], reason: 'one press, one undo');
    expect(_positionKeys(_cutRow(session)), [0]);
  });

  test('the storyboard\'s band: an S row and its Position lane — its gap '
      'gets an entry and the lane its keys, in one undo', () {
    final session = _session();
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _s1,
      anchorGlobalFrame: 0,
      headGlobalFrame: 5,
      anchorRow: const LayerRowAddress(_s1),
      spanRows: const [LayerRowAddress(_s1), LaneRowAddress(_s1, 'position')],
    );
    expect(session.cellInstances.canCreateInstanceForSelection, isTrue);

    session.cellInstances.createInstancesForSelection();

    expect(_starts(_seRow(session)), [0, 3]);
    expect(_positionKeys(_seRow(session)), [0, 1, 2, 3, 4, 5]);

    session.historyManager.undo();
    expect(_starts(_seRow(session)), [0]);
    expect(_positionKeys(_seRow(session)), [0]);
  });

  test('a storyboard band over an S row alone fills its gap — no lane '
      'needed', () {
    final session = _session();
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _s1,
      anchorGlobalFrame: 0,
      headGlobalFrame: 5,
      anchorRow: const LayerRowAddress(_s1),
      spanRows: const [LayerRowAddress(_s1)],
    );
    expect(session.cellInstances.canCreateInstanceForSelection, isTrue);

    session.cellInstances.createInstancesForSelection();

    expect(_starts(_seRow(session)), [0, 3]);
    expect(_positionKeys(_seRow(session)), [0], reason: 'no lane was swept');
  });

  test('a storyboard band over a full S row, no lane swept, has nothing to '
      'make — the ＋ is dark', () {
    final session = _session();
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _s1,
      anchorGlobalFrame: 0,
      headGlobalFrame: 2,
      anchorRow: const LayerRowAddress(_s1),
      spanRows: const [LayerRowAddress(_s1)],
    );

    expect(session.cellInstances.canCreateInstanceForSelection, isFalse);
  });

  test('a storyboard band whose S row has no gap still keys its lane — the '
      'lane alone is something to make', () {
    final session = _session();
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _s1,
      anchorGlobalFrame: 0,
      headGlobalFrame: 2,
      anchorRow: const LayerRowAddress(_s1),
      spanRows: const [LayerRowAddress(_s1), LaneRowAddress(_s1, 'position')],
    );
    expect(session.cellInstances.canCreateInstanceForSelection, isTrue);

    session.cellInstances.createInstancesForSelection();

    expect(_starts(_seRow(session)), [0], reason: 'the block fills 0..2');
    expect(_positionKeys(_seRow(session)), [0, 1, 2]);
  });
}
