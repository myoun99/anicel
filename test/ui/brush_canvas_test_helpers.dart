import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';
import 'package:anicel/src/ui/brush/eyedropper_swatch_painter.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:flutter/widgets.dart';

/// Where the tool cursor sprite under [sprite] shows, or null while it
/// shows nothing. The R3 #8 oracle since F-130: a sprite is mounted
/// whenever its tool is armed and paints nothing until there is an aim —
/// null here is what `findsNothing` used to say.
Offset? toolCursorShownAt(WidgetTester tester, Finder sprite) =>
    tester.renderObject<RenderToolCursorSprite>(sprite).debugPosition;

/// The colour the eyedropper's hover swatch last painted, or null when it
/// painted nothing. Sampled in the swatch's own `paint`, once per frame.
int? eyedropperSwatchColor(WidgetTester tester) =>
    (tester
                .widget<ToolCursorSprite>(
                  find.byKey(const ValueKey<String>('eyedropper-hover-swatch')),
                )
                .look
                .painter
            as EyedropperSwatchPainter)
        .debugLastColor;

class FakeCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];

  int get totalCalls =>
      layerTiles.length + frameComposites.length + playbackPreviews.length;

  @override
  void invalidateLayerTile(LayerTileCacheKey key) => layerTiles.add(key);

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {}

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
