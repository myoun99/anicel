import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brush_canvas_test_helpers.dart';

/// Guides are a contract about what a real gesture puts on the canvas, so
/// these drive the actual pointer pipeline rather than calling the geometry
/// directly — the unit tests next door already cover the maths, and a
/// pipeline that never consulted them would still pass those.
void main() {
  const layerId = LayerId('layer-a');
  const frameId = FrameId('frame-a');
  const canvasSize = CanvasSize(width: 200, height: 200);

  late List<BrushStrokeCommitData> commits;

  setUp(() => commits = <BrushStrokeCommitData>[]);

  BrushEditSessionState sessionState() => BrushEditSessionState(
    canvasState: CanvasSurfaceState(
      currentSurface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
    ),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );

  Widget app(CutGuides guides) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: canvasSize.width.toDouble(),
          height: canvasSize.height.toDouble(),
          child: InteractiveBrushEditCanvasView(
            sessionState: sessionState(),
            layerId: layerId,
            frameId: frameId,
            inputSettings: BrushEditCanvasInputSettings(color: 0xFFFF0000),
            guides: guides,
            onSourceStrokeCommitted: commits.add,
          ),
        ),
      ),
    ),
  );

  List<BrushDab> dabs() {
    expect(commits, hasLength(1), reason: 'one stroke, one commit');
    return commits.single.sourceDabs;
  }

  CutGuides symmetryGuides({int lineCount = 2, bool lineSymmetry = true}) {
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
            lineCount: lineCount,
            lineSymmetry: lineSymmetry,
          ),
        ),
      ],
      activeSymmetryId: id,
    );
  }

  CutGuides perspectiveGuides({bool snapEnabled = true}) => CutGuides(
    guides: [
      DrawingGuide(
        id: const GuideId('persp'),
        name: 'Perspective',
        shape: PerspectiveShape(
          // A single horizontal family: strokes must come out flat.
          vanishingPoints: [VanishingPointTowards(dx: 1, dy: 0)],
          eyeLevel: GuideAxis(
            origin: CanvasPoint(x: 0, y: 100),
            angleDegrees: 0,
          ),
          snapEnabled: snapEnabled,
        ),
      ),
    ],
  );

  testWidgets('no guides leaves the stroke exactly where it was drawn', (
    tester,
  ) async {
    await tester.pumpWidget(app(CutGuides.empty));

    await dragCanvas(tester, const [
      Offset(120, 40),
      Offset(140, 60),
      Offset(160, 80),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    expect(drawn.every((dab) => dab.center.x >= 100), isTrue);
    // Sequence numbers stay one per dab when nothing replicates.
    expect(
      drawn.map((dab) => dab.sequence).toList(),
      List<int>.generate(drawn.length, (index) => index),
    );
  });

  testWidgets('an acting symmetry puts the same stroke on both sides', (
    tester,
  ) async {
    await tester.pumpWidget(app(symmetryGuides()));

    await dragCanvas(tester, const [
      Offset(120, 40),
      Offset(140, 60),
      Offset(160, 80),
    ]);

    final drawn = dabs();
    final right = drawn.where((dab) => dab.center.x > 100).toList();
    final left = drawn.where((dab) => dab.center.x < 100).toList();

    expect(right, isNotEmpty);
    expect(left, hasLength(right.length));
    // Every dab on the right has a partner mirrored about x = 100.
    for (final dab in right) {
      expect(
        left.any(
          (other) =>
              (other.center.x - (200 - dab.center.x)).abs() < 1e-6 &&
              (other.center.y - dab.center.y).abs() < 1e-6,
        ),
        isTrue,
        reason: 'no mirror partner for ${dab.center}',
      );
    }
  });

  testWidgets('symmetry doubles the dab count and keeps sequences unique', (
    tester,
  ) async {
    await tester.pumpWidget(app(CutGuides.empty));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final plain = dabs().length;

    commits.clear();
    await tester.pumpWidget(app(symmetryGuides()));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final mirrored = dabs();

    expect(mirrored.length, plain * 2);
    expect(
      mirrored.map((dab) => dab.sequence).toSet().length,
      mirrored.length,
      reason: 'a repeated sequence number would collide in the batch',
    );
  });

  testWidgets('a four-line symmetry emits four copies', (tester) async {
    await tester.pumpWidget(app(CutGuides.empty));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);
    final plain = dabs().length;

    commits.clear();
    await tester.pumpWidget(app(symmetryGuides(lineCount: 4)));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);

    expect(dabs().length, plain * 4);
  });

  testWidgets('a switched-off symmetry replicates nothing', (tester) async {
    // Keeping several symmetry guides is fine; only the ACTING one draws.
    final kept = CutGuides(guides: symmetryGuides().guides);

    await tester.pumpWidget(app(kept));
    await dragCanvas(tester, const [Offset(120, 40), Offset(160, 80)]);

    expect(dabs().every((dab) => dab.center.x >= 100), isTrue);
  });

  testWidgets('perspective snapping flattens a wobbly stroke onto its ray', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides()));

    // Drawn with a pronounced vertical wobble; the horizontal family must
    // straighten it.
    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(60, 118),
      Offset(100, 84),
      Offset(150, 112),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    for (final dab in drawn) {
      expect(
        dab.center.y,
        closeTo(100, 1e-6),
        reason: 'the wobble should not survive the snap',
      );
    }
  });

  testWidgets('a switched-off perspective leaves the wobble alone', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides(snapEnabled: false)));

    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(60, 118),
      Offset(100, 84),
    ]);

    expect(dabs().any((dab) => (dab.center.y - 100).abs() > 1), isTrue);
  });

  testWidgets('the snapped stroke starts where the pen went down', (
    tester,
  ) async {
    // The held run is released onto the ray, and the ray passes through the
    // pen-down point — so nothing is lost off the front of the stroke.
    await tester.pumpWidget(app(perspectiveGuides()));

    await dragCanvas(tester, const [
      Offset(20, 100),
      Offset(24, 103),
      Offset(120, 96),
    ]);

    final drawn = dabs();
    final leftmost = drawn
        .map((dab) => dab.center.x)
        .reduce((a, b) => a < b ? a : b);
    expect(leftmost, closeTo(20, 1.0));
  });

  testWidgets('a short flick under the lock distance still draws', (
    tester,
  ) async {
    await tester.pumpWidget(app(perspectiveGuides()));

    await dragCanvas(tester, const [Offset(60, 100), Offset(63, 101)]);

    expect(commits, hasLength(1));
    expect(dabs(), isNotEmpty);
  });

  testWidgets('snap and symmetry compose: constrain first, then copy', (
    tester,
  ) async {
    final both = CutGuides(
      guides: [...symmetryGuides().guides, ...perspectiveGuides().guides],
      activeSymmetryId: const GuideId('sym'),
    );

    await tester.pumpWidget(app(both));
    await dragCanvas(tester, const [
      Offset(120, 100),
      Offset(140, 118),
      Offset(180, 84),
    ]);

    final drawn = dabs();
    expect(drawn, isNotEmpty);
    // Snapped flat by the perspective, then mirrored about x = 100: both
    // halves are on the eye level, and both sides are present.
    for (final dab in drawn) {
      expect(dab.center.y, closeTo(100, 1e-6));
    }
    expect(drawn.any((dab) => dab.center.x > 100), isTrue);
    expect(drawn.any((dab) => dab.center.x < 100), isTrue);
  });
}
