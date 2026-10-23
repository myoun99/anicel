import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/key_range_shift.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_span_keys_shift.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// **I-3 ⑥ — a lane move STRETCHES the keys it holds**: what a header
/// graph's box handle writes through (AE's transform box), by the lane
/// move's own law — one rigid group, nothing merged silently — each key
/// moved as far as its frame stretched.
void main() {
  late EditorSessionManager s;
  late LayerId id;

  void keyed(TransformTrack track) {
    s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    id = s.activeLayer!.id;
    s.laneVerbs.updateLayerTransformTrack(id, track);
  }

  void pick(List<String> lanes, int from, int to) =>
      s.updateLaneRangeSelectionDrag(
        layerId: id,
        laneId: lanes.first,
        anchorIndex: from,
        headIndex: to,
        spanLaneIds: lanes,
      );

  TransformTrack transform() =>
      s.layers.firstWhere((layer) => layer.id == id).transformTrack;

  Map<int, double> rotation() => {
    for (final MapEntry(key: frame, value: key)
        in transform().rotation.keys.entries)
      frame: key.value,
  };

  void stretch(List<FrameStretch> steps) {
    expect(s.laneMove.beginLaneRangeMoveDrag(), isTrue);
    for (final step in steps) {
      s.laneMove.updateLaneRangeMoveDrag(frameDelta: 0, stretch: step);
    }
    s.laneMove.endLaneRangeMoveDrag();
  }

  PropertyTrack<double> keys(Map<int, double> values) => values.entries.fold(
    PropertyTrack<double>(),
    (track, entry) => track.withKey(entry.key, entry.value),
  );

  test('stretched twice as long about its first key, every key goes twice '
      'as far from it — and the outline with them', () {
    keyed(
      TransformTrack.empty().copyWith(rotation: keys({2: 10, 4: 20, 6: 30})),
    );
    pick(['rotation'], 2, 6);

    stretch([(anchor: 2, factor: 2)]);

    expect(rotation(), {2: 10, 6: 20, 10: 30});
    final picked = s.laneRangeSelection.value!;
    expect((picked.startIndex, picked.endIndexExclusive), (2, 11));
  });

  test('stretched under 0, the keys turn about the anchor and run the other '
      'way in time — the outline turned with them', () {
    keyed(TransformTrack.empty().copyWith(rotation: keys({4: 10, 8: 20})));
    pick(['rotation'], 4, 8);

    stretch([(anchor: 8, factor: -1)]);

    expect(rotation(), {8: 20, 12: 10});
    final picked = s.laneRangeSelection.value!;
    expect((picked.startIndex, picked.endIndexExclusive), (8, 13));
  });

  test('a step that stretches two keys onto one frame is refused, and the '
      'step before it holds — nothing merges silently', () {
    keyed(
      TransformTrack.empty().copyWith(rotation: keys({0: 1, 1: 2, 8: 3})),
    );
    pick(['rotation'], 0, 8);

    stretch([(anchor: 0, factor: 2), (anchor: 0, factor: 0.25)]);

    expect(rotation(), {0: 1, 2: 2, 16: 3});
  });

  test('a home whose keys the stretch leaves where they are rides along: '
      'it refuses nothing', () {
    keyed(TransformTrack.empty().copyWith(rotation: keys({0: 10, 8: 20})));
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final effects = s.activeLayer!.effects;
    final blur = effectLaneId(effects.single.id, 'blurX');
    s.effectsAndFx.updateLayerEffects(
      id,
      effectsWithLaneKeyToggled(effects, laneId: blur, frameIndex: 0)!,
    );
    pick(['rotation', blur], 0, 8);

    stretch([(anchor: 0, factor: 2)]);

    expect(rotation(), {0: 10, 16: 20});
    expect(
      s.activeLayer!.effects.single.parameterOf('blurX').track.keys.keys,
      [0],
    );
  });

  test('a span moved nowhere is no move', () {
    final track = TransformTrack.empty().copyWith(
      rotation: keys({0: 10, 8: 20}),
    );
    expect(
      laneSpanKeysMoved(
        track,
        laneIds: const ['rotation'],
        lensOf: transformLaneLens,
        moveOn: (_) => (
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 9,
          to: (frame) => frame,
        ),
      ),
      isNull,
    );
  });

  test('a stretch of 1 moves nothing, and lands nothing to undo', () {
    keyed(TransformTrack.empty().copyWith(rotation: keys({0: 10, 8: 20})));
    pick(['rotation'], 0, 8);
    final undoable = s.canUndo;

    stretch([(anchor: 0, factor: 1)]);

    expect(rotation(), {0: 10, 8: 20});
    expect(s.dragPreview.value, isNull);
    expect(s.canUndo, undoable);
  });

  // graph-box-handles-more ⓐ — a box corner gone alone moves each key by
  // as much as it stood near it, so the move says where each lands.
  group('where each key lands is the landings\'', () {
    void land(List<Map<String, Map<int, int>>> steps) {
      expect(s.laneMove.beginLaneRangeMoveDrag(), isTrue);
      for (final step in steps) {
        s.laneMove.updateLaneRangeMoveDrag(frameDelta: 0, landings: step);
      }
      s.laneMove.endLaneRangeMoveDrag();
    }

    Map<int, double> opacity() => {
      for (final MapEntry(key: frame, value: key)
          in transform().opacity.keys.entries)
        frame: key.value,
    };

    test('each key goes where its lane\'s landing says — the same frame '
        'on another lane goes elsewhere, or stays', () {
      keyed(
        TransformTrack.empty().copyWith(
          rotation: keys({0: 10, 8: 20}),
          opacity: keys({0: 0.5, 8: 1}),
        ),
      );
      pick(['rotation', 'opacity'], 0, 8);

      land([
        {
          'rotation': {8: 12},
          'opacity': {0: 2},
        },
      ]);

      expect(rotation(), {0: 10, 12: 20});
      expect(opacity(), {2: 0.5, 8: 1});
    });

    test('the outline keeps its ends and holds every key landed past them',
        () {
      keyed(TransformTrack.empty().copyWith(rotation: keys({2: 10, 6: 20})));
      pick(['rotation'], 2, 6);

      land([
        {
          'rotation': {6: 9},
        },
      ]);

      final picked = s.laneRangeSelection.value!;
      expect((picked.startIndex, picked.endIndexExclusive), (2, 10));
    });

    test('a step that lands two keys of a lane on one frame is refused, and '
        'the step before it holds', () {
      keyed(TransformTrack.empty().copyWith(rotation: keys({0: 1, 4: 2})));
      pick(['rotation'], 0, 4);

      land([
        {
          'rotation': {4: 6},
        },
        {
          'rotation': {4: 0},
        },
      ]);

      expect(rotation(), {0: 1, 6: 2});
    });
  });
}
