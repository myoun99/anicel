import 'dart:ui' show Color;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-89 ③: a header graph draws a lane by the reading of its track its
/// value column prints ([PropertyLaneRow.curve]) — the same closure, at a
/// time between frames as well — so the line and the number beside it
/// cannot come to disagree.
void main() {
  const canvas = CanvasSize(width: 400, height: 300);
  final track = TransformTrack.empty().copyWith(
    anchorPoint: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 0, y: 0))
        .withKey(8, CanvasPoint(x: 40, y: -8)),
    position: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 100, y: 50))
        .withKey(8, CanvasPoint(x: 180, y: 10), incoming: const EaseSide()),
    scale: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 1, y: 1))
        .withKey(8, CanvasPoint(x: 2, y: 0.5)),
    rotation: PropertyTrack<double>().withKey(0, 0).withKey(8, 45),
    opacity: PropertyTrack<double>().withKey(0, 1).withKey(8, 0.25),
  );
  final blur = LayerEffect(
    id: const EffectId('blur'),
    kind: EffectKind.blur,
    parameters: {
      'blurX': EffectParameter(
        track: PropertyTrack<double>().withKey(0, 0).withKey(8, 16),
      ),
      'blurY': EffectParameter(value: 4),
    },
  );
  final layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    transformTrack: track,
    effects: [blur],
  );

  /// [row]'s lanes, every group open — read off [source] where one is
  /// given, else off the row itself.
  List<PropertyLaneRow> lanesOf(
    Layer row, {
    ({Layer layer, int frame}) Function(int frameIndex)? source,
  }) => propertyLanesForRow(
    layer: row,
    rows: [row],
    expandedGroupKeys: {
      laneGroupKey(row.id, transformGroupHeaderLane.laneId),
      laneGroupKey(row.id, effectGroupLaneId(blur.id)),
      laneGroupKey(row.id, seNameTagGroupLaneId),
    },
    valueSourceAt: source ?? (frame) => (layer: row, frame: frame),
    poseCentre: canvas,
  );

  PropertyLaneRow laneOf(List<PropertyLaneRow> lanes, String laneId) =>
      lanes.firstWhere((lane) => lane.laneId == laneId);

  test('🚨on every frame, a lane\'s curve holds the numbers its value '
      'column prints', () {
    final drawn = [
      for (final lane in lanesOf(layer))
        if (lane.curve != null) lane,
    ];
    expect([for (final lane in drawn) lane.laneId], [
      effectLaneId(blur.id, 'blurX'),
      effectLaneId(blur.id, 'blurY'),
      'anchor-point',
      'position',
      'scale',
      'rotation',
      'opacity',
    ], reason: '⛔전제: every lane of numbers draws');
    for (final lane in drawn) {
      for (var frame = 0; frame <= 10; frame += 1) {
        final numbers = lane.curve!.at(frame.toDouble());
        final printed = readoutParts(lane.valueLabel!(frame));
        expect(
          [for (final number in numbers) columnValueText(number)],
          [for (final part in printed) part.number],
          reason: '${lane.laneId} at $frame',
        );
        expect(numbers, hasLength(lane.curve!.parts.length));
      }
    }
  });

  test('between frames the curve runs on along the track', () {
    final position = laneOf(lanesOf(layer), 'position').curve!;
    final across = position.at(4.5).first;
    expect(across, greaterThan(position.at(4).first));
    expect(across, lessThan(position.at(5).first));
  });

  test('a projection moves a row\'s frames, never the time between them', () {
    // The row reads its values off another row ten frames on — a track's
    // SE row in a cut that starts at 10.
    final source = Layer(
      id: const LayerId('track'),
      name: 'T',
      frames: const [],
      transformTrack: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(10, 0).withKey(14, 40),
      ),
    );
    final rotation = laneOf(
      lanesOf(layer, source: (frame) => (layer: source, frame: frame + 10)),
      'rotation',
    );

    expect(rotation.curve!.at(2.5).single, closeTo(25, 1e-9));
    expect(rotation.valueLabel!(2), '20.00°');
  });

  test('each number is drawn in its own colour — a point across and down, '
      'Scale\'s two, Rotation, Opacity, an effect\'s parameters in order', () {
    Map<String, List<Color>> partsOf(List<PropertyLaneRow> lanes) => {
      for (final lane in lanes)
        if (lane.curve case final curve?) lane.laneId: curve.parts,
    };
    const point = [LaneCurvePalette.across, LaneCurvePalette.down];
    expect(partsOf(lanesOf(layer)), {
      effectLaneId(blur.id, 'blurX'): [LaneCurvePalette.effectParameter(0)],
      effectLaneId(blur.id, 'blurY'): [LaneCurvePalette.effectParameter(1)],
      'anchor-point': point,
      'position': point,
      'scale': [LaneCurvePalette.scale, LaneCurvePalette.scaleDown],
      'rotation': [LaneCurvePalette.rotation],
      'opacity': [LaneCurvePalette.opacity],
    });
    expect(
      LaneCurvePalette.effectParameter(1),
      isNot(LaneCurvePalette.effectParameter(0)),
    );

    final camera = cameraPropertyLanes(
      Layer(
        id: const LayerId('camera'),
        name: 'Camera',
        frames: const [],
        kind: LayerKind.camera,
      ),
      TransformTrack.empty(),
      canvasSize: canvas,
    );
    expect(
      partsOf(camera)['scale'],
      [LaneCurvePalette.scale],
      reason: 'a camera\'s zoom is one number',
    );
    expect(laneOf(camera, 'scale').curve!.at(3), [100]);
  });

  test('a header heads a graph where its lanes stand as one — Transform\'s '
      'and each effect\'s', () {
    final se = Layer(
      id: const LayerId('se'),
      name: 'SE',
      frames: const [],
      kind: LayerKind.se,
    );
    expect(
      {
        for (final lane in [...lanesOf(layer), ...lanesOf(se)])
          if (lane.isGroupHeader) lane.laneId: lane.headsAGraph,
      },
      {
        effectGroupLaneId(blur.id): true,
        transformGroupHeaderLane.laneId: true,
        seNameTagGroupLaneId: false,
      },
    );
  });
}
