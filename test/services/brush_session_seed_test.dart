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
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

/// R11-⑦: opening a frame seeds the edit session from a VALID display
/// cache instead of replaying its whole stroke history; any command
/// mutation dirties the cache first, so the replay fallback stays the
/// correctness authority.
void main() {
  const canvasSize = CanvasSize(width: 128, height: 128);
  const frameKey = BrushFrameKey(
    projectId: ProjectId('seed-project'),
    trackId: TrackId('seed-track'),
    cutId: CutId('seed-cut'),
    layerId: LayerId('seed-layer'),
    frameId: FrameId('seed-frame'),
  );
  const policy = BrushHistoryPolicy(userUndoLimit: 24, deferredBakeRatio: 0);

  BrushDab dab(double x, double y, int color) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: 12,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  BrushFrameEditingCoordinator coordinatorOver(BrushFrameStore store) =>
      BrushFrameEditingCoordinator(
        initialFrameKey: frameKey,
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
        historyPolicy: policy,
      );

  test('a cold open seeds from the donated display cache (no replay)', () {
    final store = BrushFrameStore();
    final author = coordinatorOver(store);
    author.commitSourceStroke(sourceDabs: [dab(20, 20, 0xFFCC2200)]);
    author.commitSourceStroke(sourceDabs: [dab(60, 60, 0xFF0022CC)]);

    // A fresh coordinator over the same store = the project-open shape.
    final reopened = coordinatorOver(store);
    final surface = reopened.activeSessionState.canvasState.currentSurface;
    expect(
      identical(surface, store.displayCacheOrNull(frameKey)!.previewSurface),
      isTrue,
      reason: 'a valid display cache must seed the session directly',
    );
    // And the seeded pixels are the strokes' pixels.
    expect(surfacePixelRgba(surface, 20, 20)! & 0xFF, isNonZero);
    expect(surfacePixelRgba(surface, 60, 60)! & 0xFF, isNonZero);
  });

  test('seeded pixels equal a full replay byte-for-byte at probes', () {
    final store = BrushFrameStore();
    final author = coordinatorOver(store);
    author.commitSourceStroke(sourceDabs: [dab(20, 20, 0xFFCC2200)]);
    author.commitSourceStroke(sourceDabs: [dab(24, 22, 0x8800CC44)]);

    final seeded = coordinatorOver(
      store,
    ).activeSessionState.canvasState.currentSurface;

    store.clearDisplayCaches();
    final replayed = coordinatorOver(
      store,
    ).activeSessionState.canvasState.currentSurface;

    for (final (x, y) in [(20, 20), (24, 22), (26, 25), (15, 18), (0, 0)]) {
      expect(
        surfacePixelRgba(seeded, x, y),
        surfacePixelRgba(replayed, x, y),
        reason: 'seed and replay must agree at ($x, $y)',
      );
    }
  });

  test('an undone stroke never comes back from a stale seed: the baked '
      'truth follows every snapshot restore (R19 P3b)', () {
    final store = BrushFrameStore();
    final author = coordinatorOver(store);
    author.commitSourceStroke(sourceDabs: [dab(20, 20, 0xFFCC2200)]);
    final second = author.commitSourceStroke(
      sourceDabs: [dab(90, 90, 0xFF0022CC)],
    )!;

    // Undo the second stroke: the restore donates, so a FRESH coordinator
    // seeding from baked sees exactly the post-undo picture.
    author.restoreSurfaceSnapshot(frameKey, second.preSurface);

    final surface = coordinatorOver(
      store,
    ).activeSessionState.canvasState.currentSurface;
    expect(
      surfacePixelRgba(surface, 20, 20),
      isNonZero,
      reason: 'the surviving stroke seeds from baked',
    );
    expect(
      surfacePixelRgba(surface, 90, 90),
      anyOf(isNull, 0),
      reason: 'the undone stroke must NOT come back from a stale cache',
    );
  });
}
