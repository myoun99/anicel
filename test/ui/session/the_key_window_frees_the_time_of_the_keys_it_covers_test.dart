import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;

/// I-89 ④-Q5 (A′ while it is asked): the key window's roving row frees the
/// time of the position keys its range covers between the first and the
/// last — with the name and the rest of the type, in one undo step — and
/// the key stands where its run passes it (Q④-6 A while it is asked).
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

  /// Position keys at 0 (0, 0), 2 (60, 0) and 8 (80, 0) — the one between
  /// passed at 6 once its time roves — and Scale keys on the same frames.
  void keyAWalk({bool roving = false}) {
    final layer = session.activeLayer!;
    var scale = layer.transformTrack.scale;
    for (final frame in [0, 2, 8]) {
      scale = scale.withKey(frame, p(1, 1));
    }
    laneVerbs.updateLayerTransformTrack(
      layer.id,
      layer.transformTrack.copyWith(
        position: PropertyTrack(
          keys: {
            0: PropertyKey(p(0, 0)),
            2: PropertyKey(p(60, 0), roving: roving),
            8: PropertyKey(p(80, 0)),
          },
        ),
        scale: scale,
      ),
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

  test('the row reads the position keys between the first and the last, '
      'and no other lane\'s', () {
    keyAWalk();
    select(['position', 'scale'], 0, 9);
    expect(laneVerbs.laneKeyRovingForSelection, [false]);
    select(['position'], 0, 1);
    expect(laneVerbs.laneKeyRovingForSelection, isEmpty, reason: 'first');
    select(['position'], 8, 9);
    expect(laneVerbs.laneKeyRovingForSelection, isEmpty, reason: 'last');
    select(['scale'], 0, 9);
    expect(laneVerbs.laneKeyRovingForSelection, isEmpty, reason: 'scale');
  });

  test("an effect lane offers the row no key: an effect's keys walk no "
      'path', () {
    final layerId = session.activeLayer!.id;
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final effect = session.activeLayer!.effects.single;
    final parameter = effect.parameterOf('blurX');
    session.effectsAndFx.updateLayerEffects(layerId, [
      effect.withParameter(
        'blurX',
        EffectParameter(
          value: parameter.value,
          track: parameter.track.withKey(0, 1).withKey(2, 5).withKey(8, 3),
        ),
      ),
    ]);
    select([effectLaneId(effect.id, 'blurX')], 0, 9);
    expect(laneVerbs.canNameLaneKeys, isTrue, reason: '⛔전제: it covers them');
    expect(laneVerbs.laneKeyRovingForSelection, isEmpty);
    expect(
      laneVerbs.laneKeySidesCountForSelection(true),
      isTrue,
      reason: "an effect's key keeps its time, so its sides count",
    );
  });

  /// 유저 2026-10-12: 「의미가 없다면 비활성화 시키는게 맞겟고」 — the sides of
  /// a key whose time roves set nothing: its run's timed ends pace it.
  test("a key between that roves wears no sides: the window's two rows "
      'count on it only while its time is its own', () {
    keyAWalk();
    select(['position'], 2, 3);
    final between = laneVerbs.laneKeySidesCountForSelection;
    expect(between(null), isTrue, reason: 'its time is its own');
    expect(between(false), isTrue);
    expect(between(true), isFalse, reason: 'picked to rove');
  });

  test('a key that roves takes its sides back as it is picked to keep its '
      'time', () {
    keyAWalk(roving: true);
    select(['position'], 6, 7);
    final roving = laneVerbs.laneKeySidesCountForSelection;
    expect(roving(null), isFalse);
    expect(roving(false), isTrue);
  });

  test('the rows count while any key the window covers keeps its time — '
      'an end, or a lane that walks no path', () {
    keyAWalk(roving: true);
    select(['position'], 0, 9);
    expect(
      laneVerbs.laneKeySidesCountForSelection(true),
      isTrue,
      reason: 'the first and the last keep their time',
    );
    select(['position'], 2, 7);
    expect(
      laneVerbs.laneKeySidesCountForSelection(true),
      isFalse,
      reason: '⛔전제: the position key it covers roves',
    );
    select(['position', 'scale'], 2, 7);
    expect(
      laneVerbs.laneKeySidesCountForSelection(true),
      isTrue,
      reason: 'the scale key at 2 keeps its time',
    );
  });

  test('the type alone frees the key between, which stands where its run '
      'passes it — one undo step', () {
    keyAWalk();
    select(['position', 'scale'], 0, 9);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(roving: true));
    expect(position().keys.keys, [0, 6, 8]);
    expect([for (final key in position().keys.values) key.roving], [
      false,
      true,
      false,
    ]);
    expect(
      session.activeLayer!.transformTrack.scale.keys.values.map(
        (key) => key.roving,
      ),
      everyElement(isFalse),
      reason: 'a scale walks no path',
    );
    session.undo();
    expect(position().keys.keys, [0, 2, 8]);
    expect(position().keyAt(2)!.roving, isFalse);
  });

  test('picked with a name, the key is named, freed and placed in the '
      'name\'s own undo step', () {
    keyAWalk();
    select(['position'], 2, 3);
    expect(
      laneVerbs.setLaneKeyNamesForSelection(
        'A',
        pick: const KeyTypePick(roving: true),
      ),
      isFalse,
    );
    expect(position().keyAt(6)!.name, 'A');
    expect(position().keyAt(6)!.roving, isTrue);
    session.undo();
    expect(position().keyAt(2)!.name, isNull);
    expect(position().keyAt(2)!.roving, isFalse);
  });

  test('held again, a key stays on the frame its run placed it', () {
    keyAWalk(roving: true);
    expect(position().keys.keys, [0, 6, 8], reason: '⛔전제: placed');
    select(['position'], 6, 7);
    expect(laneVerbs.laneKeyRovingForSelection, [true]);
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(roving: false));
    expect(position().keys.keys, [0, 6, 8]);
    expect(position().keyAt(6)!.roving, isFalse);
  });

  test('every pick lands on a roving key, though the first of them moves '
      'it — the window writes a lane once', () {
    final layer = session.activeLayer!;
    laneVerbs.updateLayerTransformTrack(
      layer.id,
      layer.transformTrack.copyWith(
        position: PropertyTrack(
          keys: {
            0: PropertyKey(p(0, 0)),
            10: PropertyKey(p(100, 0), roving: true),
            20: PropertyKey(p(100, 300)),
          },
        ),
      ),
    );
    expect(position().keys.keys, [0, 5, 20], reason: '⛔전제: placed');
    const ease = KeySidesEdit(
      outgoing: KeySideEdit(side: EaseSide(influence: 0.5, speed: 0)),
    );
    select(['position'], 0, 21);
    laneVerbs.setLaneKeyTypeForSelection(
      const KeyTypePick(sides: ease, path: KeyPathKind.autoBezier),
    );
    final frames = position().keys.keys.toList();
    expect(frames, hasLength(3));
    expect(frames[1], isNot(5), reason: 'the ease leaving 0 moved it');
    for (final key in position().keys.values) {
      expect(key.outgoing, isA<EaseSide>(), reason: '$key');
      expect(key.path, KeyPath.auto, reason: '$key');
    }
  });
}
