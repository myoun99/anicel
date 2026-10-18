import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

/// ⑦ (text-letters-lean-and-underline-Q6, 유저 2026-10-18: 「앱에서도
/// 만들게 — 회전 · 기울임 · 뒤집기를 텍스트 도구에」): THE FRAME A TEXT IS SET
/// IN — leaned, then mirrored, then turned about its anchor — and the one
/// place it is worked out ([CelTextFrame]): the steps it draws by are the
/// steps it is asked by.
void main() {
  CelTextFrame frameOf({
    double turn = 0,
    double lean = 0,
    bool flipped = false,
  }) => CelTextFrame.of(
    CelTextContent(
      spans: const [CelTextSpan(text: 'ab', style: TextLetterStyle())],
      anchor: CanvasPoint(x: 100, y: 50),
      rotationDegrees: turn,
      skewDegrees: lean,
      flipped: flipped,
    ),
  );

  Matcher near(double x, double y, {double within = 1e-9}) =>
      isA<ui.Offset>()
      .having((p) => p.dx, 'dx', closeTo(x, within))
      .having((p) => p.dy, 'dy', closeTo(y, within));

  test('upright, a point of the frame is the anchor and it — exactly', () {
    expect(
      frameOf().toCanvas(const ui.Offset(7.25, -3.5)),
      const ui.Offset(107.25, 46.5),
    );
  });

  test('🚨leaned, a point stands further along the lines the HIGHER it '
      'stands — as italic letters lean', () {
    final leaned = frameOf(lean: 45);

    expect(leaned.toCanvas(const ui.Offset(0, -10)), near(110, 40));
    expect(leaned.toCanvas(const ui.Offset(0, 10)), near(90, 60));
    expect(leaned.toCanvas(const ui.Offset(10, 0)), near(110, 50));
  });

  test('mirrored, the lines run the other way from the anchor, and a lean '
      'is mirrored with them', () {
    expect(
      frameOf(flipped: true).toCanvas(const ui.Offset(10, 4)),
      near(90, 54),
    );
    expect(
      frameOf(lean: 45, flipped: true).toCanvas(const ui.Offset(0, -10)),
      near(90, 40),
    );
  });

  test('turned last: a quarter turn clockwise lays the lines downwards', () {
    expect(
      frameOf(turn: 90, lean: 45).toCanvas(const ui.Offset(10, -10)),
      near(110, 70),
    );
  });

  test('🚨a point of the canvas is read back where the frame laid it — a '
      'travel too — turned, leaned and mirrored', () {
    final frame = frameOf(turn: 33, lean: -20, flipped: true);
    const local = ui.Offset(12.5, -7);

    final there = frame.toCanvas(local);
    expect(frame.toLocal(there), near(local.dx, local.dy));
    expect(
      frame.inFrame(frame.onCanvas(const ui.Offset(3, 4))),
      near(3, 4),
    );
  });

  test('🚨what draws it takes the very steps it is asked by — on a canvas '
      'and on a matrix alike', () {
    for (final (turn, lean, flipped) in [
      (0.0, 0.0, false),
      (30.0, 0.0, false),
      (30.0, 25.0, false),
      (-70.0, -15.0, true),
    ]) {
      final frame = frameOf(turn: turn, lean: lean, flipped: flipped);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      frame.applyTo(canvas);
      final drawn = Matrix4.fromFloat64List(canvas.getTransform());
      recorder.endRecording().dispose();
      final matrix = Matrix4.identity();
      frame.applyToMatrix(matrix);

      for (final local in const [ui.Offset.zero, ui.Offset(10, -6)]) {
        final asked = frame.toCanvas(local);
        // A canvas keeps its matrix in single precision.
        for (final (name, by, within) in [
          ('canvas', drawn, 1e-4),
          ('matrix', matrix, 1e-9),
        ]) {
          final laid = by.transform3(Vector3(local.dx, local.dy, 0));
          expect(
            ui.Offset(laid.x, laid.y),
            near(asked.dx, asked.dy, within: within),
            reason: '$name, turned $turn, leaning $lean, mirrored $flipped',
          );
        }
      }
    }
  });

  test('a lean keeps the area a square of the frame covers', () {
    final frame = frameOf(turn: 12, lean: 40);
    final x = frame.xStep;
    final y = frame.yStep;

    expect(x.dx * y.dy - y.dx * x.dy, closeTo(1, 1e-12));
    expect(math.sqrt(x.dx * x.dx + x.dy * x.dy), closeTo(1, 1e-12));
  });
}
