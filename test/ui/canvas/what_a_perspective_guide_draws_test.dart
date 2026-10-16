import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';

/// What a perspective guide draws (vanishing-point-types, 유저 2026-10-16),
/// read at the canvas's own calls — and what 래스터라이즈 bakes of it.
///
/// Q4 「가이드마다 막대 하나」: the guide's ONE line density is how many rays
/// each point sends, and how many lanes a family stands either side of the
/// view's middle. Q3 「손잡이로 대충」: a family's handle hangs on a stem from
/// the eye level's handle — part of the handle, drawn with the handles.
/// Q6 「화면에 보이는 그대로」: the bake is the lines as the canvas draws
/// them while the guide is picked, and nothing else.
///
/// ⚠️The eye level is hidden in every fixture, so every line on the canvas
/// is a ray, a lane or a stem.
void main() {
  const size = Size(300, 200);
  const paper = CanvasSize(width: 300, height: 200);
  const id = GuideId('per');
  const green = Color(0xFF00FF00);

  DrawingGuide guideOf(
    List<VanishingPoint> points, {
    int density = defaultGuideLineDensity,
  }) => DrawingGuide(
    id: id,
    name: '퍼스 1',
    shape: PerspectiveShape(
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 150, y: 100), angleDegrees: 0),
      eyeLevelVisible: false,
      vanishingPoints: points,
      lineDensity: density,
    ),
  );

  GuideOverlayPainter painterOf(
    DrawingGuide guide, {
    bool emphasized = false,
  }) => GuideOverlayPainter(
    guides: CutGuides(guides: [guide]),
    viewport: CanvasViewport(),
    canvasSize: paper,
    emphasized: emphasized,
    color: green,
    face: const TextStyle(),
    vanishingPointLabel: 'VP',
    selectedGuideId: id,
  );

  /// The lines [paint] draws: their two ends, and the paint.
  List<({Offset from, Offset to, Paint paint})> linesOf(
    void Function(Canvas canvas) paint,
  ) {
    final canvas = TestRecordingCanvas();
    paint(canvas);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawLine)
          (
            from: call.invocation.positionalArguments[0] as Offset,
            to: call.invocation.positionalArguments[1] as Offset,
            paint: call.invocation.positionalArguments[2] as Paint,
          ),
    ];
  }

  /// Each of [values], less the one before it, in order.
  List<double> stepsOf(Iterable<double> values) {
    final sorted = values.toList()..sort();
    return [
      for (var index = 1; index < sorted.length; index += 1)
        sorted[index] - sorted[index - 1],
    ];
  }

  group('Q4 — the guide\'s one line density', () {
    for (final density in const [
      minGuideLineDensity,
      defaultGuideLineDensity,
      maxGuideLineDensity,
    ]) {
      test('🚨at $density, each point sends $density rays, evenly round '
          'it', () {
        final apex = CanvasPoint(x: 40, y: 100);
        final lines = linesOf(
          (canvas) => painterOf(
            guideOf([
              VanishingPointAt(apex),
              VanishingPointAt(CanvasPoint(x: 260, y: 100)),
            ], density: density),
          ).paint(canvas, size),
        );

        expect(lines, hasLength(2 * density), reason: 'two points');
        final fromApex = lines.where(
          (line) => line.from == const Offset(40, 100),
        );
        expect(fromApex, hasLength(density));
        final turns = [
          for (final line in fromApex)
            math.atan2(line.to.dy - 100, line.to.dx - 40),
        ];
        for (final step in stepsOf(turns)) {
          expect(step, closeTo(2 * math.pi / density, 1e-9));
        }
      });

      test('🚨at $density, a family stands $density lanes either side of '
          'the middle, twice the view\'s long side over $density apart', () {
        final lines = linesOf(
          (canvas) => painterOf(
            guideOf([VanishingPointTowards(dx: 0, dy: 1)], density: density),
          ).paint(canvas, size),
        );

        expect(lines, hasLength(2 * density + 1));
        for (final line in lines) {
          expect(line.from.dx, closeTo(line.to.dx, 1e-9), reason: 'upright');
        }
        final across = [for (final line in lines) line.from.dx];
        expect(across, contains(closeTo(150, 1e-9)), reason: 'the middle');
        for (final step in stepsOf(across)) {
          expect(step, closeTo(2 * size.width / density, 1e-9));
        }
      });
    }
  });

  group('Q3 — the stem a family\'s handle hangs on', () {
    // A point on the plane and a family running right: the family's handle
    // stands 220 along its way from the eye level's handle at (150, 100).
    final guide = guideOf([
      VanishingPointAt(CanvasPoint(x: 40, y: 100)),
      VanishingPointTowards(dx: 1, dy: 0),
    ]);
    bool isStem(({Offset from, Offset to, Paint paint}) line) =>
        line.from == const Offset(150, 100) &&
        line.to == const Offset(370, 100);

    test('🚨while the guide tool is out the family\'s handle hangs on ONE '
        'stem from the eye level\'s handle, twice the line\'s weight — and '
        'the point on the plane on none', () {
      final lines = linesOf(
        (canvas) => painterOf(guide, emphasized: true).paint(canvas, size),
      );

      final stems = lines.where(isStem).toList();
      expect(stems, hasLength(1));
      // A paint keeps its width in 32 bits.
      expect(
        stems.single.paint.strokeWidth,
        closeTo(1.6 * 2, 1e-6),
        reason: 'picked: 1.6',
      );
      const rays = defaultGuideLineDensity;
      const lanes = defaultGuideLineDensity * 2 + 1;
      expect(
        lines,
        hasLength(rays + lanes + 1),
        reason: 'rays, lanes and the one stem — nothing for the point',
      );
    });

    test('with the guide tool put away there is no stem, as there is no '
        'handle', () {
      expect(
        linesOf((canvas) => painterOf(guide).paint(canvas, size)).where(isStem),
        isEmpty,
      );
    });

    test('🚨the lines 래스터라이즈 bakes carry no stem — the picked guide\'s '
        'lines alone', () {
      final lines = linesOf(
        (canvas) =>
            painterOf(guide, emphasized: true).paintLines(canvas, size, guide),
      );

      expect(lines.where(isStem), isEmpty);
      expect(
        lines,
        hasLength(defaultGuideLineDensity * 2 + 1 + defaultGuideLineDensity),
      );
    });
  });

  group('Q6 — 래스터라이즈\'s picture', () {
    /// The straight RGBA of the paper's pixel ([x], [y]) in [rgba].
    List<int> rgbaAt(Uint8List rgba, int x, int y) {
      final at = (y * paper.width + x) * 4;
      return rgba.sublist(at, at + 4);
    }

    testWidgets('🚨the picked guide\'s lines on the paper, a canvas pixel '
        'to a pixel, in the guide\'s colour and weight — no handle', (
      tester,
    ) async {
      final piece = await tester.runAsync(
        () => guideLinesOnPaper(
          guideOf([VanishingPointTowards(dx: 0, dy: 1)]),
          canvasSize: paper,
          color: green,
        ),
      );

      expect((piece!.originLeft, piece.originTop), (0, 0));
      expect((piece.image.width, piece.image.height), (300, 200));
      final rgba = piece.image.rgba;
      // The lanes stand 50 apart from the middle: x = 0, 50, …, 250.
      final lane = rgbaAt(rgba, 150, 10);
      expect(lane[1], greaterThan(250), reason: 'green');
      expect(lane[0] + lane[2], lessThan(10), reason: 'and only green');
      // Picked under the guide tool, a lane is 1.6 wide at 0.95 × 0.5: a
      // pixel either side of x = 150 holds 0.8 of it. Unpicked it would be
      // a 1.0 line at 0.28 × 0.5 — a fifth of this ink.
      expect(lane[3], greaterThan(60));
      expect(rgbaAt(rgba, 125, 10)[3], 0, reason: 'between the lanes');
      // The eye level's turning handle would ring (270, 100) at 5.
      expect(rgbaAt(rgba, 265, 100)[3], 0, reason: 'no handle');
      expect(rgbaAt(rgba, 275, 100)[3], 0, reason: 'no handle');
    });
  });
}
