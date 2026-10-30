import 'dart:ui' show Color;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart' show TwoScales;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId;
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart'
    show seSoundGroupLaneId;
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
  final grade = LayerEffect(
    id: const EffectId('grade'),
    kind: EffectKind.brightnessContrast,
    parameters: {
      'brightness': EffectParameter(
        track: PropertyTrack<double>().withKey(0, 0).withKey(8, 16),
      ),
      'contrast': EffectParameter(value: 4),
    },
  );
  final layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    transformTrack: track,
    effects: [grade],
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
      laneGroupKey(row.id, effectGroupLaneId(grade.id)),
      laneGroupKey(row.id, seNameTagGroupLaneId),
    },
    valueSourceAt: source ?? (frame) => (layer: row, frame: frame),
    poseCentre: canvas,
    hasPlugin: null,
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
      effectLaneId(grade.id, 'brightness'),
      effectLaneId(grade.id, 'contrast'),
      'anchor-point',
      'position',
      'scale',
      'rotation',
      'opacity',
    ], reason: '⛔전제: every lane of numbers draws');
    for (final lane in drawn) {
      for (var frame = 0; frame <= 10; frame += 1) {
        final numbers = lane.curve!.at(frame.toDouble());
        final label = lane.valueLabel!(frame);
        final printed = readoutParts(label);
        expect(
          [for (final number in numbers) columnValueText(number)],
          readsTurns(printed)
              // An angle prints its turns and degrees: the number they
              // come to.
              ? [columnValueText(columnValueOf(label)!)]
              : [for (final part in printed) part.number],
          reason: '${lane.laneId} at $frame',
        );
        expect(numbers, hasLength(lane.curve!.parts.length));
      }
    }
  });

  test('🚨on every frame, the canvas places the row by the numbers its '
      'lanes draw — it reads a frame where they read a time', () {
    final lanes = lanesOf(layer);
    for (var frame = 0; frame <= 10; frame += 1) {
      final pose = resolveLayerPoseAt(
        layer: layer,
        canvasSize: canvas,
        frameIndex: frame,
      )!;
      final anchor = resolveLayerAnchorPointAt(
        layer: layer,
        frameIndex: frame,
      )!;
      final opacity = resolveLayerEffectiveOpacityAt(
        layer: layer,
        frameIndex: frame,
      );
      final placed = {
        'anchor-point': [anchor.x, anchor.y],
        'position': [pose.center.x, pose.center.y],
        'scale': [pose.scale.x * 100, pose.scale.y * 100],
        'rotation': [pose.rotationDegrees],
        'opacity': [opacity * 100],
        effectLaneId(grade.id, 'brightness'): [
          effectParameterValueAt(layer.effects, grade.id, 'brightness', frame),
        ],
      };
      expect(
        {
          for (final laneId in placed.keys)
            laneId: laneOf(lanes, laneId).curve!.at(frame.toDouble()),
        },
        placed,
        reason: 'frame $frame',
      );
    }

    final camera = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 200, y: 150))
          .withKey(8, CanvasPoint(x: 260, y: 90)),
      scale: PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 1, y: 1))
          .withKey(8, CanvasPoint(x: 1.5, y: 1.5)),
      rotation: PropertyTrack<double>().withKey(0, 0).withKey(8, 20),
    );
    final cameraLanes = cameraPropertyLanes(
      Layer(
        id: const LayerId('camera'),
        name: 'Camera',
        frames: const [],
        kind: LayerKind.camera,
      ),
      camera,
      canvasSize: canvas,
    );
    for (var frame = 0; frame <= 10; frame += 1) {
      final shown = TransformPose.ofCamera(
        resolveCameraPoseAt(
          camera: CutCamera.fromTrack(camera),
          canvasSize: canvas,
          frameIndex: frame,
        ),
      );
      expect(
        {
          for (final laneId in ['position', 'scale', 'rotation'])
            laneId: laneOf(cameraLanes, laneId).curve!.at(frame.toDouble()),
        },
        {
          'position': [shown.center.x, shown.center.y],
          'scale': [shown.scale.x * 100],
          'rotation': [shown.rotationDegrees],
        },
        reason: 'the camera at $frame',
      );
    }
  });

  test('a lane\'s curve carries each of its keys\' two sides, by the frames '
      'its marks stand on — what a graph\'s handles stand for', () {
    final lanes = lanesOf(layer);
    const straight = (incoming: KeySide.linear, outgoing: KeySide.linear);
    expect(laneOf(lanes, 'position').curve!.sides, {
      0: straight,
      8: (incoming: const EaseSide(), outgoing: KeySide.linear),
    });
    expect(laneOf(lanes, effectLaneId(grade.id, 'brightness')).curve!.sides, {
      0: straight,
      8: straight,
    });
    expect(
      laneOf(lanes, effectLaneId(grade.id, 'contrast')).curve!.sides,
      isEmpty,
      reason: 'a value no key holds',
    );
    for (final lane in lanes) {
      if (lane.curve case final curve?) {
        expect(curve.sides.keys.toSet(), lane.keyedFrames.toSet());
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
    expect(rotation.valueLabel!(2), '0x+20.00°');
  });

  test('each number is drawn in its own colour — a point across and down, '
      'Scale\'s two, Rotation, Opacity, an effect\'s parameters in order', () {
    Map<String, List<Color>> partsOf(List<PropertyLaneRow> lanes) => {
      for (final lane in lanes)
        if (lane.curve case final curve?) lane.laneId: curve.parts,
    };
    const point = [LaneCurvePalette.across, LaneCurvePalette.down];
    expect(partsOf(lanesOf(layer)), {
      effectLaneId(grade.id, 'brightness'): [LaneCurvePalette.effectParameter(0)],
      effectLaneId(grade.id, 'contrast'): [LaneCurvePalette.effectParameter(1)],
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

  test('a header heads a graph where its lanes stand as one — Transform\'s, '
      'each effect\'s and an S row\'s 「오디오」 (I-140: its audio fx)', () {
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
        effectGroupLaneId(grade.id): true,
        transformGroupHeaderLane.laneId: true,
        seSoundGroupLaneId: true,
        seNameTagGroupLaneId: false,
      },
    );
    expect(
      transformPropertyLanes(track, scaleForm: const TwoScales()).first,
      isA<PropertyLaneRow>()
          .having((lane) => lane.isGroupHeader, 'a header', isTrue)
          .having((lane) => lane.headsAGraph, 'heads a graph', isTrue),
      reason: 'the header the Transform lanes are listed under says so too',
    );
  });
}
