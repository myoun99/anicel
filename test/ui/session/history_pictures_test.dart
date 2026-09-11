import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
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
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/shown_cels.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/history_pictures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A STEP LANDS WHEN ITS PICTURES CAN — AND ONLY FOR A USER STILL
/// WAITING ON IT (undo-held-tile-pictures, stage 1). The whole-canvas
/// measurement is `undo_into_the_room_is_whole_test`; these pin the rules
/// of the wait itself, each against the mutation that turns it red.
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
  void aStepNotReady({bool nowIsWhole = true}) {
    cache = BitmapTileImageCache();
    shown = ShownCels(cache: cache)
      ..show(Object(), (_key.layerId, _key.frameId));
    final now = _surfaceOf([1, 2]);
    next = _surfaceOf([3, 4]);
    if (nowIsWhole) {
      _givePictures(cache, now);
    }
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

  Future<void> letThePicturesLand(WidgetTester tester) async {
    for (var i = 0; i < 10; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('a step whose pictures are not ready WAITS, and lands once '
      'they are', (tester) async {
    aStepNotReady();

    pictures.step(undo: true, apply: apply);

    // ⛔Mutation: land at once → the next frame has a blank tile in it.
    expect(applied, 0);
    await letThePicturesLand(tester);
    expect(applied, 1);
    expect(shown.drawable([(_key, next)]), isTrue);
    // ⛔Mutation: file the pictures made ahead under a scope → the
    // coordinate fallback would offer the NEXT step's picture for this one.
    for (final scope in <Object?>[null, (_key.layerId, _key.frameId)]) {
      expect(
        cache.latestImageForCoord(TileCoord(x: 0, y: 0), scope: scope),
        isNull,
      );
    }
  });

  testWidgets('a picture still coming in is not waited for — the step '
      'cannot make it any less whole', (tester) async {
    aStepNotReady(nowIsWhole: false);

    pictures.step(undo: true, apply: apply);

    // ⛔Mutation: wait whatever is on screen now → the press held for
    // nothing, and every headless test's undo with it.
    expect(applied, 1);
  });

  testWidgets('a tile the decoder REFUSED is not waited for forever', (
    tester,
  ) async {
    debugRawRgbaUploader =
        (
          Uint8List rgba, {
          required int width,
          required int height,
          int? targetWidth,
          int? targetHeight,
        }) => Future<ui.Image>.error(StateError('the engine refused it'));
    addTearDown(() => debugRawRgbaUploader = null);
    final refusals = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => refusals.add(details.exception);
    aStepNotReady();

    pictures.step(undo: true, apply: apply);
    await letThePicturesLand(tester);
    FlutterError.onError = previous;

    expect(refusals, isNotEmpty, reason: 'the premise: the decoder refused');
    // ⛔Mutation: count a refused tile as not drawable → the press waits
    // for a picture that is never coming.
    expect(applied, 1);
  });

  testWidgets('a touch while it waits drops the press', (tester) async {
    aStepNotReady();
    pictures.step(undo: true, apply: apply);

    tester.binding.handlePointerEvent(
      const PointerDownEvent(position: Offset(4, 4)),
    );
    tester.binding.handlePointerEvent(
      const PointerUpEvent(position: Offset(4, 4)),
    );
    await letThePicturesLand(tester);

    // ⛔Mutation: no pointer route → it lands under whatever the user
    // began after pressing.
    expect(applied, 0);
  });

  testWidgets('a history that moved while it waited drops the press', (
    tester,
  ) async {
    aStepNotReady();
    pictures.step(undo: true, apply: apply);

    history.execute(_Nothing());
    await letThePicturesLand(tester);

    // ⛔Mutation: skip the revision → an undo of something nobody asked to
    // undo.
    expect(applied, 0);
  });

  testWidgets('work the adoption would take drops the press', (tester) async {
    aStepNotReady();
    pictures.step(undo: true, apply: apply);

    history.pendingBeforeUndoRedo = () => true;
    await letThePicturesLand(tester);

    // ⛔Mutation: skip the question → a lift landed out from under the hand.
    expect(applied, 0);
  });

  testWidgets('pressed again the same way it is still ONE step; the other '
      'way takes it back', (tester) async {
    aStepNotReady();
    pictures.step(undo: true, apply: apply);
    pictures.step(undo: true, apply: apply);
    await letThePicturesLand(tester);
    // ⛔Mutation: queue the presses → undoing goes on after the key is up.
    expect(applied, 1);

    aStepNotReady();
    pictures.step(undo: true, apply: apply);
    pictures.step(undo: false, apply: apply);
    await letThePicturesLand(tester);
    // ⛔Mutation: the other way counted as the same way → the undo lands.
    expect(applied, 0);
  });

  testWidgets('where the engine uploads on the spot, the step lands at once '
      'and whole', (tester) async {
    debugSyncImageUploadOverride = (pixels, width, height) => _solid();
    addTearDown(() => debugSyncImageUploadOverride = null);
    aStepNotReady();

    pictures.step(undo: true, apply: apply);

    // ⛔Mutation: skip the on-the-spot upload → it waits the way Skia must.
    expect(applied, 1);
    expect(shown.drawable([(_key, next)]), isTrue);
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
    expect(shown.drawable([(_key, second)]), isFalse);
    await letThePicturesLand(tester);

    // ⛔Mutation: no warm after a landing → the next press has to wait.
    expect(shown.drawable([(_key, second)]), isTrue);
    pictures.step(undo: true, apply: history.undo);
    expect(history.undoCount, 0);
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
          inputSettings: BrushToolState.defaults.toInputSettings(),
          onSourceStrokeCommitted: (_) {},
        ),
      ),
    );

    // ⛔Mutation: no registration → a step on this cel never waits for
    // its pictures, and lands blank.
    expect(ShownCels.instance.isShown(_key), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(ShownCels.instance.isShown(_key), isFalse);
  });

  testWidgets('the session undoes THROUGH the pictures — a step that is not '
      'ready waits', (tester) async {
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

    // ⛔Mutation: undo straight to the history → it lands over a blank.
    expect(session.historyManager.undoCount, before);
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
    // UNFILED, like the pictures made ahead: a scope with something in it
    // would hide the one test below that asks the scopes are left alone.
    cache.adoptDecoded(
      (coord: entry.key, tile: entry.value),
      _solid(),
      staleScope: BitmapTileImageCache.unfiled,
    );
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
}

class _Nothing implements Command {
  @override
  String get description => 'nothing';

  @override
  void execute() {}

  @override
  void undo() {}
}
