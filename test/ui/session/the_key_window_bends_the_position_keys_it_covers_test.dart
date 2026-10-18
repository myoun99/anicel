import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/camera.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';

/// I-89 ④-Q4 (A while it is asked): the key window's path half lands on the
/// position keys its range covers — with the name and the sides, in one
/// undo step — and on no other lane's, whose keys walk no path.
void main() {
  late EditorSessionManager session;

  /// Held by its own type: the mutation runner picks a file's witnesses by
  /// the tests that import it.
  late LaneVerbs laneVerbs;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    laneVerbs = session.laneVerbs;
  });

  tearDown(() => session.dispose());

  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  PropertyTrack<CanvasPoint> position() =>
      session.activeLayer!.transformTrack.position;
  PropertyTrack<CanvasPoint> scale() =>
      session.activeLayer!.transformTrack.scale;

  /// Keys at 0, 4 and 8 on the active layer's Position and Scale.
  void keyPositionAndScale() {
    final layer = session.activeLayer!;
    var position = layer.transformTrack.position;
    var scale = layer.transformTrack.scale;
    for (final frame in [0, 4, 8]) {
      position = position.withKey(frame, p(frame * 10, 0));
      scale = scale.withKey(frame, p(1, 1));
    }
    laneVerbs.updateLayerTransformTrack(
      layer.id,
      layer.transformTrack.copyWith(position: position, scale: scale),
    );
  }

  void select(List<String> lanes, int start, int end) =>
      session.laneRangeSelection.value = TimelineLaneSelection(
        layerId: session.activeLayer!.id,
        laneId: lanes.first,
        startIndex: start,
        endIndexExclusive: end,
        laneIds: lanes,
      );

  test('the row reads the position keys the range covers, and no other '
      'lane\'s', () {
    keyPositionAndScale();
    select(['position', 'scale'], 0, 9);
    expect(laneVerbs.laneKeyPathsForSelection, [
      KeyPath.straight,
      KeyPath.straight,
      KeyPath.straight,
    ]);
    select(['scale'], 0, 9);
    expect(laneVerbs.laneKeyPathsForSelection, isEmpty);
  });

  test('a curve picked with a name lands on the covered position keys in '
      'the name\'s own undo step — the scale keys beside them stay as they '
      'were', () {
    keyPositionAndScale();
    select(['position', 'scale'], 0, 5);
    expect(
      laneVerbs.setLaneKeyNamesForSelection(
        'A',
        pick: const KeyTypePick(curved: true),
      ),
      isFalse,
    );
    expect(position().keyAt(0)!.path, KeyPath.auto);
    expect(position().keyAt(4)!.path, KeyPath.auto);
    expect(position().keyAt(8)!.path, KeyPath.straight, reason: 'outside');
    expect(scale().keyAt(0)!.path, KeyPath.straight);
    expect(position().keyAt(0)!.name, 'A');

    session.undo();
    expect(position().keyAt(0)!.path, KeyPath.straight);
    expect(position().keyAt(0)!.name, isNull, reason: 'ONE step');
  });

  test('the type alone bends and straightens, each its own undo step', () {
    keyPositionAndScale();
    select(['position'], 4, 5);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: true));
    expect(position().keyAt(4)!.path, KeyPath.auto);

    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: false));
    expect(position().keyAt(4)!.path, KeyPath.straight);

    session.undo();
    expect(position().keyAt(4)!.path, KeyPath.auto);
  });

  test('an anchor point\'s keys take the row too, and the roving one — they '
      'walk a path as a position\'s do (anchor-walks-a-path)', () {
    final layer = session.activeLayer!;
    var anchor = layer.transformTrack.anchorPoint;
    for (final frame in [0, 4, 8]) {
      anchor = anchor.withKey(frame, p(frame * 10, 0));
    }
    laneVerbs.updateLayerTransformTrack(
      layer.id,
      layer.transformTrack.copyWith(anchorPoint: anchor),
    );
    select(['anchor-point'], 0, 9);
    expect(laneVerbs.laneKeyPathsForSelection, hasLength(3));
    expect(
      laneVerbs.laneKeyRovingForSelection,
      [false],
      reason: 'the key between the first and the last',
    );
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: true));
    expect(
      session.activeLayer!.transformTrack.anchorPoint.keyAt(4)!.path,
      KeyPath.auto,
    );
  });

  test('a name hands the bend to every key it links', () {
    keyPositionAndScale();
    select(['position'], 0, 1);
    laneVerbs.setLaneKeyNamesForSelection('A');
    select(['position'], 8, 9);
    laneVerbs.linkLaneKeyNamesForSelection('A');
    expect(position().keyAt(8)!.name, 'A', reason: '⛔전제');

    select(['position'], 0, 1);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: true));
    expect(position().keyAt(0)!.path, KeyPath.auto);
    expect(position().keyAt(8)!.path, KeyPath.auto);
    expect(position().keyAt(4)!.path, KeyPath.straight, reason: 'unnamed');
  });

  test('the camera\'s position keys straighten and bend the same way — '
      'smooth as they are made (I-89-Q10 B)', () {
    final camera = cameraOf(session);
    for (final frame in [0, 4, 8]) {
      session.selectFrameIndex(frame);
      camera.setCameraKeyframeAtCurrentFrame(
        camera.cameraPoseAtCurrentFrame.copyWith(center: p(frame * 10, 0)),
      );
    }
    final row = session.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row,
      laneId: 'position',
      startIndex: 4,
      endIndexExclusive: 5,
    );
    KeyPath pathAt4() =>
        session.requireActiveCut.camera.track.position.keyAt(4)!.path;
    expect(laneVerbs.laneKeyPathsForSelection, [KeyPath.auto]);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: false));
    expect(pathAt4(), KeyPath.straight);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(curved: true));
    expect(pathAt4(), KeyPath.auto);
  });
}

/// The camera collaborator under its own name, as the lane verbs are held.
Camera cameraOf(EditorSessionManager session) => session.camera;
