import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dashed_path.dart';
import 'package:anicel/src/ui/storyboard_panel.dart'
    show StoryboardCutStartsPainter;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';

/// 🪶A projection row's cut starts, zoomed out to the whole film, are a line
/// for every cut on every row (card frame-panels-build-in-one-frame,
/// 2026-10-28): each start cut its own line into dashes and drew each dash
/// on its own, again whenever the panel was shown. Every line runs the
/// row's height from its top, so one line is cut and drawn at each start —
/// and ⛔nothing on the screen moves.
void main() {
  // A cell that puts every start on a fraction of a pixel, and a row whose
  // height is no whole number of dashes.
  const size = Size(120, 23);
  const starts = [0, 3, 4, 9, 15];

  StoryboardCutStartsPainter painterOn(
    TimelineFrameGeometryHandle geometry,
    ValueNotifier<int> bucket,
  ) => StoryboardCutStartsPainter(
    starts: starts,
    geometry: geometry,
    colorScheme: const ColorScheme.light(),
    windowBucket: bucket,
  );

  /// The line as it was drawn before: cut at each start, each dash a draw
  /// of its own.
  void paintAsBefore(
    StoryboardCutStartsPainter painter,
    Canvas canvas,
    Size size,
  ) {
    final dash = Paint()
      ..color = painter.colorScheme.outline
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final x in painter.cutStarts()) {
      final edge = Path()
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
      for (final piece in dashesAlong(
        edge,
        StoryboardCutStartsPainter.dashes,
      )) {
        canvas.drawPath(piece, dash);
      }
    }
  }

  Future<Uint8List> pixelsOf(void Function(Canvas canvas) paint) async {
    const ratio = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * ratio).round(),
      (size.height * ratio).round(),
    );
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    return bytes;
  }

  late TimelineFrameGeometryHandle geometry;
  late ValueNotifier<int> bucket;
  setUp(() {
    geometry = TimelineFrameGeometryHandle(
      const TimelineFrameGeometry(
        frameCellExtent: 7.3,
        frameStartIndex: 0,
        frameEndIndexExclusive: 1000,
        // The row's width ([size]).
        viewExtentPx: 120,
      ),
    );
    bucket = ValueNotifier<int>(0);
  });
  tearDown(() {
    geometry.dispose();
    bucket.dispose();
  });

  testWidgets('every start is drawn as it was, pixel for pixel', (
    tester,
  ) async {
    final painter = painterOn(geometry, bucket);
    expect(painter.cutStarts(), hasLength(starts.length));
    await tester.runAsync(() async {
      expect(
        await pixelsOf((canvas) => painter.paint(canvas, size)),
        await pixelsOf((canvas) => paintAsBefore(painter, canvas, size)),
      );
    });
  });

  test('one draw a start — the line is cut once, not at every start', () {
    final painter = painterOn(geometry, bucket);
    final before = TestRecordingCanvas();
    paintAsBefore(painter, before, size);
    final now = TestRecordingCanvas();
    painter.paint(now, size);

    int drawsOn(TestRecordingCanvas canvas) => canvas.invocations
        .where((call) => call.invocation.memberName == #drawPath)
        .length;
    expect(drawsOn(before), greaterThan(starts.length));
    expect(drawsOn(now), starts.length);
  });
}
