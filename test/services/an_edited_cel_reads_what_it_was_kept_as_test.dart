import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/files_written_under.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨AN EDITED CEL HOLDS NO BYTE OF THE TILES ITS EDIT LEFT (card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu`; 🗣️유저 2026-11-21
/// on Q4, 「최대한 사본안만드는게 중요」, and on Q6, 「사본이나 ram에있는걸
/// 최대한 없애고싶어서」): what kept the cel is held on in the run's room
/// for them (`BrushFrameStore._heldOn`), and a tile whose slot the engine
/// lets go reads it there. ↩️Till that day the first edit of a kept cel
/// handed every tile of it its bytes — 🔬the user's line art, 337 tiles a
/// cel the mean, where a long line crosses 12.
///
/// And the room lets go of what it holds so: with the last tile that waits
/// for it, or — the cel kept anew — once each that waits is that cel's
/// still (`BrushFrameStore._letGoOfHeldBytes`). That a tile nothing holds
/// waits no more is held_bytes_go_with_the_last_tile_that_waits_test.dart's.
///
/// Here a cel of two tiles, the edit drawing on its right one — and a
/// keeper whose shells hold no bytes (`ShellsWithNoBytes`).
void main() {
  const canvasSize = CanvasSize(
    width: 2 * defaultCelTileSize,
    height: defaultCelTileSize,
  );
  const tileBytes = defaultCelTileSize * defaultCelTileSize * 4;
  final left = TileCoord(x: 0, y: 0);
  final right = TileCoord(x: 1, y: 0);
  BrushFrameKey named(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );
  final f = named('f');

  Uint8List pixelsOf(int seed) {
    final pixels = Uint8List(tileBytes);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed * 20 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return pixels;
  }

  BitmapTile inked(int seed) =>
      BitmapTile(size: defaultCelTileSize, pixels: pixelsOf(seed));

  BitmapSurface cel(int onTheLeft, int onTheRight) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: defaultCelTileSize,
    tiles: {left: inked(onTheLeft), right: inked(onTheRight)},
  );

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;

  setUp(() {
    engine = ShellsWithNoBytes();
    store = BrushFrameStore(shells: engine);
  });

  /// The cel, used and at rest: its shell, no byte of it here.
  BitmapSurface itsShell() {
    expect(store.bakedSurfaceOrNull(f), isNotNull, reason: '⛔premise');
    store.letGoOfBytesTheEngineHolds();
    final shell = store.hotBakedSurfaceOrNull(f)!;
    expect(shell.keptTileBytes, 0, reason: '⛔premise: a shell');
    return shell;
  }

  /// The cel — a shell a use took — hot no more, as a full pool has one
  /// let go whose slots went: the looks' shell again, its tiles written
  /// down still. The engine holds no slot from here, so a tile read is
  /// read where its bytes are kept.
  void cooled() {
    engine
      ..whole = false
      ..slots = false;
    store.coolWhereTheEngineLetGo(f);
    expect(store.hotBakedSurfaceOrNull(f), isNull, reason: '⛔premise');
  }

  /// [from] drawn on at its right tile alone, and stored.
  BitmapSurface drawOn(BitmapSurface from, int seed) {
    final drawn = from.copyWith(
      tiles: {left: from.tiles[left]!, right: inked(seed)},
    );
    store.storeBakedSurface(f, drawn);
    return drawn;
  }

  /// The cel — [under] the name it has by then — kept anew as a save keeps
  /// it: a stretch of a file holding [picture], adopted.
  void savedAs(BitmapSurface picture, {BrushFrameKey? under}) {
    final as = under ?? f;
    final snapshot = store.bakedSnapshotForSave();
    final saved = keepInAFile(BrushFrameStore(shells: ShellsWithNoBytes()), {
      as: picture,
    })[as]!;
    store.adoptSavedFile({
      as: saved,
    }, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
    expect(store.isCelFileBacked(as), isTrue, reason: '⛔premise: kept anew');
  }

  /// [tile] waits no more — here by its bytes coming.
  void waitsNoMore(BitmapTile tile) =>
      tile.readPixels((_, pixels) => tile.keepBytesHere(pixels));

  /// How many files lie in the run's room — under it, a store's cels
  /// lying in a folder of its own.
  int filesInTheRoom() =>
      filesWrittenUnder(Directory(SessionScratch.stagedFolder())).length;

  group('a cel the saved file keeps', () {
    late AnicelCelFileRef kept;

    setUp(() => kept = keepInAFile(store, {f: cel(4, 5)})[f]!);

    test('🚨drawn on, it weighs the tile drawn and no other — and the room '
        'holds what it was, once', () async {
      final shell = itsShell();
      final room = filesInTheRoom();

      drawOn(shell, 9);

      expect(store.hotBakedBytes, tileBytes);
      expect(shell.tiles[left]!.hasItsBytesHere, isFalse);
      expect(shell.tiles[right]!.hasItsBytesHere, isFalse);
      expect(store.keptBytesHeldOn, 1);
      expect(store.coldBakedBytes, kept.length);
      expect(filesInTheRoom(), room + 1);
      engine.slots = false;
      expect(shell.tiles[left]!.pixels, pixelsOf(4));
      expect(
        shell.tiles[right]!.pixels,
        pixelsOf(5),
        reason: 'the tile a step back holds: as it was',
      );
    });

    test('drawn on again, nothing more is held: the tiles that wait are '
        'of what it was first', () {
      final drawn = drawOn(itsShell(), 9);
      final room = filesInTheRoom();

      drawOn(drawn, 7);

      expect(store.keptBytesHeldOn, 1);
      expect(store.coldBakedBytes, kept.length);
      expect(filesInTheRoom(), room);
    });

    test('🚨kept anew, its tiles read what it is kept as now and the room '
        'lets go of what it was — ⛔not while a tile a step back holds '
        'waits', () async {
      final shell = itsShell();
      final leftAlone = shell.tiles[left]!;
      final steppedBack = shell.tiles[right]!;
      drawOn(shell, 9);
      savedAs(cel(4, 9));

      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 1, reason: 'one a step back holds waits');
      expect(store.coldBakedBytes, kept.length);
      engine.slots = false;
      expect(
        steppedBack.pixels,
        pixelsOf(5),
        reason: 'what the cel was, where it is kept as another now',
      );
      engine.slots = true;

      waitsNoMore(steppedBack);
      final room = filesInTheRoom();
      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 0);
      expect(store.coldBakedBytes, 0);
      expect(filesInTheRoom(), room - 1, reason: 'what it was: gone');
      expect(leftAlone.hasItsBytesHere, isFalse);
      engine.slots = false;
      expect(
        leftAlone.pixels,
        pixelsOf(4),
        reason: 'read by its cel\'s name: in the file that keeps it now',
      );
    });

    test('and the edit after that holds what the cel is kept as then, for '
        'the tile left alone twice', () async {
      final shell = itsShell();
      final leftAlone = shell.tiles[left]!;
      drawOn(shell, 9);
      savedAs(cel(4, 9));
      waitsNoMore(shell.tiles[right]!);
      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;
      expect(store.keptBytesHeldOn, 0, reason: '⛔premise: let go');
      final drawn = store.hotBakedSurfaceOrNull(f)!;
      final drawnOver = drawn.tiles[right]!;
      expect(drawnOver.hasItsBytesHere, isFalse, reason: '⛔premise: a shell');

      drawOn(drawn, 7);

      expect(store.keptBytesHeldOn, 1);
      expect(leftAlone.hasItsBytesHere, isFalse);
      engine.slots = false;
      expect(leftAlone.pixels, pixelsOf(4));
      expect(drawnOver.pixels, pixelsOf(9));
    });

    test('renamed while held for, it is followed by its new name: kept '
        'anew under that, the room lets go', () async {
      final shell = itsShell();
      final leftAlone = shell.tiles[left]!;
      drawOn(shell, 9);
      final h = named('h');
      store.rekeyFrames([(f, h)]);
      savedAs(cel(4, 9), under: h);
      waitsNoMore(shell.tiles[right]!);

      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 0);
      expect(store.coldBakedBytes, 0);
      engine.slots = false;
      expect(leftAlone.pixels, pixelsOf(4));
    });

    test('what is held goes for a cel a canvas stands on too: it is no '
        'pen\'s to wait for', () async {
      final shell = itsShell();
      drawOn(shell, 9);
      savedAs(cel(4, 9));
      waitsNoMore(shell.tiles[right]!);
      store.setCelsStoodOn(() => [f]);

      store.letGoOfBytesTheEngineHolds();

      expect(store.keptBytesHeldOn, 0);
    });

    test('🚨the tiles the room lets go for are written down as the '
        'cel\'s again — no shell made of it between, a canvas standing '
        'on it: the edit after holds what it is kept as then for '
        'them', () async {
      final shell = itsShell();
      final leftAlone = shell.tiles[left]!;
      drawOn(shell, 9);
      savedAs(cel(4, 9));
      waitsNoMore(shell.tiles[right]!);
      store.setCelsStoodOn(() => [f]);
      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;
      expect(store.keptBytesHeldOn, 0, reason: '⛔premise: let go');
      final drawn = store.hotBakedSurfaceOrNull(f)!;
      expect(
        drawn.tiles[right]!.hasItsBytesHere,
        isTrue,
        reason: '⛔premise: no shell made of it',
      );

      drawOn(drawn, 7);

      expect(store.keptBytesHeldOn, 1);
      engine.slots = false;
      expect(leftAlone.pixels, pixelsOf(4));
    });

    test('kept anew and hot no more, its tiles the looks\' shell\'s: the '
        'room lets go of what it was, as for a hot cel', () async {
      final shell = itsShell();
      final leftAlone = shell.tiles[left]!;
      final steppedBack = shell.tiles[right]!;
      drawOn(shell, 9);
      savedAs(cel(4, 9));
      store.letGoOfBytesTheEngineHolds();
      expect(store.keptBytesHeldOn, 1, reason: '⛔premise: one waits');
      cooled();
      waitsNoMore(steppedBack);

      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 0);
      expect(store.coldBakedBytes, 0);
      expect(leftAlone.hasItsBytesHere, isFalse);
      expect(
        leftAlone.pixels,
        pixelsOf(4),
        reason: 'read by its cel\'s name: in the file that keeps it now',
      );
    });

    test('🚨laid on another canvas where it is not hot — its kept bytes '
        'remade — the tiles that wait read what it was kept as: at that '
        'door, and at the rests after', () async {
      final shell = itsShell();
      final waiting = shell.tiles[left]!;
      cooled();

      store.resizeBakedSurfaces(
        const CanvasSize(
          width: defaultCelTileSize ~/ 2,
          height: defaultCelTileSize,
        ),
        cutId: const CutId('c'),
      );

      expect(store.isCelFileBacked(f), isFalse, reason: '⛔premise: remade');
      expect(store.isCelParked(f), isTrue, reason: '⛔premise: and parked');
      expect(store.keptBytesHeldOn, 1);
      expect(waiting.pixels, pixelsOf(4));

      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(
        store.keptBytesHeldOn,
        1,
        reason: 'the shell of what it was is no tile of what it is',
      );
      expect(waiting.pixels, pixelsOf(4));
    });
  });

  group('a cel parked in the run\'s room', () {
    late String park;

    setUp(() {
      parkCold(store, {f: cel(4, 5)});
      park = store.bakedSnapshotForSave().cold[f]!.filePath;
      expect(File(park).existsSync(), isTrue, reason: '⛔premise: parked');
    });

    test('🚨drawn on, its park is held on as it lies: no file written, '
        'none read, and the park the cel\'s no more', () async {
      final shell = itsShell();
      final room = filesInTheRoom();
      final held = store.coldBakedBytes;

      drawOn(shell, 9);
      await ScratchFile.lettingGo;

      expect(store.isCelParked(f), isFalse);
      expect(store.keptBytesHeldOn, 1);
      expect(filesInTheRoom(), room);
      expect(store.coldBakedBytes, held);
      expect(File(park).existsSync(), isTrue);
      expect(engine.reads, 0);
      engine.slots = false;
      expect(shell.tiles[left]!.pixels, pixelsOf(4));
    });

    test('🚨and goes with the last tile that waits for it', () async {
      final shell = itsShell();
      drawOn(shell, 9);

      waitsNoMore(shell.tiles[right]!);
      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;
      expect(File(park).existsSync(), isTrue, reason: 'one waits still');

      waitsNoMore(shell.tiles[left]!);
      store.letGoOfBytesTheEngineHolds();
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 0);
      expect(store.coldBakedBytes, 0);
      expect(File(park).existsSync(), isFalse);
    });

    test('a hand going down on it asks for nothing: its park is held on '
        'as it lies', () async {
      itsShell();
      final room = filesInTheRoom();
      final held = store.coldBakedBytes;

      await store.holdOnAhead(f);
      await ScratchFile.lettingGo;

      expect(filesInTheRoom(), room);
      expect(store.coldBakedBytes, held);
    });

    test('laid on another canvas where it is not hot, the park it was '
        'stays for the tiles that wait in it', () async {
      final shell = itsShell();
      final waiting = shell.tiles[left]!;
      cooled();

      store.resizeBakedSurfaces(
        const CanvasSize(
          width: defaultCelTileSize ~/ 2,
          height: defaultCelTileSize,
        ),
        cutId: const CutId('c'),
      );
      await ScratchFile.lettingGo;

      expect(File(park).existsSync(), isTrue);
      expect(store.keptBytesHeldOn, 1);
      expect(waiting.pixels, pixelsOf(4));
    });

    test('a park whose file is gone from the room holds nothing: the '
        'bytes come where the engine holds them', () async {
      final shell = itsShell();
      File(park).deleteSync();

      drawOn(shell, 9);

      expect(store.keptBytesHeldOn, 0);
      expect(shell.tiles[left]!.hasItsBytesHere, isTrue);
      expect(shell.tiles[left]!.pixels, pixelsOf(4));
    });
  });
}
