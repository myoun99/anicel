import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// WHAT THE SESSION'S TEARDOWN OWES THE RENDER CACHES.
///
/// The session used to spell this out itself; it is [RenderCaches.dispose]
/// now, and the order in it is the law: the pending warm restart is
/// cancelled and the hub listener comes off BEFORE the caches they would
/// have refilled go down. Neither half had an observer — both bodies
/// could be emptied and every suite stayed green.
void main() {
  testWidgets('the invalidation listener comes off: a brush invalidation '
      'published after teardown arms nothing', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final cut = session.activeCutOrNull!;
    final frameKey = session.brushFrameKeyForCut(
      cut,
      cut.layers.first.id,
      const FrameId('frame'),
    );
    session.dispose();

    session.renderCaches.cacheInvalidationHub.invalidateBrushFrame(
      BrushFrameCacheInvalidation(frameKey: frameKey, wholeFrame: true),
    );

    // The assertion is the binding's own: a listener still on the hub
    // would arm the warm debounce here, and a pending timer at teardown
    // fails the test. Nothing to pump — the point is that nothing is
    // waiting to be pumped.
  });

  testWidgets('the composites the session was holding are released', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final cut = session.activeCutOrNull!;

    await session.renderCaches.cutFrameCompositeCache.prepareComposite(
      cut: cut,
      frameIndex: 0,
      quality: session.playbackRig.playbackQuality,
    );
    expect(
      session.renderCaches.cutFrameCompositeCache.estimatedBytes,
      greaterThan(0),
      reason: 'the premise: there is something in the cache to release',
    );

    session.dispose();

    expect(
      session.renderCaches.cutFrameCompositeCache.estimatedBytes,
      0,
      reason:
          'a composite is a GPU image — a cache the session forgot to '
          'dispose holds every frame it ever warmed for the life of the app',
    );
  });
}
