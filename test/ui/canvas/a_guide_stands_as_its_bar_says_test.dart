import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';

/// What F-544 asked of a guide's lines (유저 2026-11-02): that they stand as
/// the bar and the colour say, with the tool in hand and without — and that
/// they reach the view from however far off they start.
void main() {
  const paper = CanvasSize(width: 300, height: 200);
  const size = Size(300, 200);
  const green = Color(0xFF00FF00);
  const red = 0xFFFF0000;
  const blue = 0xFF0000FF;
  const id = GuideId('g');

  DrawingGuide symmetry({
    double opacity = 1,
    int? color,
    CanvasPoint? origin,
    bool lineSymmetry = true,
  }) => DrawingGuide(
    id: id,
    name: '대칭',
    opacity: opacity,
    color: color,
    shape: SymmetryShape(
      axis: GuideAxis(
        origin: origin ?? CanvasPoint(x: 150, y: 100),
        angleDegrees: 90,
      ),
      lineSymmetry: lineSymmetry,
    ),
  );

  DrawingGuide perspective({
    double opacity = 1,
    int? color,
    int? eyeLevelColor,
    bool eyeLevelVisible = true,
    List<VanishingPoint>? points,
    CanvasPoint? eyeLevelAt,
  }) => DrawingGuide(
    id: id,
    name: '퍼스',
    opacity: opacity,
    color: color,
    shape: PerspectiveShape(
      eyeLevel: GuideAxis(
        origin: eyeLevelAt ?? CanvasPoint(x: 150, y: 100),
        angleDegrees: 0,
      ),
      eyeLevelVisible: eyeLevelVisible,
      eyeLevelColor: eyeLevelColor,
      vanishingPoints:
          points ?? [VanishingPointAt(CanvasPoint(x: 10, y: 100))],
    ),
  );

  GuideOverlayPainter painter(
    DrawingGuide guide, {
    bool tool = false,
    CanvasViewport? viewport,
  }) => GuideOverlayPainter(
    guides: CutGuides(guides: [guide]),
    viewport: viewport ?? CanvasViewport(),
    canvasSize: paper,
    emphasized: tool,
    color: green,
    face: const TextStyle(),
    vanishingPointLabel: 'VP',
    selectedGuideId: id,
  );

  List<({Offset from, Offset to, Paint paint})> linesOf(
    GuideOverlayPainter painter,
  ) {
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, size);
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

  /// The one of [lines] that runs furthest down.
  ({Offset from, Offset to, Paint paint}) lowest(
    List<({Offset from, Offset to, Paint paint})> lines,
  ) => lines.reduce((a, b) => a.to.dy > b.to.dy ? a : b);

  List<Paint> circlesOf(GuideOverlayPainter painter) {
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, size);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawCircle)
          call.invocation.positionalArguments[2] as Paint,
    ];
  }

  group('🚨the bar is the guide\'s opacity', () {
    test('a symmetry\'s line stands at the bar, a perspective\'s eye level '
        'and rays within it', () {
      expect(
        linesOf(painter(symmetry(opacity: 0.4))).single.paint.color.a,
        closeTo(0.4, 1e-6),
      );

      final lines = linesOf(painter(perspective(opacity: 0.4)));
      expect(lines.first.paint.color.a, closeTo(0.4 * 0.85, 1e-6));
      expect(lines.last.paint.color.a, closeTo(0.4 * 0.5, 1e-6));
    });

    for (final (name, guide) in [
      ('symmetry', symmetry()),
      ('perspective', perspective()),
    ]) {
      test('🚨$name: leaving the guide tool changes no line — colour, '
          'opacity and width alike', () {
        final out = linesOf(painter(guide));
        final held = linesOf(painter(guide, tool: true));
        expect(held, hasLength(greaterThanOrEqualTo(out.length)));
        for (var index = 0; index < out.length; index += 1) {
          expect(held[index].from, out[index].from);
          expect(held[index].to, out[index].to);
          expect(held[index].paint.color, out[index].paint.color);
          expect(held[index].paint.strokeWidth, out[index].paint.strokeWidth);
        }
      });
    }

    test('🚨a bar run down to nothing leaves the handles — they are not the '
        'lines', () {
      final fills = circlesOf(painter(symmetry(opacity: 0), tool: true));
      expect(fills, isNotEmpty);
      for (final paint in fills) {
        expect(paint.color.a, closeTo(0.95, 1e-6));
      }
    });

    testWidgets('🚨what is baked stands at the bar too', (tester) async {
      double? alphaOf(DrawingGuide guide) {
        final canvas = TestRecordingCanvas();
        paintGuideLines(canvas, [guide], canvasSize: paper, color: green);
        for (final call in canvas.invocations) {
          if (call.invocation.memberName == #drawLine) {
            return (call.invocation.positionalArguments[2] as Paint).color.a;
          }
        }
        return null;
      }

      expect(alphaOf(symmetry(opacity: 0.3)), closeTo(0.3, 1e-6));
    });
  });

  group('🚨the colour is the guide\'s', () {
    int argbOf(Paint paint) => paint.color.withValues(alpha: 1).toARGB32();

    test('one that names none wears the app\'s, one that does its own — on '
        'its handles too', () {
      expect(
        argbOf(linesOf(painter(symmetry())).single.paint),
        green.toARGB32(),
      );
      expect(
        argbOf(linesOf(painter(symmetry(color: red))).single.paint),
        red,
      );
      final fill = circlesOf(painter(symmetry(color: red), tool: true)).first;
      expect(argbOf(fill), red);
    });

    test('🚨the eye level wears its own where it names one, the guide\'s '
        'where not — and the rays never wear it', () {
      final own = linesOf(
        painter(perspective(color: red, eyeLevelColor: blue)),
      );
      expect(argbOf(own.first.paint), blue);
      expect(argbOf(own.last.paint), red);

      final worn = linesOf(painter(perspective(color: red)));
      expect(argbOf(worn.first.paint), red);
    });

    test('a guide\'s colour keeps the bar\'s opacity', () {
      final line = linesOf(
        painter(symmetry(color: red, opacity: 0.5)),
      ).single;
      expect(line.paint.color.a, closeTo(0.5, 1e-6));
    });
  });

  group('🚨a line reaches the view from however far off it starts', () {
    /// A point this far up the canvas is further off the view than twice
    /// its long side once zoomed in.
    const far = 2000.0;
    final zoomed = CanvasViewport(zoom: 2);

    test('a point\'s rays: the one straight down leaves the bottom of the '
        'view at 200%', () {
      final lines = linesOf(
        painter(
          perspective(
            eyeLevelVisible: false,
            points: [
              VanishingPointAt(
                CanvasPoint(x: 75, y: -far),
                lineDensity: 4,
              ),
            ],
          ),
          viewport: zoomed,
        ),
      );
      final down = lowest(lines);
      expect(down.from.dy, lessThan(-size.longestSide * 2));
      expect(down.to.dy, greaterThanOrEqualTo(size.height));
    });

    test('🚨an eye level whose handle stands far off still crosses the '
        'view', () {
      final horizon = linesOf(
        painter(
          perspective(eyeLevelAt: CanvasPoint(x: -far, y: 50)),
          viewport: zoomed,
        ),
      ).first;
      final left = horizon.from.dx < horizon.to.dx ? horizon.from : horizon.to;
      final right = horizon.from.dx < horizon.to.dx ? horizon.to : horizon.from;
      expect(left.dx, lessThanOrEqualTo(0));
      expect(right.dx, greaterThanOrEqualTo(size.width));
    });

    test('🚨a symmetry\'s axis from a far middle still crosses the view', () {
      final axis = linesOf(
        painter(
          symmetry(origin: CanvasPoint(x: 75, y: -far)),
          viewport: zoomed,
        ),
      ).single;
      final top = axis.from.dy < axis.to.dy ? axis.from : axis.to;
      final bottom = axis.from.dy < axis.to.dy ? axis.to : axis.from;
      expect(top.dy, lessThanOrEqualTo(0));
      expect(bottom.dy, greaterThanOrEqualTo(size.height));
    });

    test('🚨so does a ray of a symmetry that turns rather than mirrors', () {
      final rays = linesOf(
        painter(
          symmetry(
            origin: CanvasPoint(x: 75, y: -far),
            lineSymmetry: false,
          ),
          viewport: zoomed,
        ),
      );
      expect(lowest(rays).to.dy, greaterThanOrEqualTo(size.height));
    });
  });

  group('🚨hiding the eye level hides its handles (F-544)', () {
    Iterable<GuideHandleKind> kindsOf(DrawingGuide guide) =>
        guideHandles(CutGuides(guides: [guide])).map((handle) => handle.kind);

    test('its two go, the vanishing point\'s stays', () {
      expect(kindsOf(perspective()), [
        GuideHandleKind.origin,
        GuideHandleKind.eyeLevelAngle,
        GuideHandleKind.vanishingPoint,
      ]);
      expect(kindsOf(perspective(eyeLevelVisible: false)), [
        GuideHandleKind.vanishingPoint,
      ]);
    });

    test('a hidden eye level draws no handle of its own on the canvas', () {
      expect(circlesOf(painter(perspective(), tool: true)), hasLength(6));
      expect(
        circlesOf(painter(perspective(eyeLevelVisible: false), tool: true)),
        hasLength(2),
      );
    });

    test('a family at infinity keeps its handle: it has no other', () {
      expect(
        kindsOf(
          perspective(
            eyeLevelVisible: false,
            points: [VanishingPointTowards(dx: 1, dy: 0)],
          ),
        ),
        [GuideHandleKind.parallelDirection],
      );
    });
  });
}
