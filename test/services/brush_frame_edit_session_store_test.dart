import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';

void main() {
  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  test('keeps frame edit sessions isolated by BrushFrameKey', () {
    final store = BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: 4,
    );
    final frameA = key('frame-a');
    final frameB = key('frame-b');

    final sessionA = store.getOrCreate(frameA);
    final updatedA = sessionA.copyWith(
      canvasState: sessionA.canvasState.clearLastEdit(),
    );
    store.update(frameA, updatedA);

    final sessionB = store.getOrCreate(frameB);

    expect(store.getOrCreate(frameA), same(updatedA));
    expect(sessionB, isNot(same(updatedA)));
    expect(store.sessionOrNull(frameB), same(sessionB));
  });

  /// 🚨A LINKED CEL HAS ONE SESSION, because it is one picture.
  ///
  /// The frame store already folds every single-cel operation onto the
  /// physical cel; sessions are state ABOUT that cel and used not to fold
  /// at all, so each 겸용 member kept its own surface. A stroke committed
  /// through one member left the others on the pre-stroke pixels — and the
  /// row you STAND on is painted from the session, not the store.
  /// 🗣️유저 2026-09-12: 「컷1에서 그린 그림이 재생시에만 표시되고 아닐땐
  /// 안보여」 (playback reads the store; the canvas read the stale session).
  test('linked members address ONE session — the store folds the address', () {
    final store = BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: 4,
    );
    final canonical = key('frame-a');
    // The same cel seen from a 겸용 sibling: same frame, another row.
    const member = BrushFrameKey(
      projectId: ProjectId('project'),
      trackId: TrackId('track'),
      cutId: CutId('cut-2'),
      layerId: LayerId('layer-2'),
      frameId: FrameId('frame-a'),
    );
    store.setLinkResolver(
      (key) => key.cutId == const CutId('cut-2') ? canonical : key,
    );

    final session = store.getOrCreate(canonical);
    expect(
      store.sessionOrNull(member),
      same(session),
      reason: 'the sibling reads the SAME session, not one of its own',
    );
    expect(store.sessionCount, 1, reason: 'one cel, one session');

    // And a write through the sibling is a write to that one session.
    final edited = session.copyWith(
      canvasState: session.canvasState.clearLastEdit(),
    );
    store.update(member, edited);
    expect(store.getOrCreate(canonical), same(edited));
    expect(store.sessionCount, 1);

    // The protected key folds too, or eviction would drop the live session
    // and keep one nobody is holding.
    store.getOrCreate(key('frame-b'));
    store.evictBeyondRetainLimit(retainLimit: 1, protect: member);
    expect(store.sessionOrNull(canonical), same(edited));
  });
}
