import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId, effectPropertyLanes;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️A GROUP READ BY BLOCKS PRINTS WHAT THE CANVAS SHOWS, AND DRAWS ITS KEYS
/// (I-120-Q12 a + 「값 칸 숫자도 대응하도록 해서 캔버스랑 같도록」): the value
/// column reads the head of the block a frame shows, the header graph's line
/// stays the keys' curve. And a group wears the basis chip only on a row
/// with blocks of its own (I-120-Q9).
void main() {
  // A 0..3 · B 4..7 · C 8..11.
  final blocks = {
    0: const TimelineExposure.drawing(FrameId('a'), length: 4),
    4: const TimelineExposure.drawing(FrameId('b'), length: 4),
    8: const TimelineExposure.drawing(FrameId('c'), length: 4),
  };
  const blurId = EffectId('e-blur');

  Layer row({
    LayerKind kind = LayerKind.animation,
    FxBasis basis = FxBasis.frame,
  }) => Layer(
    id: const LayerId('row'),
    name: 'row',
    kind: kind,
    frames: const [],
    timeline: SplayTreeMap.of(blocks),
    transformBasis: basis,
    transformTrack: TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>(
        keys: {
          0: PropertyKey<CanvasPoint>(CanvasPoint(x: 0, y: 0)),
          12: PropertyKey<CanvasPoint>(CanvasPoint(x: 120, y: 0)),
        },
      ),
    ),
    effects: [
      LayerEffect(
        id: blurId,
        kind: EffectKind.blur,
        basis: basis,
        parameters: {
          'blurriness': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                12: const PropertyKey<double>(12),
              },
            ),
          ),
        },
      ),
    ],
  );

  List<PropertyLaneRow> lanesOf(Layer layer) => propertyLanesForRow(
    layer: layer,
    rows: [layer],
    expandedGroupKeys: {
      laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
      laneGroupKey(layer.id, effectGroupLaneId(blurId)),
    },
    valueSourceAt: (frame) => (layer: layer, frame: frame),
    poseCentre: const CanvasSize(width: 400, height: 300),
    hasPlugin: null,
  );

  PropertyLaneRow lane(List<PropertyLaneRow> lanes, String id) =>
      lanes.singleWhere((it) => it.laneId == id);

  final blurLane = effectLaneId(blurId, 'blurriness');

  group('the value column', () {
    test('on the frame prints each frame\'s own value', () {
      final lanes = lanesOf(row());
      expect(
        lane(lanes, blurLane).valueLabel!(6),
        isNot(lane(lanes, blurLane).valueLabel!(4)),
      );
      expect(
        lane(lanes, 'position').valueLabel!(6),
        isNot(lane(lanes, 'position').valueLabel!(4)),
      );
    });

    test('on the block prints the head\'s — the value the canvas shows', () {
      final frames = lanesOf(row());
      final steps = lanesOf(row(basis: FxBasis.block));
      for (final id in [blurLane, 'position']) {
        expect(
          lane(steps, id).valueLabel!(6),
          lane(frames, id).valueLabel!(4),
          reason: '$id: frame 6 shows block B, whose head is frame 4',
        );
        expect(
          lane(steps, id).valueLabel!(11),
          lane(frames, id).valueLabel!(8),
          reason: '$id: frame 11 shows block C',
        );
      }
    });
  });

  test('the line stays the keys\' curve on the block', () {
    final frames = lanesOf(row());
    final steps = lanesOf(row(basis: FxBasis.block));
    for (final id in [blurLane, 'position']) {
      for (final time in [4.0, 6.0, 6.5]) {
        expect(
          lane(steps, id).curve!.at(time),
          lane(frames, id).curve!.at(time),
          reason: '$id at $time',
        );
      }
    }
  });

  group('the basis chip', () {
    test('a row with blocks wears its groups\' bases', () {
      final lanes = lanesOf(row(basis: FxBasis.block));
      expect(
        lane(lanes, transformGroupHeaderLane.laneId).groupBasis,
        FxBasis.block,
      );
      expect(lane(lanes, effectGroupLaneId(blurId)).groupBasis, FxBasis.block);
    });

    test('a folder and an adjustment row wear none — every frame is read '
        '(I-120-Q9)', () {
      for (final kind in [LayerKind.folder, LayerKind.adjustment]) {
        final lanes = lanesOf(row(kind: kind));
        for (final header in lanes.where((it) => it.isGroupHeader)) {
          expect(header.groupBasis, isNull, reason: '$kind ${header.laneId}');
        }
      }
    });

    test('a chain asked of no row — a track\'s — wears none', () {
      final headers = effectPropertyLanes(
        row().effects,
        isExpanded: (_) => false,
      );
      expect(headers.single.groupBasis, isNull);
    });
  });
}
