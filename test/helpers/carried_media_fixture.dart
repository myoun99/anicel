import 'dart:async';
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
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
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
/// a stretch of one, framed or not — and cannot read anything that is not a
/// movie.
///
/// ⚠️A framed stretch is read the way the real decoders read one: through
/// the engine's span reader ([MediaFramedBytes]), decoded.
class ReadingVideoBackend extends FakeVideoBackend {
  ReadingVideoBackend({super.readsFramed, this.refuses})
    : super(frameCount: 3);

  /// Files this decoder will not open, whatever they hold — the answer a
  /// reader cannot move to.
  final bool Function(String path)? refuses;

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) async {
    if (refuses?.call(path) ?? false) {
      return null;
    }
    final stored = span == null
        ? MediaFileBytes(path)
        : MediaArchiveBytes(
            archivePath: path,
            dataOffset: span.offset,
            length: span.length,
            framed: span.framed,
          );
    final head = Uint8List(movieMagic.length);
    mediaSourceDecodingFrames(stored).readIntoSync(head, 0, head.length);
    if (String.fromCharCodes(head) != movieMagic) {
      return null;
    }
    return super.open(path, span: span);
  }
}

/// A [ReadingVideoBackend] that says which files the movies it was asked to
/// close were read from — what 「the old document was let go」 is measured by.
class ClosingVideoBackend extends ReadingVideoBackend {
  ClosingVideoBackend({super.refuses});

  final List<String> closed = [];
  final Map<int, String> _openAt = {};
  var _tokens = 0;

  /// Every open and close, in the order they happened — `open <path>` and
  /// `close <path>` — what 「let go FIRST, then opened again」 is read off.
  final List<String> events = [];

  /// While set, every open waits for it — the moment a reader has asked
  /// and the decoder has not answered yet.
  Completer<void>? openGate;

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) async {
    await openGate?.future;
    final opened = await super.open(path, span: span);
    if (opened == null) {
      return null;
    }
    final token = _tokens += 1;
    _openAt[token] = path;
    events.add('open $path');
    return (token: token, info: opened.info);
  }

  @override
  Future<void> close(int token) async {
    closed.add(_openAt[token]!);
    events.add('close ${_openAt[token]}');
  }
}

/// Tears the tail of the project file at [file] the way an append crash
/// does (the crash contract): the body survives, the directory does not —
/// so the next save writes the file WHOLE and swaps it in.
void tearTheTail(String file) {
  final healthy = parseAnicelZipLayoutFile(file);
  File(file).openSync(mode: FileMode.append)
    ..truncateSync(healthy.centralDirectoryOffset + 7)
    ..closeSync();
  expect(
    () => parseAnicelZipLayoutFile(file),
    throwsFormatException,
    reason: 'the premise: the tail is torn',
  );
}

Future<String> writeCarriedPicture(Directory dir) =>
    writeSolidPng(dir, 'ref.png', width: 16, height: 12);

Future<String> writeCarriedPdf(Directory dir) =>
    written(dir, 'conte.pdf', '${pdfMagic}1.4 a carried conte'.codeUnits);

/// Noise behind the magic, so staging stores it as it is — a plain stretch a
/// decoder can be pointed at.
Future<String> writeCarriedMovie(Directory dir, {int length = 4096}) =>
    written(dir, 'take.mp4', [...movieMagic.codeUnits, ...noise(length)]);

/// A pattern behind the magic, so staging — where an engine can — keeps it
/// FRAMED: the shape a movie that shrinks takes.
Future<String> writeCompressibleMovie(Directory dir) => written(dir, 'take.mp4', [
  ...movieMagic.codeUnits,
  for (var i = 0; i < 64 * 1024; i += 1) (i ~/ 97) & 0xFF,
]);

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
