import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
import '../../helpers/temp_dir.dart';

/// A full save sweeps ITS OWN stale temps from the project's folder — and
/// nothing else's files.
///
/// A process kill mid-full-save (or a rename that even the retry could
/// not land) leaves `<project>.anicel.tmp-<micros>` behind: project-sized,
/// in the USER'S folder, uploaded by whatever sync client watches it, and
/// named with a timestamp no later save ever reuses. The recovery folder
/// had this sweep from day one; the user's folder did not — but here only
/// the project's own temp prefix may be touched, because everything else
/// in that folder is the user's.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-sweep');
  });

  tearDown(() => deleteTempQuietly(directory));

  test('a successful full save collects this project\'s strays and leaves '
      'everything else alone', () async {
    const service = AnicelFileService();
    final path = '${directory.path.replaceAll('\\', '/')}/scene.anicel';

    // A stray from a killed earlier attempt, a DIFFERENT project's stray,
    // and an ordinary user file sharing the folder.
    final ourStray = File('$path.tmp-12345')..writeAsStringSync('stale');
    final theirStray = File('${directory.path}/other.anicel.tmp-9')
      ..writeAsStringSync('not ours');
    final userFile = File('${directory.path}/notes.txt')
      ..writeAsStringSync('keep');

    final store = BrushFrameStore();
    final pixels = Uint8List(8 * 8 * 4);
    store.storeBakedSurface(
      const BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('l'),
        frameId: FrameId('f1'),
      ),
      BitmapSurface(
        canvasSize: const CanvasSize(width: 16, height: 16),
        tileSize: 8,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: 8,
            pixels: pixels,
          ),
        },
      ),
    );
    await service.save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );

    expect(File(path).existsSync(), isTrue);
    expect(ourStray.existsSync(), isFalse, reason: 'our stray is collected');
    expect(theirStray.existsSync(), isTrue, reason: 'not ours to touch');
    expect(userFile.existsSync(), isTrue, reason: 'never the user\'s files');
  });
}
