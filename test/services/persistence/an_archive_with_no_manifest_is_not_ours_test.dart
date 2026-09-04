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
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

/// 🚨AN ARCHIVE WITH NO MANIFEST IS NOT OURS EITHER.
///
/// The vacuous-ownership guard (a fresh project's cels are ALL dirty, so
/// "my clean bytes are where I left them" proves nothing) reads the
/// target's own project.json and compares ids. Its first branch is the
/// entry not being there at all — a zip at our name that is not one of our
/// archives, or one whose manifest was lost.
///
/// That branch had no test: making it answer "ours" broke nothing in the
/// suite (the audit's mutation pass, 2026-09-05), and an append onto a
/// stranger's zip keeps every foreign entry alive under the new
/// project.json — the same silent retention the id comparison exists to
/// stop.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-manifestless');
  });

  tearDown(() => directory.delete(recursive: true));

  BrushFrameKey key(String project, String frame) => BrushFrameKey(
    projectId: ProjectId(project),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  /// Renames the manifest entry in place — same length, so every offset in
  /// the file stays exactly where the central directory says it is. The
  /// result parses as a zip and holds real entries; it simply has no
  /// manifest we can read an id out of.
  void loseTheManifest(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    final wanted = anicelProjectEntryNameCompressed.codeUnits;
    var hits = 0;
    for (var i = 0; i + wanted.length <= bytes.length; i += 1) {
      var matches = true;
      for (var j = 0; j < wanted.length; j += 1) {
        if (bytes[i + j] != wanted[j]) {
          matches = false;
          break;
        }
      }
      if (!matches) {
        continue;
      }
      bytes[i + wanted.length - 1] = 0x58; // 'X'
      hits += 1;
    }
    expect(
      hits,
      2,
      reason:
          'fixture: the name lives in the local header and the central '
          'directory, and both have to move together',
    );
    file.writeAsBytesSync(bytes, flush: true);
  }

  test('Save As onto a zip with NO manifest replaces it whole', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/shared name.anicel';

    final theirStore = BrushFrameStore();
    theirStore.storeBakedSurface(key('theirs', 'f1'), inked(3));
    theirStore.storeBakedSurface(key('theirs', 'f2'), inked(5));
    await service.save(
      project: createDefaultProject().copyWith(id: const ProjectId('theirs')),
      brushFrameStore: theirStore,
      filePath: path,
    );
    loseTheManifest(path);
    expect(
      parseAnicelZipLayoutFile(path).projectEntry(),
      isNull,
      reason: 'the premise: a parseable archive whose manifest we cannot find',
    );

    // A fresh project — every cel dirty, no refs into anything.
    final ourStore = BrushFrameStore();
    ourStore.storeBakedSurface(key('ours', 'f1'), inked(9));
    await service.save(
      project: createDefaultProject().copyWith(id: const ProjectId('ours')),
      brushFrameStore: ourStore,
      filePath: path,
    );

    expect(
      {for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name},
      {anicelProjectEntryNameCompressed, anicelCelEntryName(key('ours', 'f1'))},
      reason:
          'an append would have kept both foreign cels alive under our '
          'project.json — bytes of a project nobody can open, and any '
          'unzip tool can',
    );
  });
}
