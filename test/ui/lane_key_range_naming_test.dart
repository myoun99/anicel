import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Naming a lane RANGE. A name MEANS "same value", so naming the keys a
/// span covers collapses them onto one number — that is the intent rather
/// than a side effect (user 2026-08-10: "같은행 여러키 이름변경할때 한값으로
/// 뭉개는거 맞음. 그게 의도"), and it has to land as ONE undo step.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
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
      session.setLaneKeyNamesForSelection('A'),
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

    expect(session.setLaneKeyNamesForSelection('A'), isFalse);

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
    expect(session.setLaneKeyNamesForSelection('A'), isFalse);
    expect(rotation().keyAt(8)!.value, 30);

    selectRotationRange(0, 5);
    expect(
      session.setLaneKeyNamesForSelection('A'),
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
    session.linkLaneKeyNamesForSelection('A');

    expect(rotation().keyAt(0)!.value, 30);
    expect(rotation().keyAt(4)!.value, 30);
    expect(rotation().keyAt(8)!.value, 30, reason: 'the holder is untouched');
    expect(rotation().keyNames, {'A'});
  });

  test('the keys already inside the range do not collide with themselves', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    expect(session.setLaneKeyNamesForSelection('A'), isFalse);

    // Naming the SAME range again with the SAME name must not report a
    // collision: the only keys holding it are the ones doing the joining.
    expect(
      session.setLaneKeyNamesForSelection('A'),
      isFalse,
      reason: 'a range cannot collide with itself',
    );
  });

  test('the dialog opens with the name they agree on, blank when they do not', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    expect(session.laneKeyNameForSelection, isNull, reason: 'none named yet');

    session.setLaneKeyNamesForSelection('A');
    expect(session.laneKeyNameForSelection, 'A');

    // Name just one of them something else: they no longer agree.
    selectRotationRange(4, 5);
    session.setLaneKeyNamesForSelection('B');
    selectRotationRange(0, 5);
    expect(session.laneKeyNameForSelection, isNull);
  });

  test('an emptied field un-names the range and leaves the values put', () {
    keyRotation({0: 10, 4: 20});
    selectRotationRange(0, 5);
    session.setLaneKeyNamesForSelection('A');
    expect(rotation().keyAt(4)!.value, 10, reason: 'collapsed by the naming');

    expect(session.setLaneKeyNamesForSelection(null), isFalse);

    expect(rotation().keyNames, isEmpty);
    expect(rotation().keyAt(0)!.value, 10, reason: 'un-naming moves nothing');
    expect(rotation().keyAt(4)!.value, 10);
  });

  test('a range with no key at all cannot be named', () {
    selectRotationRange(0, 5);

    expect(session.canNameLaneKeys, isFalse);
    expect(session.setLaneKeyNamesForSelection('A'), isFalse);
    expect(rotation().isEmpty, isTrue);
  });
}
