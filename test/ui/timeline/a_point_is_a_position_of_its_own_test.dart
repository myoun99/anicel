import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_row_slice.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformTrackWithPositionDragged;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformPropertyLanes;
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';

/// 🗣️I-132-Q12 b (유저 2026-10-28): 「효과 매개변수에 「점」 종류를 새로」 —
/// a radial blur's centre is a point of the effect's own, and a point is a
/// transform's Position of its own: its lane is the Position row, its keys
/// key, take a value, reset, walk a path, rove and name by the transform's
/// own verbs — the ones a cel number's stand goes by (I-65-Q2
/// 「공용화된거 사용하면서」) — and the canvas places it with a cross.
void main() {
  const id = EffectId('r');
  final center = effectLaneId(id, 'center');
  const paper = CanvasSize(width: 200, height: 100);

  LayerEffect radial({
    Map<int, (CanvasPoint, String?)> at = const {},
    bool enabled = true,
  }) => LayerEffect(
    id: id,
    kind: EffectKind.radialBlur,
    enabled: enabled,
    points: {
      'center': TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>(
          keys: {
            for (final MapEntry(key: frame, value: (point, name))
                in at.entries)
              frame: PropertyKey(point, name: name),
          },
        ),
      ),
    },
  );

  group('the model', () {
    test('its centre is a point, and no number of its parameters', () {
      final fresh = LayerEffect.defaults(id: id, kind: EffectKind.radialBlur);

      expect(
        EffectKind.radialBlur.parameterSpec('center')!.unit,
        EffectParameterUnit.point,
      );
      expect(fresh.points.keys, ['center']);
      expect(fresh.points['center']!.isEmpty, isTrue);
      expect(fresh.parameters.keys, isNot(contains('center')));
      expect(fresh.lanes, ['amount', 'center', 'type', 'antialiasing']);
    });

    test('its keys round-trip, and an unkeyed one writes nothing', () {
      final keyed = radial(at: {3: (CanvasPoint(x: 10, y: 20), 'A')});

      expect(LayerEffect.fromJson(keyed.toJson()), keyed);
      expect(radial().toJson().containsKey('points'), isFalse);
      expect(LayerEffect.fromJson(radial().toJson()), radial());
    });

    test('its lane is a Position — the stand\'s one question answers both',
        () {
      final point = radial(at: {0: (CanvasPoint(x: 1, y: 2), null)});
      final number = LayerEffect.defaults(id: id, kind: EffectKind.celNumber);

      expect(point.transformLaneAt('center')!.lane, 'position');
      expect(
        identical(point.transformLaneAt('center')!.keys, point.points['center']),
        isTrue,
      );
      expect(point.transformLaneAt('amount'), isNull);
      expect(point.transformLaneAt('position'), isNull, reason: 'no stand');
      expect(number.transformLaneAt('scale')!.lane, 'scale');
      expect(number.transformLaneAt('center'), isNull);
    });

    test('sampled, it is where its keys put it — unkeyed, null, which the '
        'paper reads as its middle', () {
      ResolvedLayerEffect at(LayerEffect effect, int frame) =>
          resolveLayerEffectsAt(
            effects: [effect.withParameter('amount', EffectParameter(value: 5))],
            frameIndex: frame,
          ).single;

      expect(at(radial(), 4).points['center'], isNull);
      expect(
        effectPointOnPaper(at(radial(), 4).points['center'], paper),
        CanvasPoint(x: 100, y: 50),
      );
      final walked = radial(
        at: {
          0: (CanvasPoint(x: 0, y: 10), null),
          8: (CanvasPoint(x: 80, y: 10), null),
        },
      );
      expect(at(walked, 4).points['center'], CanvasPoint(x: 40, y: 10));
      expect(at(walked, 4), isNot(at(walked, 5)), reason: 'a sample says it');
    });
  });

  group('the rows', () {
    test('Center stands between Amount and the menus, a Position named as '
        'its effect names it', () {
      final rows = effectPropertyLanes([radial()], isExpanded: (_) => true);

      expect(rows.skip(1).map((row) => row.laneId), [
        effectLaneId(id, 'amount'),
        center,
        effectLaneId(id, 'type'),
        effectLaneId(id, 'antialiasing'),
      ]);
      final row = rows.singleWhere((it) => it.laneId == center);
      expect(row.label, AppText.strings.effectParameterName('center', 'Center'));
      expect(row.valueKind, PropertyLaneValueKind.number);
    });

    test('it reads where it stands as a layer\'s Position reads', () {
      TransformPose pose(double _) =>
          TransformPose(center: CanvasPoint(x: 30, y: 40));
      final rows = effectPropertyLanes(
        [radial()],
        isExpanded: (_) => true,
        standAt: (_, lane, time) {
          expect(lane, 'center');
          return pose(time);
        },
      );
      final layers = transformPropertyLanes(
        TransformTrack.empty(),
        scaleForm: const TwoScales(),
        poseAt: pose,
      );
      String shown(List<PropertyLaneRow> of, String lane) =>
          of.singleWhere((row) => row.laneId == lane).valueLabel!(0);

      expect(shown(rows, center), shown(layers, 'position'));
    });

    test('a row\'s lanes read it at rest as its own Position — the paper\'s '
        'middle', () {
      final row = Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: const [],
        effects: [radial()],
      );
      final lanes = propertyLanesForRow(
        layer: row,
        rows: [row],
        expandedGroupKeys: {
          laneGroupKey(row.id, effectGroupLaneId(id)),
          laneGroupKey(row.id, transformGroupHeaderLane.laneId),
        },
        valueSourceAt: (frame) => (layer: row, frame: frame),
        poseCentre: paper,
      );
      String shown(String lane) =>
          lanes.singleWhere((it) => it.laneId == lane).valueLabel!(0);

      expect(shown(center), shown('position'));
    });

    test('the header carries its keys in its union', () {
      final rows = effectPropertyLanes([
        radial(at: {6: (CanvasPoint(x: 1, y: 2), null)}),
      ], isExpanded: (_) => false);

      expect(rows.single.keyedFrames, {6});
    });
  });

  group('the edits', () {
    test('the diamond freezes where it rests — the paper\'s middle', () {
      final keyed = effectsWithLaneKeyToggled(
        [radial()],
        laneId: center,
        frameIndex: 4,
        paper: paper,
      )!;
      expect(
        keyed.single.points['center']!.position.keyAt(4)!.value,
        CanvasPoint(x: 100, y: 50),
      );
      expect(
        effectsWithLaneKeyToggled(
          keyed,
          laneId: center,
          frameIndex: 4,
          paper: paper,
        )!.single.points['center']!.isEmpty,
        isTrue,
      );
    });

    test('a typed point keys at the playhead', () {
      final moved = effectsWithLaneValueEdited(
        [radial()],
        laneId: center,
        frameIndex: 2,
        input: '30, 40',
        scaleLinked: false,
      )!;

      expect(
        moved.single.points['center']!.position.keyAt(2)!.value,
        CanvasPoint(x: 30, y: 40),
      );
      expect(moved.single.stand.isEmpty, isTrue, reason: 'not a stand');
    });

    test('the group reset puts it back on the paper\'s middle', () {
      final reset = effectsWithGroupReset(
        [
          radial(at: {3: (CanvasPoint(x: 5, y: 5), null)}),
        ],
        laneId: effectGroupLaneId(id),
        frameIndexes: [3],
        paper: paper,
      )!;

      expect(
        reset.single.points['center']!.position.keyAt(3)!.value,
        CanvasPoint(x: 100, y: 50),
      );
    });

    test('its keys move through the lens, and show no number', () {
      final lens = effectLaneLens(center)!;
      final effects = [
        radial(at: {3: (CanvasPoint(x: 5, y: 5), null)}),
      ];

      expect(lens.keysOf(effects).keys, [3]);
      expect(lens.numberShown(effects, 5), isNull);
      expect(lens.numberHeld(effects, 5), isNull);
      final shifted = lens.update(
        effects,
        <U>(PropertyTrack<U> lane) =>
            PropertyTrack<U>(keys: {7: lane.keyAt(3)!}),
      )!;
      expect(
        shifted.single.points['center']!.position.keyAt(7)!.value,
        CanvasPoint(x: 5, y: 5),
      );
    });

    test('it walks a path, asked of its effect, and a key between two '
        'may rove', () {
      final effects = [
        radial(
          at: {
            0: (CanvasPoint(x: 0, y: 0), null),
            4: (CanvasPoint(x: 4, y: 4), null),
            8: (CanvasPoint(x: 8, y: 8), null),
          },
        ),
      ];

      expect(effectLaneWalksAPath(effects, center), isTrue);
      expect(
        effectLaneWalksAPath(effects, effectLaneId(id, 'amount')),
        isFalse,
      );
      expect(effectLaneKeyCanRove(effects, center, 4), isTrue);
      expect(effectLaneKeyCanRove(effects, center, 0), isFalse);
      final written = effectsWithLaneKeysWritten(
        effects,
        laneId: center,
        frames: {4},
        pick: const KeyTypePick(roving: true),
      )!;
      expect(written.single.points['center']!.position.keyAt(4)!.roving, isTrue);
    });

    test('a named key there links by name, as a Position\'s does', () {
      final changes = namedEffectKeyChanges(
        [
          radial(at: {0: (CanvasPoint(x: 1, y: 1), 'A')}),
        ],
        [
          radial(at: {0: (CanvasPoint(x: 5, y: 6), 'A')}),
        ],
      );
      expect(changes.single.lane, 'center');

      final sibling = effectsWithNamedValues([
        radial(
          at: {
            3: (CanvasPoint(x: 1, y: 1), 'A'),
            7: (CanvasPoint(x: 2, y: 2), null),
          },
        ),
      ], changes).single.points['center']!.position;
      expect(sibling.keyAt(3)!.value, CanvasPoint(x: 5, y: 6));
      expect(sibling.keyAt(7)!.value, CanvasPoint(x: 2, y: 2));
    });

    test('its row is its own part of the layer', () {
      final row = Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: const [],
        effects: [radial()],
      );
      final moved = row.copyWith(
        effects: [
          effectsWithLaneValueEdited(
            row.effects,
            laneId: center,
            frameIndex: 0,
            input: '1, 1',
            scaleLinked: false,
          )!.single,
        ],
      );
      bool kept(String lane) =>
          identical(laneRowSlice(row, lane), laneRowSlice(moved, lane));

      expect(kept(center), isFalse);
      expect(kept(effectLaneId(id, 'amount')), isTrue);
    });
  });

  group('the canvas', () {
    test('its lane and its header declare its cross; a number of it none', () {
      expect(effectBoxedOn([radial()], center), (
        effect: radial(),
        lane: 'center',
      ));
      expect(effectBoxedOn([radial()], effectGroupLaneId(id))?.lane, 'center');
      expect(effectBoxedOn([radial()], effectLaneId(id, 'amount')), isNull);
      expect(effectBoxedOn([radial(enabled: false)], center), isNull);
    });

    test('a cel number\'s header still declares its stand', () {
      final number = LayerEffect.defaults(id: id, kind: EffectKind.celNumber);

      expect(effectBoxedOn([number], effectGroupLaneId(id))?.lane, 'position');
      expect(effectBoxedOn([number], effectLaneId(id, 'ink')), isNull);
    });

    test('the cross\'s drag keys the point, the lane\'s own keys', () {
      final moved = effectsWithTransformKeysEdited(
        [radial()],
        center,
        (keys) => transformTrackWithPositionDragged(
          keys,
          frameIndex: 5,
          position: CanvasPoint(x: 12, y: 34),
        ),
      )!;

      expect(
        moved.single.points['center']!.position.keyAt(5)!.value,
        CanvasPoint(x: 12, y: 34),
      );
      expect(
        effectsWithTransformKeysEdited(
          [radial()],
          effectLaneId(id, 'amount'),
          (keys) => keys,
        ),
        isNull,
      );
    });
  });

  // I-132: a plugin's ids are its own — one may be an id of the app's of
  // another unit, so a lane is what its effect says, never its id.
  test('a plugin\'s number named as the app\'s point is a number, and its '
      'point named as the app\'s number walks a path', () {
    final plugin = FxPluginDescription.fromJson({
      'spec': 1,
      'id': 'com.example.swap',
      'name': 'Swap',
      'vendor': 'Example',
      'version': '1',
      'can': ['cpu'],
      'params': [
        {
          'id': 'center',
          'kind': 'number',
          'label': 'Centre',
          'default': 0,
          'min': 0,
          'max': 10,
        },
        {'id': 'amount', 'kind': 'point', 'label': 'Amount'},
      ],
    })!;
    final effects = [
      LayerEffect.defaults(id: id, kind: EffectKind.plugin, plugin: plugin),
    ];
    final number = effectLaneId(id, 'center');
    final point = effectLaneId(id, 'amount');

    expect(effectLaneWalksAPath(effects, number), isFalse);
    expect(effectLaneLens(number)!.numberShown(effects, 5), 5);
    expect(effectLaneLens(number)!.numberHeld(effects, 50), 10);
    expect(effectLaneWalksAPath(effects, point), isTrue);
    expect(effectLaneLens(point)!.numberShown(effects, 5), isNull);
    expect(effectLaneLens(point)!.numberHeld(effects, 5), isNull);
  });
}
