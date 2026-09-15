import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
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
import 'package:anicel/src/services/playback/editor_cache_invalidation_hub.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-68 root fix (2026-09-11): every surface replacement leaves the
/// coordinator through one door, and that door names the surfaces the
/// change went between — so the display side can give each changed tile a
/// truthful picture whichever path produced the change, and no path can
/// forget to.
///
/// Both funnels are pinned by identity: the display side composes from
/// the very tile objects these carry, so "equal" would not be enough.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  const key = BrushFrameKey(
    projectId: ProjectId('project'),
    trackId: TrackId('track'),
    cutId: CutId('cut'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame'),
  );

  BrushFrameEditingCoordinator coordinator() => BrushFrameEditingCoordinator(
    initialFrameKey: key,
    frameStore: BrushFrameStore(),
    sessionStore: BrushFrameEditSessionStore(
      canvasSize: canvasSize,
      tileSize: 4,
    ),
    historyPolicy: const BrushHistoryPolicy(),
  );

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  test('a stroke commit announces the surface before and the one after', () {
    final c = coordinator();
    final hub = EditorCacheInvalidationHub();
    final received = <BrushFrameCacheInvalidation>[];
    hub.addBrushFrameListener(received.add);
    final before = c.currentSurfaceOf(key);

    c.commitSourceStroke(sourceDabs: [dab(4, 4)], cacheInvalidationSink: hub);

    expect(received, hasLength(1));
    final announced = received.single;
    expect(announced.transition, isNotNull);
    expect(identical(announced.transition!.before, before), isTrue);
    expect(
      identical(announced.transition!.after, c.currentSurfaceOf(key)),
      isTrue,
    );
    expect(
      identical(announced.transition!.before, announced.transition!.after),
      isFalse,
    );
  });

  test('a snapshot restore (undo, redo, a pixel verb) announces them too', () {
    final c = coordinator();
    final hub = EditorCacheInvalidationHub();
    final received = <BrushFrameCacheInvalidation>[];
    final original = c.currentSurfaceOf(key);
    c.commitSourceStroke(sourceDabs: [dab(4, 4)]);
    final edited = c.currentSurfaceOf(key);
    hub.addBrushFrameListener(received.add);

    c.restoreSurfaceSnapshot(key, original, cacheInvalidationSink: hub);

    expect(received, hasLength(1));
    final announced = received.single;
    expect(announced.wholeFrame, isTrue, reason: 'unchanged: a restore is whole');
    expect(identical(announced.transition!.before, edited), isTrue);
    expect(identical(announced.transition!.after, original), isTrue);
  });

  test('the surfaces are not part of the announcement\'s identity', () {
    final c = coordinator();
    final a = c.currentSurfaceOf(key);
    c.commitSourceStroke(sourceDabs: [dab(4, 4)]);
    final b = c.currentSurfaceOf(key);
    const bare = BrushFrameCacheInvalidation(frameKey: key, wholeFrame: true);
    final carried = BrushFrameCacheInvalidation(
      frameKey: key,
      wholeFrame: true,
      transition: (before: a, after: b),
    );
    expect(carried, equals(bare));
    expect(carried.hashCode, bare.hashCode);
  });
}
