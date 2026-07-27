import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_frame_cache_invalidation.dart';
import 'package:quick_animaker_v2/src/models/brush_frame_key.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/services/playback/editor_cache_invalidation_hub.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_cut_thumbnail_store.dart';

/// R5 regression: brush strokes never notify the session, so the
/// thumbnail store itself must notify on hub invalidations - otherwise a
/// visible storyboard never re-pulls thumbnailFor and freshly drawn
/// artwork never reaches its cut block.
void main() {
  test('a brush-frame invalidation notifies listeners once per batch', () {
    fakeAsync((async) {
      final hub = EditorCacheInvalidationHub();
      final store = StoryboardCutThumbnailStore(
        render: (_, _) async => null,
        invalidationHub: hub,
      );
      addTearDown(store.dispose);
      var notified = 0;
      store.addListener(() => notified += 1);

      final invalidation = BrushFrameCacheInvalidation(
        frameKey: BrushFrameKey(
          projectId: const ProjectId('p'),
          trackId: const TrackId('t'),
          cutId: const CutId('c'),
          layerId: const LayerId('l'),
          frameId: const FrameId('f'),
        ),
      );
      // One stroke commit fires several hub events - one notify covers all.
      hub.invalidateBrushFrame(invalidation);
      hub.invalidateBrushFrame(invalidation);
      hub.invalidateBrushFrame(invalidation);
      expect(notified, 0, reason: 'coalesced to a microtask');
      async.flushMicrotasks();
      expect(notified, 1);

      hub.invalidateBrushFrame(invalidation);
      async.flushMicrotasks();
      expect(notified, 2);
    });
  });
}

void fakeAsync(void Function(FakeAsyncDriver async) body) {
  FakeAsyncDriver.run(body);
}

/// Minimal microtask driver: runs [body] inside a zone that queues
/// microtasks so the test can flush them deterministically.
class FakeAsyncDriver {
  FakeAsyncDriver._();

  final List<void Function()> _microtasks = [];

  static void run(void Function(FakeAsyncDriver async) body) {
    final driver = FakeAsyncDriver._();
    runZoned(
      () => body(driver),
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, task) {
          driver._microtasks.add(task);
        },
      ),
    );
  }

  void flushMicrotasks() {
    while (_microtasks.isNotEmpty) {
      final task = _microtasks.removeAt(0);
      task();
    }
  }
}
