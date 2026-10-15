import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import '../../helpers/pdf_content.dart';

/// A photo laid on a sheet's ink (I-97) prints in the PDF where the page
/// shows it — the screen's `paintSheetPhotos`, in PDF space: its file
/// upright where its reference stands it on the ink's surface, the surface
/// where the window lays it, and the ink's raster over it.
void main() {
  const path = 'C:/pool/photo.png';
  final source = ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: '1',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: const [
          ConteCellSource(
            startFrame: 0,
            endFrameExclusive: 24,
            pictureFrame: 0,
            frameId: FrameId('f'),
            inkId: 'i',
          ),
        ],
      ),
    ],
  );
  final key = conteInkRowKey(const CutId('a'), 'i');
  final page = layoutConteSheet(source).single;
  final m = page.metrics;
  final band = page.cells.single.rowBandRect(m);

  /// A 40×20 photo centred on surface pixel (60, 30), turned [degrees].
  CelPhoto photo({double degrees = 0}) => CelPhoto(
    id: 1,
    reference: MediaReference(
      assetPath: path,
      pose: TransformPose(
        center: CanvasPoint(x: 60, y: 30),
        rotationDegrees: degrees,
      ),
      pictureSize: const CanvasSize(width: 40, height: 20),
    ),
  );

  /// Where surface pixel [pixel] lies on the PDF's page: from the band's
  /// corner, `paperScale` of them to a point — y up.
  Offset onPage(Offset pixel) {
    final paper = band.topLeft + pixel / m.paperScale;
    return Offset(paper.dx, m.pageHeight - paper.dy);
  }

  ContePdfPicture blank(int width, int height) => ContePdfPicture(
    rgba: Uint8List(width * height * 4),
    width: width,
    height: height,
  );

  Future<Uint8List?> written(
    WidgetTester tester, {
    required List<CelPhoto> photos,
    ContePdfPicture? raster,
  }) => tester.runAsync(
    () async => writeContePdf(
      source: source,
      pages: [page],
      fonts: await ContePdfFonts.load(),
      words: conteWordsIn(AppLanguage.ja),
      images: {path: blank(40, 20)},
      inkPictures: {key: ?raster},
      inkPhotos: {key: photos},
    ),
  );

  void expectAt(Offset laid, Offset pixel, String corner) => expect(
    (laid - onPage(pixel)).distance,
    lessThan(0.01),
    reason: '$corner: at $laid, not ${onPage(pixel)}',
  );

  testWidgets('a photo is laid where its reference stands it on the ink, '
      'its file upright in it — a window with no ink of its own as well', (
    tester,
  ) async {
    final pdf = await written(tester, photos: [photo()]);

    final laid = pdfImageCorners(pdf!).single;
    // 40×20 about (60, 30): x 40–80, y 20–40.
    expectAt(laid.topLeft, const Offset(40, 20), 'its first row\'s left');
    expectAt(laid.topRight, const Offset(80, 20), 'its first row\'s right');
    expectAt(laid.bottomLeft, const Offset(40, 40), 'its last row\'s left');
  });

  testWidgets('a turned photo turns about its centre, clockwise', (
    tester,
  ) async {
    final pdf = await written(tester, photos: [photo(degrees: 90)]);

    final laid = pdfImageCorners(pdf!).single;
    // Its first row runs down the right side: (70, 10) → (70, 50).
    expectAt(laid.topLeft, const Offset(70, 10), 'its first row\'s left');
    expectAt(laid.topRight, const Offset(70, 50), 'its first row\'s right');
    expectAt(laid.bottomLeft, const Offset(50, 10), 'its last row\'s left');
  });

  testWidgets('the ink\'s raster is laid over it', (tester) async {
    final width = (m.bodyWidth * m.paperScale).ceil();
    final height = (m.bodyHeight * m.paperScale).ceil();
    final pdf = await written(
      tester,
      photos: [photo()],
      raster: blank(width, height),
    );

    final laid = pdfImageCorners(pdf!);
    int at(Offset pixel) => laid.indexWhere(
      (image) => (image.topLeft - onPage(pixel)).distance < 0.01,
    );
    expect(at(const Offset(40, 20)), isNonNegative, reason: 'the photo');
    expect(
      at(Offset.zero),
      greaterThan(at(const Offset(40, 20))),
      reason: 'the raster, from the band\'s corner, after it',
    );
  });
}
