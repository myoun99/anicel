import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guides live in CANVAS space, but a layer carrying a transform is drawn
/// through it and its strokes record in the layer's own ARTWORK coordinates
/// — the panel wraps the view in the pose and Flutter's hit testing brings
/// pointers back the other way. So the guides have to make the same trip,
/// or the axis sits where the pen is not.
void main() {
  const canvasSize = CanvasSize(width: 200, height: 200);

  /// A quarter turn CLOCKWISE about the canvas centre.
  final quarterTurn = (
    pose: TransformPose(
      center: CanvasPoint(x: 100, y: 100),
      zoom: 1,
      rotationDegrees: 90,
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
            axis: GuideAxis(
              origin: CanvasPoint(x: 100, y: 100),
              angleDegrees: 90,
            ),
          ),
        ),
      ],
      activeSymmetryId: id,
    );
  }

  group('guidesInArtworkSpace', () {
    test('no pose leaves the guides untouched', () {
      final guides = verticalMirror();

      expect(guidesInArtworkSpace(guides, null, canvasSize), same(guides));
    });

    test('a quarter turn takes a VERTICAL axis to a HORIZONTAL one', () {
      // The layer is drawn rotated, so an axis that reads vertical on
      // screen is horizontal in the pixels the stroke is recorded into.
      final mapped = guidesInArtworkSpace(
        verticalMirror(),
        quarterTurn,
        canvasSize,
      );

      final axis = (mapped.guides.single.shape as SymmetryShape).axis;
      expect(axis.origin.x, closeTo(100, 1e-9));
      expect(axis.origin.y, closeTo(100, 1e-9));
      // 90° − 90° = 0°, give or take which end of the line is named.
      expect(axis.angleDegrees.abs() % 180, closeTo(0, 1e-9));
    });

    test('a moved layer moves the axis with it', () {
      final shifted = (
        pose: TransformPose(
          center: CanvasPoint(x: 140, y: 100),
          zoom: 1,
          rotationDegrees: 0,
        ),
        anchorPoint: null,
      );

      final mapped = guidesInArtworkSpace(
        verticalMirror(),
        shifted,
        canvasSize,
      );

      // The layer was pushed 40 to the right, so in its own pixels the axis
      // sits 40 to the left of where it does on the canvas.
      final axis = (mapped.guides.single.shape as SymmetryShape).axis;
      expect(axis.origin.x, closeTo(60, 1e-9));
    });

    test('a vanishing DIRECTION stays a direction, only turned', () {
      // A direction has no position to move, and a pose cannot make it
      // finite — the vertical family is still a family, just rotated.
      final guides = CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('p'),
            name: 'Perspective',
            shape: PerspectiveShape(
              vanishingPoints: [VanishingPointTowards(dx: 0, dy: 1)],
              eyeLevel: GuideAxis(
                origin: CanvasPoint(x: 0, y: 100),
                angleDegrees: 0,
              ),
            ),
          ),
        ],
      );

      final mapped = guidesInArtworkSpace(guides, quarterTurn, canvasSize);

      final point =
          (mapped.guides.single.shape as PerspectiveShape).vanishingPoints
              .single;
      expect(point, isA<VanishingPointTowards>());
      final resolved = point.resolve();
      expect(resolved.isInfinite, isTrue);
      final direction = resolved.directionFrom(CanvasPoint(x: 0, y: 0))!;
      // The vertical family becomes the horizontal one under a quarter turn.
      expect(direction.dy.abs(), closeTo(0, 1e-9));
      expect(direction.dx.abs(), closeTo(1, 1e-9));
    });

    test('a zoom that would collapse the layer cannot even be built', () {
      // The singular-matrix guard in guidesInArtworkSpace is a backstop, not
      // a path: the pose model refuses a zero zoom at construction, so the
      // layer can never actually collapse to nothing under it.
      expect(
        () => TransformPose(
          center: CanvasPoint(x: 100, y: 100),
          zoom: 0,
          rotationDegrees: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  testWidgets('a stroke on a POSED layer mirrors where the screen shows it', (
    tester,
  ) async {
    // The end-to-end version: the view is wrapped in exactly the matrix the
    // panel uses, and fed exactly the guides the panel would map. A drag on
    // the right of the SCREEN axis has to come back mirrored to its left.
    final commits = <BrushStrokeCommitData>[];
    final viewport = CanvasViewport();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: Transform(
                transform: layerPoseViewportWrapMatrix(
                  quarterTurn.pose,
                  canvasSize,
                  viewport,
                  anchorPoint: quarterTurn.anchorPoint,
                ),
                child: InteractiveBrushEditCanvasView(
                  sessionState: BrushEditSessionState(
                    canvasState: CanvasSurfaceState(
                      currentSurface: BitmapSurface(
                        canvasSize: canvasSize,
                        tileSize: 32,
                      ),
                    ),
                    materializationHistoryState:
                        BrushBitmapMaterializationHistoryState(),
                  ),
                  layerId: const LayerId('l'),
                  frameId: const FrameId('f'),
                  inputSettings: BrushEditCanvasInputSettings(
                    color: 0xFFFF0000,
                  ),
                  viewport: viewport,
                  guides: guidesInArtworkSpace(
                    verticalMirror(),
                    quarterTurn,
                    canvasSize,
                  ),
                  onSourceStrokeCommitted: commits.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Drawn to the RIGHT of the screen-vertical axis at x = 100.
    //
    // Driven in SCREEN coordinates on purpose. The shared drag helper
    // offsets from the view's top-left, which a rotation moves — and the
    // whole claim here is about where things land on screen, so the gesture
    // has to speak that language too. The 200×200 box sits at the origin
    // and the quarter turn maps it onto itself, so screen and canvas
    // coordinates coincide.
    final gesture = await tester.startGesture(const Offset(150, 60));
    await tester.pump();
    await gesture.moveTo(const Offset(170, 80));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // R25-④: the pen-up commit lands one frame AFTER pen-up.
    await tester.pump();

    expect(commits, hasLength(1));
    final dabs = commits.single.sourceDabs;
    expect(dabs, isNotEmpty);

    // The recorded points are ARTWORK coordinates; taking them back through
    // the pose says where they landed on the canvas the user is looking at.
    final matrix = layerPoseMatrix(
      quarterTurn.pose,
      canvasSize,
      anchorPoint: quarterTurn.anchorPoint,
    ).storage;
    Offset onCanvas(CanvasPoint point) => Offset(
      matrix[0] * point.x + matrix[4] * point.y + matrix[12],
      matrix[1] * point.x + matrix[5] * point.y + matrix[13],
    );

    final screenX = dabs.map((dab) => onCanvas(dab.center).dx).toList();
    expect(
      screenX.any((x) => x > 100.5),
      isTrue,
      reason: 'the drawn half should be right of the axis on screen',
    );
    expect(
      screenX.any((x) => x < 99.5),
      isTrue,
      reason: 'the mirrored half must land LEFT of the axis on screen — if '
          'the guide were not mapped into artwork space it would come out '
          'above or below instead',
    );
  });
}
