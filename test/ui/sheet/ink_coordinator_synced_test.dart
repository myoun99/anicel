import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_controller.dart';

/// The one sync every ink plane runs (the audit's clone scan, 2026-09-03).
/// The resize arm is the one a "never resizes" mutant survived at panel
/// level: no ink test synced a plane twice at two sizes, so the arm that
/// keeps the coordinator and resizes it went unmeasured.
void main() {
  const key = BrushFrameKey(
    projectId: ProjectId('ink-test'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  const small = CanvasSize(width: 64, height: 32);
  const large = CanvasSize(width: 128, height: 96);

  test(
    'a plane with no coordinator yet gets one over its store, at the size',
    () {
      final store = BrushFrameStore();
      final made = inkCoordinatorSynced(
        null,
        store: store,
        canvasSize: small,
        initialFrameKey: key,
      );
      expect(made.sessionStore.canvasSize, small);
      expect(made.frameStore, same(store));
    },
  );

  test('a plane that already has one KEEPS it and resizes it', () {
    final store = BrushFrameStore();
    final first = inkCoordinatorSynced(
      null,
      store: store,
      canvasSize: small,
      initialFrameKey: key,
    );
    final second = inkCoordinatorSynced(
      first,
      store: store,
      canvasSize: large,
      initialFrameKey: key,
    );
    expect(second, same(first), reason: 'the plane keeps its history');
    expect(first.sessionStore.canvasSize, large, reason: 'resized in place');
  });
}
