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
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
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

  TimesheetDocument sheetOf(Map<int, CameraPose> keys, {int duration = 24}) =>
      TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '1',
          duration: duration,
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

  test('each stretch the camera moves along carries its name on its rows, '
      'with their place in it', () {
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
      [for (var row = 2; row < 14; row += 1) row],
      reason: 'the key that ends a stretch begins the next; the last ends',
    );
  });

  // The camera row's sheet switch: the one the conte's ACTION lines read
  // too (`LayerStackQueries.cameraOnSheet`, I-93).
  test('a camera off the sheet leaves its column blank', () {
    List<TimesheetCell> cellsWith({required bool onSheet}) {
      final document = TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '1',
          duration: 24,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          layers: [
            Layer(
              id: const LayerId('camera'),
              name: 'Camera',
              kind: LayerKind.camera,
              frames: const [],
              timeline: const {},
              onTimesheet: onSheet,
            ),
          ],
          camera: CutCamera(keyframes: moving),
        ),
        projectName: 'P',
        fps: 24,
        pageSeconds: 6,
        instructionDefById: CameraInstructionSet.standard.defById,
      );
      return document.columns[cameraColumnOf(document)].cells;
    }

    expect(cellsWith(onSheet: true)[5].label, 'PAN', reason: 'fixture');
    expect(
      cellsWith(onSheet: false).map((cell) => cell.kind),
      everyElement(TimesheetCellKind.empty),
    );
  });

  // 🗣️I-89 (유저 2026-10-10): 「그리고 회전은 모아트기준대로 하자」.
  test('a turn is written 回転, before the move it rides with', () {
    CameraPose turned(double degrees, {double zoom = 1}) => CameraPose(
      center: CanvasPoint(x: 0, y: 0),
      zoom: zoom,
      rotationDegrees: degrees,
    );
    final document = sheetOf({
      2: at(0),
      8: turned(30),
      14: turned(60, zoom: 2),
    });
    final cells = document.columns[cameraColumnOf(document)].cells;

    expect((cells[5].label, cells[11].label), ('回転', '回転 T.U'));
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

  test('a move toward a key past the sheet\'s rows is not written: its line '
      'is not on the sheet either', () {
    // A key the O.L that asked for it has since let go of can lie past the
    // cut — and past the page the sheet rounds the cut up to.
    final document = sheetOf({2: at(0), 300: at(90)});
    final cells = document.columns[cameraColumnOf(document)].cells;

    expect(cells.length, lessThan(300), reason: '⛔전제');
    expect([for (final cell in cells) ?cell.label], isEmpty);
    expect(cells[3].kind, TimesheetCellKind.empty, reason: 'no line either');
  });

  /// How many pixels the sheet prints right of the first CAM column's line,
  /// over [rows] of [half] of the first page.
  Future<int> inkedBesideTheLine(
    WidgetTester tester,
    TimesheetDocument document, {
    int half = 0,
    ({int from, int to}) rows = (from: 2, to: 15),
  }) async {
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
    final left = layout.halfLeft(0, half) + layout.columnLeftInHalf(column);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.camera);
    // Clear of the line — and of its keys' rows, each of which writes its
    // key across the line (I-89 ⑤).
    final from = (left + columnWidth / 2 + 5).ceil();
    final to = (left + columnWidth - 1).floor();
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final rowsTop = layout.halfRowsTop(0);
    final keyRows = {
      for (final (frame, cell) in document.columns[column].cells.indexed)
        if (cell.kind == TimesheetCellKind.cameraKey)
          if (layout.positionOfFrame(frame) case (
            page: 0,
            half: final keyHalf,
            :final row,
          ) when keyHalf == half)
            row,
    };
    final top = rowsTop + rows.from * rowHeight;
    final bottom = rowsTop + rows.to * rowHeight;
    var inked = 0;
    for (var y = top.ceil(); y < bottom.floor() && y < height; y += 1) {
      if (keyRows.contains((y - rowsTop) ~/ rowHeight)) {
        continue;
      }
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

  testWidgets('🚨a move that runs on into the next half of the page is named '
      'once, on the half its middle lies in', (tester) async {
    // A six-second page is two halves of 72 rows: 20 → 100 has its middle
    // on 60, and runs on through the second half's first 29 rows.
    final document = sheetOf({20: at(0), 100: at(80)}, duration: 120);

    expect(
      await inkedBesideTheLine(tester, document, rows: (from: 20, to: 72)),
      greaterThan(0),
      reason: '⛔전제: the name, on the first half',
    );
    expect(
      await inkedBesideTheLine(
        tester,
        document,
        half: 1,
        rows: (from: 0, to: 29),
      ),
      0,
      reason: 'the rest of its line, and no second name',
    );
  });
}
