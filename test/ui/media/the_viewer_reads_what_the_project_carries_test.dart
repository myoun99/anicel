import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
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

  Future<void> settleAsync(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 60 && !ready(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
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
        'staged copy, and a save while it shows leaves that copy until the '
        'viewer lets go', (tester) async {
      final (:session, :path) = await carrying(tester, directory, write);
      final staged = session.mediaStagingStore.find(path)!.path;
      OriginalFate.replacedBySomethingElse.befall(path);

      final slot = await view(tester, session, path, kind);
      expect(page(), findsOneWidget, reason: 'the staged copy opened');

      await saveProject(tester, session, directory);
      expect(
        File(staged).existsSync(),
        isTrue,
        reason: 'absorbed by the save, but the viewer still reads it',
      );

      slot.request.value = null;
      await settleAsync(tester, () => !File(staged).existsSync());
      expect(
        File(staged).existsSync(),
        isFalse,
        reason: 'let go of, the absorbed copy goes — 「사본 남으면 진짜 '
            '용서안할게」',
      );
    });
  }

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
              carried: true,
            ),
          ],
        ),
        mediaStagingStore: MediaStagingStore(
          directoryPath: '${directory.path}/Staged',
        ),
        audioConformStore: soundConformStore(),
      );
      addTearDown(session.dispose);
      final staged = await session.mediaStagingStore.stage(path);
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
