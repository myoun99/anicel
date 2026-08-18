import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_content_translation.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// D5 (R7): the model half of a canvas resize — everything stored in
/// canvas coordinates moves by the anchor's content offset, and nothing
/// else changes (zoom/scale/rotation are a crop's invariants).
void main() {
  test('camera keyframe centres move; zoom and rotation do not', () {
    final camera = CutCamera(
      keyframes: {
        0: CameraPose(
          center: CanvasPoint(x: 100, y: 50),
          zoom: 1.5,
          rotationDegrees: 12,
        ),
        8: CameraPose(center: CanvasPoint(x: 300, y: 200)),
      },
    );

    final moved = translateCutCamera(camera, -40, 25);

    expect(moved.keyframeAt(0)!.center.x, 60);
    expect(moved.keyframeAt(0)!.center.y, 75);
    expect(moved.keyframeAt(0)!.zoom, 1.5);
    expect(moved.keyframeAt(0)!.rotationDegrees, 12);
    expect(moved.keyframeAt(8)!.center.x, 260);
    expect(moved.keyframeAt(8)!.center.y, 225);
  });

  test('an empty camera returns identically — the default pose recomputes '
      'the canvas centre itself', () {
    final camera = CutCamera.empty();
    expect(identical(translateCutCamera(camera, 10, 10), camera), isTrue);
  });

  test('guides move: symmetry axis origin, perspective eye level, placed '
      'vanishing points and line-derived points — directions stay', () {
    final guides = CutGuides(
      guides: [
        DrawingGuide(
          id: const GuideId('sym'),
          name: 'Axis',
          shape: SymmetryShape(
            axis: GuideAxis(
              origin: CanvasPoint(x: 10, y: 20),
              angleDegrees: 30,
            ),
          ),
        ),
        DrawingGuide(
          id: const GuideId('per'),
          name: 'Perspective',
          shape: PerspectiveShape(
            vanishingPoints: [
              VanishingPointAt(CanvasPoint(x: 5, y: 6)),
              VanishingPointTowards(dx: 0, dy: 1),
              VanishingPointFromLines(
                GuideLine(a: CanvasPoint(x: 1, y: 2), b: CanvasPoint(x: 3, y: 4)),
                GuideLine(a: CanvasPoint(x: 5, y: 6), b: CanvasPoint(x: 7, y: 8)),
              ),
            ],
            eyeLevel: GuideAxis(
              origin: CanvasPoint(x: 100, y: 200),
              angleDegrees: 0,
            ),
          ),
        ),
      ],
    );

    final moved = translateCutGuides(guides, 7, -3);

    final sym = moved.guides.first.shape as SymmetryShape;
    expect(sym.axis.origin.x, 17);
    expect(sym.axis.origin.y, 17);
    expect(sym.axis.angleDegrees, 30);

    final per = moved.guides.last.shape as PerspectiveShape;
    expect(per.eyeLevel.origin.x, 107);
    expect(per.eyeLevel.origin.y, 197);
    final at = per.vanishingPoints[0] as VanishingPointAt;
    expect(at.point.x, 12);
    expect(at.point.y, 3);
    expect(
      per.vanishingPoints[1],
      isA<VanishingPointTowards>(),
      reason: 'a direction is a vector, not a place',
    );
    final lines = per.vanishingPoints[2] as VanishingPointFromLines;
    expect(lines.first.a.x, 8);
    expect(lines.first.b.y, 1);
    expect(lines.second.a.x, 12);
  });

  test('layer transform: position keys and EXPLICIT anchor keys move; a '
      'null (unkeyed) anchor stays null', () {
    final keyed = Layer(
      id: const LayerId('keyed'),
      name: 'K',
      frames: const [],
      timeline: const {},
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {0: PropertyKey(CanvasPoint(x: 40, y: 50))},
        ),
        anchorPoint: PropertyTrack(
          keys: {0: PropertyKey(CanvasPoint(x: 12, y: 13))},
        ),
      ),
    );

    final moved = translateLayerTransform(keyed, 5, 6);
    expect(moved.transformTrack.position.keyAt(0)!.value.x, 45);
    expect(moved.transformTrack.position.keyAt(0)!.value.y, 56);
    expect(moved.transformTrack.anchorPoint.keyAt(0)!.value.x, 17);
    expect(moved.transformTrack.anchorPoint.keyAt(0)!.value.y, 19);

    final unkeyed = Layer(
      id: const LayerId('unkeyed'),
      name: 'U',
      frames: const [],
      timeline: const {},
    );
    expect(
      identical(translateLayerTransform(unkeyed, 5, 6), unkeyed),
      isTrue,
      reason: 'no canvas-coordinate keys = nothing to move',
    );
  });

  test('a zero offset is identity for the whole cut model', () {
    final camera = CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 1, y: 2))},
    );
    expect(identical(translateCutCamera(camera, 0, 0), camera), isTrue);
  });
}
