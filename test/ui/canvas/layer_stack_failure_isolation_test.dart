import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/layer_effect.dart';
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
import 'package:anicel/src/ui/quiet_turns.dart' show QuietTurn;
import 'package:anicel/src/models/composite_tree.dart';

/// D10: a cel the store cannot build is ONE row's problem.
///
/// The stack walks its layers serially, and the walk used to die on the
/// first throw — so a file-backed cel whose bytes had moved took every
/// LATER layer down with it, silently, and which rows went dark moved
/// with the walk order. The failure is skipped now, and REMEMBERED:
/// retrying it on every rebuild is a blocking open + throw per layer per
/// sweep, which is a hot loop on the old tablets this project supports.
///
/// ⚠️THE THROW COMES FROM THE STORE ([_UnreachableCels]), where an
/// unreachable cel's bytes fail to come: what is remembered is the cache's
/// record ([LayerFrameImageCache.unreadable]), kept by its making, so a
/// stand-in for the making would stand in for the record as well.
class _ThrowingCache extends LayerFrameImageCache {
  _ThrowingCache({required _UnreachableCels super.frameStore});

  /// Cels whose bytes cannot be read — everything else behaves normally.
  Set<FrameId> get failing => (frameStore as _UnreachableCels).failing;
  final List<FrameId> syncAttempts = [];

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    required bool makePictures,
    bool inkSuffices = false,
  }) {
    syncAttempts.add(key.frameId);
    return super.prepareSyncOrNull(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      makePictures: makePictures,
      inkSuffices: inkSuffices,
    );
  }

  /// The async pass is not what this pins, and letting it reach the real
  /// store would make the test wait on work with no cels behind it.
  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
    Future<QuietTurn?> Function()? turn,
  }) async => null;
}

/// A store whose [failing] cels hold a picture, as a file cel is said to,
/// and throw where their pixels are asked for — bytes the file no longer
/// holds.
class _UnreachableCels extends BrushFrameStore {
  _UnreachableCels(this.failing);

  final Set<FrameId> failing;

  @override
  bool celHasRenderableContent(BrushFrameKey key) =>
      failing.contains(key.frameId) || super.celHasRenderableContent(key);

  @override
  BitmapSurface? currentSurfaceWithoutReplay(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
    CelRead read = CelRead.use,
  }) {
    if (failing.contains(key.frameId)) {
      throw StateError('cel bytes unreachable: ${key.frameId.value}');
    }
    return super.currentSurfaceWithoutReplay(
      key,
      canvasSize: canvasSize,
      read: read,
    );
  }
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
      frameStore: _UnreachableCels({const FrameId('bad')}),
    );

    Widget host() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 200,
          child: CanvasLayerStackView(
            nodes: [
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(frameKey: _key('good-before'), opacity: 1),
              ),
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(frameKey: _key('bad'), opacity: 1),
              ),
              CompositeLeaf<CanvasStackRow>(
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

  testWidgets('a success retires the note — the record says the LAST '
      'attempt failed, not that one once did', (tester) async {
    final captured = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => captured.add(details.exception);

    final cache = _ThrowingCache(
      frameStore: _UnreachableCels({const FrameId('flaky')}),
    );

    Widget host() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 200,
          child: CanvasLayerStackView(
            nodes: [
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(frameKey: _key('flaky'), opacity: 1),
              ),
            ],
            imageCache: cache,
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
          ),
        ),
      ),
    );

    // The cel exists at revision 1 when it fails, so the note is written
    // against a revision the store can hand out AGAIN.
    cache.frameStore.getOrCreateFrame(_key('flaky'));
    await tester.pumpWidget(host());
    await tester.pump();
    final afterFailure = cache.syncAttempts.length;

    // A CONTENT change earns the retry — that is the skip list's whole
    // contract — and this one succeeds.
    cache.failing.clear();
    cache.frameStore.markCelEdited(_key('flaky'));
    await tester.pumpWidget(host());
    await tester.pump();
    final afterHeal = cache.syncAttempts.length;

    // Now a project OPEN: every frame is reseeded back to revision 1. A
    // note left standing from the old revision-1 failure would match this
    // fresh revision 1 and skip a cel that builds perfectly well.
    cache.frameStore.restoreBaked({});
    cache.frameStore.getOrCreateFrame(_key('flaky'));
    await tester.pumpWidget(host());
    await tester.pump();
    final afterReopen = cache.syncAttempts.length;

    FlutterError.onError = previous;

    expect(captured, isNotEmpty, reason: 'the first attempt really failed');
    expect(
      afterHeal,
      greaterThan(afterFailure),
      reason: 'a content change retries a cel the skip list was holding',
    );
    expect(
      afterReopen,
      greaterThan(afterHeal),
      reason: 'the success retired the note — otherwise the reseed to '
          'revision 1 makes the old failure matchable again and the row '
          'is skipped for a reason that no longer exists',
    );
  });

  testWidgets('🚨and so does a run\'s making — the record is one for every '
      'maker, kept the same by each', (tester) async {
    await tester.runAsync(() async {
      final store = _UnreachableCels({const FrameId('flaky')});
      final cache = LayerFrameImageCache(frameStore: store);
      addTearDown(cache.dispose);
      final key = _key('flaky');
      store.getOrCreateFrame(key);
      Future<void> make() => cache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const <ResolvedLayerEffect>[],
      );
      await expectLater(make(), throwsA(isA<StateError>()));
      expect(
        cache.unreadable.has(key),
        isTrue,
        reason: '⛔CONTROL: the throw is noted',
      );

      // The same content, read now.
      store.failing.clear();
      await make();

      expect(cache.unreadable.has(key), isFalse);
    });
  });
}
