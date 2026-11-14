import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';

/// 🔬Card the-grid-sheet-draws-the-whole-axis-outside-the-shared-window: a
/// GRID SHEET DRAWS THE WINDOW ITS HOST'S ROWS DRAW — the frames
/// [visibleFrameWindowFor] gives the bucket the view stands in (Q8 「타임라인
/// · X시트 · 콘티 한 법」), not the whole axis. ↩️It drew the whole axis,
/// the conte's the whole film, on a tick its dock draws live each frame.
///
/// ⚠️Plain `test`s: `Picture.toImage` never completes inside the widget
/// tester's fake-async zone.
void main() {
  const cell = 14.0;
  const across = 200.0;
  const viewport = 1600.0;
  const ground = Color(0xFF202124);

  TimelineGridSheetPainter sheetOf({TimelineGridSheetWindow? window}) =>
      TimelineGridSheetPainter(
        frameCellExtent: cell,
        framesPerSecond: 24,
        colorScheme: const ColorScheme.dark(),
        ground: ground,
        rows: TimelineGridRows(
          [
            for (var row = 0; row < 5; row += 1)
              (
                extent: 40.0,
                ground: row == 2 ? const Color(0xFF2E3440) : ground,
              ),
          ],
          dashes: const [(frame: 300, from: 0, to: 40)],
        ),
        window: window,
      );

  ui.Picture recorded(
    TimelineGridSheetPainter sheet,
    double length, {
    double shift = 0,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(-shift, 0);
    sheet.paint(canvas, Size(length, across));
    return recorder.endRecording();
  }

  test('a sheet in a windowed host records its window, however long its '
      'axis', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final window = (bucket: bucket, viewportMainExtent: viewport);
    int bytesOf(TimelineGridSheetPainter sheet, double length) {
      final picture = recorded(sheet, length);
      addTearDown(picture.dispose);
      return picture.approximateBytesUsed;
    }

    // The conte's axis at 30 cuts and at 120 (the card's 11-08 numbers).
    final short = bytesOf(sheetOf(window: window), 5542);
    final long = bytesOf(sheetOf(window: window), 22130);
    final whole = bytesOf(sheetOf(), 22130);
    final inside = ValueNotifier<int>(7);
    addTearDown(inside.dispose);
    final midway = bytesOf(
      sheetOf(window: (bucket: inside, viewportMainExtent: viewport)),
      22130,
    );
    // ignore: avoid_print
    print(
      '[sheet] recorded bytes — whole axis 22130 px: $whole · its window: '
      '$long (5542 px: $short)',
    );
    expect(
      long,
      short,
      reason: 'a window is as long as the view, not the axis',
    );
    expect(long, lessThan(whole), reason: 'it drew the whole axis');
    expect(
      midway,
      closeTo(long, long * 0.25),
      reason: 'a window down the axis is as long as the first: it rules '
          'no boundary before it',
    );
  });

  test('what it draws in its window is what the whole sheet draws '
      'there', () async {
    const length = 22130.0;
    final bucket = ValueNotifier<int>(7);
    addTearDown(bucket.dispose);
    final frames = visibleFrameWindowFor(
      bucket: bucket,
      viewportMainExtent: viewport,
      cellExtent: cell,
      frameStartIndex: 0,
      frameEndIndexExclusive: (length / cell).ceil(),
    );
    final from = timelineFrameEdge(frames.startIndex, cell);
    final to = timelineFrameEdge(frames.endIndexExclusive, cell);
    const inside = '⛔premise: a window inside the axis';
    expect(from, greaterThan(0), reason: inside);
    expect(to, lessThan(length), reason: inside);

    Future<List<int>> pixelsOf(TimelineGridSheetPainter sheet) async {
      final picture = recorded(sheet, length, shift: from);
      final image = await picture.toImage((to - from).toInt(), across.toInt());
      picture.dispose();
      final bytes = await image.toByteData();
      image.dispose();
      return bytes!.buffer.asUint8List().toList();
    }

    final windowed = await pixelsOf(
      sheetOf(window: (bucket: bucket, viewportMainExtent: viewport)),
    );
    final whole = await pixelsOf(sheetOf());
    expect(
      whole.any((byte) => byte != 0),
      isTrue,
      reason: '⛔premise: the sheet draws there',
    );
    expect(windowed, whole);
  });

  test('a bucket crossing repaints it, and nothing else of the same window '
      'does', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final window = (bucket: bucket, viewportMainExtent: viewport);
    final sheet = sheetOf(window: window);
    var repaints = 0;
    void heard() => repaints += 1;
    sheet.addListener(heard);
    addTearDown(() => sheet.removeListener(heard));

    bucket.value = 1;

    expect(repaints, 1, reason: 'the crossing reaches the sheet');
    expect(sheet.shouldRepaint(sheetOf(window: window)), isFalse);
    expect(
      sheet.shouldRepaint(
        sheetOf(window: (bucket: bucket, viewportMainExtent: viewport + 1)),
      ),
      isTrue,
      reason: 'a view of another reach draws another window',
    );
  });
}
