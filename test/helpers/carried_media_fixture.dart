import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/native/qa_video_decoder.dart' show QaVideoInfo;
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/viewer_document.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import 'fake_pdf_document.dart';
import 'fake_video_backend.dart';
import 'placed_sound_conform.dart';
import 'solid_png_fixture.dart';

/// Media for the pins of 「the project's own copy first」 (card
/// `carried-bytes-every-reader`), and readers that READ what they are handed
/// and refuse what is not their medium — so 「it opened」 in those tests
/// means 「it read THESE bytes」, not 「something was called」.

const pdfMagic = '%PDF-';
const movieMagic = 'MOVIE!';

/// A PDF opener for [PdfRenderService.debugOpenerOverride] that reads the
/// head of the bytes it is handed, a window at a time as PDFium would.
Future<ViewerDocument> openPdfThatReads(MediaByteSource source) async {
  final head = Uint8List(pdfMagic.length);
  source.readIntoSync(head, 0, head.length);
  if (String.fromCharCodes(head) != pdfMagic) {
    throw const ViewerDocumentException('not a PDF');
  }
  return FakePdfDocument(pageSizes: const [ui.Size(8, 8)]);
}

/// A movie decoder that READS what it is pointed at — a file of its own, or
/// a stretch of one — and cannot read anything that is not a movie.
class ReadingVideoBackend extends FakeVideoBackend {
  ReadingVideoBackend() : super(frameCount: 3);

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    final head = Uint8List(movieMagic.length);
    final file = File(path).openSync();
    try {
      file.setPositionSync(range?.offset ?? 0);
      file.readIntoSync(head);
    } finally {
      file.closeSync();
    }
    if (String.fromCharCodes(head) != movieMagic) {
      return null;
    }
    return super.open(path, range: range);
  }
}

Future<String> writeCarriedPicture(Directory dir) =>
    writeSolidPng(dir, 'ref.png', width: 16, height: 12);

Future<String> writeCarriedPdf(Directory dir) =>
    written(dir, 'conte.pdf', '${pdfMagic}1.4 a carried conte'.codeUnits);

/// Noise behind the magic, so staging stores it as it is — a plain stretch a
/// decoder can be pointed at.
Future<String> writeCarriedMovie(Directory dir, {int length = 4096}) =>
    written(dir, 'take.mp4', [...movieMagic.codeUnits, ...noise(length)]);

Future<String> written(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

List<int> noise(int length) {
  final random = math.Random(7);
  return [for (var i = 0; i < length; i += 1) random.nextInt(256)];
}

/// A session holding [write]'s file as CARRIED — its bytes staged the moment
/// it was registered — and the path it is known by.
Future<({EditorSessionManager session, String path})> carrying(
  WidgetTester tester,
  Directory directory,
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

Future<void> saveProject(
  WidgetTester tester,
  EditorSessionManager session,
  Directory directory,
) => tester.runAsync(
  () => session.projectDoor.saveProjectToFile(
    normalizedMediaPath('${directory.path}/project.anicel'),
    asked: SaveAsked.byAPerson,
  ),
);

/// What becomes of the file a medium was carried from.
enum OriginalFate {
  deleted,
  replacedBySomethingElse;

  void befall(String path) => switch (this) {
    OriginalFate.deleted => File(path).deleteSync(),
    OriginalFate.replacedBySomethingElse => File(
      path,
    ).writeAsBytesSync('not this file'.codeUnits),
  };
}
