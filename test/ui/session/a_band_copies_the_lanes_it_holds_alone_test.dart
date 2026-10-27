import 'package:flutter_test/flutter_test.dart';

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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️one-band-no-lane-tail-Q3 (유저 2026-10-27): 「그 레이어 자신에게」 — a
/// band's copy takes the keys on the lane rows of a layer whose cells it did
/// not sweep, and the camera row's: 「레인만 든 레이어의 키도 싣고,
/// 붙여넣으면 같은 레이어 · 같은 레인에, 띠 첫 칸에서의 간격 그대로 놓는다(카메라
/// 행이면 서 있는 컷의 카메라)」 — and 「다른 컷에 붙여넣으면 그 레이어가 없어 그
/// 키는 놓이지 않는다」. The cut lifts them with the rest, one undo.
///
/// ↩️The copy took the keys beside the cells it took (Q1), and these stayed
/// behind.
const _a = LayerId('alone-a');
const _b = LayerId('alone-b');
const _c = LayerId('alone-c');
const _camera1 = LayerId('alone-camera-1');
const _camera2 = LayerId('alone-camera-2');
const _s1 = LayerId('alone-s1');
const _cut2 = CutId('alone-cut-2');
const _position = 'position';

/// Position keys at each frame of [keys], holding (x, x) and named as given.
PropertyTrack<CanvasPoint> _keyed(Map<int, (double, String?)> keys) =>
    PropertyTrack<CanvasPoint>(
      keys: {
        for (final MapEntry(key: frame, value: (x, name)) in keys.entries)
          frame: PropertyKey(CanvasPoint(x: x, y: x), name: name),
      },
    );

TransformTrack _moved(Map<int, (double, String?)> keys) =>
    TransformTrack.empty().copyWith(position: _keyed(keys));

/// A row holding one three-frame block of its drawing from frame 0, with
/// the Position keys [keys] — an animation row, or a row of [kind].
Layer _row(
  LayerId id,
  Map<int, (double, String?)> keys, {
  LayerKind kind = LayerKind.animation,
}) => Layer(
  id: id,
  name: id.value,
  kind: kind,
  transformTrack: _moved(keys),
  frames: [
    Frame(
      id: FrameId('${id.value}-f'),
      duration: 3,
      name: 'A1',
      strokes: const [],
    ),
  ],
  timeline: {
    0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 3),
  },
);

Layer _cameraRow(LayerId id) => Layer(
  id: id,
  name: 'Camera',
  kind: LayerKind.camera,
  frames: const [],
);

