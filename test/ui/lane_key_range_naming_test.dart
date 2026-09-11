import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;

/// Naming a lane RANGE. A name MEANS "same value", so naming the keys a
/// span covers collapses them onto one number — that is the intent rather
/// than a side effect (user 2026-08-10: "같은행 여러키 이름변경할때 한값으로
/// 뭉개는거 맞음. 그게 의도"), and it has to land as ONE undo step.
void main() {
  late EditorSessionManager session;

  /// The lane verbs under test, held BY THEIR OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled `session.laneVerbs` is one
  /// the campaign reports UNNAMED and never runs a mutant against — the
  /// (link group, property) naming space lives in that file, and this is
  /// what holds it.
  late LaneVerbs laneVerbs;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    laneVerbs = session.laneVerbs;
  });

  tearDown(() => session.dispose());

  PropertyTrack<double> rotation() => session.activeLayer!.transformTrack.rotation;

  void keyRotation(Map<int, double> spec) {
    final layer = session.activeLayer!;
    var lane = layer.transformTrack.rotation;
    for (final entry in spec.entries) {
      lane = lane.withKey(entry.key, entry.value);
    }
    session.updateLayerTransformTrack(
      layer.id,
      layer.transformTrack.copyWith(rotation: lane),
    );
  }

  void selectRotationRange(int startIndex, int endIndexExclusive) {
    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: session.activeLayer!.id,
      laneId: 'rotation',
      startIndex: startIndex,
      endIndexExclusive: endIndexExclusive,
    );
  }

  test('the covered keys collapse onto ONE value, in ONE undo step', () {
    keyRotation({0: 10, 4: 20, 8: 30});
    selectRotationRange(0, 9);

    expect(
      laneVerbs.setLaneKeyNamesForSelection('A'),
      isFalse,
      reason: 'the name was free',
    );

    expect(rotation().keyAt(0)!.value, 10);
    expect(rotation().keyAt(4)!.value, 10, reason: 'collapsed onto one value');
    expect(rotation().keyAt(8)!.value, 10);
    expect(rotation().keyNames, {'A'});

    session.undo();

    expect(rotation().keyAt(4)!.value, 20, reason: 'ONE step brought it back');
    expect(rotation().keyNames, isEmpty);
  });

  test('keys OUTSIDE the range keep their own value and stay unnamed', () {
    keyRotation({0: 10, 4: 20, 8: 30});
    selectRotationRange(0, 5);

    expect(laneVerbs.setLaneKeyNamesForSelection('A'), isFalse);

    expect(rotation().keyAt(0)!.value, 10);
    expect(rotation().keyAt(4)!.value, 10);
    expect(rotation().keyAt(8)!.value, 30, reason: 'never covered');
    expect(rotation().keyAt(8)!.name, isNull);
  });

  test('a name held OUTSIDE the range is a collision, asked ONCE', () {
    keyRotation({0: 10, 4: 20, 8: 30});

    // Name the far key first, so 'A' is taken outside the range that
    // follows.
    selectRotationRange(8, 9);
    expect(laneVerbs.setLaneKeyNamesForSelection('A'), isFalse);
    expect(rotation().keyAt(8)!.value, 30);

    selectRotationRange(0, 5);
    expect(
      laneVerbs.setLaneKeyNamesForSelection('A'),
      isTrue,
      reason: 'that name is already held by the key at 8',
    );
    expect(
      rotation().keyAt(0)!.name,
      isNull,
      reason: 'a collision writes NOTHING until it is confirmed',
    );

    // Confirming ADOPTS the value the name already holds, for the whole
    // range at once.
    laneVerbs.linkLaneKeyNamesForSelection('A');

    expect(rotation().keyAt(0)!.value, 30);
    expect(rotation().keyAt(4)!.value, 30);
    expect(rotation().keyAt(8)!.value, 30, reason: 'the holder is untouched');
    expect(rotation().keyNames, {'A'});
  });

  test('the keys already inside the range do not collide with themselves', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    expect(laneVerbs.setLaneKeyNamesForSelection('A'), isFalse);

    // Naming the SAME range again with the SAME name must not report a
    // collision: the only keys holding it are the ones doing the joining.
    expect(
      laneVerbs.setLaneKeyNamesForSelection('A'),
      isFalse,
      reason: 'a range cannot collide with itself',
    );
  });

  test('the dialog opens with the name they agree on, blank when they do not', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    expect(laneVerbs.laneKeyNameForSelection, isNull, reason: 'none named yet');

    laneVerbs.setLaneKeyNamesForSelection('A');
    expect(laneVerbs.laneKeyNameForSelection, 'A');

    // Name just one of them something else: they no longer agree.
    selectRotationRange(4, 5);
    laneVerbs.setLaneKeyNamesForSelection('B');
    selectRotationRange(0, 5);
    expect(laneVerbs.laneKeyNameForSelection, isNull);
  });

  test('an emptied field un-names the range and leaves the values put', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    laneVerbs.setLaneKeyNamesForSelection('A');
    expect(rotation().keyAt(4)!.value, 10, reason: 'collapsed by the naming');

    expect(laneVerbs.setLaneKeyNamesForSelection(null), isFalse);

    expect(rotation().keyNames, isEmpty);
    expect(rotation().keyAt(0)!.value, 10, reason: 'un-naming moves nothing');
    expect(rotation().keyAt(4)!.value, 10);
  });

  test('a range with no key at all cannot be named', () {
    selectRotationRange(0, 5);

    expect(laneVerbs.canNameLaneKeys, isFalse);
    expect(laneVerbs.setLaneKeyNamesForSelection('A'), isFalse);
    expect(rotation().isEmpty, isTrue);
  });

  // ── F-17: the key window's TYPE ──

  test('the TYPE lands with the name on every covered key, in the SAME '
      'undo step — the key window is one edit', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    expect(
      laneVerbs.laneKeyInterpolationForSelection,
      PropertyKeyInterpolation.linear,
      reason: 'the window opens on the type the keys agree on',
    );

    laneVerbs.setLaneKeyNamesForSelection(
      'A',
      interpolation: PropertyKeyInterpolation.hold,
    );
    expect(rotation().keyAt(0)!.interpolation, PropertyKeyInterpolation.hold);
    expect(rotation().keyAt(4)!.interpolation, PropertyKeyInterpolation.hold);
    expect(rotation().keyNames, {'A'});

    session.undo();
    expect(
      rotation().keyAt(0)!.interpolation,
      PropertyKeyInterpolation.linear,
      reason: 'one step took the type…',
    );
    expect(rotation().keyNames, isEmpty, reason: '…and the name with it');
  });

  test('keys that DISAGREE on their type open the window with none picked, '
      'and the type alone can still be written — leaving the names', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(4, 5);
    laneVerbs.setLaneKeyNamesForSelection('B');
    laneVerbs.setLaneKeyInterpolationsForSelection(
      PropertyKeyInterpolation.hold,
    );
    expect(rotation().keyAt(4)!.interpolation, PropertyKeyInterpolation.hold);
    expect(
      rotation().keyAt(4)!.name,
      'B',
      reason: 'the type alone leaves the name',
    );
    expect(
      rotation().keyAt(0)!.interpolation,
      PropertyKeyInterpolation.linear,
      reason: 'outside the range',
    );

    selectRotationRange(0, 5);
    expect(laneVerbs.laneKeyInterpolationForSelection, isNull);
  });

  // ── F-17/F-84: the camera row IS its transform header ──

  LayerId standOnCamera(int frame) {
    final camera = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    session.standOnRow(LayerRowAddress(camera.id), frameIndex: frame);
    return camera.id;
  }

  void keyCameraHere() => session.camera.setCameraKeyframeAtCurrentFrame(
    session.camera.cameraPoseAtCurrentFrame,
  );

  test('standing on the CAMERA row stands on its transform header: one name '
      'and one type land on every camera member key there', () {
    standOnCamera(2);
    keyCameraHere();
    expect(laneVerbs.canNameLaneKeys, isTrue, reason: 'its instance is its KEY');

    laneVerbs.setLaneKeyNamesForSelection(
      'Pan',
      interpolation: PropertyKeyInterpolation.hold,
    );

    final track = session.activeCutOrNull!.camera.track;
    for (final key in [
      track.position.keyAt(2),
      track.scale.keyAt(2),
      track.rotation.keyAt(2),
    ]) {
      expect(key!.name, 'Pan');
      expect(key.interpolation, PropertyKeyInterpolation.hold);
    }
  });

  test('a cell band on the camera row ALONE is a header span; a band that '
      'holds other rows stays CELLS', () {
    final cameraId = standOnCamera(2);
    keyCameraHere();
    standOnCamera(5);
    keyCameraHere();
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: cameraId,
      startIndex: 0,
      endIndexExclusive: 6,
    );

    laneVerbs.setLaneKeyNamesForSelection('Pan');
    final track = session.activeCutOrNull!.camera.track;
    expect(track.position.keyAt(2)!.name, 'Pan');
    expect(track.position.keyAt(5)!.name, 'Pan');

    final drawingId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: cameraId,
      startIndex: 0,
      endIndexExclusive: 6,
      layerIds: [cameraId, drawingId],
    );
    expect(
      laneVerbs.laneVerbRange,
      isNull,
      reason: 'a band holding more than the camera claims the press as cells',
    );
  });

  test('an EFFECT lane takes the type too — the fx header opens the same '
      'window (F-17)', () {
    final layerId = session.activeLayer!.id;
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    Layer layer() => session.layers.firstWhere((each) => each.id == layerId);
    final laneId = effectLaneId(layer().effects.single.id, 'blurX');
    session.updateLaneRangeSelectionDrag(
      layerId: layerId,
      laneId: laneId,
      anchorIndex: 1,
      headIndex: 3,
      spanLaneIds: [laneId],
    );
    expect(session.cellInstances.createInstancesForSelection(), isTrue);

    laneVerbs.setLaneKeyNamesForSelection('B');
    laneVerbs.setLaneKeyInterpolationsForSelection(
      PropertyKeyInterpolation.hold,
    );

    final track = layer().effects.single.parameterOf('blurX').track;
    for (final frame in [1, 2, 3]) {
      expect(track.keyAt(frame)!.interpolation, PropertyKeyInterpolation.hold);
      expect(
        track.keyAt(frame)!.name,
        'B',
        reason: 'the type alone leaves the name',
      );
    }
    expect(
      laneVerbs.laneKeyInterpolationForSelection,
      PropertyKeyInterpolation.hold,
    );
  });
}
