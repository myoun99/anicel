import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/command.dart' show WorkAhead;
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/canvas_traces.dart';
import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/history_verbs.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」): a redo that runs a resize again
/// moved every cel of the cut on the UI thread — 2.2 s on S5_BA's 127 cels,
/// with no window. The document's step goes behind the wait window now when
/// it has work ahead of it, and the work runs on the machine's workers.
///
/// Here the window is a door that holds the step until the test lets it go;
/// the real window is the app's (`a_resize_redo_waits_behind_the_canvas_size_
/// window_test`).
void main() {
  late EditorSessionManager session;
  late HistoryVerbs verbs;
  late List<({WorkAhead ahead, VoidCallback step})> waited;

  setUp(() {
    final canvas = CanvasSelectionCommands();
    final text = CelTextCommands();
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(() {
      session.dispose();
      text.dispose();
      canvas.dispose();
    });
    waited = [];
    verbs = HistoryVerbs(
      selection: canvas,
      traces: CanvasTraces([canvas]),
      text: text,
      session: session,
      contactIsDown: () => false,
      behindTheWaitWindow: (ahead, step) async =>
          waited.add((ahead: ahead, step: step)),
    );
  });

  CanvasSize sizeNow() => session.requireActiveCut.canvasSize;

  /// The active cut two pixels smaller about its centre: the picture moves
  /// one pixel up and to the left, no whole tile.
  void shrink() {
    final size = sizeNow();
    session.cutVerbs.resizeActiveCutCanvas(
      CanvasSize(width: size.width - 2, height: size.height - 2),
      anchor: CanvasResizeAnchor.center,
    );
  }

  /// A picture drawn on [cutId] — hot, as an undo puts every one back.
  BrushFrameKey draw(CutId cutId) {
    final key = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: cutId,
      layerId: const LayerId('l'),
      frameId: const FrameId('drawn'),
    );
    final cut = session.repository.requireProject().tracks
        .expand((track) => track.cuts)
        .firstWhere((cut) => cut.id == cutId);
    session.renderCaches.brushFrameStore.storeBakedSurface(
      key,
      BitmapSurface(canvasSize: cut.canvasSize, tileSize: 8).putTiles([
        (
          coord: TileCoord(x: 1, y: 1),
          tile: BitmapTile(size: 8, pixels: Uint8List(256)..fillRange(0, 256, 9)),
        ),
      ]),
    );
    return key;
  }

  test('🎯a resize done again waits while its pictures move ahead, and the '
      'step takes them; its undo does not wait', () async {
    final store = session.renderCaches.brushFrameStore;
    final drawn = draw(session.requireActiveCut.id);
    final before = sizeNow();
    shrink();
    final resized = sizeNow();

    verbs.undo();
    expect(waited, isEmpty, reason: 'an undo puts the pictures back as they were');
    expect(sizeNow(), before);

    verbs.redo();
    expect(waited, hasLength(1));
    expect(sizeNow(), before, reason: 'nothing is taken before the work');
    final reports = <double>[];
    await waited.single.ahead(reports.add);
    expect(reports, [1.0]);
    expect(store.movedAheadOf(drawn), isNotNull);
    final movedHere = store.celsMovedHere;
    waited.single.step();
    expect(sizeNow(), resized);
    expect(store.celsMovedHere, movedHere, reason: 'moved ahead, not here');
  });

  test('a step that waited is not taken over a history that moved on', () async {
    shrink();
    shrink();
    verbs.undo();
    verbs.redo();
    final (:ahead, :step) = waited.single;
    await ahead((_) {});
    session.undo();
    expect(session.historyManager.redoCount, 2, reason: 'premise');
    step();
    expect(
      session.historyManager.redoCount,
      2,
      reason: 'the press was for the step undone first, and nothing else',
    );
  });

  test('nor over work begun since — and is taken once there is none', () async {
    shrink();
    final resized = sizeNow();
    verbs.undo();
    verbs.redo();
    final (:ahead, :step) = waited.single;
    await ahead((_) {});
    var pending = true;
    session.historyManager.pendingBeforeUndoRedo = () => pending;
    step();
    expect(session.historyManager.redoCount, 1);
    pending = false;
    step();
    expect(session.historyManager.redoCount, 0);
    expect(sizeNow(), resized);
  });

  test('a redo that only walks to its edit first does not wait (I-41)', () {
    shrink();
    final resized = sizeNow();
    verbs.undo();
    session.selectFrameIndex(1);
    expect(session.currentFrameIndex, 1, reason: 'premise: elsewhere');
    verbs.redo();
    expect(waited, isEmpty);
    expect(session.currentFrameIndex, 0, reason: 'walked to the edit');
    expect(sizeNow(), isNot(resized));
    verbs.redo();
    expect(waited, hasLength(1));
  });

  group('a 겸용 변경 that takes the other cut\'s canvas', () {
    late CutId target;

    setUp(() {
      session.cutVerbs.duplicateActiveCut();
      target = session.activeTrack.cuts
          .firstWhere((cut) => cut.id != session.requireActiveCut.id)
          .id;
    });

    test('works its resize out ahead: the target\'s pictures moved', () async {
      final size = sizeNow();
      session.cutCommandCoordinator.resizeCutCanvas(
        cutId: target,
        canvasSize: CanvasSize(width: size.width - 2, height: size.height - 2),
      );
      final drawn = draw(target);
      final ahead = session.cutVerbs.convertActiveCutToLinkedAhead(target);
      expect(ahead, isNotNull);
      await ahead!((_) {});
      final store = session.renderCaches.brushFrameStore;
      expect(store.movedAheadOf(drawn), isNotNull);
      final movedHere = store.celsMovedHere;
      session.cutVerbs.convertActiveCutToLinked(target);
      expect(store.celsMovedHere, movedHere, reason: 'moved ahead, not here');
    });

    test('has nothing ahead where the canvases agree, or for itself', () {
      expect(session.cutVerbs.convertActiveCutToLinkedAhead(target), isNull);
      expect(
        session.cutVerbs.convertActiveCutToLinkedAhead(
          session.requireActiveCut.id,
        ),
        isNull,
      );
    });
  });
}
