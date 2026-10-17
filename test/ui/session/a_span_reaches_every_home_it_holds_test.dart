import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// **F-374 — a lane span reaches every home it holds lanes of.**
///
/// 🗣️유저 2026-10-17: 「참조fx도 똑같이 fx로서 법 통일 … 그런 각종 fx관련 싹
/// 통일」. A span is sliced out of the rows the rail drew (#1381), so it may
/// hold lanes of a row's own transform, its effect chain and its name tag
/// at once — and Create, Delete and the key window answer for all of them
/// in one undo. ↩️Each verb asked whether an fx lane was in the span and
/// then worked the fx chain alone or the transform alone, and a span of
/// the name tag's lanes made, took and named nothing.
void main() {
  final blurLane = effectLaneId(const EffectId('e1'), 'blurX');

  LayerEffect blur(Map<int, PropertyKey<double>> keys) => LayerEffect(
    id: const EffectId('e1'),
    kind: EffectKind.blur,
    parameters: {
      'blurX': EffectParameter(track: PropertyTrack<double>(keys: keys)),
    },
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// The cut's drawing row, a Position key and a blur's key at frame 3.
  Layer keyedCel(EditorSessionManager s) {
    final cel = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    s.laneVerbs.updateLayerTransformTrack(
      cel.id,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>(
          keys: {3: PropertyKey(CanvasPoint(x: 10, y: 0))},
        ),
      ),
    );
    s.effectsAndFx.updateLayerEffects(cel.id, [
      blur({3: const PropertyKey<double>(4)}),
    ]);
    return cel;
  }

  Set<int> positionKeys(EditorSessionManager s, Layer row) =>
      s.layerById(row.id)!.transformTrack.position.keys.keys.toSet();

  Set<int> blurKeys(EditorSessionManager s, Layer row) => s
      .layerById(row.id)!
      .effects
      .single
      .parameters['blurX']!
      .track
      .keys
      .keys
      .toSet();

  TimelineLaneSelection span(
    Layer row,
    List<String> laneIds,
    int start,
    int endExclusive,
  ) => TimelineLaneSelection(
    layerId: row.id,
    laneId: laneIds.first,
    startIndex: start,
    endIndexExclusive: endExclusive,
    laneIds: laneIds,
  );

  /// The default project's first SE row — a track's — tagged [track].
  Layer taggedSe(EditorSessionManager s, SeNameTagTrack track) {
    final se = s.activeTrack.seLayers.first;
    s.cutCommandCoordinator.setSeNameTag(
      layerId: se.id,
      seNameTag: SeNameTag(track: track),
    );
    return se;
  }

  SeNameTagTrack tagKeysOf(EditorSessionManager s) =>
      s.activeTrack.seLayers.first.seNameTag!.track!;

  test('🎯a span over a transform lane and an fx lane makes keys on BOTH — '
      'one undo', () {
    final s = session();
    final cel = keyedCel(s);
    final lane = span(cel, ['position', blurLane], 5, 7);
    s.laneRangeSelection.value = lane;

    s.laneVerbs.createLaneKeysForSelection(lane);

    expect(positionKeys(s, cel), {3, 5, 6});
    expect(blurKeys(s, cel), {3, 5, 6});
    s.undo();
    expect(positionKeys(s, cel), {3});
    expect(blurKeys(s, cel), {3}, reason: 'one step for the two homes');
  });

  test('🎯…and Delete takes the keys of both — one undo', () {
    final s = session();
    final cel = keyedCel(s);
    final lane = span(cel, ['position', blurLane], 2, 5);
    s.laneRangeSelection.value = lane;

    expect(s.laneVerbs.removeLaneKeysForSelection(lane), isTrue);

    expect(positionKeys(s, cel), isEmpty);
    expect(blurKeys(s, cel), isEmpty);
    s.undo();
    expect(positionKeys(s, cel), {3});
    expect(blurKeys(s, cel), {3});
  });

  test('🎯Create freezes what the lane SHOWS on every frame — between eased '
      'keys too', () {
    final s = session();
    final cel = keyedCel(s);
    s.effectsAndFx.updateLayerEffects(cel.id, [
      blur({
        0: const PropertyKey<double>(0, outgoing: EaseSide()),
        10: const PropertyKey<double>(10, incoming: EaseSide()),
      }),
    ]);
    final shown = s.layerById(cel.id)!.effects.single.parameters['blurX']!;
    final before = {for (var f = 1; f < 10; f += 1) f: shown.resolveAt(f)};
    final lane = span(cel, [blurLane], 1, 10);
    s.laneRangeSelection.value = lane;

    s.laneVerbs.createLaneKeysForSelection(lane);

    final made = s.layerById(cel.id)!.effects.single.parameters['blurX']!;
    expect(
      {for (var f = 1; f < 10; f += 1) f: made.track.keyAt(f)!.value},
      before,
      reason:
          'each key the navigator\'s ◆ on the lane as the press found '
          'it — ↩️each was frozen off the one made before it, on a curve '
          'that one had bent',
    );
  });

  test('🎯a span over the name tag\'s lanes makes keys there, and Delete '
      'takes them — one undo each', () {
    final s = session();
    final se = taggedSe(
      s,
      SeNameTagTrack(
        fontSize: PropertyTrack<double>(
          keys: {3: const PropertyKey<double>(20)},
        ),
      ),
    );
    final made = span(se, [seNameTagSizeLaneId], 5, 7);
    s.laneRangeSelection.value = made;

    s.laneVerbs.createLaneKeysForSelection(made);
    expect(tagKeysOf(s).fontSize.keys.keys, [3, 5, 6]);
    expect(tagKeysOf(s).fontSize.keyAt(5)!.value, 20, reason: 'as it shows');

    final taken = span(se, [seNameTagSizeLaneId], 2, 6);
    s.laneRangeSelection.value = taken;
    expect(s.laneVerbs.laneVerbRangeHasKeys, isTrue);
    expect(s.laneVerbs.removeLaneKeysForSelection(taken), isTrue);
    expect(tagKeysOf(s).fontSize.keys.keys, [6]);

    s.undo();
    expect(tagKeysOf(s).fontSize.keys.keys, [3, 5, 6]);
    s.undo();
    expect(tagKeysOf(s).fontSize.keys.keys, [3]);
  });

  test('🎯the key window names a name tag\'s keys, and gives its sides to '
      'the members that take them — a flag holds by nature (#902)', () {
    final s = session();
    final se = taggedSe(
      s,
      SeNameTagTrack(
        fontSize: PropertyTrack<double>(
          keys: {3: const PropertyKey<double>(20, outgoing: EaseSide())},
        ),
        bold: PropertyTrack<bool>(
          keys: {3: const PropertyKey<bool>(true, outgoing: KeyExit.hold)},
        ),
      ),
    );
    s.laneRangeSelection.value = span(
      se,
      [seNameTagSizeLaneId, seNameTagBoldLaneId],
      3,
      4,
    );
    expect(s.laneVerbs.canNameLaneKeys, isTrue);
    expect(
      s.laneVerbs.laneKeySidesForSelection,
      [(incoming: KeySide.linear, outgoing: const EaseSide())],
      reason: 'the window opens on the size key\'s sides alone',
    );

    expect(
      s.laneVerbs.setLaneKeyNamesForSelection(
        'N',
        pick: const KeyTypePick(sides: KeySidesEdit.linear),
      ),
      isFalse,
    );

    final keys = tagKeysOf(s);
    expect(keys.fontSize.keyAt(3)!.name, 'N');
    expect(keys.bold.keyAt(3)!.name, 'N');
    expect(keys.fontSize.keyAt(3)!.outgoing, KeySide.linear);
    expect(keys.bold.keyAt(3)!.outgoing, KeyExit.hold, reason: 'a flag');
  });

  test('a name the tag already holds outside the span is TAKEN — asked '
      'before any key is written, and joined, its value adopted', () {
    final s = session();
    final se = taggedSe(
      s,
      SeNameTagTrack(
        fontSize: PropertyTrack<double>(
          keys: {
            3: const PropertyKey<double>(20, name: 'N'),
            6: const PropertyKey<double>(30),
          },
        ),
      ),
    );
    s.laneRangeSelection.value = span(se, [seNameTagSizeLaneId], 5, 7);

    expect(s.laneVerbs.setLaneKeyNamesForSelection('N'), isTrue);
    expect(tagKeysOf(s).fontSize.keyAt(6)!.name, isNull, reason: 'untouched');

    s.laneVerbs.linkLaneKeyNamesForSelection('N');
    expect(tagKeysOf(s).fontSize.keyAt(6)!.name, 'N');
    expect(tagKeysOf(s).fontSize.keyAt(6)!.value, 20, reason: 'adopted');
  });

  test('a span over a flag alone offers the window\'s sides and refuses '
      'them', () {
    final s = session();
    final se = taggedSe(
      s,
      SeNameTagTrack(
        bold: PropertyTrack<bool>(
          keys: {3: const PropertyKey<bool>(true, outgoing: KeyExit.hold)},
        ),
      ),
    );
    s.laneRangeSelection.value = span(se, [seNameTagBoldLaneId], 3, 4);

    expect(s.laneVerbs.laneKeySidesCountForSelection(null), isFalse);
  });
}
