import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart' show ResolvedLayerEffect;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🚨A FRAME'S ROWS ARE ASKED FOR AT ONCE (a-picture-is-made-once,
/// 2026-10-10): each row's picture waits for its raster to come back, and
/// asked one after another a frame of thirteen rows waited thirteen round
/// trips. The warm's walk and the canvas's own are the same walk, so both
/// are pinned: a frame of three missing rows has all three asked for before
/// the first comes back.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey keyOf(String frame) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: LayerId('layer-$frame'),
    frameId: FrameId(frame),
  );

  final frames = ['a', 'b', 'c'];

  /// A store with the three rows' cels drawn on, so each has a picture to
  /// make.
  BrushFrameStore inked() {
    final store = BrushFrameStore();
    for (final frame in frames) {
      inkCelIn(
        store,
        keyOf(frame),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 4, y: 4),
        size: 4,
        tileSize: 4,
      );
    }
    return store;
  }

  List<CanvasLayerImageRequest> rows() => [
    for (final frame in frames)
      CanvasLayerImageRequest(frameKey: keyOf(frame), opacity: 1),
  ];

  test('the warm asks for every missing row of a frame at once', () async {
    final cache = _Gated(frameStore: inked());
    addTearDown(cache.dispose);
    final pictures = CanvasPictures(
      layerImages: cache,
      rowsOf: (_, _) => rows(),
      qualityAt: (_, _) => PlaybackQuality.full,
    );

    final making = pictures.make((
      cut: Cut(
        id: const CutId('cut'),
        name: 'Cut',
        duration: 1,
        canvasSize: canvasSize,
        layers: const [],
      ),
      frameIndex: 0,
    ), shouldAbort: () => false);
    await pumpEventQueue();
    expect(
      cache.most,
      frames.length,
      reason: 'every row asked for before the first came back',
    );

    cache.gate.complete();
    expect(await making, isTrue);
  });

  testWidgets('the canvas asks for every row it lacks at once', (
    tester,
  ) async {
    final cache = _Gated(frameStore: inked());
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 8,
          height: 8,
          child: CanvasLayerStackView(
            nodes: [
              for (final row in rows()) CompositeLeaf<CanvasStackRow>(row),
            ],
            imageCache: cache,
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      cache.most,
      frames.length,
      reason: 'every row asked for before the first came back',
    );
    cache.gate.complete();
    await tester.pump();
  });
}

/// An image cache whose every ask waits at one gate, counting how many wait
/// there at once; past the gate it answers with no picture.
class _Gated extends LayerFrameImageCache {
  _Gated({required super.frameStore});

  final gate = Completer<void>();
  int _waiting = 0;
  int most = 0;

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
  }) async {
    _waiting += 1;
    most = math.max(most, _waiting);
    await gate.future;
    _waiting -= 1;
    return null;
  }
}
