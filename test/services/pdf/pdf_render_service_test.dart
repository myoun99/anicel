import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';

import '../../helpers/fake_pdf_document.dart';

/// The PDF seam's test doctrine: flutter_tester never touches the FFI
/// plugin (there is no Dart fallback to save it), so absence is the
/// DEFAULT here and fakes enter only through the debug opener.
void main() {
  tearDown(PdfRenderService.debugResetForTests);

  test('under flutter_tester the renderer is absent: open() is null and '
      'availability reports false (the honest-absence state)', () async {
    expect(await PdfRenderService.ensureAvailable(), isFalse);
    expect(PdfRenderService.availability, isFalse);
    expect(
      await PdfRenderService.open(const MediaFileBytes('C:/nowhere/x.pdf')),
      isNull,
    );
  });

  test('debugOpenerOverride routes open() to the fake and flips '
      'availability without any FFI', () async {
    final fake = FakePdfDocument(pageSizes: const [ui.Size(100, 200)]);
    final asked = <MediaByteSource>[];
    PdfRenderService.debugOpenerOverride = (source) async {
      asked.add(source);
      return fake;
    };

    expect(PdfRenderService.availability, isTrue);
    expect(await PdfRenderService.ensureAvailable(), isTrue);
    const where = MediaFileBytes('C:/anywhere/y.pdf');
    final document = await PdfRenderService.open(where);
    expect(document, same(fake));
    expect(asked, [where], reason: 'the seam is handed where the bytes are');
    expect(document!.pageCount, 1);
    expect(document.pageSize(0), const ui.Size(100, 200));

    final image = await document.renderPage(0, width: 10, height: 20);
    expect((image.width, image.height), (10, 20));
    image.dispose();
    expect(fake.renderRequests, [(0, 10, 20)]);
  });

  group('a window PDFium asks for', () {
    final window = Uint8List(64);

    test('is read off the isolate, never with it standing still — a cloud '
        'file comes down inside a read', () async {
      final reader = _Reader(
        (size) => size,
        sync: (_) => throw StateError('read with the isolate standing'),
      );

      expect(await readPdfWindow(reader, window, 0, 64), 64);
    });

    test('read whole, is its size', () async {
      expect(await readPdfWindow(_Reader((size) => size), window, 0, 64), 64);
    });

    test('read SHORT, is 0 — PDFium takes any other number for success',
        () async {
      expect(
        await readPdfWindow(_Reader((size) => size - 1), window, 0, 64),
        0,
      );
    });

    test('a read that throws is 0, not a page drawn from a stale buffer',
        () async {
      expect(
        await readPdfWindow(
          _Reader((_) => throw const FileSystemException('gone')),
          window,
          0,
          64,
        ),
        0,
      );
    });
  });

  // 🗣️유저 11-23 「pdf읽기는 퍼센트 안들어간단게 뭐야 … 당연히
  // 넣어야하는거아니야?」 — what PDFium reads while it opens is the file's
  // read (F-608-Q2).
  group('how far a PDF is read while it opens', () {
    test('rises with the bytes read, of the bytes the file holds', () {
      final heard = <double>[];
      final reads = PdfOpeningReads(400, heard.add);

      reads.took(100);
      reads.took(200);
      reads.took(100);

      expect(heard, [0.25, 0.75, 1]);
    });

    test('a window read again counts again, and stops at the whole', () {
      final heard = <double>[];
      final reads = PdfOpeningReads(400, heard.add)..took(300);

      reads.took(300);

      expect(heard, [0.75, 1]);
    });

    test("once open, a page's reads are its rasterizing's — not told", () {
      final heard = <double>[];
      final reads = PdfOpeningReads(400, heard.add)..took(100);

      reads.opened();
      reads.took(100);

      expect(heard, [0.25]);
    });

    test('a failed window (0) reads nothing', () {
      final heard = <double>[];
      PdfOpeningReads(400, heard.add).took(0);

      expect(heard, isEmpty);
    });
  });

  test('a test opener that hears the reads is told them', () async {
    final fake = FakePdfDocument(pageSizes: const [ui.Size(1, 1)]);
    final heard = <double>[];
    PdfRenderService.debugOpenerOverride =
        (source, {void Function(double fraction)? onRead}) async {
      onRead?.call(1);
      return fake;
    };

    await PdfRenderService.open(
      const MediaFileBytes('C:/anywhere/z.pdf'),
      onRead: heard.add,
    );

    expect(heard, [1]);
  });

  test('debugResetForTests clears the override and the probe verdict', () {
    PdfRenderService.debugOpenerOverride = (_) async =>
        FakePdfDocument(pageSizes: const [ui.Size(1, 1)]);
    expect(PdfRenderService.availability, isTrue);
    PdfRenderService.debugResetForTests();
    expect(PdfRenderService.availability, isNull);
  });
}

/// A window reader that answers [answer] for any window.
class _Reader implements MediaWindowReader {
  _Reader(this.answer, {int Function(int size)? sync}) : _sync = sync ?? answer;

  final int Function(int size) answer;
  final int Function(int size) _sync;

  @override
  int readIntoSync(Uint8List buffer, int position, int size) => _sync(size);

  @override
  Future<int> readInto(Uint8List buffer, int position, int size) async =>
      answer(size);

  @override
  void close() {}
}
