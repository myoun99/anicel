import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';

import '../../helpers/conte_camera.dart';
import '../../helpers/pdf_content.dart';

/// The PDF prints a moving camera's path the way the page does (유저
/// 2026-09-29/30): the first and last frames and the four corner trails as
/// lines where the marks lay them, and each key's name turned with its
/// frame.
void main() {
  final words = conteWordsIn(AppLanguage.ja);

  ConteSheetSource sheetOf(ConteCameraWork work) => ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: '1',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: [
          ConteCellSource(
            startFrame: 0,
            endFrameExclusive: 24,
            pictureFrame: 0,
            camera: work,
          ),
        ],
      ),
    ],
  );

  Future<(Uint8List, List<SheetMark>, double)> printedOf(
    WidgetTester tester,
    ConteCameraWork work,
  ) async {
    final source = sheetOf(work);
    final page = layoutConteSheet(source).single;
    final pdf = (await tester.runAsync(
      () async => writeContePdf(
        source: source,
        pages: [page],
        fonts: await ContePdfFonts.load(),
        words: words,
      ),
    ))!;
    return (
      pdf,
      contePageMarks(page, source, words: words),
      page.metrics.pageHeight,
    );
  }

  testWidgets('the frames and the trails print as lines, where the marks lay '
      'them', (tester) async {
    final (pdf, marks, height) = await printedOf(
      tester,
      conteCameraPan(across: 0.3, down: 0.5),
    );
    final strokes = pdfStrokes(pdf);
    final expected = marks.whereType<SheetStroke>().toList();
    expect(expected, hasLength(6), reason: 'fixture: four trails, two frames');
    for (final mark in expected) {
      final printed = strokes.where(
        (stroke) =>
            stroke.closed == mark.closed &&
            stroke.points.length == mark.points.length &&
            [
              for (final (index, point) in mark.points.indexed)
                (stroke.points[index] - Offset(point.dx, height - point.dy))
                    .distance,
            ].every((miss) => miss < 1e-3),
      );
      expect(
        printed,
        hasLength(1),
        reason: '${mark.closed ? 'a frame' : 'a trail'} at ${mark.points}',
      );
    }
  });

  testWidgets('a name turns with its frame, and a name on a square frame is '
      'not turned', (tester) async {
    const turn = math.pi / 6;
    List<Offset> turned(Offset centre) => [
      for (final corner in const [
        Offset(-960, -540),
        Offset(960, -540),
        Offset(960, 540),
        Offset(-960, 540),
      ])
        centre +
            Offset(
              corner.dx * math.cos(turn) - corner.dy * math.sin(turn),
              corner.dx * math.sin(turn) + corner.dy * math.cos(turn),
            ),
    ];
    final first = turned(const Offset(1500, 1000));
    final last = turned(const Offset(2500, 1000));
    final (pdf, _, _) = await printedOf(
      tester,
      ConteCameraWork(
        screen: const Size(1920, 1080),
        field: const Rect.fromLTRB(0, 0, 4000, 2000),
        keys: [
          ConteCameraKey(
            corners: first,
            role: ConteCameraKeyRole.first,
            label: 'IN',
          ),
          ConteCameraKey(
            corners: last,
            role: ConteCameraKeyRole.last,
            label: 'OUT',
          ),
        ],
        trails: [
          for (var corner = 0; corner < 4; corner += 1)
            [first[corner], last[corner]],
        ],
      ),
    );
    final turns = [
      for (final matrix in pdfTransforms(pdf))
        if ((matrix[1] + math.sin(turn)).abs() < 1e-3 &&
            (matrix[0] - math.cos(turn)).abs() < 1e-3)
          matrix,
    ];
    expect(
      turns,
      hasLength(2),
      reason: 'IN and OUT, each turned clockwise on the page — the other '
          'way round in the PDF\'s upward y',
    );

    final (square, _, _) = await printedOf(tester, conteCameraPan(across: 1));
    expect(
      [
        for (final matrix in pdfTransforms(square))
          if (matrix[1].abs() > 1e-6 || matrix[2].abs() > 1e-6) matrix,
      ],
      isEmpty,
      reason: 'nothing turned on a camera that does not turn',
    );
  });
}
