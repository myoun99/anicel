import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_row_slice.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformPropertyLanes;

/// I-65 (유저 Q2): 「셀번호fx 자체적으로 위치/크기값 구현. 트랜스폼에 있는거처럼
/// 위치/비율 두개 키. 공용화된거 사용하면서」 — where a cel number stands its
/// letters is a transform's Position and Scale lanes under the effect's
/// header, read and edited by the transform's own verbs.
void main() {
  const id = EffectId('n');
  final position = effectLaneId(id, 'position');
  final scale = effectLaneId(id, 'scale');
  const paper = CanvasSize(width: 200, height: 100);

  LayerEffect number({Map<int, CanvasPoint> at = const {}}) => LayerEffect(
    id: id,
    kind: EffectKind.celNumber,
    stand: TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>(
        keys: {
          for (final MapEntry(key: frame, value: point) in at.entries)
            frame: PropertyKey(point),
        },
      ),
    ),
  );

  group('the rows', () {
    test('Position and Scale lead the parameters under the header', () {
      final rows = effectPropertyLanes([number()], isExpanded: (_) => true);

      expect(rows.first.isGroupHeader, isTrue);
      expect(rows.skip(1).map((row) => row.laneId), [
        position,
        scale,
        for (final spec in effectParametersOf(EffectKind.celNumber))
          effectLaneId(id, spec.id),
      ]);
      expect(effectLaneDisplayOrder(number()), [
        for (final row in rows.skip(1)) row.laneId,
      ]);
    });

    test('the header carries their keys in its union', () {
      final rows = effectPropertyLanes([
        number(at: {6: CanvasPoint(x: 1, y: 2)}),
      ], isExpanded: (_) => false);

      expect(rows.single.keyedFrames, {6});
    });

    test('they read where the number stands, as a layer\'s do', () {
      TransformPose pose(double _) => TransformPose(
        center: CanvasPoint(x: 30, y: 40),
        scaleX: 1.5,
        scaleY: 0.5,
      );
      final rows = effectPropertyLanes(
        [number()],
        isExpanded: (_) => true,
        standAt: (_, time) => pose(time),
      );
      final layers = transformPropertyLanes(
        TransformTrack.empty(),
        scaleForm: const TwoScales(),
        poseAt: pose,
      );
      String shown(List<PropertyLaneRow> of, String lane) =>
          of.singleWhere((row) => row.laneId == lane).valueLabel!(0);

      expect(shown(rows, position), shown(layers, 'position'));
      expect(shown(rows, scale), shown(layers, 'scale'));
    });

    test('an effect that draws no picture has no such rows', () {
      final blur = LayerEffect.defaults(id: id, kind: EffectKind.blur);
      final rows = effectPropertyLanes([blur], isExpanded: (_) => true);

      expect(rows.map((row) => row.laneId), isNot(contains(position)));
      expect(
        effectsWithLaneKeyToggled(
          [blur],
          laneId: position,
          frameIndex: 0,
          paper: paper,
        ),
        isNull,
      );
    });
  });

  group('the edits', () {
    test('the diamond freezes where it rests — the paper\'s middle', () {
      final keyed = effectsWithLaneKeyToggled(
        [number()],
        laneId: position,
        frameIndex: 4,
        paper: paper,
      )!;
      expect(
        keyed.single.stand.position.keyAt(4)!.value,
        CanvasPoint(x: 100, y: 50),
      );

      final unkeyed = effectsWithLaneKeyToggled(
        keyed,
        laneId: position,
        frameIndex: 4,
        paper: paper,
      )!;
      expect(unkeyed.single.stand.position.isEmpty, isTrue);
    });

    test('with no paper to rest on it keys nothing', () {
      expect(
        effectsWithLaneKeyToggled([number()], laneId: position, frameIndex: 4),
        isNull,
      );
    });

    test('a typed Position and Scale key at the playhead', () {
      final moved = effectsWithLaneValueEdited(
        [number()],
        laneId: position,
        frameIndex: 2,
        input: '30, 40',
        scaleLinked: false,
      )!;
      expect(
        moved.single.stand.position.keyAt(2)!.value,
        CanvasPoint(x: 30, y: 40),
      );

      final sized = effectsWithLaneValueEdited(
        moved,
        laneId: scale,
        frameIndex: 2,
        input: '150, 80%',
        scaleLinked: false,
      )!;
      expect(
        sized.single.stand.scale.keyAt(2)!.value,
        CanvasPoint(x: 1.5, y: 0.8),
      );
    });

    test('a linked Scale carries the box left as it was shown', () {
      final sized = effectsWithLaneValueEdited(
        [number()],
        laneId: scale,
        frameIndex: 0,
        input: '200, 100%',
        scaleLinked: true,
      )!;

      expect(
        sized.single.stand.scale.keyAt(0)!.value,
        CanvasPoint(x: 2, y: 2),
      );
    });

    test('the group reset puts a keyed stand back on the paper\'s middle', () {
      final reset = effectsWithGroupReset(
        [
          number(at: {3: CanvasPoint(x: 5, y: 5)}),
        ],
        laneId: effectGroupLaneId(id),
        frameIndexes: [3],
        paper: paper,
      )!;

      expect(
        reset.single.stand.position.keyAt(3)!.value,
        CanvasPoint(x: 100, y: 50),
      );
    });

    test('and leaves it as it is with no paper', () {
      expect(
        effectsWithGroupReset(
          [
            number(at: {3: CanvasPoint(x: 5, y: 5)}),
          ],
          laneId: effectGroupLaneId(id),
          frameIndexes: [3],
        ),
        isNull,
      );
    });

    test('its keys move through the lens, as a layer\'s Position does', () {
      final lens = effectLaneLens(position)!;
      final effects = [
        number(at: {3: CanvasPoint(x: 5, y: 5)}),
      ];

      expect(lens.keyFrames(effects), {3});
      expect(lens.keysOf(effects).keys, [3]);
      expect(lens.numberShown(5), isNull);

      final shifted = lens.update(
        effects,
        <U>(PropertyTrack<U> lane) =>
            PropertyTrack<U>(keys: {7: lane.keyAt(3)!}),
      )!;
      expect(
        shifted.single.stand.position.keyAt(7)!.value,
        CanvasPoint(x: 5, y: 5),
      );
      expect(effectLaneKeyFrames(shifted, effectGroupLaneId(id)), {7});
    });
  });

  test('no parameter of any kind is named as a stand lane is — the id '
      'alone tells them apart', () {
    for (final kind in EffectKind.values) {
      for (final spec in effectParametersOf(kind)) {
        expect(effectStandLanes, isNot(contains(spec.id)), reason: kind.name);
      }
    }
    expect(effectLaneWalksAPath(position), isTrue);
    expect(effectLaneWalksAPath(scale), isFalse);
    expect(effectLaneWalksAPath(effectLaneId(id, 'red')), isFalse);
  });

  group('the keys', () {
    test('a stand Position key between two may rove, as a layer\'s may', () {
      final effects = [
        number(
          at: {
            0: CanvasPoint(x: 0, y: 0),
            4: CanvasPoint(x: 4, y: 4),
            8: CanvasPoint(x: 8, y: 8),
          },
        ),
      ];

      expect(effectLaneKeyCanRove(effects, position, 4), isTrue);
      expect(effectLaneKeyCanRove(effects, position, 0), isFalse);
      expect(effectLaneKeyCanRove(effects, scale, 4), isFalse);
    });

    test('a parameter\'s never may', () {
      final red = effectLaneId(id, 'red');
      final keyed = [0, 4, 8].fold(
        [number()],
        (effects, frame) => effectsWithLaneValueEdited(
          effects,
          laneId: red,
          frameIndex: frame,
          input: '$frame',
          scaleLinked: false,
        )!,
      );

      expect(keyed.single.parameterOf('red').track.keys, hasLength(3));
      expect(effectLaneKeyCanRove(keyed, red, 4), isFalse);
    });

    test('the key window\'s path and roving reach a stand Position', () {
      final effects = [
        number(
          at: {
            0: CanvasPoint(x: 0, y: 0),
            4: CanvasPoint(x: 4, y: 4),
            8: CanvasPoint(x: 8, y: 8),
          },
        ),
      ];

      final written = effectsWithLaneKeysWritten(
        effects,
        laneId: position,
        frames: {4},
        pick: const KeyTypePick(roving: true),
      )!;
      expect(written.single.stand.position.keyAt(4)!.roving, isTrue);
    });
  });

  test('a stand lane\'s row is its own part of the layer', () {
    final row = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: const [],
      effects: [number()],
    );
    Layer edited(LayerEffect Function(LayerEffect effect) edit) =>
        row.copyWith(effects: [edit(row.effects.single)]);
    final recoloured = edited(
      (effect) => effect.withParameter(
        'red',
        effect.parameterOf('red').copyWith(value: 9),
      ),
    );
    final moved = edited(
      (effect) => effect.copyWith(
        stand: effect.stand.copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 1, y: 1),
          ),
        ),
      ),
    );

    bool kept(Layer after, String lane) =>
        identical(laneRowSlice(row, lane), laneRowSlice(after, lane));

    expect(kept(recoloured, position), isTrue, reason: 'a colour edit');
    expect(kept(moved, scale), isTrue, reason: 'a Position edit, on Scale');
    expect(kept(moved, position), isFalse, reason: 'a Position edit');
  });
}
