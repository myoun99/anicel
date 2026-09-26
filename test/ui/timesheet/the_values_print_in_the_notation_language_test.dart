import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/sheet/sheet_strata.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/run_edge_fixtures.dart';

/// The values print words too — a whole-cut hold its 止め, a repeat its
/// リピート (UI-R10 #6 · UI-R11 #15) — so a change of the notation language
/// re-records the values, not the form alone. In the app's own faces: the
/// test font sets every glyph as one square.
void main() {
  setUpAll(loadTheAppFaces);

  final cut = Cut(
    id: const CutId('c'),
    name: '1',
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      // One cel held from row 1 to the end: the hold word (UI-R11 #15).
      rederiveRunBehaviors(
        Layer(
          id: const LayerId('a'),
          name: 'A',
          kind: LayerKind.animation,
          frames: [
            Frame(id: const FrameId('a-1'), duration: 1, strokes: const []),
          ],
          timeline: const {
            0: TimelineExposure.drawing(
              FrameId('a-1'),
              length: 2,
              endEdge: holdMark,
            ),
          },
        ),
        cutFrameCount: 24,
      ),
    ],
  );
  final document = TimesheetDocument.fromCut(
    cut: cut,
    projectName: 'P',
    fps: 24,
  );

  TimesheetDocumentPainter values(AppLanguage language) =>
      TimesheetDocumentPainter(
        document: document,
        layout: TimesheetDocumentLayout(document: document),
        face: const TextStyle(
          fontFamily: AppTypography.bundledFamily,
          fontFamilyFallback: AppTypography.bundledFallback,
        ),
        layers: SheetStratum.content.layers,
        words: timesheetWordsIn(language),
      );

  Future<Uint8List> printed(
    WidgetTester tester,
    TimesheetDocumentPainter painter,
  ) async {
    final size = painter.layout.documentSize;
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final bytes = (await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return bytes;
  }

  testWidgets('a new notation language re-records the values, whose hold '
      'word it prints', (tester) async {
    final ja = values(AppLanguage.ja);
    final ko = values(AppLanguage.ko);
    expect(
      listEquals(await printed(tester, ja), await printed(tester, ko)),
      isFalse,
      reason: 'fixture: the values print a word of the language',
    );
    expect(ko.shouldRepaint(ja), isTrue);
    expect(values(AppLanguage.ja).shouldRepaint(ja), isFalse);
  });
}
