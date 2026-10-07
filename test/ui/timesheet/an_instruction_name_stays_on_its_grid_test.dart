import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
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

/// 🚨AN INSTRUCTION'S NAME STAYS ON THE GRID IT IS WRITTEN ON (F-286).
///
/// 유저 2026-10-04: 「타임시트 용지패널의 카메라 지시, 지금 6초 컷에서 6초만큼의
/// 지시가 있을때, 지시 메모? TB같은 지시의 중앙에 생기는 글자가 스샷처럼 칸
/// 밖으로 나가는데, 이런 경우 중앙 아니어도 되니까 칸 안으로 들어가도록. 딱
/// 보니까 지시명 길어질수록 용지 밖으로 나갈거같아보여서」.
///
/// The name is written down the column at the span's middle, and spills
/// past a span too short for it (the sheet's own rule). A six-second span on
/// a six-second page has its middle on the left half's last line; a short
/// span at the cut's end has it on the grid's last rows. Read where nothing
/// but the paper should be — the CAM columns under the grid — in the values
/// stratum alone.
void main() {
  setUpAll(loadTheAppFaces);

  TimesheetDocument document(
    Map<int, InstructionEvent> instructions, {
    CameraInstructionDef? Function(String id)? defs,
  }) => TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '12',
          duration: 144,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          layers: [
            Layer(
              id: const LayerId('cam'),
              name: 'CAM',
              kind: LayerKind.instruction,
              frames: const [],
              timeline: const {},
              instructions: instructions,
            ),
          ],
        ),
        projectName: 'P',
        fps: 24,
        pageSeconds: 6,
        instructionDefById: defs ?? CameraInstructionSet.standard.defById,
      );

  /// How many pixels the values print in the CAM columns from [top] to
  /// [bottom] of [half] on the first page.
  Future<int> inkedUnder(
    WidgetTester tester,
    TimesheetDocument document, {
    required bool continuous,
    required int half,
  }) async {
    final layout = TimesheetDocumentLayout(
      document: document,
      continuous: continuous,
    );
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

    final rows = continuous
        ? document.rowCount
        : layout.halfStrips.singleWhere((strip) => strip.half == half).rowCount;
    final gridBottom =
        layout.halfRowsTop(0) + rows * TimesheetDocumentLayout.rowHeight;
    var inked = 0;
    for (var column = 0; column < document.columns.length; column += 1) {
      final kind = document.columns[column].kind;
      if (kind != TimesheetColumnKind.camera) {
        continue;
      }
      final left =
          layout.halfLeft(0, continuous ? 0 : half) +
          layout.columnLeftInHalf(column);
      final right = left + layout.columnWidthFor(kind);
      // A few pixels clear of the grid's own last line (the cut's red end
      // line is a value, and the cut ends on the page's last row).
      for (var y = gridBottom.ceil() + 3; y < gridBottom + 60; y += 1) {
        if (y >= height) {
          break;
        }
        for (var x = left.floor(); x < right.ceil(); x += 1) {
          if (rgba[(y * width + x) * 4 + 3] != 0) {
            inked += 1;
          }
        }
      }
    }
    return inked;
  }

  testWidgets('🎯a six-second T.B on a six-second page writes its name on '
      'the left half, not under it', (tester) async {
    expect(
      await inkedUnder(
        tester,
        document({0: const InstructionEvent(instructionId: 'tb', length: 144)}),
        continuous: false,
        half: 0,
      ),
      0,
    );
  });

  // Two frames at the cut's very end: the name is longer than its span,
  // and the span's middle is the grid's last line.
  final atTheEnd = {
    142: const InstructionEvent(instructionId: 'pan-down', length: 2),
  };

  testWidgets('🎯a long name on a short span at the end of the page stays '
      'above the half\'s last line', (tester) async {
    expect(
      await inkedUnder(
        tester,
        document(atTheEnd),
        continuous: false,
        half: 1,
      ),
      0,
    );
  });

  testWidgets('the same in the continuous view: above the strip\'s last '
      'line', (tester) async {
    expect(
      await inkedUnder(tester, document(atTheEnd), continuous: true, half: 0),
      0,
    );
  });

  testWidgets('a name longer than the whole half — a set of one\'s own can '
      'name an instruction so — packs to the half\'s length', (tester) async {
    final long = CameraInstructionDef(
      id: 'long',
      name: 'FOLLOW ' * 30,
      iconKey: 'follow',
    );
    expect(
      await inkedUnder(
        tester,
        document({
          0: const InstructionEvent(instructionId: 'long', length: 72),
        }, defs: (id) => id == 'long' ? long : null),
        continuous: false,
        half: 0,
      ),
      0,
    );
  });
}
