import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// D10: a cel the store cannot build is ONE row's problem.
///
/// The stack walks its layers serially, and the walk used to die on the
/// first throw — so a file-backed cel whose bytes had moved took every
/// LATER layer down with it, silently, and which rows went dark moved
/// with the walk order. The failure is skipped now, and REMEMBERED:
/// retrying it on every rebuild is a blocking open + throw per layer per
/// sweep, which is a hot loop on the old tablets this project supports.
class _ThrowingCache extends LayerFrameImageCache {
  _ThrowingCache({required super.frameStore, required this.failing});

  /// Cels whose build throws — everything else behaves normally.
  final Set<FrameId> failing;
  final List<FrameId> syncAttempts = [];

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
  }) {
    syncAttempts.add(key.frameId);
    if (failing.contains(key.frameId)) {
      throw StateError('cel bytes unreachable: ${key.frameId.value}');
    }
    return null;
  }

  /// The async pass is not what this pins, and letting it reach the real
  /// store would make the test wait on work with no cels behind it.
  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    bool Function()? shouldAbort,
  }) async => null;
}

BrushFrameKey _key(String frame) => BrushFrameKey(
  projectId: const ProjectId('p'),
  trackId: const TrackId('t'),
  cutId: const CutId('c'),
  layerId: LayerId('layer-$frame'),
  frameId: FrameId(frame),
);

void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);

  testWidgets('a cel that cannot be built does not take the layers after '
      'it down, and is not retried on every rebuild', (tester) async {
    // The reported failures are expected here; keep them off the harness's
    // own failure channel while still letting the code report them.
    final captured = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => captured.add(details.exception);

    final cache = _ThrowingCache(
      frameStore: BrushFrameStore(),
      failing: {const FrameId('bad')},
    );

    Widget host() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 200,
          child: CanvasLayerStackView(
            nodes: [
              CanvasLayerImageNode(
                CanvasLayerImageRequest(frameKey: _key('good-before'), opacity: 1),
              ),
              CanvasLayerImageNode(
                CanvasLayerImageRequest(frameKey: _key('bad'), opacity: 1),
              ),
              CanvasLayerImageNode(
                CanvasLayerImageRequest(frameKey: _key('good-after'), opacity: 1),
              ),
            ],
            imageCache: cache,
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();
    final firstPass = List.of(cache.syncAttempts);

    // A rebuild must not re-open the same broken cel: nothing about it
    // changed, and the open blocks.
    await tester.pumpWidget(host());
    await tester.pump();
    final secondPass = List.of(cache.syncAttempts);

    // ⚠️Restore the channel BEFORE any expect — the binding asserts on a
    // test that leaves it overridden.
    FlutterError.onError = previous;

    expect(
      firstPass.map((id) => id.value),
      contains('good-after'),
      reason: 'the row AFTER the failing one must still be attempted — one '
          'unreachable cel used to abandon the whole walk',
    );
    expect(captured, isNotEmpty, reason: 'and the failure is not hidden');
    expect(
      secondPass.where((id) => id.value == 'bad').length,
      1,
      reason: 'the failed revision is remembered — retrying it per rebuild '
          'is a blocking open and throw per layer per sweep',
    );
  });
}
