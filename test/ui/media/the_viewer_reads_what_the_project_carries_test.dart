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

  // ⏸INTERIM — board `carried-movie-compressed-Q1`. A movie kept COMPRESSED
  // has no decoder that reads it where it lies, so the viewer reads the
  // original while there is one, exactly as it did before 2026-09-24.
  group('a carried movie kept COMPRESSED', () {
    /// A session carrying a movie whose staged copy is FRAMED — the shape a
    /// 6.7%-smaller MP4 takes — with its original beside it.
    Future<({EditorSessionManager session, String path})> framed() async {
      final path = normalizedMediaPath(
        await writeCarriedMovie(directory, length: 512),
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
      final staged = File(
        session.mediaStagingStore.pathFor(path, framed: true),
      );
      staged.parent.createSync(recursive: true);
      staged.writeAsBytesSync(const [0, 1, 2, 3]);
      return (session: session, path: path);
    }

    testWidgets('opens from its original while the original is there', (
      tester,
    ) async {
      final (:session, :path) = (await tester.runAsync(framed))!;

      await view(tester, session, path, MediaAssetKind.video);

      expect(page(), findsOneWidget);
      expect(movies.openedAt.single.path, path);
    });

    testWidgets('and without it says the movie is only read in place', (
      tester,
    ) async {
      final (:session, :path) = (await tester.runAsync(framed))!;
      File(path).deleteSync();

      await view(tester, session, path, MediaAssetKind.video);

      expect(page(), findsNothing);
      expect(find.textContaining('read in place'), findsOneWidget);
      expect(movies.openedAt, isEmpty, reason: 'never handed to a decoder');
    });
  });
}
