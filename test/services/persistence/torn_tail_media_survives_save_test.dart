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
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import '../../helpers/temp_dir.dart';

/// The heal save must not be the destroyer.
///
/// An append crash destroys only the file's TAIL — the crash contract —
/// so the media entries' bytes survive in the body, and the next save is
/// the heal that streams them forward. But the save resolved its sources
/// with the strict tail parser: a torn tail read as "nothing is inside",
/// a carried asset whose import original was gone (the whole reason
/// carrying exists) was silently omitted, and the full rewrite renamed a
/// media-less archive over the file that still physically held the bytes.
/// Silent, permanent loss, on the exact flow that advertises itself as
/// recovery.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-torn-media');
  });

  tearDown(() => deleteTempQuietly(directory));

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
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
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  test('a torn tail does not cost the carried media its bytes — the heal '
      'save streams them forward', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/project.anicel';
    final audioPath = '${directory.path.replaceAll('\\', '/')}/대사.wav';
    final audioBytes = List<int>.generate(300, (i) => (i * 7) & 0xFF);
    File(audioPath).writeAsBytesSync(audioBytes, flush: true);

    final project = createDefaultProject().copyWith(
      mediaAssets: [MediaAsset(path: audioPath, name: '대사.wav', carried: true)],
    );
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
      mediaToStore: {audioPath: MediaFileBytes(audioPath)},
    );
    final mediaEntryNames = mediaEntryNamesFor({
      audioPath: MediaFileBytes(audioPath),
    });

    // The import original leaves — carrying exists so this is survivable.
    File(audioPath).deleteSync();

    // An append crash tears the tail: everything below the central
    // directory survives, the tail does not.
    final healthy = parseAnicelZipLayoutFile(path);
    File(path).openSync(mode: FileMode.append)
      ..truncateSync(healthy.centralDirectoryOffset + 7)
      ..closeSync();
    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);

    // The save-side resolution must still find the bytes — the walk
    // recovers what the tail no longer names.
    final sources = projectMediaSources(
      project: project,
      projectFilePath: path,
      mediaEntryNames: mediaEntryNames,
    );
    expect(
      sources[audioPath],
      isA<MediaArchiveBytes>(),
      reason:
          'the torn file still holds the bytes; "nothing is inside" '
          'was the answer that made the heal save destroy them',
    );

    // The heal itself: one edited cel, then the save the open flow
    // promises will make the file whole again.
    store.storeBakedSurface(key('f1'), inked(9));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
      mediaToStore: sources,
    );

    final healed = parseAnicelZipLayoutFile(path);
    final mediaEntry = healed.entryNamed(anicelMediaEntryName(audioPath));
    expect(mediaEntry, isNotNull, reason: 'the media survived the heal');
    final raf = File(path).openSync();
    try {
      raf.setPositionSync(mediaEntry!.dataOffset);
      expect(
        raf.readSync(mediaEntry.length),
        audioBytes,
        reason: 'byte-exactly',
      );
    } finally {
      raf.closeSync();
    }
  });

  test('an asset recorded INSIDE and found nowhere refuses the save '
      'loudly instead of certifying the loss', () {
    final audioPath = '${directory.path.replaceAll('\\', '/')}/gone.wav';
    final project = createDefaultProject().copyWith(
      mediaAssets: [
        MediaAsset(path: audioPath, name: 'gone.wav', carried: true),
      ],
    );
    // A valid archive that simply does not hold the entry — and no
    // original on disk either. Proceeding would write an archive without
    // the asset and rename it over whatever still had the bytes.
    final archivePath = '${directory.path}/empty.anicel';
    writeAnicelArchiveFile(path: archivePath, entries: const []);

    expect(
      () => projectMediaSources(
        project: project,
        projectFilePath: archivePath,
        mediaEntryNames: mediaEntryNamesFor({
          audioPath: MediaFileBytes(audioPath),
        }),
      ),
      throwsStateError,
    );
  });
}
