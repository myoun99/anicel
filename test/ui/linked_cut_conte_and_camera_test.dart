import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 겸용컷 — the CONTE row and the CAMERA row link too (F-84, 유저
/// 2026-09-11: 「확인말한거 그대로 맞아. 내가 원하던게 그거야. 그리고 겸용컷
/// 지금 카메라레이어가 없네」). A cut holds one of each, so they pair by kind;
/// the conte row shares its pictures like any drawing row, and the camera
/// keeps the transform law — lanes each cut's own, a NAMED key one value
/// across the group (「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로
/// 통일해줘」).
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  Cut cutById(CutId cutId) =>
      session.activeTrack.cuts.firstWhere((cut) => cut.id == cutId);

  List<Layer> rowsOf(CutId cutId, LayerKind kind) => [
    for (final layer in cutById(cutId).layers)
      if (layer.kind == kind) layer,
  ];

  Layer cameraOf(CutId cutId) => rowsOf(cutId, LayerKind.camera).single;

  CanvasPoint cameraAt(CutId cutId, int frame) =>
      cutById(cutId).camera.track.position.keyAt(frame)!.value;

  /// Keys the ACTIVE cut's camera position at [points] (frame → point).
  void keyCamera(Map<int, CanvasPoint> points) {
    var position = PropertyTrack<CanvasPoint>();
    for (final MapEntry(key: frame, value: point) in points.entries) {
      position = position.withKey(frame, point);
    }
    session.updateActiveCutCameraTrack(
      TransformTrack.empty().copyWith(position: position),
    );
  }

  /// Makes the active cut 겸용 with a fresh sibling (which becomes active).
  ({CutId source, CutId linked}) makeLinkedPair() {
    final source = session.requireActiveCut.id;
    session.cutVerbs.createLinkedCutFromActiveCut();
    return (source: source, linked: session.requireActiveCut.id);
  }

  test("a 겸용 cut gets a CAMERA row — a linked copy of the source's, its "
      'lanes copied rather than shared', () {
    keyCamera({0: CanvasPoint(x: 0, y: 0), 6: CanvasPoint(x: 60, y: 0)});

    final pair = makeLinkedPair();

    expect(
      rowsOf(pair.linked, LayerKind.camera),
      hasLength(1),
      reason: 'the 겸용 cut has its camera row',
    );
    expect(
      session.layerVerbs.isLayerLinked(cameraOf(pair.linked).id),
      isTrue,
      reason: "linked to the source's — one camera, two uses",
    );
    expect(
      cutById(pair.linked).camera,
      cutById(pair.source).camera,
      reason: "the lanes arrive as the source's",
    );
  });

  test('a NAMED camera key moved in one cut moves in its 겸용 sibling — an '
      "unnamed one stays each cut's own, and one undo takes both", () {
    session.updateActiveCutCameraTrack(
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(6, CanvasPoint(x: 60, y: 0))
            .withKeyName(0, 'A'),
      ),
    );
    final pair = makeLinkedPair();

    session.selectCut(pair.source);
    final track = cutById(pair.source).camera.track;
    session.updateActiveCutCameraTrack(
      track.copyWith(
        position: track.position
            .withKey(0, CanvasPoint(x: 5, y: 5))
            .withKey(6, CanvasPoint(x: 70, y: 0)),
      ),
    );

    expect(
      cameraAt(pair.linked, 0),
      CanvasPoint(x: 5, y: 5),
      reason: 'same name, same value',
    );
    expect(
      cameraAt(pair.linked, 6),
      CanvasPoint(x: 60, y: 0),
      reason: "an unnamed key is that cut's own lane",
    );

    session.undo();
    expect(cameraAt(pair.source, 0), CanvasPoint(x: 0, y: 0));
    expect(
      cameraAt(pair.linked, 0),
      CanvasPoint(x: 0, y: 0),
      reason: 'one undo step for the whole group',
    );
  });

  test("a camera lane's names span the 겸용 group: a name held only in the "
      'sibling is TAKEN here, and joining adopts its value', () {
    keyCamera({0: CanvasPoint(x: 0, y: 0)});
    final pair = makeLinkedPair();
    // The linked cut moves its own, unnamed key — nothing crosses.
    final linkedTrack = cutById(pair.linked).camera.track;
    session.updateActiveCutCameraTrack(
      linkedTrack.copyWith(
        position: linkedTrack.position.withKey(0, CanvasPoint(x: 9, y: 9)),
      ),
    );
    expect(cameraAt(pair.source, 0), CanvasPoint(x: 0, y: 0));

    void standOnKey(CutId cutId) {
      session.selectCut(cutId);
      session.standOnRow(
        LaneRowAddress(cameraOf(cutId).id, 'position'),
        frameIndex: 0,
      );
    }

    standOnKey(pair.source);
    expect(session.laneVerbs.setLaneKeyNamesForSelection('B'), isFalse);

    standOnKey(pair.linked);
    expect(
      session.laneVerbs.setLaneKeyNamesForSelection('B'),
      isTrue,
      reason: "held by the sibling's camera — the group is one naming space",
    );
    expect(
      cutById(pair.linked).camera.track.position.keyAt(0)!.name,
      isNull,
      reason: 'a collision writes nothing',
    );

    session.laneVerbs.linkLaneKeyNamesForSelection('B');
    final joined = cutById(pair.linked).camera.track.position.keyAt(0)!;
    expect(joined.name, 'B');
    expect(
      joined.value,
      CanvasPoint(x: 0, y: 0),
      reason: 'joining ADOPTS the value the name holds',
    );
  });

  test('a canvas pose write keeps the key HOLD — and the 겸용 sibling '
      'follows in value AND type', () {
    session.updateActiveCutCameraTrack(
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKeyName(0, 'A'),
      ),
    );
    final source = session.requireActiveCut.id;
    session.standOnRow(
      LaneRowAddress(cameraOf(source).id, 'position'),
      frameIndex: 0,
    );
    session.laneVerbs.setLaneKeyInterpolationsForSelection(
      PropertyKeyInterpolation.hold,
    );
    final pair = makeLinkedPair();

    // The canvas gizmo's write: a POSE at the playhead, no type in hand.
    session.selectCut(pair.source);
    session.camera.setCameraKeyframeAtCurrentFrame(
      CameraPose(center: CanvasPoint(x: 12, y: 12), zoom: 1),
    );

    PropertyKey<CanvasPoint> keyOf(CutId cutId) =>
        cutById(cutId).camera.track.position.keyAt(0)!;
    expect(
      keyOf(pair.source).interpolation,
      PropertyKeyInterpolation.hold,
      reason: '「홀드인상태서 … 값 바꾸면 홀드가 리니어로 돌아와」 — no longer',
    );
    expect(keyOf(pair.linked).value, CanvasPoint(x: 12, y: 12));
    expect(
      keyOf(pair.linked).interpolation,
      PropertyKeyInterpolation.hold,
      reason: 'the sibling holds the same key, type included',
    );
  });

  test('the TYPE alone crosses the 겸용 group on a named key', () {
    session.updateActiveCutCameraTrack(
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKeyName(0, 'A'),
      ),
    );
    final pair = makeLinkedPair();

    session.standOnRow(
      LaneRowAddress(cameraOf(pair.linked).id, 'position'),
      frameIndex: 0,
    );
    session.laneVerbs.setLaneKeyInterpolationsForSelection(
      PropertyKeyInterpolation.hold,
    );

    expect(
      cutById(pair.source).camera.track.position.keyAt(0)!.interpolation,
      PropertyKeyInterpolation.hold,
      reason: '「겸용컷끼리 홀드/리니어타입 … 싹다링크해야하는데」',
    );
  });

  test('the CONTE row links too — one per cut, the same pictures, and a '
      'fresh timeline the 겸용 cut exposes anew', () {
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final source = session.requireActiveCut.id;
    final sourceConte = rowsOf(source, LayerKind.storyboard).single;

    final pair = makeLinkedPair();

    final conte = rowsOf(pair.linked, LayerKind.storyboard);
    expect(conte, hasLength(1));
    expect(session.layerVerbs.isLayerLinked(conte.single.id), isTrue);
    expect(
      [for (final frame in conte.single.frames) frame.id],
      [for (final frame in sourceConte.frames) frame.id],
      reason: 'the pictures are one',
    );
    expect(
      conte.single.timeline,
      isEmpty,
      reason: 'the 겸용 cut exposes the shared bank on its own',
    );
  });

  test('a conte row added to a 겸용 cut appears in the sibling that has none '
      '— and a sibling with its own keeps just that one', () {
    final pair = makeLinkedPair();

    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    expect(
      rowsOf(pair.source, LayerKind.storyboard),
      hasLength(1),
      reason: 'existence is shared: the sibling gains the conte row too',
    );

    // Part them: the linked cut's conte row goes its own way, then goes.
    session.layerVerbs.unlinkActiveLayer();
    session.layerVerbs.deleteActiveLayer();
    expect(rowsOf(pair.linked, LayerKind.storyboard), isEmpty);
    expect(rowsOf(pair.source, LayerKind.storyboard), hasLength(1));

    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    expect(rowsOf(pair.linked, LayerKind.storyboard), hasLength(1));
    expect(
      rowsOf(pair.source, LayerKind.storyboard),
      hasLength(1),
      reason: 'a cut holds ONE conte row: the sibling with its own keeps it',
    );
  });
}
