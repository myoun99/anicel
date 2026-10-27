import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;
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
/// a cel row and a camera row; the session stands in a. [linkedCels], when
/// given, are the two cels — 겸용, one link group.
void main() {
  Cut cut(
    String id,
    int duration,
    CanvasSize canvas, {
    CutCamera? camera,
    Layer? cel,
  }) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: canvas,
    camera: camera,
    layers: [
      cel ?? Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  LayerLinkMember celOfCut(String id) => LayerLinkMember(
    trackId: const TrackId('t1'),
    cutId: CutId(id),
    layerId: LayerId('$id-cel'),
  );

  EditorSessionManager standingInA({
    CutCamera? bCamera,
    ({Layer a, Layer b})? linkedCels,
  }) {
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
              cut(
                'a',
                24,
                const CanvasSize(width: 640, height: 360),
                cel: linkedCels?.a,
              ),
              cut(
                'b',
                30,
                const CanvasSize(width: 800, height: 600),
                camera: bCamera,
                cel: linkedCels?.b,
              ),
            ],
          ),
        ],
        linkRegistry: linkedCels == null
            ? null
            : LayerLinkRegistry(
                groups: [
                  LayerLinkGroup(
                    id: 'cels',
                    members: [celOfCut('a'), celOfCut('b')],
                  ),
                ],
              ),
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

  /// Cut [id]'s cel row holding [transform] and [effects].
  Layer celHolding(
    String id, {
    TransformTrack? transform,
    List<LayerEffect> effects = const [],
  }) => Layer(
    id: LayerId('$id-cel'),
    name: 'A',
    frames: const [],
    transformTrack: transform,
    effects: effects,
  );

  /// A position key at frame 0 holding [value], named [name].
  TransformTrack positionAt0(CanvasPoint value, {String? name}) =>
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty()
            .withKey(0, value)
            .withKeyName(0, name),
      );

  /// A blur whose blurX has a key at frame 0 holding [value], named [name]
  /// — the same effect on either cel, as a link group's chain is.
  List<LayerEffect> blurXAt0(double value, {String? name}) => [
    LayerEffect(
      id: const EffectId('fx'),
      kind: EffectKind.blur,
      parameters: {
        'blurriness': EffectParameter(
          track: PropertyTrack<double>.empty()
              .withKey(0, value)
              .withKeyName(0, name),
        ),
      },
    ),
  ];

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

  test('what a camera write to a cut not stood in is held to is THAT cut\'s '
      'camera — a key it already holds past its frames does not stop it', () {
    // A file can bring a camera key in past its cut's frames
    // (cameraWriteKeepsKeysIn): b's at 40, past its 30. a's camera holds
    // none, so read against a's, the key at 40 would be a new one put out.
    final session = standingInA(
      bCamera: CutCamera(
        keyframes: {40: CameraPose(center: CanvasPoint(x: 400, y: 300))},
      ),
    );

    session.laneVerbs.toggleLaneKeyAt(
      const LayerId('b-cam'),
      'position',
      27,
      frameIsGlobal: false,
      description: 'key',
    );

    expect(
      cutOf(session, 'b').camera.track.position.keyAt(27),
      isNotNull,
      reason: 'the key past b\'s end was b\'s already',
    );
  });

  test('a write to a row of a cut not stood in reaches its 겸용 sibling by '
      'the names it moved — the link group of the cut holding it', () {
    final session = standingInA(
      linkedCels: (
        a: celHolding(
          'a',
          transform: positionAt0(CanvasPoint(x: 1, y: 1), name: 'N'),
        ),
        b: celHolding(
          'b',
          transform: positionAt0(CanvasPoint(x: 1, y: 1), name: 'N'),
        ),
      ),
    );

    session.laneVerbs.updateLayerTransformTrack(
      const LayerId('b-cel'),
      positionAt0(CanvasPoint(x: 5, y: 5), name: 'N'),
    );

    expect(
      celOf(session, 'a').transformTrack.position.keyAt(0)?.value,
      CanvasPoint(x: 5, y: 5),
      reason: 'same name, same value: a\'s cel is b\'s sibling',
    );
  });

  test('a name given to keys of a row of a cut not stood in is looked for in '
      'that row\'s link group — a sibling holding it is asked about before '
      'anything is written, and joining takes its value', () {
    final session = standingInA(
      linkedCels: (
        a: celHolding(
          'a',
          transform: positionAt0(CanvasPoint(x: 1, y: 1), name: 'N'),
        ),
        b: celHolding('b', transform: positionAt0(CanvasPoint(x: 2, y: 2))),
      ),
    );
    session.laneRangeSelection.value = const TimelineLaneSelection(
      layerId: LayerId('b-cel'),
      laneId: 'position',
      startIndex: 0,
      endIndexExclusive: 1,
    );
    PropertyKey<CanvasPoint>? key() =>
        celOf(session, 'b').transformTrack.position.keyAt(0);

    expect(
      session.laneVerbs.setLaneKeyNamesForSelection('N'),
      isTrue,
      reason: 'a\'s cel, b\'s sibling, holds the name',
    );
    expect(key()?.name, isNull, reason: 'nothing is written while asked');

    session.laneVerbs.linkLaneKeyNamesForSelection('N');
    expect(key()?.name, 'N');
    expect(key()?.value, CanvasPoint(x: 1, y: 1), reason: 'joining adopts');
  });

  test('so is a name given to an effect key of that row', () {
    final session = standingInA(
      linkedCels: (
        a: celHolding('a', effects: blurXAt0(3, name: 'N')),
        b: celHolding('b', effects: blurXAt0(8)),
      ),
    );
    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: const LayerId('b-cel'),
      laneId: effectLaneId(const EffectId('fx'), 'blurriness'),
      startIndex: 0,
      endIndexExclusive: 1,
    );
    PropertyKey<double>? key() => celOf(
      session,
      'b',
    ).effects.single.parameterOf('blurriness').track.keyAt(0);

    expect(
      session.laneVerbs.setLaneKeyNamesForSelection('N'),
      isTrue,
      reason: 'a\'s cel, b\'s sibling, holds the name',
    );
    expect(key()?.name, isNull, reason: 'nothing is written while asked');

    session.laneVerbs.linkLaneKeyNamesForSelection('N');
    expect(key()?.name, 'N');
    expect(key()?.value, 3, reason: 'joining adopts');
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
