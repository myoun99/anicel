import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// 🗣️F-227 (유저 2026-09-29): 「컷ol만들면 여백 길이 제대로 생기는데, 그 경우
/// 진짜 엔드라인은 여백라인이 엔드라인이됨. 즉 타임시트패널에서 엔드라인을
/// 여백엔드라인에 맞춰서 위치시키고, … 라인을 빨간색이 아닌 여백 엔드라인색으로
/// 그림. 그리고 ol여백이 있는 컷은 초수에도 기입함. 2+0 이라는 기존 초수가
/// 있고, 그 밑에 작게, (2+12)라는 여백포함한 초수를 기입해주는것이 관례」.
///
/// Measured as INK on the sheet the panel paints: where the end line is, what
/// colour it is, and whether the duration box prints a second length.
void main() {
  const cutId = CutId('cut-1');
  // An O.L crossing the cut's end: 6 frames of のりしろ past its 24.
  const crossing = <TransitionSpan>[
    (start: 18, length: 12, mark: CameraInstructionMarkType.ol),
  ];

  TimesheetDocument sheet(List<TransitionSpan> spans) =>
      TimesheetDocument.fromCut(
        cut: Cut(
          id: cutId,
          name: '1',
          duration: 24,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          layers: [
            Layer(
              id: const LayerId('a'),
              name: 'A',
              frames: [
                Frame(id: const FrameId('a-f1'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
              },
            ),
          ],
        ),
        projectName: 'P',
        fps: 24,
        transitionSpans: spans,
      );

  Future<(ByteData, int, TimesheetDocumentLayout)> rasterize(
    WidgetTester tester,
    TimesheetDocument document, {
    TimelineDragPreview? preview,
  }) async {
    final layout = TimesheetDocumentLayout(document: document);
    final width = (layout.paperLeft + layout.paperWidth + 8).ceil();
    final height = (layout.halfRowsTop(0) +
            document.pageFrameCount * TimesheetDocumentLayout.rowHeight)
        .ceil();
    final channel = ValueNotifier<TimelineDragPreview?>(preview);
    addTearDown(channel.dispose);
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      TimesheetDocumentPainter(
        words: timesheetWordsIn(AppLanguage.en),
        face: const TextStyle(),
        document: document,
        layout: layout,
        dragPreview: channel,
        cutId: cutId,
      ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
      final image = await recorder.endRecording().toImage(width, height);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    return (data!, width, layout);
  }

  bool near(ByteData bytes, int at, Color color) {
    int channel(double v) => (v * 255).round();
    return (bytes.getUint8(at) - channel(color.r)).abs() < 24 &&
        (bytes.getUint8(at + 1) - channel(color.g)).abs() < 24 &&
        (bytes.getUint8(at + 2) - channel(color.b)).abs() < 24;
  }

  /// How many pixels of the half's width wear [color] on the end line a
  /// cut of [frames] rows would draw.
  int lineInk(
    (ByteData, int, TimesheetDocumentLayout) raster,
    int frames,
    Color color,
  ) {
    final (bytes, width, layout) = raster;
    final line = layout.cutEndLineFor(frames);
    final left = layout.halfLeft(line.page, line.half).ceil();
    final y = line.y.round();
    var count = 0;
    for (var x = left; x < left + layout.halfWidth.floor(); x += 1) {
      if (near(bytes, (y * width + x) * 4, color)) {
        count += 1;
      }
    }
    return count;
  }

  bool inkDiffers(ByteData before, ByteData after, int width, Rect box) {
    for (var y = box.top.floor(); y < box.bottom.ceil(); y += 1) {
      for (var x = box.left.floor(); x < box.right.ceil(); x += 1) {
        final at = (y * width + x) * 4;
        if (before.getUint32(at) != after.getUint32(at)) {
          return true;
        }
      }
    }
    return false;
  }

  testWidgets('a cut that owes のりしろ ends its sheet at the drawn end, in the '
      'のりしろ colour — and the red conte end line is gone', (tester) async {
    final raster = await rasterize(tester, sheet(crossing));
    final half = raster.$3.halfWidth;
    expect(
      lineInk(raster, 30, AppColors.noriShiro),
      greaterThan(half * 0.8),
      reason: 'the end line sits under row 30 — 24 conte + 6 のりしろ',
    );
    expect(lineInk(raster, 24, AppColors.danger), 0);
    expect(lineInk(raster, 30, AppColors.danger), 0);
  });

  testWidgets('CONTROL: with nothing crossing, the red line ends the conte', (
    tester,
  ) async {
    final raster = await rasterize(tester, sheet(const []));
    expect(
      lineInk(raster, 24, AppColors.danger),
      greaterThan(raster.$3.halfWidth * 0.8),
    );
  });

  testWidgets('the drawn end follows a cut-length drag, のりしろ riding it', (
    tester,
  ) async {
    final raster = await rasterize(
      tester,
      sheet(crossing),
      preview: CutTrimDragPreview(previewDurations: {cutId: 36}),
    );
    expect(
      lineInk(raster, 42, AppColors.noriShiro),
      greaterThan(raster.$3.halfWidth * 0.8),
    );
    expect(lineInk(raster, 30, AppColors.noriShiro), 0);
  });

  testWidgets('the duration box prints the drawn length small UNDER the conte '
      '尺, and nothing there without のりしろ', (tester) async {
    final owes = await rasterize(tester, sheet(crossing));
    final plain = await rasterize(tester, sheet(const []));
    final box = owes.$3
        .headerFieldBoxes(0)
        .firstWhere((box) => box.field == TimesheetHeaderField.time)
        .rect;
    final value = TimesheetDocumentPainter.headerValueRect(box);
    final valueBand = Rect.fromLTRB(
      value.left,
      value.top,
      value.right,
      value.top + TimesheetDocumentPainter.headerValueSize,
    );
    final underBand = Rect.fromLTRB(
      value.left,
      valueBand.bottom + 2,
      value.right,
      box.bottom - 1,
    );
    expect(
      inkDiffers(plain.$1, owes.$1, owes.$2, underBand),
      isTrue,
      reason: '(1 + 6) is printed under the value',
    );
    expect(
      inkDiffers(plain.$1, owes.$1, owes.$2, valueBand),
      isFalse,
      reason: 'the big number is the conte 尺 either way — 1 + 0',
    );
  });
}
