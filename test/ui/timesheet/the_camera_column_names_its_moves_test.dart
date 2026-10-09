import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/app_faces.dart';

/// 🗣️I-73 ⑤: 「이거는 타임시트패널에도 동일하게 표기하게할거야. 지시로서」 —
/// the camera's moves are written in the sheet's first CAM column as an
/// instruction column writes a span's name: down the column beside its
/// line, over the stretch's middle (「타임시트 CAM 첫 칸에도 같은 이름」).
///
/// The camera keys 2 → 8 → 14 on a 24-frame cut: a pan, then a zoom in.
void main() {
  setUpAll(loadTheAppFaces);

  CameraPose at(double x, {double zoom = 1}) =>
      CameraPose(center: CanvasPoint(x: x, y: 0), zoom: zoom);

  TimesheetDocument sheetOf(Map<int, CameraPose> keys) =>
      TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '1',
          duration: 24,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          layers: const [],
          camera: CutCamera(keyframes: keys),
        ),
        projectName: 'P',
        fps: 24,
        pageSeconds: 6,
        instructionDefById: CameraInstructionSet.standard.defById,
      );

  final moving = {2: at(0), 8: at(30), 14: at(30, zoom: 2)};
  final still = {2: at(0), 8: at(0), 14: at(0)};

  int cameraColumnOf(TimesheetDocument document) => document.columns
      .indexWhere((column) => column.kind == TimesheetColumnKind.camera);

  test('each stretch the camera moves along carries its name on its middle '
      'row, with the stretch\'s rows', () {
    final document = sheetOf(moving);
    final cells = document.columns[cameraColumnOf(document)].cells;

    expect(
      (cells[5].kind, cells[5].label, cells[5].spanLength, cells[5].spanOffset),
      (TimesheetCellKind.cameraSpan, 'PAN', 7, 3),
      reason: '2 → 8, its middle row',
    );
    expect(
      (cells[11].label, cells[11].spanLength, cells[11].spanOffset),
      ('T.U', 7, 3),
    );
    expect(
      [
        for (var row = 0; row < 24; row += 1)
          if (cells[row].label != null) row,
      ],
      [5, 11],
      reason: 'a key\'s row writes nothing of its own',
    );
  });

  test('a stretch of one row names its move on its first key', () {
    final document = sheetOf({
      2: at(0),
      3: at(0, zoom: 0.5),
      9: at(4, zoom: 0.5),
    });
    final cells = document.columns[cameraColumnOf(document)].cells;

    expect(
      (cells[2].kind, cells[2].label, cells[2].spanOffset),
      (TimesheetCellKind.cameraKey, null, null),
      reason: '2 → 3 is a cut, not a move',
    );
    expect(cells[6].label, 'PAN', reason: '3 → 9, its middle row');
  });

  /// How many pixels the sheet prints right of the first CAM column's line,
  /// over the rows from 2 to 14.
  Future<int> inkedBesideTheLine(
    WidgetTester tester,
    TimesheetDocument document,
  ) async {
    final layout = TimesheetDocumentLayout(document: document);
    final painter = TimesheetDocumentPainter(
      document: document,
      layout: layout,
      face: const TextStyle(
        fontFamily: AppTypography.bundledFamily,
        fontFamilyFallback: AppTypography.bundledFallback,
      ),
      words: timesheetWordsIn(AppLanguage.ja),
      layers: SheetStratum.content.layers,
    );
    final size = layout.documentSize;
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final width = size.width.ceil();
    final height = size.height.ceil();
    final rgba = (await tester.runAsync(() async {
      final image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();

    final column = cameraColumnOf(document);
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.camera);
    // Clear of the line and its keys' dots (3.4 round the middle).
    final from = (left + columnWidth / 2 + 5).ceil();
    final to = (left + columnWidth - 1).floor();
    final top = layout.halfRowsTop(0) + 2 * TimesheetDocumentLayout.rowHeight;
    final bottom =
        layout.halfRowsTop(0) + 15 * TimesheetDocumentLayout.rowHeight;
    var inked = 0;
    for (var y = top.ceil(); y < bottom.floor() && y < height; y += 1) {
      for (var x = from; x < to; x += 1) {
        if (rgba[(y * width + x) * 4 + 3] != 0) {
          inked += 1;
        }
      }
    }
    return inked;
  }

  testWidgets('🎯the names are printed beside the line — and nothing is '
      'where the camera holds still', (tester) async {
    expect(await inkedBesideTheLine(tester, sheetOf(still)), 0);
    expect(await inkedBesideTheLine(tester, sheetOf(moving)), greaterThan(0));
  });
}
