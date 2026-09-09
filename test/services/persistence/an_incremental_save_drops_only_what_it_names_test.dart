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

/// 🚨★★★**AN INCREMENTAL SAVE REMOVES WHAT IT CAN NAME, AND NOTHING
/// ELSE.**
///
/// The save's delete step exists for two jobs: media the project stopped
/// carrying, and conforms rendered under settings the project has moved
/// off. Both are chosen by PREFIX — `media/`, `conform/` — so an entry
/// under any other name is not a candidate, and the appender rebuilds the
/// central directory from「everything that was there, minus what I am
/// dropping」.
///
/// ⛔**Nothing tested that.** Every existing suite writes archives this
/// build wrote, so every entry in them is one of the kinds the sweep
/// already knows; a sweep widened to「anything not in my live set」would
/// have passed all of them and quietly eaten the first entry a later round
/// added. The round that turns autosave into a real incremental save adds
/// exactly such a kind, and this is the pin that has to be standing first.
///
/// 🧪The stand-in is an entry with a name from no prefix at all. It is not
/// a format proposal — it is the cheapest thing that is honestly OUTSIDE
/// what the sweep knows, which is the only property under test.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-drops-only');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

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

  test('🚨 an entry from no kind it knows SURVIVES an incremental save', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/project.anicel';
    final project = createDefaultProject();
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    // A stranger's row, appended the way this build appends anything.
    const strangerName = 'somebody-elses/row.bin';
    final strangerBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    appendAnicelEntries(
      path: path,
      newEntries: {strangerName: strangerBytes},
    );
    expect(
      parseAnicelZipLayoutFile(path).entryNamed(strangerName),
      isNotNull,
      reason: 'fixture: it is in the central directory to begin with',
    );

    // One edited cel — the ordinary incremental save, which rebuilds the
    // central directory and is therefore the moment a row can vanish.
    store.storeBakedSurface(key('f1'), inked(5));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final entry = parseAnicelZipLayoutFile(path).entryNamed(strangerName);
    expect(
      entry,
      isNotNull,
      reason: '⛔A save deletes what it can NAME — media the project '
          'stopped carrying, conforms at settings it moved off. An entry '
          'it does not recognise is not garbage it gets to collect; the '
          'next round puts a new kind in here and this is what says the '
          'sweep will leave it alone.',
    );

    final raf = File(path).openSync();
    try {
      raf.setPositionSync(entry!.dataOffset);
      expect(
        raf.readSync(entry.length),
        strangerBytes,
        reason: 'and it still points at the same bytes — surviving the '
            'directory rebuild is not the same as surviving intact',
      );
    } finally {
      raf.closeSync();
    }
  });

  test('🚨 but a COMPACTION does NOT — it rebuilds from what the project '
      'holds, and that is the trap for whoever adds the next kind', () async {
    // ⛔This pins the behaviour, it does not bless it. The two roads out
    // of a save are not the same shape: an APPEND rebuilds the central
    // directory from「everything that was there, minus what I drop」, so a
    // row it does not recognise rides along; a COMPACTION writes a new
    // file from the project's cels, media, conforms and project.json, so a
    // row nothing enumerates is simply never written.
    //
    // 🚨Nothing loses anything today — this build is the only writer, and
    // every entry it makes is one of those kinds. The next round puts a
    // new kind of entry in the archive, and it would pass every existing
    // test, survive appends, and vanish the first time the garbage ratio
    // crossed the threshold — hours later, on somebody's real project.
    // Whoever adds it: put it in the rebuild, or find this test failing
    // and know why.
    const service = AnicelFileService();
    final path = '${directory.path}/compacted.anicel';
    final project = createDefaultProject();
    final store = BrushFrameStore();
    for (var i = 0; i < 4; i += 1) {
      store.storeBakedSurface(key('f$i'), inked(i + 1));
    }
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    const strangerName = 'somebody-elses/row.bin';
    final strangerBytes = Uint8List.fromList(List<int>.filled(96, 7));
    appendAnicelEntries(
      path: path,
      newEntries: {strangerName: strangerBytes},
    );

    // Rewrite the same cels over and over: each pass shadows the last, so
    // the garbage ratio climbs until the save compacts instead of
    // appending.
    final before = File(path).lengthSync();
    for (var pass = 0; pass < 6; pass += 1) {
      for (var i = 0; i < 4; i += 1) {
        store.storeBakedSurface(key('f$i'), inked(pass * 10 + i + 2));
      }
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
    }
    expect(
      File(path).lengthSync(),
      lessThan(before * 6),
      reason: 'fixture: the file must have been compacted at least once, or '
          'this test is the append one again',
    );

    expect(
      parseAnicelZipLayoutFile(path).entryNamed(strangerName),
      isNull,
      reason: 'a whole rewrite writes what the project holds. If this ever '
          'starts passing, somebody taught the rebuild to carry unknown '
          'rows across — which is a fine answer, and this test is then the '
          'place that says so out loud.',
    );
  });
}
