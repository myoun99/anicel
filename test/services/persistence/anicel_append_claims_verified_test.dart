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

/// The incremental append's claim — "my bytes are already in this file" —
/// is VERIFIED against the file, not assumed from the path.
///
/// Two ways the claim goes false with the path equal, both reached by Save
/// As landing on an existing name: the file is a DIFFERENT project's
/// archive (a fresh project's cels are all dirty, so the soundness
/// precondition passes vacuously — appending would keep every foreign
/// entry alive under the new project.json, silently retaining the replaced
/// project's whole content in the file), and a file replaced out from
/// under live refs (the pre-F-14 placeholder did exactly that), where an
/// append writes only the dirty cels and every clean one silently
/// vanishes.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-claims');
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

  test('Save As onto a FOREIGN archive replaces it whole — nothing of the '
      'old project survives underneath', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/shared name.anicel';

    // Someone else's project lives at the name first.
    final theirStore = BrushFrameStore();
    theirStore.storeBakedSurface(key('theirs', 'f1'), inked(3));
    theirStore.storeBakedSurface(key('theirs', 'f2'), inked(5));
    await service.save(
      project: createDefaultProject().copyWith(
        id: const ProjectId('theirs'),
      ),
      brushFrameStore: theirStore,
      filePath: path,
    );
    final theirEntries = {
      for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name,
    };
    expect(theirEntries.length, greaterThan(1));

    // A fresh project — every cel dirty, no refs into anything — saves to
    // the same name, as a Save As that confirmed the replacement does.
    final ourStore = BrushFrameStore();
    ourStore.storeBakedSurface(key('ours', 'f1'), inked(9));
    await service.save(
      project: createDefaultProject().copyWith(id: const ProjectId('ours')),
      brushFrameStore: ourStore,
      filePath: path,
    );

    final replaced = parseAnicelZipLayoutFile(path);
    final ourCelName = anicelCelEntryName(key('ours', 'f1'));
    expect(
      {for (final entry in replaced.entries) entry.name},
      {anicelProjectEntryNameCompressed, ourCelName},
      reason: 'replace means REPLACE — an append here would have kept every '
          'foreign cel alive under the new project.json, quietly retaining '
          'the other project\'s content (and its bytes for anyone with an '
          'unzip tool)',
    );
  });

  test('a file replaced out from under live refs fails LOUDLY instead of '
      'appending a hollow archive', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/live.anicel';
    final store = BrushFrameStore();
    final project = createDefaultProject().copyWith(
      id: const ProjectId('ours'),
    );
    store.storeBakedSurface(key('ours', 'f1'), inked(3));
    store.storeBakedSurface(key('ours', 'f2'), inked(5));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    // The file is replaced by a minimal valid archive behind the session's
    // back (what the pre-F-14 Save As placeholder did to the live project).
    // The refs still say their bytes are inside; the file no longer holds
    // them.
    File(path).writeAsBytesSync(const [
      0x50, 0x4B, 0x05, 0x06, //
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ], flush: true);

    // One cel edited; the other is clean and file-backed.
    store.storeBakedSurface(key('ours', 'f2'), inked(9));

    // The old behaviour appended project.json + the dirty cel onto the
    // empty archive and reported success — the clean cel silently ceased
    // to exist. The claim verification routes this to the full rewrite,
    // which tries to READ the clean cel from the gutted file and throws.
    // Loud beats silent: the bytes were already destroyed outside the
    // save; what the save must not do is certify the loss.
    // The message predicate keeps this honest: an unsendable-capture
    // mistake in the save isolate also throws, before reaching the file at
    // all — that throw must not green this expectation. (Not a type check:
    // IndexError from the gutted read IS an ArgumentError by inheritance.)
    await expectLater(
      service.save(project: project, brushFrameStore: store, filePath: path),
      throwsA(
        predicate(
          (error) => !'$error'.contains('isolate message'),
          'a failure from reading the gutted file, not from isolate '
          'messaging',
        ),
      ),
    );
  });

  test('a file swapped for a DIFFERENT healthy archive is never appended '
      'into — the clean cel survives or the save refuses', () async {
    // The gutted-file case above is also caught by the compaction check
    // (a placeholder is 100% garbage), so it cannot observe the claim
    // verification on its own. A HEALTHY foreign archive passes the
    // compaction check — the verification layer is the only thing standing
    // between it and a hollow append that silently drops every clean cel.
    const service = AnicelFileService();
    final path = '${directory.path}/swapped.anicel';
    final store = BrushFrameStore();
    final project = createDefaultProject().copyWith(
      id: const ProjectId('ours'),
    );
    store.storeBakedSurface(key('ours', 'f1'), inked(3));
    store.storeBakedSurface(key('ours', 'f2'), inked(5));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    // Behind the session's back, a different project's healthy archive
    // lands at the path (a sync client restoring the wrong file has this
    // exact shape). The refs still claim the path; the file no longer
    // holds their bytes.
    final foreignPath = '${directory.path}/foreign.anicel';
    final foreignStore = BrushFrameStore();
    foreignStore.storeBakedSurface(key('theirs', 'g1'), inked(7));
    await service.save(
      project: createDefaultProject().copyWith(
        id: const ProjectId('theirs'),
      ),
      brushFrameStore: foreignStore,
      filePath: foreignPath,
    );
    File(path).writeAsBytesSync(
      File(foreignPath).readAsBytesSync(),
      flush: true,
    );

    store.storeBakedSurface(key('ours', 'f2'), inked(9));

    Object? error;
    try {
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
    } on Object catch (thrown) {
      error = thrown;
    }
    // Refusing loudly is acceptable — the bytes were destroyed outside the
    // save. What is forbidden is the silent outcome: an append that writes
    // project.json + the dirty cel and reports success while the clean cel
    // quietly ceases to exist.
    if (error == null) {
      expect(
        parseAnicelZipLayoutFile(
          path,
        ).entryNamed(anicelCelEntryName(key('ours', 'f1'))),
        isNotNull,
        reason: 'a completed save must carry the clean cel — a hollow '
            'append would have written only the dirty one',
      );
    }
  });

  test('🚨an ordinary re-save APPENDS — it does not rewrite the file whole',
      () async {
    // The regression this pins: compressing the manifest made the
    // ownership check (which reads the target's project id) parse deflate
    // bytes as UTF-8, throw, and fall back to「replace, don't append」. Every
    // save became a full rewrite — on a project carrying media that means
    // re-streaming every megabyte on every Ctrl+S, silently.
    //
    // ⛔A size assertion is what catches it, because nothing else does: the
    // file is still correct after a full rewrite, just written the
    // expensive way.
    const service = AnicelFileService();
    final store = BrushFrameStore();
    final path = '${directory.path}/append.anicel';
    final project = createDefaultProject();

    store.storeBakedSurface(key('a', 'f1'), inked(1));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    final first = File(path).lengthSync();

    // ⚠️The SAME cel, re-inked: that kills its file ref, so there are ZERO
    // clean refs and the save takes the ownership-check branch — which is
    // the one that reads the manifest, and the one the regression broke.
    store.storeBakedSurface(key('a', 'f1'), inked(2));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      File(path).lengthSync(),
      greaterThan(first),
      reason:
          'an append leaves the superseded bytes behind, so the file GROWS. '
          'A full rewrite would land at roughly the same size and look fine.',
    );
  });
}
