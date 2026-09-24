import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 2026-09-11: 「막힌부분 파일 뭐든 관계없이 법 하나로 통일해서
/// 해결하도록」 — card `carried-image-pdf-cannot-be-viewed`.
///
/// The viewer asks ONE question for every kind whose document reads bytes —
/// where are they ([ProjectFile.holdMediaBytes]) — and the project's own
/// copy answers before the file it came from: 「품은 순간 데이터를
/// 가지고있고 불변이었으면좋겠어서」 (유저 2026-08-30). So ONE test walks
/// the kinds (the shape that measures one law, not three), and the original
/// is made unreadable in every case: were it the one read, the viewer would
/// say it could not read it.
///
/// ⚠️Every reader here READS the bytes it is handed and refuses what is not
/// its medium — a real decoder for the image, a magic check for the PDF and
/// the movie ([carried_media_fixture]) — so 「it opened」 means 「it read the
/// carried bytes」.
/// ⚠️Sound is not in the walk: its picture is the waveform the conform store
/// makes, and that store asks the same question itself
/// (`resolveByteSource: projectFile.mediaByteSourceFor`,
/// `media_carried_read_side_test`).
void main() {
  late Directory directory;
  late ReadingVideoBackend movies;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-viewer-carries');
    PdfRenderService.debugOpenerOverride = openPdfThatReads;
    debugVideoDecodeBackend = movies = ReadingVideoBackend();
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  final kinds =
      <({MediaAssetKind kind, Future<String> Function(Directory) write})>[
        (kind: MediaAssetKind.image, write: writeCarriedPicture),
        (kind: MediaAssetKind.pdf, write: writeCarriedPdf),
        (kind: MediaAssetKind.video, write: writeCarriedMovie),
      ];

  Future<void> settleAsync(
    WidgetTester tester,
    bool Function() ready, {
    void Function()? everyFrame,
  }) async {
    for (var i = 0; i < 60 && !ready(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      everyFrame?.call();
    }
  }

  /// The least the viewer held drawn over the frames [settleAsync] pumps
  /// with it as `everyFrame`, from the first page it drew — ZERO the moment
  /// the panel empties its pages, which is what a blink is.
  Future<({int Function() least, void Function() everyFrame})>
  drawnAtEveryFrame(WidgetTester tester, EditorSessionManager session) async {
    await settleAsync(
      tester,
      () => session.renderCaches.viewerRasterBytes > 0,
    );
    var least = session.renderCaches.viewerRasterBytes;
    return (
      least: () => least,
      everyFrame: () =>
          least = math.min(least, session.renderCaches.viewerRasterBytes),
    );
  }

  Finder page() => find.byKey(const ValueKey<String>('media-viewer-page'));

  /// The viewer on [path], settled on whatever it could open.
  Future<MediaViewerSlot> view(
    WidgetTester tester,
    EditorSessionManager session,
    String path,
    MediaAssetKind kind,
  ) async {
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
    slot.request.value = MediaViewerRequest(path: path, kind: kind);
    await settleAsync(tester, () => tester.any(page()));
    return slot;
  }

  for (final (:kind, :write) in kinds) {
    for (final fate in OriginalFate.values) {
      testWidgets('${kind.name}, carried and saved, its original '
          '${fate.name}: the viewer shows the carried copy — held while shown, '
          'given back on close', (tester) async {
        final (:session, :path) = await carrying(tester, directory, write);
        await saveProject(tester, session, directory);
        fate.befall(path);

        final slot = await view(tester, session, path, kind);

        expect(page(), findsOneWidget, reason: 'the carried copy opened');
        expect(
          session.projectFile.heldArchiveEntries,
          hasLength(1),
          reason: 'its entry stays where the document reads it',
        );

        slot.request.value = null;
        await settleAsync(
          tester,
          () => session.projectFile.heldArchiveEntries.isEmpty,
        );
        expect(session.projectFile.heldArchiveEntries, isEmpty);
      });
    }

    testWidgets('${kind.name}, carried and not yet saved: the viewer shows the '
        'staged copy, and a save while it shows moves it onto the project '
        'file — the copy goes, the page stays', (tester) async {
      final (:session, :path) = await carrying(tester, directory, write);
      final staged = stagedCopyIn(session, path)!.path;
      OriginalFate.replacedBySomethingElse.befall(path);

      final slot = await view(tester, session, path, kind);
      expect(page(), findsOneWidget, reason: 'the staged copy opened');
      final drawn = await drawnAtEveryFrame(tester, session);
      expect(drawn.least(), greaterThan(0), reason: 'the premise: drawn');

      await saveProject(tester, session, directory);
      await settleAsync(
        tester,
        () => !File(staged).existsSync(),
        everyFrame: drawn.everyFrame,
      );
      expect(
        File(staged).existsSync(),
        isFalse,
        reason: 'absorbed by the save, and the viewer followed it — held '
            'while it showed, the copy used to stay beside the entry that '
            'replaced it (「사본 남으면 진짜 용서안할게」)',
      );
      expect(
        drawn.least(),
        greaterThan(0),
        reason: 'the page drawn stayed drawn at every frame: nothing blinked',
      );
      expect(
        session.projectFile.heldArchiveEntries,
        hasLength(1),
        reason: 'it reads the entry now',
      );

      slot.request.value = null;
      await settleAsync(
        tester,
        () => session.projectFile.heldArchiveEntries.isEmpty,
      );
      expect(session.projectFile.heldArchiveEntries, isEmpty);
    });
  }

  testWidgets('a movie on the page follows the project saved as another '
      'file', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedMovie,
    );
    await view(tester, session, path, MediaAssetKind.video);
    await saveProject(tester, session, directory);
    final first = session.projectFile.path!;
    await settleAsync(tester, () => movies.openedAt.last.path == first);
    expect(movies.openedAt.last.path, first, reason: 'the premise');

    final elsewhere = normalizedMediaPath('${directory.path}/as.anicel');
    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        elsewhere,
        asked: SaveAsked.byAPerson,
      ),
    );
    await settleAsync(tester, () => movies.openedAt.last.path == elsewhere);

    expect(movies.openedAt.last.path, elsewhere);
    expect(page(), findsOneWidget);
  });

  testWidgets('🚨a movie on the page asked to let go of its file — what a '
      'whole write onto the file asks first — lets go FIRST, then opens it '
      'again: the page stays, and closing gives back what it took up', (
    tester,
  ) async {
    final closing = ClosingVideoBackend();
    debugVideoDecodeBackend = movies = closing;
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedMovie,
    );
    await saveProject(tester, session, directory);
    final file = session.projectFile.path!;
    final slot = await view(tester, session, path, MediaAssetKind.video);
    expect(page(), findsOneWidget, reason: 'the premise');
    final drawn = await drawnAtEveryFrame(tester, session);
    expect(drawn.least(), greaterThan(0), reason: 'the premise: drawn');
    closing.events.clear();

    // Asked straight, not through a save: the page's reader answers on the
    // test's own clock, which a save run on the real one never pumps.
    unawaited(session.projectFile.readersLetGoOf(file));
    await settleAsync(
      tester,
      () => closing.events.length >= 2,
      everyFrame: drawn.everyFrame,
    );

    expect(closing.events, [
      'close $file',
      'open $file',
    ], reason: 'let go of first, then opened again');
    expect(
      drawn.least(),
      greaterThan(0),
      reason: 'the page drawn stayed drawn at every frame: nothing blinked',
    );

    slot.request.value = null;
    await settleAsync(
      tester,
      () => session.projectFile.heldArchiveEntries.isEmpty,
    );
    expect(session.projectFile.heldArchiveEntries, isEmpty);
  });

  testWidgets('a movie let go of for a file it then cannot open says so — '
      'there is nothing left to read', (tester) async {
    var refusing = false;
    debugVideoDecodeBackend = movies = ClosingVideoBackend(
      refuses: (_) => refusing,
    );
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedMovie,
    );
    await saveProject(tester, session, directory);
    await view(tester, session, path, MediaAssetKind.video);
    expect(page(), findsOneWidget, reason: 'the premise');
    refusing = true;

    unawaited(
      session.projectFile.readersLetGoOf(session.projectFile.path!),
    );
    final failed = find.textContaining(AppText.strings.mediaViewerLoadFailed);
    await settleAsync(tester, () => tester.any(failed));

    expect(failed, findsOneWidget);
  });

  testWidgets('a movie the save moves where it will not open stays on the '
      'page, read where it was', (tester) async {
    var refused = 0;
    debugVideoDecodeBackend = movies = ReadingVideoBackend(
      refuses: (path) {
        final isTheFile = path.endsWith('project.anicel');
        refused += isTheFile ? 1 : 0;
        return isTheFile;
      },
    );
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedMovie,
    );
    final staged = stagedCopyIn(session, path)!.path;
    await view(tester, session, path, MediaAssetKind.video);
    expect(page(), findsOneWidget, reason: 'the premise');

    await saveProject(tester, session, directory);
    await settleAsync(tester, () => refused > 0);
    await tester.pump();

    expect(refused, greaterThan(0), reason: 'the premise: it tried');
    expect(page(), findsOneWidget, reason: 'nothing is gained by losing it');
    expect(
      File(staged).existsSync(),
      isTrue,
      reason: 'still read, so still held',
    );
  });

  // A movie kept COMPRESSED is read where the project keeps it: the decoder
  // is fed its blocks decoded (board `carried-movie-compressed-Q1`, 유저
  // 「압축 유지 + 풀면서 디코더에 먹이는 리더를 플랫폼마다 만든다」). Only a
  // device whose decoder cannot be fed one — Android below 9 — reads the
  // original instead, and only while there is one: the cost 유저 accepted.
  group('a carried movie kept COMPRESSED', () {
    /// A session carrying a movie whose staged copy is FRAMED — the shape a
    /// 6.7%-smaller MP4 takes — with its original beside it. Null when this
    /// run has no engine to frame it with.
    Future<({EditorSessionManager session, String path, String staged})?>
    framed() async {
      final path = normalizedMediaPath(
        await writeCompressibleMovie(directory),
      );
      final session = EditorSessionManager(
        initialProject: createDefaultProject().copyWith(
          mediaAssets: [
            MediaAsset(
              path: path,
              name: 'take',
              kind: MediaAssetKind.video,
              carriedAs: 'c1',
            ),
          ],
        ),
        mediaStagingStore: MediaStagingStore(
          directoryPath: '${directory.path}/Staged',
        ),
        audioConformStore: soundConformStore(),
      );
      addTearDown(session.dispose);
      final staged = await session.mediaStagingStore.stage(
        carryIn(session, path)!,
      );
      if (staged == null || !staged.framed) {
        return null;
      }
      return (session: session, path: path, staged: staged.path);
    }

    for (final original in ['there', 'gone']) {
      testWidgets('its original $original: opens from the project\'s own '
          'copy, framed', (tester) async {
        final carried = await tester.runAsync(framed);
        if (carried == null) {
          markTestSkipped('no engine on this run to frame the copy with');
          return;
        }
        if (original == 'gone') {
          File(carried.path).deleteSync();
        }

        await view(tester, carried.session, carried.path, MediaAssetKind.video);

        expect(page(), findsOneWidget);
        final opened = movies.openedAt.single;
        expect(opened.path, carried.staged);
        expect(
          opened.span?.framed,
          isTrue,
          reason: 'fed to the decoder as the framed stretch it is — and '
              'READ, because the reader here refuses what is not a movie',
        );
      });
    }

    group('on a device whose decoder cannot be fed one', () {
      setUp(() {
        debugVideoDecodeBackend = movies = ReadingVideoBackend(
          readsFramed: false,
        );
      });

      testWidgets('opens from its original while the original is there', (
        tester,
      ) async {
        final carried = await tester.runAsync(framed);
        if (carried == null) {
          markTestSkipped('no engine on this run to frame the copy with');
          return;
        }

        await view(tester, carried.session, carried.path, MediaAssetKind.video);

        expect(page(), findsOneWidget);
        expect(movies.openedAt.single.path, carried.path);
      });

      testWidgets('and without it says this device cannot read it', (
        tester,
      ) async {
        final carried = await tester.runAsync(framed);
        if (carried == null) {
          markTestSkipped('no engine on this run to frame the copy with');
          return;
        }
        File(carried.path).deleteSync();

        await view(tester, carried.session, carried.path, MediaAssetKind.video);

        expect(page(), findsNothing);
        expect(find.textContaining('cannot read that movie'), findsOneWidget);
        expect(movies.openedAt, isEmpty, reason: 'never handed to a decoder');
      });
    });
  });
}
