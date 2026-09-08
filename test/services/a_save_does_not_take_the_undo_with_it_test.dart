import 'dart:io';
import 'dart:typed_data';

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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/project_scratch_folder.dart';

/// 🚨★★★**THE SAVE DELETES IN ONE ROOM AND THE UNDO LIVES IN THE OTHER.**
///
/// This is the failure the two rooms exist to prevent, and it is the kind
/// nothing reports: the save succeeds, the archive is intact, the log is
/// quiet, and only pressing Ctrl+Z shows that the older edits stopped
/// coming back. A cooled cel is unsaved work waiting to move INTO the
/// project file and the save absorbs it — deleting its scratch file is
/// the save doing its job. An undo payload sits in 휘발성 and must be
/// standing when that is over.
///
/// ⚠️The premise is asserted, not assumed: the case fails if the save did
/// not actually delete anything in the staged room, because a test where
/// nothing was deleted proves nothing about deletion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvasSize = CanvasSize(width: 16, height: 16);
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey keyOf() => const BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapSurface surfaceOf(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        origin: BitmapTile(coord: origin, size: 8, pixels: pixels),
      },
    );
  }

  /// ⚠️Recursive: a cooled cel's name carries its own folder
  /// (`cels/<encoded>.celz`, so a crash dump can still say which picture
  /// it was), and a flat listing would find the room empty and prove
  /// nothing.
  List<String> filesIn(String folder) {
    final directory = Directory(folder);
    if (!directory.existsSync()) {
      return const [];
    }
    return [
      for (final entity in directory.listSync(recursive: true))
        if (entity is File) entity.path,
    ];
  }

  test('a save absorbs the cooled cel and takes its file — and the parked '
      'undo is still there, byte for byte', () async {
    final directory = await Directory.systemTemp.createTemp('qa-undo-save');
    deleteAfterSessionEnds(directory);

    final key = keyOf();
    final savedPicture = surfaceOf(17);
    final store = BrushFrameStore()
      ..restoreBaked({
        key: AnicelCelBlob.encode(
          AnicelCelEntry.fromSurface(key, savedPicture),
        ),
      });
    expect(store.isCelCold(key), isTrue, reason: 'a real file in 이사대기');
    final stagedBefore = filesIn(SessionScratch.stagedFolder());
    expect(stagedBefore, isNotEmpty);

    // The picture an undo would put back, parked in the OTHER room.
    final undonePicture = surfaceOf(99);
    final parked = UndoSurfaceSnapshot(
      key: key,
      snapshot: undonePicture,
      sharedWith: null,
    );
    expect(await parked.park(), isTrue);
    final volatileBefore = filesIn(SessionScratch.volatileFolder());
    expect(volatileBefore, isNotEmpty);

    await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: '${directory.path}/saved.anicel',
    );

    // The premise: the save really did delete in the staged room.
    expect(store.isCelFileBacked(key), isTrue);
    expect(store.isCelCold(key), isFalse);
    expect(
      stagedBefore.any((path) => !File(path).existsSync()),
      isTrue,
      reason: 'a case where nothing was deleted proves nothing about deletion',
    );

    // And the law: the other room was not touched.
    expect(
      volatileBefore.every((path) => File(path).existsSync()),
      isTrue,
      reason: '⛔the save must not reach 휘발성',
    );
    final restored = parked.surfaceOver(null);
    expect(restored, isNotNull, reason: 'the undo still has its payload');
    expect(
      restored!.tiles[origin]!.pixels,
      undonePicture.tiles[origin]!.pixels,
      reason: 'and it comes back byte for byte, after a full save',
    );
  });
}
