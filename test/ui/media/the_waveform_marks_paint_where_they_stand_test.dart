import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/media/waveform_marks_painter.dart';

/// The marks over a sound's band, as they PAINT: the span the import window
/// keeps of it, and the playhead both the viewer and that window draw.
///
/// F-282 ④ (2026-10-09): the import window's preview became the export
/// window's panel, and the span's wash — a widget of its own over a band the
/// preview drew itself — became a mark in the band's own transform. What a
/// test can read off the painter is where it was told the span stands; this
/// reads where it is washed.
void main() {
  /// [painter] on a band 100 wide and 10 tall, read back as the alpha of
  /// each column across the band's middle row.
  Future<List<int>> alphaAcross(
    WidgetTester tester,
    WaveformMarksPainter painter,
  ) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(100, 10));
    final picture = recorder.endRecording();
    final rgba = (await tester.runAsync(() async {
      final image = await picture.toImage(100, 10);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return [for (var x = 0; x < 100; x += 1) rgba[(5 * 100 + x) * 4 + 3]];
  }

  /// A second of sound on that band, the playhead at nine tenths of it.
  WaveformMarksPainter marks({({double from, double to})? kept}) =>
      WaveformMarksPainter(
        atSeconds: 0.9,
        ofSeconds: 1,
        docSize: const Size(100, 10),
        viewport: CanvasViewport(),
        effectiveRatio: 1,
        color: const Color(0xFF0000FF),
        kept: kept,
      );

  testWidgets('the span kept is washed from IN to OUT, and nothing beside '
      'it', (tester) async {
    final alpha = await alphaAcross(tester, marks(kept: (from: 0.25, to: 0.5)));

    expect(alpha[37], greaterThan(0), reason: 'inside the span');
    expect(alpha[12], 0, reason: 'before IN');
    expect(alpha[70], 0, reason: 'after OUT, short of the playhead');
  });

  testWidgets('nothing kept washes nothing — the playhead alone', (
    tester,
  ) async {
    final alpha = await alphaAcross(tester, marks());

    expect(alpha[37], 0, reason: 'no span');
    expect(
      alpha[89] + alpha[90],
      greaterThan(0),
      reason: 'CONTROL: the playhead, at nine tenths',
    );
  });
}
