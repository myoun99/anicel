import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_content_translation.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

const _canvas = CanvasSize(width: 1920, height: 1080);

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

    final moved = translateCutCamera(
      camera,
      -40,
      25,
      from: _canvas,
      centreDx: -40,
      centreDy: 25,
    );

    expect(moved.keyframeAt(0)!.center.x, 60);
    expect(moved.keyframeAt(0)!.center.y, 75);
    expect(moved.keyframeAt(0)!.zoom, 1.5);
    expect(moved.keyframeAt(0)!.rotationDegrees, 12);
    expect(moved.keyframeAt(8)!.center.x, 260);
    expect(moved.keyframeAt(8)!.center.y, 225);
  });

  test('an empty camera on a resize that moves the centre with the content '
      'returns identically — the default pose recomputes the same place', () {
    final camera = CutCamera.empty();
    expect(
      identical(
        translateCutCamera(
          camera,
          10,
          10,
          from: _canvas,
          centreDx: 10,
          centreDy: 10,
        ),
        camera,
      ),
      isTrue,
    );
  });

  // F-362: off the centre anchor the canvas centre moves by another offset
  // than the content, and an unkeyed camera re-read it — it left its picture.
  test('an unkeyed camera off the centre anchor is keyed where it stood and '
      'moves with the content', () {
    final moved = translateCutCamera(
      CutCamera.empty(),
      0,
      0,
      from: _canvas,
      centreDx: 100,
      centreDy: 50,
    );

    expect(moved.track.position.keyAt(0)!.value, CanvasPoint(x: 960, y: 540));
    expect(moved.track.position.keys.length, 1);
    expect(moved.track.scale.isEmpty, isTrue);
    expect(moved.track.rotation.isEmpty, isTrue);
  });

  test('a camera keyed on other lanes alone keeps them and gains only the '
      'position it stood at, moved with the content', () {
    final camera = CutCamera.fromTrack(
      TransformTrack.empty().copyWith(
        rotation: PropertyTrack(
          keys: {3: const PropertyKey(10.0), 9: const PropertyKey(40.0)},
        ),
      ),
    );

    final moved = translateCutCamera(
      camera,
      -200,
      -100,
      from: _canvas,
      centreDx: -100,
      centreDy: -50,
    );

    expect(moved.track.position.keyAt(0)!.value, CanvasPoint(x: 760, y: 440));
    expect(moved.track.rotation, camera.track.rotation);
  });

  test('a centre resize by an odd size keys the camera on the content '
      'rounded half a pixel off the centre', () {
    final moved = translateCutCamera(
      CutCamera.empty(),
      1,
      0,
      from: _canvas,
      centreDx: 0.5,
      centreDy: 0,
    );

    expect(moved.track.position.keyAt(0)!.value, CanvasPoint(x: 961, y: 540));
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

  test('layer transform: EXPLICIT anchors move with the content offset '
      '(position too); a NULL anchor moves its position by Δcentre — the '
      'pose subtracts the canvas centre, so that is what keeps the '
      'render pinned to the picture', () {
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

    final moved = translateLayerForResize(
      keyed,
      from: _canvas,
      dx: 5,
      dy: 6,
      centreDx: 99,
      centreDy: 99,
    );
    expect(moved.transformTrack.position.keyAt(0)!.value.x, 45);
    expect(moved.transformTrack.position.keyAt(0)!.value.y, 56);
    expect(moved.transformTrack.anchorPoint.keyAt(0)!.value.x, 17);
    expect(moved.transformTrack.anchorPoint.keyAt(0)!.value.y, 19);

    // Null anchor + position keys: a topLeft EXTENSION (content offset
    // 0) still moves the implicit anchor — the canvas centre — so the
    // position keys must follow Δcentre or the layer visibly jumps.
    final nullAnchored = Layer(
      id: const LayerId('null-anchored'),
      name: 'N',
      frames: const [],
      timeline: const {},
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {0: PropertyKey(CanvasPoint(x: 40, y: 50))},
        ),
      ),
    );
    final followed = translateLayerForResize(
      nullAnchored,
      from: _canvas,
      dx: 0,
      dy: 0,
      centreDx: 200,
      centreDy: 0,
    );
    expect(followed.transformTrack.position.keyAt(0)!.value.x, 240);
    expect(followed.transformTrack.position.keyAt(0)!.value.y, 50);
    expect(followed.transformTrack.anchorPoint.isEmpty, isTrue);

    final unkeyed = Layer(
      id: const LayerId('unkeyed'),
      name: 'U',
      frames: const [],
      timeline: const {},
    );
    expect(
      identical(
        translateLayerForResize(
          unkeyed,
          from: _canvas,
          dx: 5,
          dy: 6,
          centreDx: 3,
          centreDy: 3,
        ),
        unkeyed,
      ),
      isTrue,
      reason: 'no canvas-coordinate keys = nothing to move',
    );
  });

  // F-362: an explicit anchor moves by the content offset, and an UNKEYED
  // position read the canvas centre — which walked by Δcentre instead.
  test('an unkeyed position under a keyed anchor is keyed where it stood '
      'and moves with the content', () {
    final anchored = Layer(
      id: const LayerId('anchored'),
      name: 'A',
      frames: const [],
      timeline: const {},
      transformTrack: TransformTrack.empty().copyWith(
        anchorPoint: PropertyTrack(
          keys: {0: PropertyKey(CanvasPoint(x: 12, y: 13))},
        ),
      ),
    );

    final moved = translateLayerForResize(
      anchored,
      from: _canvas,
      dx: 5,
      dy: 6,
      centreDx: 99,
      centreDy: 99,
    );

    expect(
      moved.transformTrack.position.keyAt(0)!.value,
      CanvasPoint(x: 965, y: 546),
    );
    expect(moved.transformTrack.position.keys.length, 1);
    expect(
      moved.transformTrack.anchorPoint.keyAt(0)!.value,
      CanvasPoint(x: 17, y: 19),
    );
  });

  // I-68 (유저 2026-10-10 「캔버스 크기 변경 … 가」 — 기준점대로): where a
  // reference's picture stands is a place on the canvas, like a camera's
  // centre, so it moves by the CONTENT offset — never by Δcentre, which a
  // null anchor's position follows — and nothing else of its pose moves.
  test('a reference\'s pose moves by the content offset, its scale and turn '
      'untouched — its row\'s own empty transform as it was', () {
    final pose = TransformPose(
      center: CanvasPoint(x: 1170, y: 827),
      scaleX: 0.5,
      scaleY: 2,
      rotationDegrees: 30,
    );
    final reference = Layer(
      id: const LayerId('paper'),
      name: 'P',
      frames: const [],
      timeline: const {},
      mediaReference: MediaReference(
        assetPath: '/paper.png',
        pose: pose,
        pictureSize: const CanvasSize(width: 100, height: 60),
      ),
    );

    final moved = translateLayerForResize(
      reference,
      from: _canvas,
      dx: 600,
      dy: -40,
      centreDx: 300,
      centreDy: -20,
    );

    expect(
      moved.mediaReference!.pose,
      pose.copyWith(center: CanvasPoint(x: 1770, y: 787)),
    );
    expect(moved.mediaReference!.assetPath, '/paper.png');
    expect(
      moved.mediaReference!.pictureSize,
      const CanvasSize(width: 100, height: 60),
    );
    expect(moved.transformTrack.position.isEmpty, isTrue);
    expect(moved.transformTrack.anchorPoint.isEmpty, isTrue);
  });

  // F-374: the reference fx's keys and where its file is laid stand on the
  // same canvas as its pose, so they move by the same content offset.
  test('a reference\'s fx position keys and where its file is laid move by '
      'the content offset too — its turn keys untouched', () {
    final pose = TransformPose(center: CanvasPoint(x: 1170, y: 827));
    final fx = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 1170, y: 827))
          .withKey(10, CanvasPoint(x: 1370, y: 827)),
      rotation: PropertyTrack<double>().withKey(10, 30),
    );
    final reference = Layer(
      id: const LayerId('paper'),
      name: 'P',
      frames: const [],
      timeline: const {},
      mediaReference: MediaReference(
        assetPath: '/paper.png',
        pose: pose,
        pictureSize: const CanvasSize(width: 100, height: 60),
        fx: fx,
        laid: TransformPose(center: CanvasPoint(x: 1370, y: 827)),
      ),
    );

    final moved = translateLayerForResize(
      reference,
      from: _canvas,
      dx: 600,
      dy: -40,
      centreDx: 300,
      centreDy: -20,
    ).mediaReference!;

    expect(
      moved.fx.position.keys.map((frame, key) => MapEntry(frame, key.value)),
      {0: CanvasPoint(x: 1770, y: 787), 10: CanvasPoint(x: 1970, y: 787)},
    );
    expect(moved.fx.rotation, fx.rotation);
    expect(moved.laid, TransformPose(center: CanvasPoint(x: 1970, y: 787)));
  });

  test('camera translation goes through the LANES: hold interpolation, '
      'key names and a lone scale key all survive', () {
    final camera = CutCamera.fromTrack(
      TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {
            0: PropertyKey(
              CanvasPoint(x: 100, y: 50),
              outgoing: KeyExit.hold,
              name: 'A',
            ),
            8: PropertyKey(CanvasPoint(x: 300, y: 200)),
          },
        ),
        scale: PropertyTrack(keys: {4: PropertyKey(uniformScale(1.5))}),
      ),
    );

    final moved = translateCutCamera(
      camera,
      10,
      -5,
      from: _canvas,
      centreDx: 10,
      centreDy: -5,
    );
    final position = moved.track.position;
    expect(position.keyAt(0)!.value.x, 110);
    expect(
      position.keyAt(0)!.outgoing,
      KeyExit.hold,
      reason: 'a stepped camera must not start panning after a resize — '
          'the pose-facade rebuild linearized holds (adversarial review)',
    );
    expect(position.keyAt(0)!.name, 'A');
    expect(
      position.keyAt(4),
      isNull,
      reason: 'no synthesized position key at the scale key\'s frame',
    );
    expect(
      moved.track.scale.keyAt(4)!.value,
      uniformScale(1.5),
      reason: 'a scale is two numbers and no place on the canvas',
    );
    expect(moved.track.scale.keys.length, 1);
  });

  test('a zero offset is identity for the whole cut model', () {
    final camera = CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 1, y: 2))},
    );
    expect(
      identical(
        translateCutCamera(
          camera,
          0,
          0,
          from: _canvas,
          centreDx: 0,
          centreDy: 0,
        ),
        camera,
      ),
      isTrue,
    );
  });
}
