import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// F-88 (유저 2026-09-12): 「타임라인 엔드라인 조절할때 타임시트헤더의 초수랑
/// 페이지수같은것도 갱신」.
///
/// Measured as INK, on the sheet the panel paints: while a cut-length drag
/// is in flight the header's duration box re-prints, and a box the drag
/// does not touch does not. The cut-end line already followed the drag —
/// the words beside it did not.
void main() {
  const cutId = CutId('cut-1');
  final document = TimesheetDocument.fromCut(
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
  );
  final layout = TimesheetDocumentLayout(document: document);
  final width = (layout.paperLeft + layout.paperWidth + 8).ceil();
  const height = 512;

  Future<ByteData> rasterize(
    WidgetTester tester,
    ValueNotifier<TimelineDragPreview?> channel,
  ) async {
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      TimesheetDocumentPainter(
        document: document,
        layout: layout,
        dragPreview: channel,
        cutId: cutId,
      ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
      final image = await recorder.endRecording().toImage(width, height);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    return data!;
  }

  bool inkDiffers(ByteData before, ByteData after, Rect box) {
    final bottom = box.bottom.ceil() < height ? box.bottom.ceil() : height;
    final right = box.right.ceil() < width ? box.right.ceil() : width;
    for (var y = box.top.floor(); y < bottom; y += 1) {
      for (var x = box.left.floor(); x < right; x += 1) {
        final at = (y * width + x) * 4;
        if (before.getUint32(at) != after.getUint32(at)) {
          return true;
        }
      }
    }
    return false;
  }

  Rect boxOf(TimesheetHeaderField field) => layout
      .headerFieldBoxes(0)
      .firstWhere((box) => box.field == field)
      .rect;

  testWidgets('the duration box re-prints while the cut end is dragged, and '
      'the cut number beside it does not', (tester) async {
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);

    final before = await rasterize(tester, channel);
    // The drag has the cut at 2400 frames — 100 seconds and none, where the
    // document still says one second.
    //
    // 🚨THE LENGTH OF THE LABEL IS THE MEASUREMENT (2026-09-16). The first
    // draft dragged to 150 frames ('6 + 6' against '1 + 0') and the raster
    // came back BYTE-IDENTICAL: the test font draws every glyph as the same
    // box, so two strings of equal length paint equal ink whatever their
    // characters are. Measured: 0 differing pixels in the whole 1128×512
    // sheet while `livePlaybackFrameCount` really did read 24 → 150. A
    // label that grows ('100 + 0', seven characters against five) is what
    // this raster can see.
    channel.value = CutTrimDragPreview(
      previewDurations: {cutId: 2400},
    );
    final after = await rasterize(tester, channel);

    expect(
      inkDiffers(before, after, boxOf(TimesheetHeaderField.time)),
      isTrue,
      reason: 'the header prints the length the drag is holding',
    );
    expect(
      inkDiffers(before, after, boxOf(TimesheetHeaderField.cut)),
      isFalse,
      reason: 'a box the drag does not speak for stands still',
    );
    expect(
      document.durationLabel,
      '1+0',
      reason: 'the DOCUMENT stays stale — only the paint follows the hand',
    );
  });
}
