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

  test('debugResetForTests clears the override and the probe verdict', () {
    PdfRenderService.debugOpenerOverride = (_) async =>
        FakePdfDocument(pageSizes: const [ui.Size(1, 1)]);
    expect(PdfRenderService.availability, isTrue);
    PdfRenderService.debugResetForTests();
    expect(PdfRenderService.availability, isNull);
  });
}
