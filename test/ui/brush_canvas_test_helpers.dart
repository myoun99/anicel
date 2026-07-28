import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

class FakeCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];

  int get totalCalls =>
      layerTiles.length + frameComposites.length + playbackPreviews.length;

  @override
  void invalidateLayerTile(LayerTileCacheKey key) => layerTiles.add(key);

  @override
  void invalidateBrushFrame(invalidation) {}

  @override
  void invalidateFrameComposite(FrameCompositeCacheKey key) =>
      frameComposites.add(key);

  @override
  void invalidatePlaybackPreview(PlaybackPreviewCacheKey key) =>
      playbackPreviews.add(key);
}

Finder interactiveBrushCanvasFinder() =>
    find.byType(InteractiveBrushEditCanvasView);

Offset canvasGlobalOffset(WidgetTester tester, Offset localOffset) {
  return tester.getTopLeft(interactiveBrushCanvasFinder()) + localOffset;
}

Future<void> tapCanvas(
  WidgetTester tester,
  Offset localOffset, {
  int pointer = 1,
}) async {
  final gesture = await tester.startGesture(
    canvasGlobalOffset(tester, localOffset),
    pointer: pointer,
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
  // R25-④: the pen-up commit lands one frame AFTER pen-up.
  await tester.pump();
}

Future<void> dragCanvas(
  WidgetTester tester,
  List<Offset> localOffsets, {
  int pointer = 1,
}) async {
  assert(localOffsets.isNotEmpty);

  final gesture = await tester.startGesture(
    canvasGlobalOffset(tester, localOffsets.first),
    pointer: pointer,
  );
  await tester.pump();

  for (final localOffset in localOffsets.skip(1)) {
    await gesture.moveTo(canvasGlobalOffset(tester, localOffset));
    await tester.pump();
  }

  await gesture.up();
  await tester.pump();
  // R25-④: the pen-up commit lands one frame AFTER pen-up.
  await tester.pump();
}
