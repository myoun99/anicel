import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/brush_lift_move_history_command.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/commands/resize_cut_canvas_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/brush_canvas_fixture.dart';

/// 🚨★★★A READ-AHEAD IS A HEAD START, NEVER A SECOND PICTURE
/// (undo-held-tile-pictures, stage 1). The next step's parked payload is
/// read back BEFORE the press, so its pictures can be ready when it lands
/// — and the one way that could go wrong is a copy put together against a
/// cel that moved on in between. These pin that a copy is adopted only
/// against the very surface it leaned on, that the budget can take it back
/// without losing anything, and that the history reads a step the way the
/// step will run it.
///
/// Every case names the mutation that turns it red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one snapshot', () {
    const size = 8;
    const canvas = CanvasSize(width: 64, height: 64);
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );

    PlacedTile tileOf(int x, int fill) => (
      coord: TileCoord(x: x, y: 0),
      tile: BitmapTile(
        size: size,
        pixels: BitmapTile.blank(size: size).pixels
          ..fillRange(0, BitmapTile.bytesFor(size), fill),
      ),
    );

    BitmapSurface surfaceOf(Iterable<PlacedTile> tiles) => BitmapSurface(
      canvasSize: canvas,
      tileSize: size,
      tiles: {for (final t in tiles) t.coord: t.tile},
    );

    // Two tiles: one the entry shares with its neighbour, one it alone
    // holds — the shape every parked payload has.
    late PlacedTile shared;
    late PlacedTile mine;
    late UndoSurfaceSnapshot snapshot;

    setUp(() async {
      shared = tileOf(0, 11);
      mine = tileOf(1, 22);
      snapshot = UndoSurfaceSnapshot(
        key: key,
        snapshot: surfaceOf([shared, mine]),
        sharedWith: surfaceOf([shared]),
      );
      expect(await snapshot.park(), isTrue);
      expect(snapshot.residentBytes, 0);
    });

    test('reading ahead holds the picture in RAM, still parked', () {
      final live = surfaceOf([shared]);

      final ahead = snapshot.readAhead(live)!;

      expect(identical(ahead.tiles[shared.coord], shared.tile), isTrue);
      expect(ahead.tiles[mine.coord]!.pixels, mine.tile.pixels);
      // ⛔Mutation: leave the copy off the books → RAM the budget cannot
      // see, the very thing the census work exists to end.
      expect(snapshot.residentBytes, BitmapTile.bytesFor(size));
      expect(snapshot.isParked, isTrue);
      // Asked again against the same cel: the same copy, not a second read.
      expect(identical(snapshot.readAhead(live), ahead), isTrue);
    });

    test('the step ADOPTS what was read against the cel it is handed', () {
      final live = surfaceOf([shared]);
      final ahead = snapshot.readAhead(live)!;

      final restored = snapshot.surfaceOver(live);

      // ⛔Mutation: read the file again in the step → another object, and
      // the pictures made for this one go unused.
      expect(identical(restored, ahead), isTrue);
      expect(snapshot.isParked, isFalse);
      expect(snapshot.residentBytes, BitmapTile.bytesFor(size));
    });

    test('🚨a cel that moved on gets the EXACT picture, never the read-ahead',
        () {
      snapshot.readAhead(surfaceOf([shared]));
      // The cel moved on in between: the shared coordinate holds another
      // tile now — what a lift's erase, or any edit, would leave there.
      final moved = tileOf(0, 33);

      final restored = snapshot.surfaceOver(surfaceOf([moved]))!;

      // ⛔Mutation: adopt the read-ahead whatever the cel → the tile the
      // cel no longer has, painted back over it.
      expect(identical(restored.tiles[shared.coord], moved.tile), isTrue);
      expect(restored.tiles[mine.coord]!.pixels, mine.tile.pixels);
    });

    test('the budget takes a read-ahead back — and the file was kept, so '
        'nothing is lost', () async {
      final live = surfaceOf([shared]);
      snapshot.readAhead(live);

      expect(await snapshot.park(), isTrue);

      // ⛔Mutation: park() keeps the copy → RAM that never goes.
      expect(snapshot.residentBytes, 0);
      expect(snapshot.isParked, isTrue);
      // ⛔Mutation: remove the file at the read-ahead → nothing to read here.
      final restored = snapshot.surfaceOver(live)!;
      expect(restored.tiles[mine.coord]!.pixels, mine.tile.pixels);
    });

    test('an entry that left the stack reads nothing ahead', () {
      snapshot.drop();

      // ⛔Mutation: skip the dropped check → a picture from a deleted file's
      // leftovers, or a read of a file that is gone.
      expect(snapshot.readAhead(surfaceOf([shared])), isNull);
    });
  });

  group('the history reads a step the way the step runs', () {
    // Four 128px tiles: room for a stroke to leave some of them alone.
    const cel = CanvasSize(width: 256, height: 256);

    BrushStrokeHistoryCommand stroke(
      BrushFrameEditingCoordinator coordinator,
      int color,
      List<CanvasPoint> centres,
      double size,
    ) => BrushStrokeHistoryCommand(
      coordinator: coordinator,
      strokeData: BrushStrokeCommitData(
        sourceDabs: [
          for (var i = 0; i < centres.length; i += 1)
            BrushDab(
              center: centres[i],
              color: color,
              size: size,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.square,
              pressure: 1,
              sequence: i,
            ),
        ],
      ),
    );

    BrushStrokeHistoryCommand fill(BrushFrameEditingCoordinator c, int color) =>
        stroke(c, color, [CanvasPoint(x: 128, y: 128)], 252);

    BrushFrameEditingCoordinator newCel() =>
        BrushCanvasFixture.createCoordinator(
          frameKeys: BrushCanvasFixture.createFrameKeys(),
          canvasSize: cel,
        );

    test('the next undo is read against the cel as it stands, and the undo '
        'adopts it', () async {
      final coordinator = newCel();
      final key = coordinator.activeFrameKey;
      final history = HistoryManager();
      addTearDown(history.dispose);
      final strokes = [
        for (final color in const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF])
          fill(coordinator, color),
      ];
      final pictures = <BitmapSurface>[];
      for (final each in strokes) {
        history.execute(each);
        pictures.add(coordinator.currentSurfaceOf(key));
      }
      // The deep two parked, the way the spill leaves them.
      expect(await strokes[0].parkPayload(), isTrue);
      expect(await strokes[1].parkPayload(), isTrue);
      history.undo(); // The top one, still resident.

      final ahead = history.readAhead(undo: true, wants: (_) => true);

      expect(ahead.keys, [key]);
      final now = ahead[key]!.now;
      expect(identical(now, coordinator.currentSurfaceOf(key)), isTrue);
      final next = ahead[key]!.next;
      _expectSamePixels(next, pictures[0]);
      history.undo();
      // ⛔Mutation: the step reads the file again → another object.
      expect(identical(coordinator.currentSurfaceOf(key), next), isTrue);
    });

    test('a cel nobody shows is not read — its payload stays in the room',
        () async {
      final coordinator = newCel();
      final history = HistoryManager();
      addTearDown(history.dispose);
      final strokes = [
        for (final color in const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF])
          fill(coordinator, color),
      ];
      strokes.forEach(history.execute);
      expect(await strokes[0].parkPayload(), isTrue);
      expect(await strokes[1].parkPayload(), isTrue);
      history.undo();

      final ahead = history.readAhead(undo: true, wants: (_) => false);

      expect(ahead, isEmpty);
      // ⛔Mutation: read whatever [wants] says → a disk read, and RAM, for
      // pictures nobody will draw.
      expect(strokes[1].estimatedRetainedBytes(undone: false), 0);
      history.readAhead(undo: true, wants: (_) => true);
      expect(strokes[1].estimatedRetainedBytes(undone: false), greaterThan(0));
    });

    test('🚨a composite is read in the order its step runs — a later child '
        'leans on what an earlier one put back', () async {
      final coordinator = newCel();
      final key = coordinator.activeFrameKey;
      final history = HistoryManager();
      addTearDown(history.dispose);
      history.execute(fill(coordinator, 0xFFFF0000));
      final red = coordinator.currentSurfaceOf(key);
      // Green on the left column only, blue on the right column only: each
      // leaves the other's tiles alone, so each payload SHARES the other
      // half — and the left undo's shared half is what the right undo put
      // back a moment earlier.
      final left = stroke(coordinator, 0xFF00FF00, [
        CanvasPoint(x: 64, y: 64),
        CanvasPoint(x: 64, y: 192),
      ], 112);
      final right = stroke(coordinator, 0xFF0000FF, [
        CanvasPoint(x: 192, y: 64),
        CanvasPoint(x: 192, y: 192),
      ], 112);
      final both = CompositeCommand(
        description: 'both',
        commands: [left, right],
      );
      history.execute(both);
      expect(await both.parkPayload(), isTrue);

      final ahead = history.readAhead(undo: true, wants: (_) => true);

      _expectSamePixels(ahead[key]!.next, red);
      history.undo();
      // ⛔Mutation: walk the children in execute order → each read leans
      // on a surface the step never hands in, the step reads the files
      // again, and what was read ahead is not what lands.
      expect(
        identical(coordinator.currentSurfaceOf(key), ahead[key]!.next),
        isTrue,
      );
    });

    test('the next REDO is read too, and the redo adopts it', () async {
      final coordinator = newCel();
      final key = coordinator.activeFrameKey;
      final history = HistoryManager();
      addTearDown(history.dispose);
      final strokes = [
        for (final color in const [0xFFFF0000, 0xFF00FF00])
          fill(coordinator, color),
      ];
      final pictures = <BitmapSurface>[];
      for (final each in strokes) {
        history.execute(each);
        pictures.add(coordinator.currentSurfaceOf(key));
      }
      history.undo();
      // The undone one parked, the way the spill parks redo first.
      expect(await strokes[1].parkPayload(), isTrue);

      final ahead = history.readAhead(undo: false, wants: (_) => true);

      // ⛔Mutation: read the before-half for a redo → the very picture the
      // redo is about to take away.
      _expectSamePixels(ahead[key]!.next, pictures[1]);
      history.redo();
      expect(
        identical(coordinator.currentSurfaceOf(key), ahead[key]!.next),
        isTrue,
      );
    });

    test('a confirmed move is read the same way, and its undo adopts it',
        () async {
      final coordinator = newCel();
      final key = coordinator.activeFrameKey;
      final history = HistoryManager();
      addTearDown(history.dispose);
      history.execute(fill(coordinator, 0xFFFF0000));
      final red = coordinator.currentSurfaceOf(key);
      final move = BrushLiftMoveHistoryCommand(
        coordinator: coordinator,
        frameKey: key,
        preLiftSurface: red,
        landingDabs: [
          BrushDab(
            center: CanvasPoint(x: 192, y: 192),
            color: 0xFF0000FF,
            size: 100,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
      history.execute(move);
      expect(await move.parkPayload(), isTrue);

      final ahead = history.readAhead(undo: true, wants: (_) => true);

      // ⛔Mutation: read the after-half for an undo → the landed stamp.
      _expectSamePixels(ahead[key]!.next, red);
      history.undo();
      expect(
        identical(coordinator.currentSurfaceOf(key), ahead[key]!.next),
        isTrue,
      );
    });

    test('a resize undo reads its cels with the reader its undo uses, and '
        'the undo adopts them', () async {
      final project = createDefaultProject();
      final track = project.tracks.first;
      final cut = track.cuts.first;
      final key = BrushFrameKey(
        projectId: project.id,
        trackId: track.id,
        cutId: cut.id,
        layerId: const LayerId('l'),
        frameId: const FrameId('f'),
      );
      final store = BrushFrameStore()
        ..storeBakedSurface(
          key,
          BitmapSurface(
            canvasSize: cut.canvasSize,
            tileSize: 128,
            tiles: {
              TileCoord(x: 1, y: 1): BitmapTile(
                size: 128,
                pixels: BitmapTile.blank(size: 128).pixels
                  ..fillRange(0, BitmapTile.bytesFor(128), 0x7F),
              ),
            },
          ),
        );
      final original = store.bakedSurfaceOrNull(key)!;
      final history = HistoryManager();
      addTearDown(history.dispose);
      final resize = ResizeCutCanvasCommand(
        repository: ProjectRepository(initialProject: project),
        cutId: cut.id,
        canvasSize: CanvasSize(
          width: cut.canvasSize.width - 128,
          height: cut.canvasSize.height - 128,
        ),
        anchor: CanvasResizeAnchor.center,
        brushFrameStore: store,
      );
      history.execute(resize);
      expect(await resize.parkPayload(), isTrue);

      final ahead = history.readAhead(undo: true, wants: (_) => true);

      // ⛔Mutation: read nothing for a resize → its undo lands on tiles
      // whose pictures nobody made.
      _expectSamePixels(ahead[key]!.next, original);
      history.undo();
      expect(
        identical(store.bakedSurfaceOrNull(key), ahead[key]!.next),
        isTrue,
      );
    });

    test('🚨when the budget runs out, the read-ahead copies go before any '
        'entry does', () async {
      final coordinator = newCel();
      final history = HistoryManager();
      addTearDown(history.dispose);
      addTearDown(() => VolatileScratchFiles.ceilingBytes = 0);
      final strokes = [
        for (final color in const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF])
          fill(coordinator, color),
      ];
      strokes.forEach(history.execute);
      expect(await strokes[0].parkPayload(), isTrue);
      expect(await strokes[1].parkPayload(), isTrue);
      history.undo();
      history.readAhead(undo: true, wants: (_) => true);
      final copy = strokes[1].estimatedRetainedBytes(undone: false);
      expect(copy, greaterThan(0), reason: 'the premise: a copy was read');
      // Exactly what the redo entry holds, so the copy IS the excess.
      history.byteBudget = history.retainedBytes - copy;

      history.readAhead(undo: true, wants: (_) => true);
      await history.drainSpilling();

      // ⛔Mutation: shed without giving the copies back first → the redo
      // entry goes, a step lost to keep a head start.
      expect(history.redoCount, 1);
      expect(strokes[1].estimatedRetainedBytes(undone: false), 0);
    });
  });

  test('the revision moves with every change to the stacks', () {
    final history = HistoryManager();
    addTearDown(history.dispose);
    final seen = <int>[history.revision];
    history.execute(_Nothing());
    seen.add(history.revision);
    history.undo();
    seen.add(history.revision);
    history.redo();
    seen.add(history.revision);
    history.clear();
    seen.add(history.revision);

    // ⛔Mutation: any one of the four stops counting → a step that waited
    // lands over a history that moved.
    expect(seen.toSet(), hasLength(seen.length));
  });
}

void _expectSamePixels(BitmapSurface actual, BitmapSurface expected) {
  expect(actual.tiles.keys.toSet(), expected.tiles.keys.toSet());
  for (final entry in expected.tiles.entries) {
    expect(
      actual.tiles[entry.key]!.pixels,
      entry.value.pixels,
      reason: 'the tile at ${entry.key}',
    );
  }
}

class _Nothing implements Command {
  @override
  String get description => 'nothing';

  @override
  void execute() {}

  @override
  void undo() {}
}
