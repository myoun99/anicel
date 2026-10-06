import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_font_file.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_font_sources.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🚨★★★A PROJECT FILE CARRIES THE FONTS REGISTERED WITH IT (R9-rest, the
/// text tool's faces).
///
/// That a font a text is set in is saved WITH the project was settled in
/// the text tool's consultation (2026-10-06, item ③ — the session's
/// recommendation, answered 「권장대로」), and how long one stays is the
/// user's own sentence: 🗣️「뺄때까지 두는게 맞지않나 싶은데. 글꼴을 사실상
/// 등록하는거잖아. 프리미어프로처럼」. So a font's bytes go in under a name
/// minted for it, once; they stay for as long as the project's own list
/// names them — on a machine that was never brought the font too — and
/// leave with the first save after a person took the font out.
///
/// The journeys are the ones a carried conform is held to, for the same
/// reason (`a_dead_conform_leaves_the_archive_test`): 「what the project
/// may hold」 is not 「what this machine can write」.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-fonts-in-file');
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
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  /// A stand-in for a font file on this device: what matters here is that
  /// its bytes are large enough to see in a file's length, and its own.
  String deviceFont(String name, int length, int fill) {
    final path = '${directory.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsBytesSync(List<int>.filled(length, fill), flush: true);
    return path;
  }

  const sansName = 'ab12-cd34-font-1.ttf';
  const serifName = 'ef56-ab78-font-2.otf';

  ProjectFontFile registered(
    String carriedAs, {
    String family = 'Probe Sans',
  }) => ProjectFontFile(
    carriedAs: carriedAs,
    facts: FontFaceFacts(
      family: family,
      weight: 400,
      italic: false,
      fsType: 0,
    ),
  );

  Project carrying(List<ProjectFontFile> fonts) =>
      createDefaultProject().copyWith(fonts: fonts);

  /// What a save is handed on a device that HOLDS the fonts: each as a
  /// file to stream in.
  ProjectFontsToStore fromDevice(Map<String, String> pathByCarriedAs) =>
      ProjectFontsToStore(
        held: {
          for (final name in pathByCarriedAs.keys) anicelFontEntryName(name),
        },
        entries: {
          for (final entry in pathByCarriedAs.entries)
            anicelFontEntryName(entry.key): MediaFileBytes(entry.value),
        },
      );

  ({AnicelFileService service, String path, BrushFrameStore store}) saving() {
    final store = BrushFrameStore()..storeBakedSurface(key('f1'), inked(3));
    return (
      service: const AnicelFileService(),
      path: '${directory.path}/project.anicel',
      store: store,
    );
  }

  AnicelZipEntry? entryOf(String path, String carriedAs) =>
      parseAnicelZipLayoutFile(path).entryNamed(anicelFontEntryName(carriedAs));

  Uint8List bytesOf(String path, AnicelZipEntry entry) {
    final file = File(path).openSync();
    try {
      file.setPositionSync(entry.dataOffset);
      return file.readSync(entry.length);
    } finally {
      file.closeSync();
    }
  }

  test('🚨a font registered with the project is IN its file after a save, '
      'byte for byte, under the name minted for it', () async {
    final s = saving();
    final font = deviceFont('probe.ttf', 30000, 7);

    await s.service.save(
      project: carrying([registered(sansName)]),
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: font}),
    );

    final entry = entryOf(s.path, sansName);
    expect(entry, isNotNull);
    expect(entry!.name, 'fonts/$sansName');
    expect(bytesOf(s.path, entry), File(font).readAsBytesSync());
  });

  test('🚨a font the file already holds is NOT written again by a save '
      'that appends to it', () async {
    final s = saving();
    final font = deviceFont('probe.ttf', 400000, 7);
    final project = carrying([registered(sansName)]);
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: font}),
    );
    final afterFirst = File(s.path).lengthSync();

    s.store.storeBakedSurface(key('f1'), inked(5));
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: font}),
    );

    expect(
      File(s.path).lengthSync() - afterFirst,
      lessThan(100000),
      reason:
          '⛔the FILE LENGTH is the instrument: a save that streamed the '
          'font again would grow by another 400KB and pass every assertion '
          'about what the file holds.',
    );
    expect(entryOf(s.path, sansName)!.length, 400000);
  });

  test('🚨a font written once is what its name MEANS: other bytes offered '
      'under the same name later do not take its place', () async {
    final s = saving();
    final project = carrying([registered(sansName)]);
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: deviceFont('first.ttf', 30000, 7)}),
    );

    // The device was brought another file of the same face since — and
    // one of another LENGTH, which is what a conform would be rewritten
    // for.
    s.store.storeBakedSurface(key('f1'), inked(5));
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: deviceFont('second.ttf', 31000, 9)}),
    );

    final entry = entryOf(s.path, sansName)!;
    expect(entry.length, 30000);
    expect(bytesOf(s.path, entry).first, 7);
  });

  test('🚨a font a person took OUT of the project leaves its file with the '
      'next save — and the others stay', () async {
    final s = saving();
    final sans = deviceFont('sans.ttf', 30000, 7);
    final serif = deviceFont('serif.otf', 20000, 9);
    await s.service.save(
      project: carrying([registered(sansName), registered(serifName)]),
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({sansName: sans, serifName: serif}),
    );
    expect(entryOf(s.path, sansName), isNotNull, reason: '⛔fixture');
    expect(entryOf(s.path, serifName), isNotNull, reason: '⛔fixture');

    s.store.storeBakedSurface(key('f1'), inked(5));
    await s.service.save(
      project: carrying([registered(serifName)]),
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fromDevice({serifName: serif}),
    );

    expect(entryOf(s.path, sansName), isNull);
    expect(entryOf(s.path, serifName), isNotNull);
  });

  group('on a machine that was never brought the font', () {
    /// What `projectFontSources` hands a save there: the project's list
    /// names the font, and the only place its bytes are is the file being
    /// saved.
    ProjectFontsToStore heldInTheFile(String path, Project project) =>
        projectFontSources(
          project: project,
          projectFilePath: path,
          staging: null,
          deviceFontFile: (file) => null,
        );

    test('🚨⛔a save that changes one drawing keeps the font — the journey '
        'carrying it exists to serve', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)}),
      );

      s.store.storeBakedSurface(key('f1'), inked(5));
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: heldInTheFile(s.path, project),
      );

      final entry = entryOf(s.path, sansName);
      expect(entry, isNotNull);
      expect(entry!.length, 30000);
      expect(bytesOf(s.path, entry).first, 7);
    });

    test('🚨a save UNDER ANOTHER NAME carries it across: its bytes are '
        'streamed out of the file being left behind', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)}),
      );
      final copy = '${directory.path}/copy.anicel';

      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: copy,
        fonts: heldInTheFile(s.path, project),
        rewriteWhole: true,
      );

      final entry = entryOf(copy, sansName);
      expect(entry, isNotNull);
      expect(bytesOf(copy, entry!), List<int>.filled(30000, 7));
    });

    test('🚨a save that PACKS the file moves the font with the rest: its '
        'bytes are whole where they land, and found there', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)}),
      );
      // A hole in front of the font, as a deleted medium leaves: the next
      // save is past the garbage ratio, so it packs in place.
      appendAnicelEntries(
        path: s.path,
        newEntries: {'junk.bin': Uint8List(64 * 1024)},
      );
      appendAnicelEntries(
        path: s.path,
        newEntries: {
          anicelFontEntryName(sansName): bytesOf(
            s.path,
            entryOf(s.path, sansName)!,
          ),
        },
        removeNames: const {'junk.bin'},
      );
      final before = File(s.path).lengthSync();
      final was = entryOf(s.path, sansName)!.dataOffset;

      s.store.storeBakedSurface(key('f1'), inked(5));
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: heldInTheFile(s.path, project),
      );

      expect(
        File(s.path).lengthSync(),
        lessThan(before - 32 * 1024),
        reason: '⛔fixture: this save packed the file',
      );
      final entry = entryOf(s.path, sansName)!;
      expect(entry.dataOffset, lessThan(was), reason: '⛔fixture: it moved');
      expect(bytesOf(s.path, entry), List<int>.filled(30000, 7));
      expect(
        heldInTheFile(s.path, project)
            .entries[anicelFontEntryName(sansName)]!
            .readSync(),
        List<int>.filled(30000, 7),
      );
    });

    test('🚨a whole rewrite of the SAME file keeps it too', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)}),
      );

      s.store.storeBakedSurface(key('f1'), inked(5));
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: heldInTheFile(s.path, project),
        rewriteWhole: true,
      );

      final entry = entryOf(s.path, sansName);
      expect(entry, isNotNull);
      expect(bytesOf(s.path, entry!), List<int>.filled(30000, 7));
    });
  });

  group('🚨a font the project names whose bytes are NOWHERE this machine '
      'can reach', () {
    // Taken out, saved, and put back by an undo — on a machine that was
    // never brought it: the list names it again, and nothing holds it.
    final nowhere = ProjectFontsToStore(
      held: {anicelFontEntryName(sansName)},
      entries: const {},
    );

    test('does not fail the save, by either road — nothing is written for '
        'it and nothing else is lost', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);

      final lostWhole = await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: nowhere,
      );
      s.store.storeBakedSurface(key('f1'), inked(5));
      final lostAppended = await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: nowhere,
      );

      expect(lostWhole, isEmpty);
      expect(lostAppended, isEmpty);
      expect(entryOf(s.path, sansName), isNull);
      expect(
        parseAnicelZipLayoutFile(s.path).entryNamed(
          anicelCelEntryName(key('f1')),
        ),
        isNotNull,
      );
    });

    test('🚨⛔and takes nothing away: what LEAVES is asked of the names the '
        'project holds, never of what a save was handed bytes for', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)}),
      );
      expect(entryOf(s.path, sansName), isNotNull, reason: '⛔fixture');

      // A font is not something a machine can make again, as it can a
      // conform — so a save that was handed no bytes for one (its file
      // could not be read at that moment, say) is not a person taking it
      // out.
      s.store.storeBakedSurface(key('f1'), inked(5));
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: nowhere,
      );

      final entry = entryOf(s.path, sansName);
      expect(entry, isNotNull);
      expect(bytesOf(s.path, entry!), List<int>.filled(30000, 7));
    });

    test('and `projectFontSources` says exactly that of it: held, with no '
        'bytes to write', () {
      final project = carrying([registered(sansName)]);

      final sources = projectFontSources(
        project: project,
        projectFilePath: null,
        staging: null,
        deviceFontFile: (file) => null,
      );

      expect(sources.held, {anicelFontEntryName(sansName)});
      expect(sources.entries, isEmpty);
    });
  });

  group('where a font\'s bytes are read from', () {
    /// This run's room, with [bytes] kept in it under [name] — as a save
    /// that took the font out of its file leaves them.
    MediaStagingStore roomKeeping(String name, List<int> bytes) {
      final room = '${directory.path.replaceAll('\\', '/')}/Room';
      File('$room/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes, flush: true);
      return MediaStagingStore(directoryPath: room);
    }

    test('a project that carries none is handed nothing to hold', () {
      final sources = projectFontSources(
        project: carrying(const []),
        projectFilePath: null,
        staging: null,
        deviceFontFile: (file) => fail('nothing to ask about'),
      );

      expect(sources.held, isEmpty);
      expect(sources.entries, isEmpty);
    });

    test('the file this device\'s library keeps, where the project file '
        'has none yet — asked by the NAME the font is carried under', () {
      final sans = deviceFont('sans.ttf', 500, 7);
      final serif = deviceFont('serif.otf', 600, 9);
      final asked = <String>[];

      final sources = projectFontSources(
        project: carrying([registered(sansName), registered(serifName)]),
        projectFilePath: null,
        staging: null,
        deviceFontFile: (file) {
          asked.add(file);
          return file == serifName ? serif : sans;
        },
      );

      expect(asked, [sansName, serifName]);
      expect(sources.held, {
        anicelFontEntryName(sansName),
        anicelFontEntryName(serifName),
      });
      String fileOf(String carriedAs) =>
          (sources.entries[anicelFontEntryName(carriedAs)]! as MediaFileBytes)
              .path;
      expect(fileOf(sansName), sans);
      expect(fileOf(serifName), serif);
    });

    test('🚨the FILE\'s own entry before any other copy: once written, the '
        'entry is what the name means', () async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({sansName: deviceFont('first.ttf', 30000, 7)}),
      );

      final sources = projectFontSources(
        project: project,
        projectFilePath: s.path,
        staging: roomKeeping(sansName, List.filled(40, 3)),
        deviceFontFile: (file) => deviceFont('second.ttf', 31000, 9),
      );

      final source = sources.entries[anicelFontEntryName(sansName)];
      expect(source, isA<MediaArchiveBytes>());
      expect(source!.lengthSync(), 30000);
      expect(source.readSync().first, 7);
    });

    test('🚨the copy this run\'s ROOM keeps before the device\'s: a font a '
        'save took out of the file, back in the list after an undo, is '
        'read from where that save left it', () {
      final sources = projectFontSources(
        project: carrying([registered(sansName)]),
        projectFilePath: null,
        staging: roomKeeping(sansName, List.filled(40, 3)),
        deviceFontFile: (file) => deviceFont('second.ttf', 31000, 9),
      );

      final source = sources.entries[anicelFontEntryName(sansName)];
      expect(source, isA<MediaAppFileBytes>());
      expect(source!.storedIsFramed, isFalse);
      expect(source.readSync(), List.filled(40, 3));
    });

    group('🚨a project is a file from anywhere: a font it names by anything '
        'but ONE NAME of the library\'s', () {
      const unsafe = [
        '../../outside-1.ttf',
        r'..\outside-1.ttf',
        'C:/Windows/win.ini',
        'folder/ab12-cd34-font.ttf',
        'nul.ttf',
        'ab12-cd34-font.exe',
        '',
      ];

      test('is not held, not looked for anywhere, and has no bytes to '
          'write — the others of the project are unaffected', () {
        final asked = <String>[];

        final sources = projectFontSources(
          project: carrying([
            for (final name in unsafe) registered(name),
            registered(sansName),
          ]),
          projectFilePath: null,
          staging: roomKeeping(sansName, List.filled(40, 3)),
          deviceFontFile: (file) {
            asked.add(file);
            return null;
          },
        );

        expect(sources.held, {anicelFontEntryName(sansName)});
        expect(sources.entries.keys, [anicelFontEntryName(sansName)]);
        expect(asked, isEmpty, reason: 'the room answered for the one');
        expect(
          projectFontEntryNames(
            carrying([for (final name in unsafe) registered(name)]),
          ),
          isEmpty,
        );
      });

      test('⛔is not read out of the project file either, though an entry '
          'by that name is there', () async {
        final s = saving();
        const name = '../outside-1.ttf';
        await s.service.save(
          project: carrying([registered(name)]),
          brushFrameStore: s.store,
          filePath: s.path,
          // A file written by something that is not this app.
          fonts: ProjectFontsToStore(
            held: {anicelFontEntryName(name)},
            entries: {
              anicelFontEntryName(name): MediaFileBytes(
                deviceFont('crafted.ttf', 100, 5),
              ),
            },
          ),
        );
        final layout = parseAnicelZipLayoutFile(s.path);
        expect(
          layout.entryNamed(anicelFontEntryName(name)),
          isNotNull,
          reason: '⛔fixture',
        );

        expect(
          storedFontBytesFor(
            name,
            layout: layout,
            archivePath: s.path,
            staging: null,
            deviceFontFile: (file) => fail('never made a path of'),
          ),
          isNull,
        );
      });
    });
  });

  group('🚨what a save takes OUT of the file goes to the room first', () {
    /// A project file holding both fonts, and where each entry lies in it.
    Future<String> fileHoldingBoth() async {
      final s = saving();
      await s.service.save(
        project: carrying([registered(sansName), registered(serifName)]),
        brushFrameStore: s.store,
        filePath: s.path,
        fonts: fromDevice({
          sansName: deviceFont('sans.ttf', 30000, 7),
          serifName: deviceFont('serif.otf', 20000, 9),
        }),
      );
      return s.path;
    }

    final both = {
      anicelFontEntryName(sansName),
      anicelFontEntryName(serifName),
    };

    test('the entries the file was written with that the project no '
        'longer holds — each under its own name, where it lies now', () async {
      final path = await fileHoldingBoth();
      final sans = entryOf(path, sansName)!;

      final left = fontsLeftBehind(
        projectFilePath: path,
        fontsInFile: both,
        held: {anicelFontEntryName(serifName)},
      );

      expect(left, [
        (name: sansName, offset: sans.dataOffset, length: sans.length),
      ]);
    });

    test('⛔none, of a font the project still holds', () async {
      final path = await fileHoldingBoth();

      expect(
        fontsLeftBehind(projectFilePath: path, fontsInFile: both, held: both),
        isEmpty,
      );
    });

    test('none, where the file does not hold what the record says — or '
        'there is no file to read', () async {
      final path = await fileHoldingBoth();
      const never = 'ab12-0000-font-9.ttf';

      expect(
        fontsLeftBehind(
          projectFilePath: path,
          fontsInFile: {anicelFontEntryName(never)},
          held: const {},
        ),
        isEmpty,
      );
      expect(
        fontsLeftBehind(
          projectFilePath: '${directory.path}/gone.anicel',
          fontsInFile: both,
          held: const {},
        ),
        isEmpty,
      );
      expect(
        fontsLeftBehind(
          projectFilePath: null,
          fontsInFile: both,
          held: const {},
        ),
        isEmpty,
      );
    });

    test('🚨⛔never an entry under a name that is not one of the library\'s '
        '— what comes back is WRITTEN, under that name, into the room', () async {
      final s = saving();
      const crafted = [
        'fonts/../outside-1.ttf',
        'fonts/nul.ttf',
        'fonts/ab12-cd34-font.exe',
        'media/ab12-cd34-font.ttf',
      ];
      await s.service.save(
        project: carrying(const []),
        brushFrameStore: s.store,
        filePath: s.path,
        // A file written by something that is not this app: every one of
        // these entries is IN it.
        fonts: ProjectFontsToStore(
          held: {...crafted},
          entries: {
            for (final name in crafted)
              name: MediaFileBytes(deviceFont('crafted.ttf', 100, 5)),
          },
        ),
      );
      final layout = parseAnicelZipLayoutFile(s.path);
      for (final name in crafted) {
        expect(layout.entryNamed(name), isNotNull, reason: '⛔fixture $name');
      }

      expect(
        fontsLeftBehind(
          projectFilePath: s.path,
          fontsInFile: {...crafted},
          held: const {},
        ),
        isEmpty,
      );
    });

    test('and what a save lets go of in the room afterwards is the fonts it '
        'had bytes for, by the names the room keeps them under', () {
      final stored = ProjectFontsToStore(
        held: {...both, anicelFontEntryName('ab12-0000-font-9.ttf')},
        entries: {
          for (final name in both) name: const MediaFileBytes('anywhere'),
          'fonts/../outside-1.ttf': const MediaFileBytes('anywhere'),
          'media/ab12-cd34-font.ttf': const MediaFileBytes('anywhere'),
        },
      );

      expect(fontNamesStored(stored), unorderedEquals([sansName, serifName]));
      expect(fontNamesStored(const ProjectFontsToStore.none()), isEmpty);
    });
  });

  group('the bar', () {
    Future<List<double>> reportsOf({required bool whole}) async {
      final s = saving();
      final project = carrying([registered(sansName)]);
      if (!whole) {
        // A file to append onto, without the font in it.
        await s.service.save(
          project: createDefaultProject(),
          brushFrameStore: s.store,
          filePath: s.path,
        );
        s.store.storeBakedSurface(key('f1'), inked(5));
      }
      final reports = <double>[];
      await s.service.save(
        project: project,
        brushFrameStore: s.store,
        filePath: s.path,
        // Large on purpose: the font has to be worth several reports of
        // its own, or a short denominator could hide inside the rounding.
        fonts: fromDevice({sansName: deviceFont('probe.ttf', 4 << 20, 7)}),
        onProgress: reports.add,
      );
      expect(entryOf(s.path, sansName), isNotNull, reason: '⛔fixture');
      return reports;
    }

    const roads = [('a whole write', true), ('an append', false)];
    for (final (road, whole) in roads) {
      test('🚨$road counts the font it is about to write: the bar arrives '
          'at the end exactly once', () async {
        final reports = await reportsOf(whole: whole);

        expect(reports, isNotEmpty, reason: 'nothing crossed the port');
        expect(reports.last, 1.0);
        expect(
          reports.where((value) => value >= 1.0).length,
          1,
          reason:
              'the bar reached the end more than once — the denominator '
              'forgot the font, so its write ran behind a full bar',
        );
      });
    }
  });

  group('whether the file is worth packing down', () {
    test('🚨a font is bulk a rewrite copies for nothing, as media is: it is '
        'out of what the garbage is measured against', () {
      // Ten megabytes of font beside one of cels, and a megabyte and a
      // half of dead cel bytes: more than the cels weigh — and an eighth of
      // the whole file, which would never be packed if the font counted.
      const cels = 1 << 20;
      const font = 10 << 20;
      const garbage = 3 << 19;
      bool packs(String fontEntryName) => anicelNeedsCompaction(
        fileLength: cels + font + garbage,
        entries: [
          (name: 'cels/a.celz', length: cels),
          (name: fontEntryName, length: font),
        ],
      );

      expect(packs(anicelFontEntryName(sansName)), isTrue);
      expect(
        packs('other/$sansName'),
        isFalse,
        reason: '⛔fixture: the same bytes, were they not a carried kind',
      );
    });

    test('every carried kind is asked by one list', () {
      expect(anicelCarriedEntryPrefixes, [
        anicelMediaEntryPrefix,
        anicelConformEntryPrefix,
        anicelFontEntryPrefix,
      ]);
      for (final prefix in anicelCarriedEntryPrefixes) {
        expect(anicelEntryIsCarried('${prefix}x'), isTrue, reason: prefix);
      }
      expect(anicelEntryIsCarried('cels/x.celz'), isFalse);
      expect(anicelEntryIsCarried(anicelProjectEntryNameCompressed), isFalse);
      expect(anicelFontEntryName('a-b-c.ttf'), 'fonts/a-b-c.ttf');
    });
  });

  test('⛔the other kinds a project carries are swept as they were: a font '
      'in the list does not keep a medium the pool let go of', () async {
    final s = saving();
    final audio = deviceFont('take.wav', 20000, 1);
    final carry = (poolPath: audio, token: 'c1');
    final project = carrying([registered(sansName)]);
    final fonts = fromDevice({sansName: deviceFont('probe.ttf', 30000, 7)});
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      mediaToStore: {carry: MediaFileBytes(audio)},
      conforms: const ProjectConforms.none(),
      fonts: fonts,
    );
    expect(
      parseAnicelZipLayoutFile(s.path).entryNamed(anicelMediaEntryName(carry)),
      isNotNull,
      reason: '⛔fixture',
    );

    s.store.storeBakedSurface(key('f1'), inked(5));
    await s.service.save(
      project: project,
      brushFrameStore: s.store,
      filePath: s.path,
      fonts: fonts,
    );

    final after = parseAnicelZipLayoutFile(s.path);
    expect(after.entryNamed(anicelMediaEntryName(carry)), isNull);
    expect(after.entryNamed(anicelFontEntryName(sansName)), isNotNull);
  });
}
