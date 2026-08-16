import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// #31 — 스토리보드는 액티브 컷만 굽는다, 남은 절반 (유저 확정: 스토리보드
/// 프로 따라서). The session's warm restart carries the NEXT cut in
/// storyboard order behind the active one, so the neighbouring bar goes
/// green and entering that cut plays from cache — without the user ever
/// having activated it.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cutNamed(String id, String layerId, String frameId) => Cut(
    id: CutId(id),
    name: id,
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId(layerId),
        name: layerId,
        frames: [
          Frame(id: FrameId(frameId), duration: 1, strokes: const []),
        ],
        timeline: {0: TimelineExposure.drawing(FrameId(frameId), length: 1)},
      ),
    ],
  );

  BitmapSurface inkedSurface(int seed) {
    final pixels = Uint8List(4 * 4 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 4,
          pixels: pixels,
        ),
      },
    );
  }

  test('a warm restart on the FIRST cut bakes the SECOND cut\'s composites '
      'without it ever being activated', () async {
    final first = cutNamed('cut-1', 'layer-1', 'frame-1');
    final second = cutNamed('cut-2', 'layer-2', 'frame-2');
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [first, second]),
        ],
      ),
    );
    addTearDown(session.dispose);
    expect(session.activeCutOrNull!.id, const CutId('cut-1'), reason: 'fixture');

    // Content for both cuts, the way an open seeds them.
    final firstKey = session.brushFrameKeyForCut(
      session.activeCutOrNull!,
      const LayerId('layer-1'),
      const FrameId('frame-1'),
    );
    session.brushFrameStore.storeBakedSurface(firstKey, inkedSurface(3));
    session.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(
        second,
        const LayerId('layer-2'),
        const FrameId('frame-2'),
      ),
      inkedSurface(5),
    );

    // One edit-burst invalidation: the debounced restart rebuilds the warm
    // order — which must now carry cut-2 behind cut-1.
    session.cacheInvalidationHub.invalidateBrushFrame(
      BrushFrameCacheInvalidation(frameKey: firstKey, wholeFrame: true),
    );
    // Debounce trailing edge, then the run itself.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await session.prerenderScheduler.idle;

    expect(
      session.cutFrameCompositeCache.validCompositeOrNull(
        cut: first,
        frameIndex: 0,
        quality: session.playbackQuality,
      ),
      isNotNull,
      reason: 'the active cut warms first, as before',
    );
    expect(
      session.cutFrameCompositeCache.validCompositeOrNull(
        cut: second,
        frameIndex: 0,
        quality: session.playbackQuality,
      ),
      isNotNull,
      reason: '#31: the next cut in storyboard order warms behind the '
          'active one — moving there must not be the thing that starts '
          'the bake',
    );
  });
}
