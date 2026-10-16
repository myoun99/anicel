import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter_test/flutter_test.dart';

/// **I-89-Q23 — a cut not stood in is edited where it is.**
///
/// 🗣️유저 2026-10-16: 「강제로 서있게해서 고치는건 유저에게 선택지가
/// 제공안되는거라 불편함 … 안서고 고친다는게 이번에 처음 생기니
/// 다른곳에서도 쓸수있으니 제대로 모듈/법통일」. A lane verb handed a row of a
/// cut the session does not stand in reads and writes it in THAT cut — its
/// canvas, its camera, the frames it is drawn for — and leaves the session
/// standing where it stood.
///
/// Cuts a [0, 24) on a 640×360 canvas and b [24, 54) on 800×600, each with
/// a cel row and a camera row; the session stands in a.
void main() {
  Cut cut(String id, int duration, CanvasSize canvas) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: canvas,
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  EditorSessionManager standingInA() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('not-stood-in'),
        name: 'Not stood in',
        createdAt: DateTime.utc(2026, 10, 16),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              cut('a', 24, const CanvasSize(width: 640, height: 360)),
              cut('b', 30, const CanvasSize(width: 800, height: 600)),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    expect(session.activeCutId, const CutId('a'), reason: '⛔전제');
    return session;
  }

  Cut cutOf(EditorSessionManager session, String id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == CutId(id));

  Layer celOf(EditorSessionManager session, String id) => cutOf(
    session,
    id,
  ).layers.firstWhere((layer) => layer.id == LayerId('$id-cel'));

  test('a key made on a row of a cut not stood in is that row\'s, frozen in '
      'its own canvas — one undo, and the session stays where it stood', () {
    final session = standingInA();

    session.laneVerbs.toggleLaneKeyAt(
      const LayerId('b-cel'),
      'position',
      3,
      frameIsGlobal: false,
      description: 'key',
    );

    expect(
      celOf(session, 'b').transformTrack.position.keyAt(3)?.value,
      CanvasPoint(x: 400, y: 300),
      reason: 'the middle of b\'s canvas, not of the one stood in',
    );
    expect(celOf(session, 'a').transformTrack.position.keys, isEmpty);
    expect(session.activeCutId, const CutId('a'));

    session.undo();
    expect(celOf(session, 'b').transformTrack.position.keys, isEmpty);
  });

  test('a camera key is made on the camera of a cut not stood in, frozen at '
      'where that camera stands — on a frame that cut is drawn for, and the '
      'one stood in is not', () {
    final session = standingInA();
    const lane = TimelineLaneSelection(
      layerId: LayerId('b-cam'),
      laneId: 'position',
      startIndex: 27,
      endIndexExclusive: 28,
    );

    expect(session.laneVerbs.canCreateLaneKeysFor(lane), isTrue);
    session.laneVerbs.toggleLaneKeyAt(
      lane.layerId,
      lane.laneId,
      27,
      frameIsGlobal: false,
      description: 'key',
    );

    expect(
      cutOf(session, 'b').camera.track.position.keyAt(27)?.value,
      CanvasPoint(x: 400, y: 300),
      reason: 'b\'s camera at rest frames b\'s canvas',
    );
    expect(cutOf(session, 'a').camera.track.position.keys, isEmpty);
    expect(session.activeCutId, const CutId('a'));
  });

  test('a row of a cut not stood in is reset to the middle of its own '
      'canvas', () {
    final session = standingInA();
    session.laneVerbs.updateLayerTransformTrack(
      const LayerId('b-cel'),
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 10, y: 10),
        ),
      ),
    );

    expect(
      session.laneVerbs.resetLaneGroup(
        const LayerId('b-cel'),
        transformGroupHeaderLane.laneId,
      ),
      isTrue,
    );
    expect(
      celOf(session, 'b').transformTrack.position.keyAt(0)?.value,
      CanvasPoint(x: 400, y: 300),
    );
  });
}
