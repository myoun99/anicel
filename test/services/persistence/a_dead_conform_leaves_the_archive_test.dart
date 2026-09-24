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
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**THE SETTINGS-CHANGE SWEEP, AND THE THING IT MUST NOT SWEEP.**
///
/// 유저 2026-08-30, answering `conform-in-project`: 「레이트 변경 등
/// 죽은파일만 깔끔하게 잘 걷어낼것」. A conform built under a rate the
/// project has left is dead weight — an hour of dialogue is ~428MB
/// compressed, and one per rate the project ever used is exactly the pile
/// the user asked not to have.
///
/// ⛔But「dead」and「not built on THIS machine yet」are different things,
/// and the first shape of this could not tell them apart: it asked whether
/// a conform sat at the current settings' CACHE path, and on a machine
/// that had only just opened the project the answer was no for every
/// sound. Open it somewhere new, draw one stroke, save — and every conform
/// the file carried would have been swept, on exactly the journey carrying
/// them exists to serve.
///
/// Two changes separate them, and both are needed. The settings ride in
/// the entry NAME, so a conform built at another rate is under a name this
/// project never asks for. And `projectConformSources` resolves from the
/// ARCHIVE as well as the cache, so a project that already holds one
/// answers with it rather than with nothing.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-conform-rm');
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

  /// A stand-in for the cached conform — this file is about the ARCHIVE
  /// side, so what matters is that these bytes are large and identifiable.
  String writeConform(String name, int length, int fill) {
    final path = '${directory.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsBytesSync(List<int>.filled(length, fill), flush: true);
    return path;
  }

  String conformName(
    String asset, {
    int sampleRate = 48000,
    int speedNumerator = 1,
    int speedDenominator = 1,
  }) => anicelConformEntryName(
    asset,
    sampleRate: sampleRate,
    speedNumerator: speedNumerator,
    speedDenominator: speedDenominator,
  );

  /// What a save is handed when this asset's conform is in the CACHE — a
  /// file to stream in.
  ProjectConforms carrying(
    String asset,
    String conformPath, {
    int sampleRate = 48000,
  }) => ProjectConforms({
    conformName(asset, sampleRate: sampleRate): MediaFileBytes(conformPath),
  });

  /// What a save is handed on a machine whose cache is EMPTY but whose
  /// project already holds the conform: the ARCHIVE's own entry, resolved
  /// out of the file being saved. This is what `projectConformSources`
  /// produces there, and reproducing its shape is the point of the test.
  ProjectConforms alreadyInside(
    String archivePath,
    String asset, {
    int sampleRate = 48000,
  }) {
    final name = conformName(asset, sampleRate: sampleRate);
    final entry = parseAnicelZipLayoutFile(archivePath).entryNamed(name);
    return entry == null
        ? const ProjectConforms.none()
        : ProjectConforms({
            name: MediaArchiveBytes(
              archivePath: archivePath,
              dataOffset: entry.dataOffset,
              length: entry.length,
              entryCrc32: entry.crc32,
            ),
          });
  }

  ({
    AnicelFileService service,
    String path,
    String audio,
    BrushFrameStore store,
  })
  project() {
    final path = '${directory.path}/project.anicel';
    final audio = '${directory.path.replaceAll('\\', '/')}/대사.wav';
    File(audio).writeAsBytesSync(List<int>.filled(200, 1), flush: true);
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    return (
      service: const AnicelFileService(),
      path: path,
      audio: audio,
      store: store,
    );
  }

  /// 🚨**THE BAR HAS TO KNOW THE CONFORMS ARE COMING.**
  ///
  /// A full rewrite writes the conforms LAST and they are the largest
  /// entries in the file — an hour of dialogue against a few cels. A
  /// denominator that counts only the cels and the media therefore reaches
  /// 1.0 before the biggest write begins, and the window sits at 100%
  /// through the whole of it. That is the same defect the append path was
  /// fixed for, and this asserts the property `_SaveProgress.finish` names:
  /// **the bar arrives at the end exactly once.** Arriving twice is what an
  /// end announced early looks like from outside.
  test('🚨 a full rewrite counts the conforms it is about to write', () async {
    final p = project();
    final reports = <double>[];
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      // Large on purpose: the conform has to be worth several reports of
      // its own, or a short denominator could hide inside the rounding.
      conforms: carrying(p.audio, writeConform('a.conform', 4 << 20, 7)),
      onProgress: reports.add,
    );

    expect(reports, isNotEmpty, reason: 'nothing crossed the port at all');
    expect(reports.last, 1.0);
    expect(
      reports.where((value) => value >= 1.0).length,
      1,
      reason:
          'the bar reached the end more than once — the denominator forgot '
          'an entry, so the rest of the write ran behind a full bar',
    );
  });

  test('🚨a conform built at OTHER settings leaves the archive', () async {
    final p = project();
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, writeConform('a.conform', 40000, 7)),
    );
    expect(
      parseAnicelZipLayoutFile(p.path).entryNamed(conformName(p.audio)),
      isNotNull,
    );

    // The project's audio rate moved to 44.1k. Nothing at 48k is a conform
    // this project may hold any more.
    p.store.storeBakedSurface(key('f1'), inked(5));
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: const ProjectConforms.none(),
    );

    final after = parseAnicelZipLayoutFile(p.path);
    expect(
      after.entryNamed(conformName(p.audio)),
      isNull,
      reason: 'a 48k conform in a 44.1k project is dead weight',
    );
    expect(
      after.entryNamed(anicelMediaEntryName(p.audio)),
      isNotNull,
      reason:
          '⛔and the SOUND stays. Sweeping the derived thing must never '
          'touch the thing it was derived from.',
    );
  });

  test('🚨⛔but an EMPTY CACHE does not make it dead', () async {
    final p = project();
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, writeConform('a.conform', 40000, 7)),
    );

    // Another machine: the project carries the conform, the cache holds
    // nothing, and the user draws one stroke and saves before any sound is
    // played. `projectConformSources` answers with the ARCHIVE's own
    // entry — which is the fix — and the entry must survive.
    p.store.storeBakedSurface(key('f1'), inked(5));
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: alreadyInside(p.path, p.audio),
    );

    final entry = parseAnicelZipLayoutFile(
      p.path,
    ).entryNamed(conformName(p.audio));
    expect(
      entry,
      isNotNull,
      reason:
          '⛔this is the data-loss shape. Sweeping by「what was written」 '
          'would take every conform on the first save after an open, which '
          'is the journey carrying them exists to serve.',
    );
    expect(entry!.length, 40000);
  });

  test('an UNCHANGED conform is not streamed again', () async {
    final p = project();
    final conformPath = writeConform('대사.conform', 400000, 7);
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, conformPath),
    );
    final afterFirst = File(p.path).lengthSync();

    p.store.storeBakedSurface(key('f1'), inked(5));
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, conformPath),
    );

    expect(
      File(p.path).lengthSync() - afterFirst,
      lessThan(100000),
      reason:
          '⛔the FILE LENGTH is the instrument. A save that re-streamed an '
          'unchanged conform would grow by another 400KB and pass every '
          'assertion about content — and on a real project that is '
          'hundreds of megabytes rewritten to change one drawing.',
    );
  });

  test('a REBUILT conform replaces the old bytes', () async {
    final p = project();
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, writeConform('a.conform', 40000, 7)),
    );

    // The source changed, so the pipeline rebuilt — a different conform at
    // the same address, under the same entry name.
    p.store.storeBakedSurface(key('f1'), inked(5));
    await p.service.save(
      project: createDefaultProject(),
      brushFrameStore: p.store,
      filePath: p.path,
      mediaToStore: {p.audio: MediaFileBytes(p.audio)},
      conforms: carrying(p.audio, writeConform('b.conform', 50000, 9)),
    );

    final entry = parseAnicelZipLayoutFile(
      p.path,
    ).entryNamed(conformName(p.audio))!;
    expect(entry.length, 50000);
    final raf = File(p.path).openSync();
    try {
      raf.setPositionSync(entry.dataOffset);
      expect(
        raf.readSync(entry.length),
        List<int>.filled(50000, 9),
        reason:
            'the rebuilt conform, not the one it replaced — a name already '
            'in the archive is not proof the bytes under it are current',
      );
    } finally {
      raf.closeSync();
    }
  });
}
