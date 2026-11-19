import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_content_translation.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
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

    final moved = carryCutCamera(
      camera,
      resizeWalk(dx: -40, dy: 25, centreDx: -40, centreDy: 25),
      from: _canvas,
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
        carryCutCamera(
          camera,
          resizeWalk(dx: 10, dy: 10, centreDx: 10, centreDy: 10),
          from: _canvas,
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
    final moved = carryCutCamera(
      CutCamera.empty(),
      resizeWalk(dx: 0, dy: 0, centreDx: 100, centreDy: 50),
      from: _canvas,
    );

    expect(moved.track.position.keyAt(0)?.value, CanvasPoint(x: 960, y: 540));
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

    final moved = carryCutCamera(
      camera,
      resizeWalk(dx: -200, dy: -100, centreDx: -100, centreDy: -50),
      from: _canvas,
    );

    expect(moved.track.position.keyAt(0)?.value, CanvasPoint(x: 760, y: 440));
    expect(moved.track.rotation, camera.track.rotation);
  });

  test('a centre resize by an odd size keys the camera on the content '
      'rounded half a pixel off the centre', () {
    final moved = carryCutCamera(
      CutCamera.empty(),
      resizeWalk(dx: 1, dy: 0, centreDx: 0.5, centreDy: 0),
      from: _canvas,
    );

    expect(moved.track.position.keyAt(0)?.value, CanvasPoint(x: 961, y: 540));
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

    final moved = carryCutGuides(
      guides,
      resizeWalk(dx: 7, dy: -3, centreDx: 0, centreDy: 0),
    );

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

    final moved = carryLayerForResize(
      keyed,
      from: _canvas,
      walk: resizeWalk(
        dx: 5,
        dy: 6,
        centreDx: 99,
        centreDy: 99,
      ),
    );
    expect(moved.transformTrack.position.keyAt(0)?.value.x, 45);
    expect(moved.transformTrack.position.keyAt(0)?.value.y, 56);
    expect(moved.transformTrack.anchorPoint.keyAt(0)?.value.x, 17);
    expect(moved.transformTrack.anchorPoint.keyAt(0)?.value.y, 19);

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
    final followed = carryLayerForResize(
      nullAnchored,
      from: _canvas,
      walk: resizeWalk(
        dx: 0,
        dy: 0,
        centreDx: 200,
        centreDy: 0,
      ),
    );
    expect(followed.transformTrack.position.keyAt(0)?.value.x, 240);
    expect(followed.transformTrack.position.keyAt(0)?.value.y, 50);
    expect(followed.transformTrack.anchorPoint.isEmpty, isTrue);

    final unkeyed = Layer(
      id: const LayerId('unkeyed'),
      name: 'U',
      frames: const [],
      timeline: const {},
    );
    expect(
      identical(
        carryLayerForResize(
          unkeyed,
          from: _canvas,
          walk: resizeWalk(
            dx: 5,
            dy: 6,
            centreDx: 3,
            centreDy: 3,
          ),
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

    final moved = carryLayerForResize(
      anchored,
      from: _canvas,
      walk: resizeWalk(
        dx: 5,
        dy: 6,
        centreDx: 99,
        centreDy: 99,
      ),
    );

    expect(
      moved.transformTrack.position.keyAt(0)?.value,
      CanvasPoint(x: 965, y: 546),
    );
    expect(moved.transformTrack.position.keys.length, 1);
    expect(
      moved.transformTrack.anchorPoint.keyAt(0)?.value,
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

    final moved = carryLayerForResize(
      reference,
      from: _canvas,
      walk: resizeWalk(
        dx: 600,
        dy: -40,
        centreDx: 300,
        centreDy: -20,
      ),
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

    final moved = carryLayerForResize(
      reference,
      from: _canvas,
      walk: resizeWalk(
        dx: 600,
        dy: -40,
        centreDx: 300,
        centreDy: -20,
      ),
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

    final moved = carryCutCamera(
      camera,
      resizeWalk(dx: 10, dy: -5, centreDx: 10, centreDy: -5),
      from: _canvas,
    );
    final position = moved.track.position;
    expect(position.keyAt(0)?.value.x, 110);
    expect(
      position.keyAt(0)?.outgoing,
      KeyExit.hold,
      reason: 'a stepped camera must not start panning after a resize — '
          'the pose-facade rebuild linearized holds (adversarial review)',
    );
    expect(position.keyAt(0)?.name, 'A');
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

  // Card a-canvas-resize-leaves-effect-points-behind: an effect's points and
  // where a cel number stands are the row's paper's, as its cels' pixels
  // are — read where the picture reads them, before and after.
  group('an effect keeps its place on the picture through a resize', () {
    const grown = CanvasSize(width: 2320, height: 1080);
    // The picture stays put (dx 0) as the paper grows right; its middle
    // walks 200 right.
    final leftEdge = resizeWalk(dx: 0, dy: 0, centreDx: 200, centreDy: 0);

    Layer rowWith(List<LayerEffect> effects) => Layer(
      id: const LayerId('fx-row'),
      name: 'F',
      frames: const [],
      timeline: const {},
      effects: effects,
    );

    Layer resized(Layer row, ResizeWalk walk) =>
        carryLayerForResize(row, from: _canvas, walk: walk);

    CanvasPoint centreOf(Layer row, CanvasSize paper) => effectPointOnPaper(
      effectPointAt(row.effects.single.points['center']!, 0),
      paper,
    );

    TransformTrack keyedAt(CanvasPoint point) => TransformTrack.empty()
        .copyWith(position: PropertyTrack(keys: {0: PropertyKey(point)}));

    final radialBlur = LayerEffect.defaults(
      id: const EffectId('radial'),
      kind: EffectKind.radialBlur,
    );

    test('a keyed point moves by the content offset', () {
      final row = rowWith([
        radialBlur.copyWith(
          points: {'center': keyedAt(CanvasPoint(x: 100, y: 200))},
        ),
      ]);
      final moved = resized(
        row,
        resizeWalk(dx: 5, dy: 6, centreDx: 99, centreDy: 99),
      );
      expect(centreOf(moved, _canvas), CanvasPoint(x: 105, y: 206));
    });

    test('an unkeyed point stays where the picture is, not the paper '
        'middle', () {
      final row = rowWith([radialBlur]);
      final before = centreOf(row, _canvas);
      final moved = resized(row, leftEdge);
      expect(centreOf(moved, grown), before);
    });

    test('a cel number stands where it stood, at its size', () {
      final number = LayerEffect.defaults(
        id: const EffectId('number'),
        kind: EffectKind.celNumber,
      ).copyWith(
        stand: keyedAt(CanvasPoint(x: 300, y: 400)).copyWith(
          scale: PropertyTrack(keys: {0: PropertyKey(uniformScale(1.5))}),
        ),
      );
      final unkeyed = LayerEffect.defaults(
        id: const EffectId('number-at-rest'),
        kind: EffectKind.celNumber,
      );
      final moved = resized(rowWith([number, unkeyed]), resizeWalk(
        dx: 5,
        dy: 6,
        centreDx: 205,
        centreDy: 6,
      ));
      final stood = effectStandPose(
        effectStandAt(moved.effects[0].stand, 0),
        grown,
      );
      expect(stood.center, CanvasPoint(x: 305, y: 406));
      expect(stood.scale, uniformScale(1.5));
      expect(
        effectStandPose(effectStandAt(moved.effects[1].stand, 0), grown)
            .center,
        CanvasPoint(x: 965, y: 546),
        reason: 'at rest it stood on the old paper\'s middle, (960, 540)',
      );
    });

    test('an effect with no place on the paper leaves the row as it was', () {
      final row = rowWith([
        LayerEffect.defaults(id: const EffectId('blur'), kind: EffectKind.blur),
      ]);
      expect(identical(resized(row, leftEdge), row), isTrue);
    });
  });

  // 🗣️I-180: a resize that fits the picture to the new canvas carries every
  // place by its scale, and a number that sizes something by one factor —
  // the two scales' geometric mean (Q2 a · Q4 a).
  group('a fit carries what stands on the canvas by its scale', () {
    // 1920×1080 → 3840×2160 kept in proportion (비율 유지): twice, its
    // centre to the new centre.
    final twice = resizeWalk(
      sx: 2,
      sy: 2,
      dx: 0,
      dy: 0,
      centreDx: 0,
      centreDy: 0,
    );
    // 1920×1080 → 3840×1080 stretched (비율 무시): twice across, once down.
    final across = resizeWalk(
      sx: 2,
      sy: 1,
      dx: 0,
      dy: 0,
      centreDx: 0,
      centreDy: 0,
    );
    final sizeAcross = math.sqrt(2);

    test('the camera keeps the film: its place carried, its zoom divided', () {
      final keyed = CutCamera(
        keyframes: {
          0: CameraPose(center: CanvasPoint(x: 100, y: 50), zoom: 1.5),
        },
      );
      final moved = carryCutCamera(keyed, twice, from: _canvas);
      expect(moved.track.position.keyAt(0)!.value, CanvasPoint(x: 200, y: 100));
      expect(moved.track.scale.keyAt(0)!.value, uniformScale(0.75));

      final unkeyed = carryCutCamera(CutCamera(), across, from: _canvas);
      expect(
        unkeyed.track.scale.keyAt(0)!.value.x,
        closeTo(1 / sizeAcross, 1e-12),
        reason: 'an unkeyed zoom stood at 1 — keyed there, then divided by '
            'the one size factor (I-180-Q4 a)',
      );
      expect(unkeyed.track.position.isEmpty, isTrue);
    });

    test('a row\'s places and path handles are carried; its scale stays', () {
      final row = Layer(
        id: const LayerId('fit'),
        name: 'F',
        frames: const [],
        timeline: const {},
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack(
            keys: {
              0: PropertyKey(
                CanvasPoint(x: 40, y: 50),
                path: SplitPath(
                  ahead: CanvasPoint(x: 10, y: 4),
                  behind: CanvasPoint(x: -6, y: 0),
                ),
              ),
            },
          ),
          anchorPoint: PropertyTrack(
            keys: {0: PropertyKey(CanvasPoint(x: 12, y: 13))},
          ),
          scale: PropertyTrack(keys: {0: PropertyKey(uniformScale(1.5))}),
        ),
      );
      final moved = carryLayerForResize(row, from: _canvas, walk: across);
      final position = moved.transformTrack.position.keyAt(0)!;
      expect(position.value, CanvasPoint(x: 80, y: 50));
      expect(
        position.path,
        SplitPath(
          ahead: CanvasPoint(x: 20, y: 4),
          behind: CanvasPoint(x: -12, y: 0),
        ),
      );
      expect(
        moved.transformTrack.anchorPoint.keyAt(0)!.value,
        CanvasPoint(x: 24, y: 13),
      );
      expect(
        moved.transformTrack.scale.keyAt(0)!.value,
        uniformScale(1.5),
        reason: 'its cels are laid anew at the scale; a row\'s is of them',
      );
    });

    test('a way across the canvas turns where the scale differs across and '
        'down, and a quarter turn stays one', () {
      final guides = CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('sym'),
            name: 'Axis',
            shape: SymmetryShape(
              axis: GuideAxis(
                origin: CanvasPoint(x: 10, y: 20),
                angleDegrees: 45,
              ),
            ),
          ),
          DrawingGuide(
            id: const GuideId('per'),
            name: 'Perspective',
            shape: PerspectiveShape(
              vanishingPoints: [
                VanishingPointTowards(dx: 1, dy: 1),
                VanishingPointTowards(dx: 0, dy: 1),
              ],
              eyeLevel: GuideAxis(
                origin: CanvasPoint(x: 100, y: 200),
                angleDegrees: 90,
              ),
            ),
          ),
        ],
      );
      final moved = carryCutGuides(guides, across);
      final sym = moved.guides.first.shape as SymmetryShape;
      expect(sym.axis.origin, CanvasPoint(x: 20, y: 20));
      expect(
        sym.axis.angleDegrees,
        closeTo(math.atan(0.5) * 180 / math.pi, 1e-9),
      );
      final per = moved.guides.last.shape as PerspectiveShape;
      expect(per.eyeLevel.angleDegrees, 90);
      final diagonal = per.vanishingPoints[0] as VanishingPointTowards;
      expect(diagonal.dx, closeTo(2 / math.sqrt(5), 1e-12));
      expect(diagonal.dy, closeTo(1 / math.sqrt(5), 1e-12));
      final down = per.vanishingPoints[1] as VanishingPointTowards;
      expect((down.dx, down.dy), (0.0, 1.0));
    });

    test('a joined path turns its way and reaches as far as the scale '
        'carries it', () {
      final row = Layer(
        id: const LayerId('joined'),
        name: 'J',
        frames: const [],
        timeline: const {},
        transformTrack: TransformTrack.empty().copyWith(
          anchorPoint: PropertyTrack(
            keys: {0: PropertyKey(CanvasPoint(x: 0, y: 0))},
          ),
          position: PropertyTrack(
            keys: {
              0: PropertyKey(
                CanvasPoint(x: 0, y: 0),
                path: const JoinedPath(degrees: 45, ahead: 10, behind: 4),
              ),
            },
          ),
        ),
      );
      final path = carryLayerForResize(row, from: _canvas, walk: across)
          .transformTrack
          .position
          .keyAt(0)!
          .path as JoinedPath;
      // (cos 45°, sin 45°) at 2 × 1 is (√2, √½): √2.5 long.
      expect(path.degrees, closeTo(math.atan(0.5) * 180 / math.pi, 1e-9));
      expect(path.ahead, closeTo(10 * math.sqrt(2.5), 1e-9));
      expect(path.behind, closeTo(4 * math.sqrt(2.5), 1e-9));
    });

    test('a reference\'s file is sized as the picture is, across and down',
        () {
      final pose = TransformPose(
        center: CanvasPoint(x: 100, y: 60),
        scaleX: 0.5,
        scaleY: 0.25,
      );
      final row = Layer(
        id: const LayerId('ref'),
        name: 'R',
        frames: const [],
        timeline: const {},
        mediaReference: MediaReference(
          assetPath: 'a.png',
          pose: pose,
          pictureSize: const CanvasSize(width: 400, height: 300),
          fx: TransformTrack.empty().copyWith(
            scale: PropertyTrack(
              keys: {4: PropertyKey(CanvasPoint(x: 0.5, y: 0.5))},
            ),
          ),
        ),
      );
      final moved = carryLayerForResize(
        row,
        from: _canvas,
        walk: across,
      ).mediaReference!;
      expect(moved.pose.center, CanvasPoint(x: 200, y: 60));
      expect((moved.pose.scaleX, moved.pose.scaleY), (1.0, 0.25));
      expect(moved.laid.center, CanvasPoint(x: 200, y: 60));
      expect(moved.fx.scale.keyAt(4)!.value, CanvasPoint(x: 1, y: 0.5));
    });

    test('an effect\'s point is carried, and its pixel values and the size '
        'its letters stand at go by the one size factor', () {
      final radial = LayerEffect.defaults(
        id: const EffectId('radial'),
        kind: EffectKind.radialBlur,
      ).copyWith(
        points: {
          'center': TransformTrack.empty().copyWith(
            position: PropertyTrack(
              keys: {0: PropertyKey(CanvasPoint(x: 100, y: 200))},
            ),
          ),
        },
      );
      final blur = LayerEffect.defaults(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
      ).withParameter(
        'blurriness',
        EffectParameter(
          value: 10,
          track: PropertyTrack(
            keys: {0: const PropertyKey(10.0), 8: const PropertyKey(30.0)},
          ),
        ),
      );
      final number = LayerEffect.defaults(
        id: const EffectId('number'),
        kind: EffectKind.celNumber,
      );
      final moved = carryLayerForResize(
        Layer(
          id: const LayerId('fx'),
          name: 'X',
          frames: const [],
          timeline: const {},
          effects: [radial, blur, number],
        ),
        from: _canvas,
        walk: across,
      ).effects;
      expect(
        moved[0].points['center']!.position.keyAt(0)!.value,
        CanvasPoint(x: 200, y: 200),
      );
      final blurriness = moved[1].parameterOf('blurriness');
      expect(blurriness.value, closeTo(10 * sizeAcross, 1e-9));
      expect(blurriness.track.keyAt(8)!.value, closeTo(30 * sizeAcross, 1e-9));
      expect(
        moved[1].parameterOf('blurDimensions'),
        blur.parameterOf('blurDimensions'),
        reason: 'a choice is no size',
      );
      final stood = effectStandPose(
        effectStandAt(moved[2].stand, 0),
        const CanvasSize(width: 3840, height: 1080),
      );
      expect(
        stood.center,
        CanvasPoint(x: 1920, y: 540),
        reason: 'at rest it stood on the old middle, which the fit carries '
            'to the new',
      );
      expect(stood.scaleX, closeTo(sizeAcross, 1e-12));
      expect(stood.scaleY, closeTo(sizeAcross, 1e-12));
    });
  });

  test('a zero offset is identity for the whole cut model', () {
    final camera = CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 1, y: 2))},
    );
    expect(
      identical(
        carryCutCamera(
          camera,
          resizeWalk(dx: 0, dy: 0, centreDx: 0, centreDy: 0),
          from: _canvas,
        ),
        camera,
      ),
      isTrue,
    );
  });
}
