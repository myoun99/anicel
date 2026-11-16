import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';

/// 🔬Card the-grid-sheet-draws-the-whole-axis-outside-the-shared-window: a
/// GRID SHEET DRAWS THE WINDOW ITS HOST'S ROWS ARE LAID IN — the window
/// [TimelineFrameGeometry.windowedAt] gives the bucket the view stands in
/// (Q8 「타임라인 · X시트 · 콘티 한 법」), not the whole axis. ↩️It drew
/// the whole axis, the conte's the whole film, on a tick its dock draws
/// live each frame.
///
/// 🔬Card conte-sideways-scroll-build-spikes (11-16): and its canvas IS
/// that window, so the axis' end a drag past it grows a screen at a time
/// repaints nothing of it. ↩️Ruled over its window but as long as the axis,
/// it was laid out and painted again at every screen grown.
///
/// ⚠️Plain `test`s: `Picture.toImage` never completes inside the widget
/// tester's fake-async zone.
void main() {
  const cell = 14.0;
  const across = 200.0;
  const viewport = 1600.0;
  const ground = Color(0xFF202124);

  /// The axis [length] px long, its view [reach] px, seen through the
  /// window of the bucket the view stands in.
  TimelineFrameGeometry framesOf(
    double length,
    int bucket, {
    double reach = viewport,
  }) => TimelineFrameGeometry(
    frameCellExtent: cell,
    frameStartIndex: 0,
    frameEndIndexExclusive: (length / cell).ceil(),
    viewExtentPx: reach,
  ).windowedAt(bucket);

  TimelineFrameGeometryHandle windowOf(double length, int bucket) {
    final handle = TimelineFrameGeometryHandle(framesOf(length, bucket));
    addTearDown(handle.dispose);
    return handle;
  }

  TimelineGridSheetPainter sheetOf({TimelineFrameGeometryHandle? geometry}) =>
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
        geometry: geometry,
      );

  /// [sheet] as its box lays it: its window long under a [geometry], else
  /// [length] long.
  ui.Picture recorded(
    TimelineGridSheetPainter sheet,
    double length, {
    double shift = 0,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(-shift, 0);
    final window = sheet.geometry?.value.windowExtentPx;
    sheet.paint(canvas, Size(window ?? length, across));
    return recorder.endRecording();
  }

  test('a sheet in a windowed host records its window, however long its '
      'axis', () {
    int bytesOf(TimelineGridSheetPainter sheet, double length) {
      final picture = recorded(sheet, length);
      addTearDown(picture.dispose);
      return picture.approximateBytesUsed;
    }

    // The conte's axis at 30 cuts and at 120 (the card's 11-08 numbers).
    final short = bytesOf(sheetOf(geometry: windowOf(5542, 0)), 5542);
    final long = bytesOf(sheetOf(geometry: windowOf(22130, 0)), 22130);
    final whole = bytesOf(sheetOf(), 22130);
    final midway = bytesOf(sheetOf(geometry: windowOf(22130, 7)), 22130);
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
    final window = windowOf(length, 7);
    final from = window.value.windowOriginPx;
    final extent = window.value.windowExtentPx;
    const inside = '⛔premise: a window inside the axis';
    expect(from, greaterThan(0), reason: inside);
    expect(from + extent, lessThan(length), reason: inside);
    expect(from, from.roundToDouble(), reason: '⛔premise: on a pixel');

    Future<List<int>> pixelsOf(TimelineGridSheetPainter sheet) async {
      final picture = recorded(
        sheet,
        length,
        shift: sheet.geometry == null ? from : 0,
      );
      final image = await picture.toImage(extent.toInt(), across.toInt());
      picture.dispose();
      final bytes = await image.toByteData();
      image.dispose();
      return bytes!.buffer.asUint8List().toList();
    }

    final windowed = await pixelsOf(sheetOf(geometry: window));
    final whole = await pixelsOf(sheetOf());
    expect(
      whole.any((byte) => byte != 0),
      isTrue,
      reason: '⛔premise: the sheet draws there',
    );
    expect(windowed, whole);
  });

  // What a growth reaches is ruled before it is reached: the sheet is not
  // painted again when the axis grows (below), so a sheet cut where the
  // axis ended would show none of the room grown, the view walking into it
  // without a window crossing. The rows' own law (Q8: a row with a window
  // draws its window, not cut where the axis ends).
  test('past the axis\' end it rules on to its window\'s', () async {
    const length = 2000.0;
    final window = windowOf(length, 0);
    final extent = window.value.windowExtentPx;
    final end = ((length / cell).ceil() * cell).toInt();
    expect(extent, greaterThan(end + 400), reason: '⛔premise: a window '
        'reaching past the end');
    final picture = recorded(sheetOf(geometry: window), length);
    final image = await picture.toImage(extent.toInt(), across.toInt());
    picture.dispose();
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    // A column of the first row's pixels, past the end, inked by a line —
    // past the line that closes the axis' last frame, which stands on the
    // end, cut there or not.
    bool inked(int x) => bytes[(10 * extent.toInt() + x) * 4 + 3] != 0;
    final past = [
      for (var x = end + cell ~/ 2; x < end + 400; x += 1)
        if (inked(x)) x,
    ];
    expect(past, isNotEmpty, reason: 'the sheet stopped where the axis did');
  });

  test('a window move repaints it, and the axis growing in its window does '
      'not', () {
    const length = 22130.0;
    final window = windowOf(length, 0);
    final sheet = sheetOf(geometry: window);
    var repaints = 0;
    void heard() => repaints += 1;
    sheet.addListener(heard);
    addTearDown(() => sheet.removeListener(heard));

    // A drag past the end grows the axis a screen, the view where it was.
    window.value = framesOf(length + viewport, 0);
    expect(repaints, 0, reason: 'the axis growing repainted the sheet');

    window.value = framesOf(length + viewport, 3);
    expect(
      window.value.windowOriginPx,
      greaterThan(0),
      reason: '⛔premise: a window that moved',
    );
    expect(repaints, 1, reason: 'the window move reaches the sheet');
    expect(sheet.shouldRepaint(sheetOf(geometry: window)), isFalse);

    window.value = framesOf(length + viewport, 3, reach: viewport + 1);
    expect(repaints, 2, reason: 'a view of another reach draws another window');
  });
}
