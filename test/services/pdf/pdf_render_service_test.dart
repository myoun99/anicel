import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
    expect(await PdfRenderService.open('C:/nowhere/x.pdf'), isNull);
  });

  test('debugOpenerOverride routes open() to the fake and flips '
      'availability without any FFI', () async {
    final fake = FakePdfDocument(pageSizes: const [ui.Size(100, 200)]);
    PdfRenderService.debugOpenerOverride = (path) async => fake;

    expect(PdfRenderService.availability, isTrue);
    expect(await PdfRenderService.ensureAvailable(), isTrue);
    final document = await PdfRenderService.open('C:/anywhere/y.pdf');
    expect(document, same(fake));
    expect(document!.pageCount, 1);
    expect(document.pageSize(0), const ui.Size(100, 200));

    final image = await document.renderPage(0, width: 10, height: 20);
    expect((image.width, image.height), (10, 20));
    image.dispose();
    expect(fake.renderRequests, [(0, 10, 20)]);
  });

  test('debugResetForTests clears the override and the probe verdict', () {
    PdfRenderService.debugOpenerOverride = (path) async =>
        FakePdfDocument(pageSizes: const [ui.Size(1, 1)]);
    expect(PdfRenderService.availability, isTrue);
    PdfRenderService.debugResetForTests();
    expect(PdfRenderService.availability, isNull);
  });
}
