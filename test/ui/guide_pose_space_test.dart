import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/services/layer_pose_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guides stand on the CANVAS, but a layer carrying a transform is drawn
/// through its placement and its strokes record in the layer's own ARTWORK
/// coordinates — the panel wraps the view in the placement and Flutter's
/// hit testing brings pointers back the other way. So what a guide measures
/// makes the same trip, or the axis sits where the pen is not.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)」. ↩️These pinned `guidesInArtworkSpace`, which carried the guide
/// itself into the artwork — its axis, its vanishing points — and let the
/// stroke measure there. The last two cases are what that got wrong.
void main() {
  const canvasSize = CanvasSize(width: 200, height: 200);
  final centre = CanvasPoint(x: 100, y: 100);

  /// A quarter turn CLOCKWISE about the canvas centre.
  final quarterTurn = (
    pose: TransformPose.uniform(center: centre, zoom: 1, rotationDegrees: 90),
    anchorPoint: null,
  );

  /// Stretched to one and a half along its own x, shrunk along its own y,
  /// and turned — a placement no pose is under a folder, and no similarity.
  final stretchedAndTurned = (
    pose: TransformPose(
      center: CanvasPoint(x: 110, y: 95),
      scaleX: 1.5,
      scaleY: 0.75,
      rotationDegrees: 30,
    ),
    anchorPoint: null,
  );

  CutGuides verticalMirror() {
    const id = GuideId('sym');
    return CutGuides(
      guides: [
        DrawingGuide(
          id: id,
          name: 'Symmetry',
          shape: SymmetryShape(
            axis: GuideAxis(origin: centre, angleDegrees: 90),
          ),
        ),
      ],
      activeSymmetryId: id,
    );
  }

  final mirror = verticalMirror().actingSymmetry!;

  /// [point] mirrored across the canvas's vertical line x = 100.
  CanvasPoint mirrored(CanvasPoint point) =>
      CanvasPoint(x: 200 - point.x, y: point.y);

  void expectNear(CanvasPoint actual, CanvasPoint expected, {String? reason}) {
    expect(actual.x, closeTo(expected.x, 1e-9), reason: reason);
    expect(actual.y, closeTo(expected.y, 1e-9), reason: reason);
  }

  group('guideSpaceOf', () {
    test('an unplaced row draws on the canvas itself', () {
      expect(identical(guideSpaceOf(null), GuideSpace.canvas), isTrue);
      expect(GuideSpace.canvas.isCanvas, isTrue);
    });

    test('a placed row\'s space is its placement, and the way back', () {
      final placement = placementOf(stretchedAndTurned, canvasSize);

      final space = guideSpaceOf(placement);

      expect(space.isCanvas, isFalse);
      expect(space.toCanvas, placement);
      final artwork = CanvasPoint(x: 37, y: 141);
      expectNear(space.toStroke.apply(space.toCanvas.apply(artwork)), artwork);
    });

    test('a zoom that would collapse the layer cannot even be built', () {
      // The no-way-back answer in guideSpaceOf is a backstop, not a path:
      // the pose model refuses a zero scale at construction, so the layer
      // can never actually collapse to nothing under it.
      expect(
        () => TransformPose.uniform(center: centre, zoom: 0),
        throwsArgumentError,
      );
    });
  });

  group('a symmetry\'s copies in a placed row', () {
    /// Where the copy of [artwork] lands on the canvas.
    CanvasPoint copyOnCanvas(GuideSpace space, CanvasPoint artwork) {
      final copies = symmetryCopiesIn(space, mirror);
      expect(copies, hasLength(2));
      expect(copies.first.isIdentity, isTrue, reason: 'the original');
      return space.toCanvas.apply(copies.last.apply(artwork));
    }

    test('a quarter-turned row: the copy is the canvas\'s mirror image', () {
      final space = guideSpaceOf(placementOf(quarterTurn, canvasSize));
      for (final artwork in [
        CanvasPoint(x: 60, y: 150),
        CanvasPoint(x: 133.5, y: 12.25),
      ]) {
        expectNear(
          copyOnCanvas(space, artwork),
          mirrored(space.toCanvas.apply(artwork)),
        );
      }
    });

    test('a row pushed aside: the copy is the canvas\'s mirror image', () {
      final space = guideSpaceOf(
        placementOf((
          pose: TransformPose(center: CanvasPoint(x: 140, y: 100)),
          anchorPoint: null,
        ), canvasSize),
      );
      final artwork = CanvasPoint(x: 30, y: 70);
      expectNear(
        copyOnCanvas(space, artwork),
        mirrored(space.toCanvas.apply(artwork)),
      );
    });

    test('🚨a row stretched along one axis and turned: the copy is STILL the '
        'canvas\'s mirror image — and so it is not a rigid copy in the row\'s '
        'own pixels', () {
      final space = guideSpaceOf(placementOf(stretchedAndTurned, canvasSize));
      final a = CanvasPoint(x: 60, y: 150);
      final b = CanvasPoint(x: 133.5, y: 12.25);
      for (final artwork in [a, b]) {
        expectNear(
          copyOnCanvas(space, artwork),
          mirrored(space.toCanvas.apply(artwork)),
        );
      }
      // The premise that makes this a different law from the old one: in
      // the row's own pixels the copy does not keep distances.
      final copy = symmetryCopiesIn(space, mirror).last;
      double apart(CanvasPoint p, CanvasPoint q) =>
          (Offset(p.x, p.y) - Offset(q.x, q.y)).distance;
      expect(
        (apart(copy.apply(a), copy.apply(b)) - apart(a, b)).abs(),
        greaterThan(1),
      );
    });
  });

  /// The view on a row placed by [placed], wrapped in exactly the matrix the
  /// panel uses and handed exactly what the panel hands it; the dabs of one
  /// drag from [from] to [to] on the SCREEN, as the canvas shows them.
  Future<List<Offset>> dragOnAPlacedRow(
    WidgetTester tester,
    LayerPoseSample placed, {
    required Offset from,
    required Offset to,
  }) async {
    final commits = <BrushStrokeCommitData>[];
    final viewport = CanvasViewport();
    final cel = BitmapSurface(canvasSize: canvasSize, tileSize: 32);
    final placement = placementOf(placed, canvasSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: Transform(
                transform: placementViewportWrapMatrix(placement, viewport),
                child: InteractiveBrushEditCanvasView(
                  celNow: () => cel,
                  layerId: const LayerId('l'),
                  frameId: const FrameId('f'),
                  inputSettings: () => BrushEditCanvasInputSettings(
                    color: 0xFFFF0000,
                  ),
                  viewport: viewport,
                  guides: verticalMirror(),
                  guideSpace: guideSpaceOf(placement),
                  onSourceStrokeCommitted: commits.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Driven in SCREEN coordinates on purpose. The shared drag helper
    // offsets from the view's top-left, which a placement moves — and the
    // whole claim here is about where things land on screen, so the gesture
    // has to speak that language too. The 200×200 box sits at the origin
    // with the viewport at rest, so screen and canvas coordinates coincide.
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // R25-④: the pen-up commit lands one frame AFTER pen-up.
    await tester.pump();

    expect(commits, hasLength(1));
    final dabs = commits.single.sourceDabs;
    expect(dabs, isNotEmpty);
    // The recorded points are ARTWORK coordinates; taking them back through
    // the placement says where they landed on the canvas the user sees.
    return [
      for (final dab in dabs)
        Offset(
          placement.apply(dab.center).x,
          placement.apply(dab.center).y,
        ),
    ];
  }

  testWidgets('a stroke on a POSED layer mirrors where the screen shows it', (
    tester,
  ) async {
    // Drawn to the RIGHT of the screen-vertical axis at x = 100.
    final onCanvas = await dragOnAPlacedRow(
      tester,
      quarterTurn,
      from: const Offset(150, 60),
      to: const Offset(170, 80),
    );

    final screenX = [for (final point in onCanvas) point.dx];
    expect(
      screenX.any((x) => x > 100.5),
      isTrue,
      reason: 'the drawn half should be right of the axis on screen',
    );
    expect(
      screenX.any((x) => x < 99.5),
      isTrue,
      reason: 'the mirrored half must land LEFT of the axis on screen — if '
          'the guide were read in the artwork as it stands on the canvas it '
          'would come out above or below instead',
    );
  });

  testWidgets('🚨on a row stretched along one axis and turned, every dab has '
      'its mirror image on the SCREEN', (tester) async {
    final onCanvas = await dragOnAPlacedRow(
      tester,
      stretchedAndTurned,
      from: const Offset(150, 60),
      to: const Offset(170, 80),
    );

    expect(onCanvas.any((point) => point.dx > 100.5), isTrue);
    for (final point in onCanvas) {
      final image = Offset(200 - point.dx, point.dy);
      expect(
        onCanvas.any((other) => (other - image).distance < 1e-6),
        isTrue,
        reason: 'the dab at $point has no mirror image at $image',
      );
    }
  });
}
