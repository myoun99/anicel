import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/native/qa_video_decoder.dart' show QaVideoInfo;
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/viewer_document.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
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
/// the movie — so 「it opened」 means 「it read the carried bytes」.
/// ⚠️Sound is not in the walk: its picture is the waveform the conform store
/// makes, and that store asks the same question itself
/// (`resolveByteSource: projectFile.mediaByteSourceFor`,
/// `media_carried_read_side_test`).
void main() {
  late Directory directory;
  late _ReadingVideoBackend movies;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-viewer-carries');
    PdfRenderService.debugOpenerOverride = (source) async {
      final head = Uint8List(_pdfMagic.length);
      source.readIntoSync(head, 0, head.length);
      if (String.fromCharCodes(head) != _pdfMagic) {
        throw const ViewerDocumentException('not a PDF');
      }
      return FakePdfDocument(pageSizes: const [ui.Size(8, 8)]);
    };
    debugVideoDecodeBackend = movies = _ReadingVideoBackend();
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  final kinds =
      <({MediaAssetKind kind, Future<String> Function(Directory) write})>[
        (
          kind: MediaAssetKind.image,
          write: (dir) =>
              writeSolidPng(dir, 'ref.png', width: 16, height: 12),
        ),
        (
          kind: MediaAssetKind.pdf,
          write: (dir) async => _written(
            dir,
            'conte.pdf',
            '${_pdfMagic}1.4 a carried conte'.codeUnits,
          ),
        ),
        (
          kind: MediaAssetKind.video,
          // Noise behind the magic, so staging stores it as it is — a plain
          // stretch a decoder can be pointed at.
          write: (dir) async => _written(dir, 'take.mp4', [
            ..._movieMagic.codeUnits,
            for (final byte in _noise(4096)) byte,
          ]),
        ),
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

  /// A session holding [write]'s file as CARRIED — its bytes staged the
  /// moment it was registered — and the path it is known by.
  Future<({EditorSessionManager session, String path})> carrying(
    WidgetTester tester,
    Future<String> Function(Directory) write,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${directory.path}/Staged',
      ),
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);
    final path = normalizedMediaPath((await tester.runAsync(
      () => write(directory),
    ))!);
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([path], copyIntoProject: true),
    );
    return (session: session, path: path);
  }

  Future<void> save(WidgetTester tester, EditorSessionManager session) =>
      tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          normalizedMediaPath('${directory.path}/project.anicel'),
          asked: SaveAsked.byAPerson,
        ),
      );

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
    for (final fate in ['deleted', 'replaced by something else']) {
      testWidgets('${kind.name}, carried and saved, its original $fate: the '
          'viewer shows the carried copy — held while shown, given back on '
          'close', (tester) async {
        final (:session, :path) = await carrying(tester, write);
        await save(tester, session);
        if (fate == 'deleted') {
          File(path).deleteSync();
        } else {
          File(path).writeAsBytesSync('not this file'.codeUnits);
        }

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
      final (:session, :path) = await carrying(tester, write);
      final staged = session.mediaStagingStore.find(path)!.path;
      File(path).writeAsBytesSync('not this file'.codeUnits);

      final slot = await view(tester, session, path, kind);
      expect(page(), findsOneWidget, reason: 'the staged copy opened');

      await save(tester, session);
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
        await _written(directory, 'take.mp4', [
          ..._movieMagic.codeUnits,
          for (final byte in _noise(512)) byte,
        ]),
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

const _pdfMagic = '%PDF-';
const _movieMagic = 'MOVIE!';

Future<String> _written(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

List<int> _noise(int length) {
  final random = math.Random(7);
  return [for (var i = 0; i < length; i += 1) random.nextInt(256)];
}

/// A decoder that READS what it is pointed at — a file of its own, or a
/// stretch of one — and cannot read anything that is not a movie.
class _ReadingVideoBackend extends FakeVideoBackend {
  _ReadingVideoBackend() : super(frameCount: 3);

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    final head = Uint8List(_movieMagic.length);
    final file = File(path).openSync();
    try {
      file.setPositionSync(range?.offset ?? 0);
      file.readIntoSync(head);
    } finally {
      file.closeSync();
    }
    if (String.fromCharCodes(head) != _movieMagic) {
      return null;
    }
    return super.open(path, range: range);
  }
}
