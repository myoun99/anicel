import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/app_corner_radii.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import '../../helpers/pdf_content.dart';

Rect _bounds(List<Offset> points) => Rect.fromLTRB(
  points.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
  points.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
  points.map((p) => p.dx).reduce((a, b) => a > b ? a : b),
  points.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
);

/// The PDF's picture windows are the app's corner, as the panel draws them
/// (유저 2026-09-25: 「모서리 둥글게하자. 우리 앱 통일 모서리 따라서」). A PDF
/// has no superellipse, so the writer TRACES the engine's own shape; a
/// window written as a plain rectangle, or traced too coarsely to keep its
/// curve, prints a corner the panel never showed.
void main() {
  testWidgets('a window in the PDF is traced: its corner cut, the curve '
      'there, its sides where the window\'s are', (tester) async {
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
            ),
          ],
        ),
      ],
    );
    final page = layoutConteSheet(source).single;
    final m = page.metrics;
    final pdf = await tester.runAsync(() async {
      return writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: conteWordsIn(AppLanguage.ja),
      );
    });

    // The first row's window, turned into the PDF's upward y.
    final paper = m.windowRect(0);
    final window = Rect.fromLTRB(
      paper.left,
      m.pageHeight - paper.bottom,
      paper.right,
      m.pageHeight - paper.top,
    );
    final traced = pdfClosedPaths(pdf!).where((path) {
      final bounds = _bounds(path);
      return (bounds.left - window.left).abs() < 0.01 &&
          (bounds.top - window.top).abs() < 0.01 &&
          (bounds.right - window.right).abs() < 0.01 &&
          (bounds.bottom - window.bottom).abs() < 0.01;
    }).toList();
    expect(traced, hasLength(1), reason: 'the window is one traced path');

    const radius = AppCornerRadii.window;
    final points = traced.single;
    // The PDF's top-left, the paper's bottom-left: no point stands on the
    // square corner…
    expect(
      points.where((p) => (p - window.topLeft).distance < radius * 0.2),
      isEmpty,
      reason: 'the corner is cut',
    );
    // …and the curve that cuts it is there, off both sides.
    expect(
      points.where(
        (p) =>
            p.dx > window.left + 0.05 &&
            p.dx < window.left + radius &&
            p.dy > window.top + 0.05 &&
            p.dy < window.top + radius,
      ),
      isNotEmpty,
      reason: 'the corner is a curve, not a chamfer of two points',
    );
  });
}