/// Cut 1: A (its key K at 0) and B (N at 1, and keys at 11 and 20), its
/// camera moved at 1. Cut 2: C alone, its camera still.
EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('alone-project'),
      name: 'Alone',
      createdAt: DateTime.utc(2026, 10, 28),
      tracks: [
        Track(
          id: const TrackId('alone-track'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('alone-cut-1'),
              name: '1',
              duration: 24,
              canvasSize: const CanvasSize(width: 32, height: 32),
              camera: CutCamera.fromTrack(_moved({1: (9, null)})),
              layers: [
                _cameraRow(_camera1),
                _row(_a, {0: (1, 'K')}),
                _row(_b, {1: (7, 'N'), 11: (3, null), 20: (5, null)}),
              ],
            ),
            Cut(
              id: _cut2,
              name: '2',
              duration: 24,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [_cameraRow(_camera2), _row(_c, const {})],
            ),
          ],
          // The track's own row, keyed at global 25 — cut 2's frame 1.
          seLayers: [
            _row(_s1, {25: (4, null)}, kind: LayerKind.se),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

Layer _layer(EditorSessionManager s, LayerId id) =>
    s.layers.firstWhere((layer) => layer.id == id);

/// [track]'s Position keys by frame, each as (x, name).
Map<int, (double, String?)> _keysIn(TransformTrack track) => {
  for (final MapEntry(key: frame, value: key) in track.position.keys.entries)
    frame: (key.value.x, key.name),
};

Map<int, (double, String?)> _keysOf(EditorSessionManager s, LayerId id) =>
    _keysIn(_layer(s, id).transformTrack);

/// The track's own row's Position keys, on the track's axis.
Map<int, (double, String?)> _trackRowKeys(EditorSessionManager s) => _keysIn(
  s.repository.requireProject().tracks.single.seLayers.single.transformTrack,
);

/// [row]'s blocks by start, each its length.
Map<int, int?> _blocksOf(EditorSessionManager s, LayerId id) => {
  for (final MapEntry(key: start, value: block)
      in _layer(s, id).timeline.entries)
    if (!block.ghost && block.frameId != null) start: block.length,
};

/// The band over A's cells and B's Position lane — not B's cells — over
/// [from]..[from] + 5, and the rows [plus].
void _sweep(
  EditorSessionManager s, {
  int from = 0,
  List<TimelineRowAddress> plus = const [],
}) => s.updateFrameRangeSelectionDrag(
  layerId: _a,
  anchorIndex: from,
  headIndex: from + 5,
  spanRows: [
    const LayerRowAddress(_a),
    const LaneRowAddress(_b, _position),
    ...plus,
  ],
);

void main() {
  test('🚨a band over a row\'s cells and ANOTHER row\'s lane copies that '
      'lane\'s keys too — a paste lays them on that row\'s same lane, as far '
      'from where it starts as they were from the band\'s first cell, over '
      'the frames they span, its cells and the keys past them unmoved — one '
      'undo', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweep(s);
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();
    expect(s.clipboard.bankedRowLayerIds, [_a], reason: 'B\'s cells stay');

    s.standOnRow(const LayerRowAddress(_a), frameIndex: 6);
    expect(s.frameRangeSelection.value, isNull, reason: '⛔전제: no band');
    final steps = s.historyManager.undoCount;
    pill.pasteIndependentFrame();

    expect(_blocksOf(s, _a), {0: 3, 6: 3});
    expect(_keysOf(s, _a), {0: (1.0, 'K')}, reason: 'its lane was not swept');
    expect(_keysOf(s, _b), {
      1: (7.0, 'N'),
      7: (7.0, null),
      20: (5.0, null),
    }, reason: 'N at 6 + 1, a value of its own; 11 under it replaced; 20 left');
    expect(_blocksOf(s, _b), {0: 3});
    expect(s.historyManager.undoCount, steps + 1);
    s.undo();
    expect(_blocksOf(s, _a), {0: 3});
    expect(_keysOf(s, _b), {1: (7.0, 'N'), 11: (3.0, null), 20: (5.0, null)});
  });

  test('pasted over a band, they start where the band starts on their '
      'row, not where the cursor stands', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweep(s);
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();

    s.standOnRow(const LayerRowAddress(_a), frameIndex: 15);
    s.updateFrameRangeSelectionDrag(
      layerId: _a,
      anchorIndex: 12,
      headIndex: 8,
      spanRows: const [LayerRowAddress(_a)],
    );
    expect(
      s.currentFrameIndex,
      isNot(8),
      reason: '⛔전제: the cursor is not at the band\'s start',
    );
    pill.pasteIndependentFrame();

    expect(_keysOf(s, _b), {
      1: (7.0, 'N'),
      9: (7.0, null),
      20: (5.0, null),
    });
  });

  test('a track\'s own row keys the track\'s frames: its lane\'s keys go '
      'back where the paste starts on that axis, the cut\'s start and all', () {
    final s = _session();
    s.selectCut(_cut2);
    s.standOnRow(const LayerRowAddress(_c), frameIndex: 0);
    s.updateFrameRangeSelectionDrag(
      layerId: _c,
      anchorIndex: 0,
      headIndex: 5,
      spanRows: const [LayerRowAddress(_c), LaneRowAddress(_s1, _position)],
    );
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();

    s.standOnRow(const LayerRowAddress(_c), frameIndex: 6);
    pill.pasteIndependentFrame();

    expect(_blocksOf(s, _c), {0: 3, 6: 3});
    expect(_trackRowKeys(s), {
      25: (4.0, null),
      31: (4.0, null),
    }, reason: 'cut 2 starts at 24: 24 + 6 + 1');
  });

  test('🚨a 잘라내기 lifts those keys with its cells, from that row\'s '
      'lane, leaving the rest of the row — one undo', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweep(s);
    final pill = TimelineToolbarPanelContext(s);
    final steps = s.historyManager.undoCount;
    pill.cutRun();

    expect(_blocksOf(s, _a), isEmpty);
    expect(_keysOf(s, _a), {0: (1.0, 'K')});
    expect(_keysOf(s, _b), {11: (3.0, null), 20: (5.0, null)});
    expect(_blocksOf(s, _b), {0: 3});
    expect(s.historyManager.undoCount, steps + 1);
    s.undo();
    expect(_keysOf(s, _b), {1: (7.0, 'N'), 11: (3.0, null), 20: (5.0, null)});
  });

  test('🚨a 링크 붙여넣기 keeps their names — and asks first where the row '
      'holds a name at another value; joined, the key takes what the name '
      'holds there', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweep(s);
    TimelineToolbarPanelContext(s).copyFrame();
    // N moves to another value after the copy.
    s.laneVerbs.updateLayerTransformTrack(
      _b,
      _moved({1: (8, 'N'), 11: (3, null), 20: (5, null)}),
    );
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 6);
    final steps = s.historyManager.undoCount;

    final joins = s.clipboard.pasteLinkedAt(s.clipboard.timelinePlace);
    expect(joins, hasLength(1));
    expect(joins!.single.layerId, _b);
    expect(joins.single.held, isEmpty);
    expect(joins.single.keyNames, {'N'});
    expect(_blocksOf(s, _a), {0: 3}, reason: 'nothing yet');
    expect(s.historyManager.undoCount, steps);

    expect(
      s.clipboard.pasteLinkedAt(
        s.clipboard.timelinePlace,
        joinTakenNames: true,
      ),
      isNull,
    );
    expect(_blocksOf(s, _a), {0: 3, 6: 3});
    expect(_keysOf(s, _b), {
      1: (8.0, 'N'),
      7: (8.0, 'N'),
      20: (5.0, null),
    });
    expect(s.historyManager.undoCount, steps + 1);
  });

  test('🚨the camera row\'s keys go to the camera of the cut stood in — and '
      'a row that cut does not hold takes nothing', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweep(s, plus: const [LayerRowAddress(_camera1)]);
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();
    expect(s.clipboard.bankedRowLayerIds, [_a]);

    s.selectCut(_cut2);
    s.standOnRow(const LayerRowAddress(_c), frameIndex: 4);
    final steps = s.historyManager.undoCount;
    pill.pasteIndependentFrame();

    expect(_blocksOf(s, _c), {0: 3, 4: 3});
    expect(
      _keysIn(s.activeCutOrNull!.camera.track),
      {5: (9.0, null)},
      reason: 'cut 2\'s camera, at 4 + 1',
    );
    expect(s.historyManager.undoCount, steps + 1);
    final cut1 = s.repository.requireProject().tracks.single.cuts.first;
    expect(_keysIn(cut1.camera.track), {1: (9.0, null)});
    expect(
      _keysIn(cut1.layers.firstWhere((layer) => layer.id == _b).transformTrack),
      {1: (7.0, 'N'), 11: (3.0, null), 20: (5.0, null)},
      reason: 'B is cut 1\'s — the paste in cut 2 leaves it be',
    );
  });
}
