import 'dart:ui' as ui;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/cels_ahead.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/shown_cels.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/history_pictures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A STEP LANDS AT THE PRESS, AND ITS PICTURES ARE MADE AHEAD
/// (undo-held-tile-pictures, stage 1 — and the one door, 2026-09-17: a
/// tile pictures itself inside the paint that shows it, so no step ever
/// waits and no frame on the way is blank). The whole-canvas measurement
/// is `undo_into_the_room_is_whole_test`; these pin the warm-ahead, each
/// against the mutation that turns it red.
void main() {
  late BitmapTileImageCache cache;
  late ShownCels shown;
  late HistoryManager history;
  late HistoryPictures pictures;
  late BitmapSurface next;
  var applied = 0;

  void apply() => applied += 1;

  /// A canvas showing [_key] whole, and a step that would put [next] back
  /// on it, whose pictures nobody has made yet.
  void aStepNotReady() {
    cache = BitmapTileImageCache();
    shown = ShownCels(cache: cache)
      ..show(Object(), (_key.layerId, _key.frameId));
    final now = _surfaceOf([1, 2]);
    next = _surfaceOf([3, 4]);
    _givePictures(cache, now);
    history = HistoryManager()..execute(_PutsBack(now: now, next: next));
    pictures = HistoryPictures(history: history, shown: shown);
    applied = 0;
    // The values, not the variables: a test that sets up twice must not
    // tear the second one down twice.
    final madeHistory = history;
    final madePictures = pictures;
    addTearDown(() {
      madePictures.dispose();
      madeHistory.dispose();
    });
  }

  bool pictured(BitmapSurface surface) =>
      surface.tiles.values.every((tile) => cache.imageFor(tile) != null);

  Future<void> letTheWarmRun(WidgetTester tester) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
  }

  testWidgets('a step whose pictures are not made yet lands at the press — '
      'the paint that shows it makes them', (tester) async {
    aStepNotReady();

    pictures.step(undo: true, apply: apply);

    // ⛔Mutation: wait for the pictures → the press holds for nothing, and
    // every headless test's undo with it.
    expect(applied, 1);
  });

  testWidgets('after a step lands, the NEXT one is warmed while the user '
      'looks at this one', (tester) async {
    cache = BitmapTileImageCache();
    shown = ShownCels(cache: cache)
      ..show(Object(), (_key.layerId, _key.frameId));
    final now = _surfaceOf([1, 2]);
    final first = _surfaceOf([3, 4]);
    final second = _surfaceOf([5, 6]);
    _givePictures(cache, now);
    _givePictures(cache, first);
    history = HistoryManager()
      ..execute(_PutsBack(now: first, next: second))
      ..execute(_PutsBack(now: now, next: first));
    pictures = HistoryPictures(history: history, shown: shown);
    addTearDown(() {
      pictures.dispose();
      history.dispose();
    });

    pictures.step(undo: true, apply: history.undo);
    expect(history.undoCount, 1);
    expect(pictured(second), isFalse, reason: 'premise: not made yet');
    await letTheWarmRun(tester);

    // ⛔Mutation: no warm after a landing → the next step's pictures are
    // made in the paint that shows it, all at once, instead of ahead.
    expect(pictured(second), isTrue);
    pictures.step(undo: true, apply: history.undo);
    expect(history.undoCount, 0);
  });

  testWidgets('the warm makes pictures only for cels a canvas paints', (
    tester,
  ) async {
    cache = BitmapTileImageCache();
    shown = ShownCels(cache: cache); // Nothing shown.
    final now = _surfaceOf([1, 2]);
    next = _surfaceOf([3, 4]);
    history = HistoryManager()
      ..execute(_PutsBack(now: now, next: next))
      ..execute(_PutsBack(now: now, next: next));
    pictures = HistoryPictures(history: history, shown: shown);
    addTearDown(() {
      pictures.dispose();
      history.dispose();
    });

    pictures.step(undo: true, apply: history.undo);
    await letTheWarmRun(tester);

    // ⛔Mutation: warm every cel → pictures nobody draws are made and held.
    expect(pictured(next), isFalse);
  });

  testWidgets('the sheet ink view says which cel it paints, while it paints '
      'it', (tester) async {
    final store = BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 64, height: 64),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveBrushEditCanvasView(
          sessionState: store.getOrCreate(_key),
          layerId: _key.layerId,
          frameId: _key.frameId,
          inputSettings: () => BrushToolState.defaults.toInputSettings(),
          onSourceStrokeCommitted: (_) {},
        ),
      ),
    );

    // ⛔Mutation: no registration → the warm never makes this cel's next
    // step ahead of the press.
    expect(ShownCels.instance.isShown(_key), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(ShownCels.instance.isShown(_key), isFalse);
  });

  testWidgets('the session undoes THROUGH the pictures, and the step lands '
      'at the press', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final canvas = Object();
    ShownCels.instance.show(canvas, (_key.layerId, _key.frameId));
    addTearDown(() => ShownCels.instance.hide(canvas));
    final now = _surfaceOf([7, 8]);
    _givePictures(BitmapTileImageCache.instance, now);
    session.historyManager.execute(
      _PutsBack(now: now, next: _surfaceOf([9, 10])),
    );
    final before = session.historyManager.undoCount;

    session.undo();

    expect(session.historyManager.undoCount, before - 1);
  });
}

const _key = BrushFrameKey(
  projectId: ProjectId('p'),
  trackId: TrackId('t'),
  cutId: CutId('c'),
  layerId: LayerId('l'),
  frameId: FrameId('f'),
);

const _tile = 8;

BitmapSurface _surfaceOf(List<int> fills) => BitmapSurface(
  canvasSize: CanvasSize(width: _tile * fills.length, height: _tile),
  tileSize: _tile,
  tiles: {
    for (var i = 0; i < fills.length; i += 1)
      TileCoord(x: i, y: 0): BitmapTile(
        size: _tile,
        pixels: BitmapTile.blank(size: _tile).pixels
          ..fillRange(0, BitmapTile.bytesFor(_tile), fills[i]),
      ),
  },
);

void _givePictures(BitmapTileImageCache cache, BitmapSurface surface) {
  for (final entry in surface.tiles.entries) {
    cache.adoptDecoded(entry.value, _solid());
  }
}

ui.Image _solid() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_tile, _tile);
  picture.dispose();
  return image;
}

/// A step that would put [next] back on [_key] over [now], read ahead the
/// way the real ones are. It changes nothing itself: what the tests count
/// is the gate calling `apply`.
class _PutsBack implements Command, PictureRestoringCommand {
  _PutsBack({required this.now, required this.next});

  final BitmapSurface now;
  final BitmapSurface next;

  late final UndoSurfaceSnapshot _snapshot = UndoSurfaceSnapshot(
    key: _key,
    snapshot: next,
    sharedWith: null,
  );

  @override
  String get description => 'puts back';

  @override
  void execute() {}

  @override
  void undo() {}

  @override
  void readAhead(CelsAhead cels, {required bool undo}) =>
      cels.readSnapshot(_key, _snapshot, () => now);

  @override
  void dropReadAhead() => _snapshot.dropReadAhead();

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) {}
}
