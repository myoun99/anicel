import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// R19 P3b: the display cache is an ALIAS of the baked truth — donations
/// keep it fresh across every commit and snapshot restore, and the
/// service's rebuild path is a reference reseed (no replay exists).
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  final key = BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: const FrameId('frame'),
  );

  BrushFrameEditingCoordinator coordinator() {
    return BrushFrameEditingCoordinator(
      initialFrameKey: key,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    );
  }

  BrushFrameDisplayCacheService serviceFor(BrushFrameStore store) {
    return BrushFrameDisplayCacheService(
      frameStore: store,
      canvasSize: canvasSize,
      tileSize: 4,
    );
  }

  test('the prepared cache aliases the baked truth', () {
    final c = coordinator();
    c.commitSourceStroke(sourceDabs: [_dab(4, 4, 0)]);

    final cache = serviceFor(c.frameStore).prepareFramePreview(key);

    expect(cache.isValid, isTrue);
    expect(
      identical(cache.previewSurface, c.frameStore.bakedSurfaceOrNull(key)),
      isTrue,
    );
    expect(c.frameStore.getOrCreateFrame(key).inactivePreviewDirty, isFalse);
  });

  test('commit, undo and redo keep the display cache FRESH (donation on '
      'every mutation — consumers never find a dirty cache)', () {
    final c = coordinator();
    final service = serviceFor(c.frameStore);
    final outcome = c.commitSourceStroke(sourceDabs: [_dab(2, 2, 0)])!;
    service.prepareFramePreview(key);
    expect(c.frameStore.hasValidDisplayCache(key), isTrue);

    final second = c.commitSourceStroke(sourceDabs: [_dab(8, 8, 1)])!;
    expect(c.frameStore.displayCacheOrNull(key)!.dirty, isFalse);
    expect(
      identical(
        c.frameStore.validPreviewSurfaceOrNull(key),
        second.postSurface,
      ),
      isTrue,
    );

    c.restoreSurfaceSnapshot(key, second.preSurface); // undo the 2nd stroke
    expect(c.frameStore.displayCacheOrNull(key)!.dirty, isFalse);
    expect(
      identical(
        c.frameStore.validPreviewSurfaceOrNull(key),
        outcome.postSurface,
      ),
      isTrue,
      reason: 'chain sharing: pre(2nd) IS post(1st)',
    );

    c.restoreSurfaceSnapshot(key, second.postSurface); // redo
    expect(c.frameStore.displayCacheOrNull(key)!.dirty, isFalse);
    expect(
      identical(
        c.frameStore.validPreviewSurfaceOrNull(key),
        second.postSurface,
      ),
      isTrue,
    );
  });

  test('valid preview is reused', () {
    final c = coordinator();
    final service = serviceFor(c.frameStore);
    c.commitSourceStroke(sourceDabs: [_dab(3, 3, 0)]);

    final first = service.prepareFramePreview(key);
    final second = service.prepareFramePreview(key);

    expect(identical(first, second), isTrue);
    expect(c.frameStore.validPreviewSurfaceOrNull(key), first.previewSurface);
  });

  test('an invalidated cache on an EMPTY cel reseeds blank, never stale', () {
    final store = BrushFrameStore();
    final service = BrushFrameDisplayCacheService(
      frameStore: store,
      canvasSize: canvasSize,
      tileSize: 4,
    );

    final cache = service.prepareFramePreview(key);

    expect(cache.previewSurface.tiles, isEmpty);
    expect(cache.isValid, isTrue);
  });

  test('live pointer path skips cache generation', () {
    final c = coordinator();

    c.activeSessionState;

    expect(c.frameStore.displayCacheOrNull(key), isNull);
  });
}

BrushDab _dab(double x, double y, int sequence) {
  return BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );
}
