import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/native/qa_video_decoder.dart' show QaVideoInfo;
import 'package:anicel/src/services/media/held_viewer_document.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/video_viewer_document.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**WHAT A READER HOLDS BY OFFSET, A SAVE DOES NOT MOVE.**
///
/// The viewer opens a carried movie on its stretch of the `.anicel`, and
/// the decoder reads that stretch by offset, frame after frame — a carried
/// PDF likewise, a page at a time. Since 2026-09-23 a save packs the file
/// IN PLACE (deleting-save-compacts-Q1) — live bytes slide down, and the
/// next round writes over where they were — so a movie moved under an open
/// document hands the decoder whatever landed there. The cels' refs move
/// with their bytes; a decoder cannot. Its entry stays put until it lets
/// go, and the first save after that packs the hole.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-held-range');
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  group('the push-down', () {
    // A 10-byte span at 0, then a 20-byte hole, a 10-byte span at 30, a
    // 20-byte hole, and a 10-byte span at 60.
    const live = <AnicelLiveSpan>[
      (offset: 0, size: 10),
      (offset: 30, size: 10),
      (offset: 60, size: 10),
    ];

    test('the premise: unheld, both spans behind a hole slide down', () {
      final plan = planAnicelPushDown(live);

      expect(plan.moves, [
        (from: 30, to: 10, size: 10),
        (from: 60, to: 20, size: 10),
      ]);
      expect(plan.end, 30);
    });

    test('🎯a span something holds stays, and what follows packs against '
        'it', () {
      final plan = planAnicelPushDown(live, staying: {30});

      expect(plan.moves, [(from: 60, to: 40, size: 10)]);
      expect(plan.end, 50, reason: 'the hole in front of it waits');
    });
  });

  Uint8List filled(int length, int seed) => Uint8List.fromList(
    List<int>.generate(length, (i) => (i * seed + 7) & 0xFF),
  );

  test('🚨a compaction leaves a held entry where its reader reads it, byte '
      'for byte — and the next one, unheld, packs it', () async {
    final path = '${directory.path}/held.anicel';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        (name: 'head.bin', bytes: filled(1024, 3)),
        (name: 'junk.bin', bytes: filled(64 * 1024, 5)),
        (name: 'movie.mp4', bytes: filled(4096, 11)),
        (name: 'more-junk.bin', bytes: filled(8 * 1024, 17)),
        (name: 'tail.bin', bytes: filled(2048, 13)),
      ],
    );
    final hole = appendAnicelEntries(
      path: path,
      newEntries: const {},
      removeNames: const {'junk.bin', 'more-junk.bin'},
    );
    final movie = hole.entryNamed('movie.mp4')!;

    final packed = await compactAnicelInPlace(
      path: path,
      layout: hole,
      readers: (move: (_) async {}, holding: const {'movie.mp4'}),
    );

    final stayed = packed.entryNamed('movie.mp4')!;
    expect(stayed.dataOffset, movie.dataOffset);
    final bytes = File(path).readAsBytesSync();
    expect(
      Uint8List.sublistView(
        bytes,
        movie.dataOffset,
        movie.dataOffset + movie.length,
      ),
      filled(4096, 11),
      reason: 'what the open document reads is still the movie',
    );
    expect(
      packed.entryNamed('tail.bin')!.dataOffset,
      lessThan(hole.entryNamed('tail.bin')!.dataOffset),
      reason: 'the rest still packs',
    );

    final after = await compactAnicelInPlace(
      path: path,
      layout: parseAnicelZipLayoutFile(path),
      readers: (move: (_) async {}, holding: const {}),
    );
    expect(
      after.entryNamed('movie.mp4')!.dataOffset,
      lessThan(movie.dataOffset),
      reason: 'let go of, its hole is packed — deferred, not given up',
    );
  });

  test('a held document gives its bytes back only AFTER the decoder has '
      'closed them', () async {
    final events = <String>[];
    final backend = _ClosingBackend(events);
    debugVideoDecodeBackend = backend;
    final archive = '${directory.path}/project.anicel';
    final movie = await VideoViewerDocument.open(
      MediaArchiveBytes(archivePath: archive, dataOffset: 4096, length: 512),
    );
    expect(backend.openedAt, [
      (path: archive, span: (offset: 4096, length: 512, framed: false)),
    ], reason: 'the premise: opened on its stretch of the archive');
    late final HeldMediaBytes held;
    held = HeldMediaBytes(
      source: MediaFileBytes(archive),
      release: () => events.add('released'),
      moved: const Stream<HeldBytesMove>.empty(),
      again: () async => held,
    );
    final document = HeldViewerDocument(movie!, held);

    await document.dispose();

    expect(events, ['closed', 'released']);
  });

  group('the session', () {
    /// A session holding a carried "movie" of [length] random bytes — random
    /// so staging stores it as it is, a plain stretch a decoder can be
    /// pointed at — saved once to [path].
    Future<({EditorSessionManager session, String movie})> savedWithAMovie(
      WidgetTester tester,
      String path, {
      int length = 512,
    }) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 4);
      final s = EditorSessionManager(
        initialProject: createDefaultProject(),
        mediaStagingStore: MediaStagingStore(
          directoryPath: '${directory.path}/Staged',
        ),
        audioConformStore: soundConformStore(),
      );
      addTearDown(s.dispose);
      final random = math.Random(7);
      final movie = normalizedMediaPath('${directory.path}/take.mp4');
      File(movie).writeAsBytesSync([
        for (var i = 0; i < length; i += 1) random.nextInt(256),
      ]);
      await tester.runAsync(() async {
        // Carried into the POOL, not placed: a row on the canvas holds its
        // movie for as long as it can play, and follows it onto the entry
        // the save writes (`a_reader_follows_what_the_save_absorbed_test`)
        // — a reader of its own, and not the one these measure.
        await s.mediaPool.importMediaFiles([movie], copyIntoProject: true);
        await s.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byAPerson,
        );
      });
      return (session: s, movie: movie);
    }

    /// The entry [movie]'s carry is stored under — plain, as random bytes
    /// are ([savedWithAMovie]).
    String entryOf(EditorSessionManager s, String movie) =>
        anicelMediaEntryName(carryIn(s, movie)!);

    /// Garbage past the ratio, behind everything — so the next save packs.
    void pastTheRatio(String path) {
      appendAnicelEntries(
        path: path,
        newEntries: {'junk.bin': Uint8List(256 * 1024)},
      );
      appendAnicelEntries(
        path: path,
        newEntries: const {},
        removeNames: const {'junk.bin'},
      );
    }

    testWidgets('a hold counts its readers and gives back once each', (
      tester,
    ) async {
      final path = normalizedMediaPath('${directory.path}/counted.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final file = session.projectFile;
      final entry = entryOf(session, movie);

      final first = (await tester.runAsync(
        () => file.holdMediaBytes(movie),
      ))!;
      final second = (await tester.runAsync(
        () => file.holdMediaBytes(movie),
      ))!;

      expect(
        first.source.span?.path,
        path,
        reason: 'the premise: a stretch of it',
      );
      expect(file.heldArchiveEntries, {entry});
      first.release();
      first.release();
      expect(file.heldArchiveEntries, {entry}, reason: 'one reader is left');
      second.release();
      expect(file.heldArchiveEntries, isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('🚨a hold asked for while a save runs waits for it to end — '
        'the save may be moving those very bytes', (tester) async {
      final path = normalizedMediaPath('${directory.path}/waits.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final file = session.projectFile;

      file.beginSave();
      var held = false;
      final asked = file.holdMediaBytes(movie).then((_) => held = true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(held, isFalse);
      expect(file.heldArchiveEntries, isEmpty);

      file.endSave();
      await tester.runAsync(() => asked);
      expect(held, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('🎯a save that packs the file leaves the movie the viewer '
        'holds where the viewer reads it — and packs it once let go', (
      tester,
    ) async {
      final path = normalizedMediaPath('${directory.path}/project.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final bytes = File(movie).readAsBytesSync();
      final entry = entryOf(session, movie);
      pastTheRatio(path);
      final held = (await tester.runAsync(
        () => session.projectFile.holdMediaBytes(movie),
      ))!;
      final range = held.source.span!;
      final before = File(path).lengthSync();

      await tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byAPerson,
        ),
      );

      expect(
        File(path).lengthSync(),
        lessThan(before - 128 * 1024),
        reason: 'the premise: this save packed the file',
      );
      final kept = parseAnicelZipLayoutFile(path).entryNamed(entry)!;
      expect(kept.dataOffset, range.offset);
      final raf = File(path).openSync();
      try {
        raf.setPositionSync(range.offset);
        expect(raf.readSync(range.length), bytes);
      } finally {
        raf.closeSync();
      }

      held.release();
      pastTheRatio(path);
      await tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byAPerson,
        ),
      );
      expect(
        parseAnicelZipLayoutFile(path).entryNamed(entry)!.dataOffset,
        lessThan(range.offset),
        reason: 'let go of, it packs like anything else',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('🚨an entry something holds does not leave with the save that '
        'stops carrying it — a viewer on an asset just taken out of the '
        'pool reads on', (tester) async {
      final path = normalizedMediaPath('${directory.path}/dropped.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final bytes = File(movie).readAsBytesSync();
      final entry = entryOf(session, movie);
      final held = (await tester.runAsync(
        () => session.projectFile.holdMediaBytes(movie),
      ))!;
      final range = held.source.span!;

      expect(session.mediaPool.removeMediaAsset(movie), isTrue);
      pastTheRatio(path);
      await tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byAPerson,
        ),
      );

      final kept = parseAnicelZipLayoutFile(path).entryNamed(entry);
      expect(kept, isNotNull, reason: 'held, it stays in the directory');
      expect(kept!.dataOffset, range.offset, reason: 'and where it was read');
      final raf = File(path).openSync();
      try {
        raf.setPositionSync(range.offset);
        expect(raf.readSync(range.length), bytes);
      } finally {
        raf.closeSync();
      }

      held.release();
      await tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byAPerson,
        ),
      );
      expect(
        parseAnicelZipLayoutFile(path).entryNamed(entry),
        isNull,
        reason: 'let go of, it leaves with the next save',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a path in the OS spelling finds what the pool spelling '
        'carries', (tester) async {
      final path = normalizedMediaPath('${directory.path}/spelled.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final osSpelling = movie.replaceAll('/', r'\');
      expect(
        session.projectFile.projectHoldsMediaBytes(osSpelling),
        isTrue,
        reason: 'the question a door asks before copying anything',
      );

      final held = (await tester.runAsync(
        () => session.projectFile.holdMediaBytes(osSpelling),
      ))!;

      expect(
        held.source.span?.path,
        path,
        reason: 'the carried entry, not the original',
      );
      expect(session.projectFile.heldArchiveEntries, {
        entryOf(session, movie),
      });
      held.release();
      expect(session.projectFile.heldArchiveEntries, isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('🚨a torn tail still names what the file carries — a reader '
        'reads the entry, not an original that is gone', (tester) async {
      final path = normalizedMediaPath('${directory.path}/torn.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      File(movie).deleteSync();
      // An append crash tears only the tail (the crash contract).
      final healthy = parseAnicelZipLayoutFile(path);
      File(path).openSync(mode: FileMode.append)
        ..truncateSync(healthy.centralDirectoryOffset + 7)
        ..closeSync();
      expect(
        () => parseAnicelZipLayoutFile(path),
        throwsFormatException,
        reason: 'the premise: the tail is torn',
      );

      final held = (await tester.runAsync(
        () => session.projectFile.holdMediaBytes(movie),
      ))!;

      expect(
        held.source.span?.path,
        path,
        reason: 'the body still holds the bytes; the save already knew it',
      );
      held.release();
      await tester.pumpAndSettle();
    });

    testWidgets('🎯the viewer holds a carried movie for as long as it shows '
        'it, and gives it back when it closes', (tester) async {
      final path = normalizedMediaPath('${directory.path}/viewed.anicel');
      final (:session, :movie) = await savedWithAMovie(tester, path);
      final backend = FakeVideoBackend(frameCount: 4);
      debugVideoDecodeBackend = backend;
      final slot = MediaViewerSlot();
      addTearDown(slot.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: 0,
            ),
          ),
        ),
      );

      slot.request.value = MediaViewerRequest(
        path: movie,
        kind: MediaAssetKind.video,
        name: 'take',
      );
      await tester.pumpAndSettle();

      expect(
        backend.openedAt.last.path,
        path,
        reason: 'the ORIGINAL is still there, and the carried copy is what '
            'the viewer reads — 「품은 순간 … 불변」',
      );
      expect(session.projectFile.heldArchiveEntries, {
        entryOf(session, movie),
      });

      slot.request.value = null;
      await tester.pumpAndSettle();

      expect(session.projectFile.heldArchiveEntries, isEmpty);
    });

    for (final (what, backend) in [
      ('no reader in this build', FakeVideoBackend(supported: false)),
      ('a reader that cannot read it', _RefusingBackend()),
    ]) {
      testWidgets('a movie that never opens — $what — gives its range back at '
          'once', (tester) async {
        final path = normalizedMediaPath('${directory.path}/refused.anicel');
        final (:session, :movie) = await savedWithAMovie(tester, path);
        File(movie).deleteSync();
        debugVideoDecodeBackend = backend;
        final slot = MediaViewerSlot();
        addTearDown(slot.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaViewerTabHost(
                viewerId: 'media-viewer',
                session: session,
                request: slot.request,
                position: 0,
              ),
            ),
          ),
        );

        slot.request.value = MediaViewerRequest(
          path: movie,
          kind: MediaAssetKind.video,
          name: 'take',
        );
        await tester.pumpAndSettle();

        expect(session.projectFile.heldArchiveEntries, isEmpty);
      });
    }
  });
}

/// A decoder that is there and cannot read this movie.
class _RefusingBackend extends FakeVideoBackend {
  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) async => null;
}

/// A decoder that says when it has closed.
class _ClosingBackend extends FakeVideoBackend {
  _ClosingBackend(this.events);

  final List<String> events;

  @override
  Future<void> close(int token) async => events.add('closed');
}
