import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Layer drawingLayer({
    String id = 'layer-1',
    double opacity = 1,
    bool isVisible = true,
  }) {
    return Layer(
      id: LayerId(id),
      name: 'A',
      frames: [frame('frame-1'), frame('frame-2')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 6),
        6: TimelineExposure.drawing(const FrameId('frame-2'), length: 4),
      },
      opacity: opacity,
      isVisible: isVisible,
    );
  }

  Cut cut({
    List<Layer>? layers,
    CanvasSize canvasSize = const CanvasSize(width: 100, height: 50),
  }) {
    return Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: layers ?? [drawingLayer()],
      duration: 24,
      canvasSize: canvasSize,
    );
  }

  CutFrameCompositeSignature signature({
    Cut? forCut,
    int frameIndex = 0,
    PlaybackQuality quality = PlaybackQuality.half,
    int Function(LayerId, FrameId)? revisionOf,
    Set<LayerId> fxBypassedLayerIds = const {},
  }) {
    return computeCutFrameCompositeSignature(
      cut: forCut ?? cut(),
      frameIndex: frameIndex,
      quality: quality,
      revisionOf: revisionOf ?? (_, _) => 7,
      fxBypassedLayerIds: fxBypassedLayerIds,
    );
  }

  test('held frames share one signature', () {
    expect(signature(frameIndex: 0), signature(frameIndex: 5));
    expect(signature(frameIndex: 6), signature(frameIndex: 9));
    expect(signature(frameIndex: 0), isNot(signature(frameIndex: 6)));
  });

  test('blank exposure contributes no layer', () {
    expect(signature(frameIndex: 10).layers, isEmpty);
  });

  test('camera and hidden layers are excluded', () {
    final withExtras = cut(
      layers: [
        drawingLayer(),
        drawingLayer(id: 'hidden', isVisible: false),
        drawingLayer(id: 'transparent', opacity: 0),
        Layer(
          id: const LayerId('camera'),
          name: 'Camera',
          frames: const [],
          timeline: const {},
          kind: LayerKind.camera,
        ),
      ],
    );

    expect(signature(forCut: withExtras), signature());
  });

  test('source revision changes the signature', () {
    expect(
      signature(revisionOf: (_, _) => 1),
      isNot(signature(revisionOf: (_, _) => 2)),
    );
  });

  test('opacity, visibility, quality and canvas size change the signature', () {
    final base = signature();

    expect(
      signature(forCut: cut(layers: [drawingLayer(opacity: 0.5)])),
      isNot(base),
    );
    expect(
      signature(
        forCut: cut(canvasSize: const CanvasSize(width: 200, height: 100)),
      ),
      isNot(base),
    );
    expect(signature(quality: PlaybackQuality.full), isNot(base));
  });

  test('layer order is part of the signature', () {
    final ab = cut(
      layers: [
        drawingLayer(),
        drawingLayer(id: 'layer-2'),
      ],
    );
    final ba = cut(
      layers: [
        drawingLayer(id: 'layer-2'),
        drawingLayer(),
      ],
    );

    expect(signature(forCut: ab), isNot(signature(forCut: ba)));
  });

  test('undrawn frames participate with their resolver revision', () {
    final drawn = signature(
      revisionOf: (_, frameId) => frameId.value == 'frame-1' ? 3 : 0,
    );
    final undrawn = signature(revisionOf: (_, _) => 0);

    expect(drawn, isNot(undrawn));
    expect(undrawn.layers.single.sourceRevision, 0);
  });

  test('a layer transform joins the signature: edits invalidate, animated '
      'poses split held frames, identity stays null', () {
    expect(signature().layers.single.pose, isNull);

    final moved = cut(
      layers: [
        drawingLayer().copyWith(
          transformTrack: TransformTrack(
            keyframes: {
              0: TransformPose(center: CanvasPoint(x: 0, y: 0)),
              5: TransformPose(center: CanvasPoint(x: 10, y: 0)),
            },
          ),
        ),
      ],
    );

    // Transform work changes the composite's identity...
    expect(signature(forCut: moved), isNot(signature()));
    // ...and an animated pose splits frames a held exposure would share.
    expect(
      signature(forCut: moved, frameIndex: 0),
      isNot(signature(forCut: moved, frameIndex: 3)),
    );
    // A HOLD-flat stretch still deduplicates: past the last key the pose
    // freezes, so signatures match again.
    expect(
      signature(forCut: moved, frameIndex: 5),
      signature(forCut: moved, frameIndex: 5),
    );
  });

  test('the anchor point and the animated Opacity join the signature '
      '(their edits invalidate composites)', () {
    final anchored = cut(
      layers: [
        drawingLayer().copyWith(
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>().withKey(
              0,
              CanvasPoint(x: 5, y: 5),
            ),
            anchorPoint: PropertyTrack<CanvasPoint>().withKey(
              0,
              CanvasPoint(x: 10, y: 10),
            ),
          ),
        ),
      ],
    );
    final unanchored = cut(
      layers: [
        drawingLayer().copyWith(
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>().withKey(
              0,
              CanvasPoint(x: 5, y: 5),
            ),
          ),
        ),
      ],
    );
    expect(signature(forCut: anchored), isNot(signature(forCut: unanchored)));
    expect(
      signature(forCut: anchored).layers.single.anchorPoint,
      CanvasPoint(x: 10, y: 10),
    );

    final fading = cut(
      layers: [
        drawingLayer().copyWith(
          transformTrack: TransformTrack.empty().copyWith(
            opacity: PropertyTrack<double>().withKey(0, 1).withKey(4, 0.5),
          ),
        ),
      ],
    );
    // The animated multiplier splits frames a held exposure would share...
    expect(
      signature(forCut: fading, frameIndex: 0),
      isNot(signature(forCut: fading, frameIndex: 2)),
    );
    // ...and a fully faded-out sample drops the layer entirely.
    final gone = cut(
      layers: [
        drawingLayer().copyWith(
          transformTrack: TransformTrack.empty().copyWith(
            opacity: PropertyTrack<double>().withKey(0, 0),
          ),
        ),
      ],
    );
    expect(signature(forCut: gone).layers, isEmpty);
  });

  test('the fx-bypass view state joins the signature, so flipping the '
      'switch self-invalidates (pose/anchor drop, opacity back to static)', () {
    final moved = cut(
      layers: [
        drawingLayer(opacity: 0.8).copyWith(
          transformTrack: TransformTrack(
            keyframes: {0: TransformPose(center: CanvasPoint(x: 0, y: 0))},
          ).copyWith(opacity: PropertyTrack<double>().withKey(0, 0.5)),
        ),
      ],
    );

    final applied = signature(forCut: moved);
    final bypassed = signature(
      forCut: moved,
      fxBypassedLayerIds: {const LayerId('layer-1')},
    );

    expect(applied, isNot(bypassed));
    expect(bypassed.layers.single.pose, isNull);
    expect(bypassed.layers.single.anchorPoint, isNull);
    expect(bypassed.layers.single.opacity, closeTo(0.8, 1e-9));
    expect(applied.layers.single.opacity, closeTo(0.4, 1e-9));
  });
}
