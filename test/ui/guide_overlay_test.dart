import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasPoint _point(double x, double y) => CanvasPoint(x: x, y: y);

CutGuides _symmetry() {
  const id = GuideId('sym');
  return CutGuides(
    guides: [
      DrawingGuide(
        id: id,
        name: 'Symmetry',
        shape: SymmetryShape(
          axis: GuideAxis(origin: _point(100, 100), angleDegrees: 90),
        ),
      ),
    ],
    activeSymmetryId: id,
  );
}

CutGuides _perspective({bool constrainToEyeLevel = true}) => CutGuides(
  guides: [
    DrawingGuide(
      id: const GuideId('p'),
      name: 'Perspective',
      shape: PerspectiveShape(
        vanishingPoints: [
          VanishingPointAt(_point(400, 100)),
          VanishingPointTowards(dx: 0, dy: 1),
        ],
        eyeLevel: GuideAxis(origin: _point(100, 100), angleDegrees: 0),
        constrainToEyeLevel: constrainToEyeLevel,
      ),
    ),
  ],
);

SymmetryShape _shapeOf(CutGuides guides) =>
    guides.guides.single.shape as SymmetryShape;

PerspectiveShape _perspectiveOf(CutGuides guides) =>
    guides.guides.single.shape as PerspectiveShape;

void main() {
  group('guideHandles', () {
    test('a symmetry offers its origin and a rotate handle', () {
      final handles = guideHandles(_symmetry());

      expect(handles.map((handle) => handle.kind), [
        GuideHandleKind.origin,
        GuideHandleKind.axisAngle,
      ]);
      expect(handles.first.position, _point(100, 100));
    });

    test('a hidden guide offers nothing to grab', () {
      final hidden = _symmetry().copyWith(
        guides: [_symmetry().guides.single.copyWith(visible: false)],
      );

      expect(guideHandles(hidden), isEmpty);
    });

    test('a vanishing point at INFINITY has no handle', () {
      // A direction is not somewhere you can grab; it is set from the tool
      // settings, which is also the only place it can be stated exactly.
      final handles = guideHandles(_perspective());

      final vanishing = handles
          .where((handle) => handle.kind == GuideHandleKind.vanishingPoint)
          .toList();
      expect(vanishing, hasLength(1));
      expect(vanishing.single.vanishingPointIndex, 0);
    });

    test('the nearest handle within reach wins, and none outside it', () {
      final handles = guideHandles(_symmetry());

      expect(
        guideHandleAt(handles, _point(104, 103), grabRadius: 10)?.kind,
        GuideHandleKind.origin,
      );
      expect(guideHandleAt(handles, _point(160, 160), grabRadius: 10), isNull);
    });
  });

  group('dragGuideHandle', () {
    test('dragging the origin moves the axis, keeping its angle', () {
      final guides = _symmetry();
      final handle = guideHandles(guides).first;

      final moved = dragGuideHandle(guides, handle, _point(40, 70));

      expect(_shapeOf(moved).axis.origin, _point(40, 70));
      expect(_shapeOf(moved).axis.angleDegrees, 90);
    });

    test('dragging the far handle rotates the axis about its origin', () {
      final guides = _symmetry();
      final handle = guideHandles(guides)[1];

      // Straight to the right of the origin: the axis becomes horizontal.
      final rotated = dragGuideHandle(guides, handle, _point(300, 100));

      expect(_shapeOf(rotated).axis.angleDegrees, closeTo(0, 1e-9));
      expect(_shapeOf(rotated).axis.origin, _point(100, 100));
    });

    test('a drag onto the origin itself does not spin the axis to zero', () {
      final guides = _symmetry();
      final handle = guideHandles(guides)[1];

      final dragged = dragGuideHandle(guides, handle, _point(100, 100));

      expect(_shapeOf(dragged).axis.angleDegrees, 0);
    });

    test('a constrained vanishing point lands on the eye level', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.vanishingPoint);

      final dragged = dragGuideHandle(guides, handle, _point(600, 480));

      final position =
          _perspectiveOf(dragged).vanishingPoints.first.resolve().position!;
      expect(position.x, closeTo(600, 1e-9));
      expect(position.y, closeTo(100, 1e-9), reason: 'pulled onto the horizon');
    });

    test('an unconstrained vanishing point lands where it was dropped', () {
      final guides = _perspective(constrainToEyeLevel: false);
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.vanishingPoint);

      final dragged = dragGuideHandle(guides, handle, _point(600, 480));

      final position =
          _perspectiveOf(dragged).vanishingPoints.first.resolve().position!;
      expect(position.y, closeTo(480, 1e-9));
    });

    test('dragging one vanishing point leaves the others alone', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.vanishingPoint);

      final dragged = dragGuideHandle(guides, handle, _point(600, 100));

      // The vertical family must still be exactly vertical.
      final second = _perspectiveOf(dragged).vanishingPoints[1];
      expect(second, isA<VanishingPointTowards>());
      expect(second.resolve().isInfinite, isTrue);
    });

    test('tilting the eye level keeps its origin', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.eyeLevelAngle);

      final tilted = dragGuideHandle(guides, handle, _point(200, 200));

      expect(_perspectiveOf(tilted).eyeLevel.angleDegrees, closeTo(45, 1e-9));
      expect(_perspectiveOf(tilted).eyeLevel.origin, _point(100, 100));
    });

    test('a handle for a guide that is gone changes nothing', () {
      final guides = _symmetry();
      final handle = guideHandles(guides).first;

      final empty = CutGuides.empty;
      expect(dragGuideHandle(empty, handle, _point(1, 1)), same(empty));
    });

    test('dragging never disturbs the acting-symmetry pointer', () {
      final guides = _symmetry();
      final handle = guideHandles(guides).first;

      final moved = dragGuideHandle(guides, handle, _point(10, 10));

      expect(moved.activeSymmetryId, guides.activeSymmetryId);
      expect(moved.actingSymmetry, isNotNull);
    });
  });

  // TS9: the handle layer is the third tool input layer that was taking
  // fingers while the one-finger slot was on flip — and the only one of the
  // three with no test at all, which is how it stayed missing.
  group('the handle layer obeys the touch law', () {
    Future<CutGuides?> dragHandle(
      WidgetTester tester,
      PointerDeviceKind kind,
    ) async {
      CutGuides? live;
      final guides = _symmetry();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuideEditLayer(
              guides: guides,
              viewport: CanvasViewport(),
              onGuidesChanged: (next) => live = next,
              onGuidesCommitted: (_) {},
            ),
          ),
        ),
      );
      // The origin handle sits at canvas (100,100) — identity viewport, so
      // that is where the pointer goes.
      final origin = tester.getTopLeft(find.byType(GuideEditLayer));
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: kind,
      );
      await tester.pump();
      await gesture.moveTo(origin + const Offset(140, 120));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      return live;
    }

    testWidgets('a finger moves no handle while the slot is on flip', (
      tester,
    ) async {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      addTearDown(() {
        AppInput.settings.value = AppInputSettings.testCorpusBaseline;
      });

      expect(await dragHandle(tester, PointerDeviceKind.touch), isNull);
      expect(
        await dragHandle(tester, PointerDeviceKind.stylus),
        isNotNull,
        reason: 'the pen edits guides as before',
      );
    });
  });
}
