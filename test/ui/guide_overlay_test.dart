import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerDownEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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

    test('🚨a family at infinity\'s handle is its WAY\'s — 220 along it from '
        'the eye level\'s handle — and two parallel drawn lines get none', () {
      // ↩️It had none until 2026-10-16: 「a direction is not somewhere you
      // can grab」 (vanishing-point-types-Q3: 「둘 다 — 손잡이로 대충, 각도
      // 칸으로 정확히」).
      final handles = guideHandles(_perspective());

      final way = handles.singleWhere(
        (handle) => handle.kind == GuideHandleKind.parallelDirection,
      );
      expect(way.vanishingPointIndex, 1);
      expect(way.position, _point(100, 320));
      final standing = handles.singleWhere(
        (handle) => handle.kind == GuideHandleKind.vanishingPoint,
      );
      expect(standing.vanishingPointIndex, 0);

      final drawn = CutGuides(
        guides: [
          _perspective().guides.single.copyWith(
            shape: _perspectiveOf(_perspective()).copyWith(
              vanishingPoints: [
                VanishingPointFromLines(
                  GuideLine(a: _point(0, 0), b: _point(10, 0)),
                  GuideLine(a: _point(0, 5), b: _point(10, 5)),
                ),
              ],
            ),
          ),
        ],
      );
      expect(
        guideHandles(drawn).where(
          (handle) => handle.vanishingPointIndex != null,
        ),
        isEmpty,
        reason: 'its lines say its way',
      );
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

    test('🚨dragging a family\'s handle turns it to run from the eye '
        'level\'s handle to the hand — NOT pulled onto the eye level, and '
        'the point on the plane stays', () {
      final guides = _perspective();
      expect(
        _perspectiveOf(guides).constrainToEyeLevel,
        isTrue,
        reason: '⛔fixture: the points are held to the eye level',
      );
      final handle = guideHandles(guides).firstWhere(
        (h) => h.kind == GuideHandleKind.parallelDirection,
      );

      // (300, 400) from the eye level's handle at (100, 100).
      final turned = dragGuideHandle(guides, handle, _point(400, 500));

      final points = _perspectiveOf(turned).vanishingPoints;
      final family = points[1] as VanishingPointTowards;
      expect(family.dx, closeTo(0.6, 1e-12));
      expect(family.dy, closeTo(0.8, 1e-12));
      expect(points.first, VanishingPointAt(_point(400, 100)));
    });

    test('a family\'s handle dropped on the eye level\'s handle turns it '
        'nowhere', () {
      final guides = _perspective();
      final handle = guideHandles(guides).firstWhere(
        (h) => h.kind == GuideHandleKind.parallelDirection,
      );

      expect(dragGuideHandle(guides, handle, _point(100, 100)), same(guides));
    });

    test('tilting the eye level keeps its origin', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.eyeLevelAngle);

      final tilted = dragGuideHandle(guides, handle, _point(200, 200));

      expect(_perspectiveOf(tilted).eyeLevel.angleDegrees, closeTo(45, 1e-9));
      expect(_perspectiveOf(tilted).eyeLevel.origin, _point(100, 100));
    });

    // 유저 (guide-sym): 「소실점 아이레벨 고정 시 아이레벨을 움직이면 소실점도」.
    // BOTH eye-level handles are wired to the one rule — sliding and tilting
    // are two ways to move one line.
    test('sliding the eye level carries the vanishing points', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.origin);

      final slid = dragGuideHandle(guides, handle, _point(140, 160));

      final at = _perspectiveOf(slid).vanishingPoints.first.resolve().position!;
      expect(at.x, closeTo(440, 1e-9));
      expect(at.y, closeTo(160, 1e-9));
      // The vertical family is a DIRECTION; a slide does not move it.
      expect(
        _perspectiveOf(slid).vanishingPoints[1],
        isA<VanishingPointTowards>(),
      );
      expect(
        _perspectiveOf(slid).vanishingPoints[1].resolve().isInfinite,
        isTrue,
      );
    });

    test('tilting the eye level carries the vanishing points', () {
      final guides = _perspective();
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.eyeLevelAngle);

      final tilted = dragGuideHandle(guides, handle, _point(100, 220));

      expect(_perspectiveOf(tilted).eyeLevel.angleDegrees, closeTo(90, 1e-9));
      final at =
          _perspectiveOf(tilted).vanishingPoints.first.resolve().position!;
      expect(at.x, closeTo(100, 1e-9));
      expect(at.y, closeTo(400, 1e-9), reason: 'turned with the horizon');
    });

    test('an unconstrained eye level moves alone', () {
      final guides = _perspective(constrainToEyeLevel: false);
      final handle = guideHandles(guides)
          .firstWhere((h) => h.kind == GuideHandleKind.origin);

      final slid = dragGuideHandle(guides, handle, _point(140, 160));

      expect(_perspectiveOf(slid).eyeLevel.origin, _point(140, 160));
      final at = _perspectiveOf(slid).vanishingPoints.first.resolve().position!;
      expect(at.x, closeTo(400, 1e-9));
      expect(at.y, closeTo(100, 1e-9));
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

  // 🗣️I-136 (유저 2026-10-27): 「캔버스에서 어떤 조작 할때도 쉬프트 통해
  // 누른상태면 한쪽으로만. 즉 x,y가 있다치면 x 안건들고 y만 이동」.
  group('Shift keeps a handle that MOVES a point to one way (I-136)', () {
    setUp(CanvasTouchContacts.reset);
    tearDown(CanvasTouchContacts.reset);

    /// [guides] with the handle under [from] dragged by [by] — Shift held
    /// through it when [shift].
    Future<CutGuides> drag(
      WidgetTester tester,
      CutGuides guides,
      Offset from,
      Offset by, {
      bool shift = true,
      PointerDeviceKind kind = PointerDeviceKind.mouse,
    }) async {
      CutGuides? live;
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
      final origin = tester.getTopLeft(find.byType(GuideEditLayer));
      if (shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      final hand = await tester.startGesture(origin + from, kind: kind);
      await tester.pump();
      await hand.moveBy(by);
      await tester.pump();
      await hand.up();
      await tester.pump();
      if (shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      return live!;
    }

    (double, double) originOf(CutGuides guides) {
      final origin = _shapeOf(guides).axis.origin;
      return (origin.x, origin.y);
    }

    testWidgets('the origin goes across alone, from where it STOOD — a '
        'press off its middle does not pull it under the pen', (
      tester,
    ) async {
      final moved = await drag(
        tester,
        _symmetry(),
        const Offset(103, 102),
        const Offset(40, 15),
      );

      expect(originOf(moved), (140.0, 100.0));
    });

    testWidgets('↩️without Shift the handle stands under the pen', (
      tester,
    ) async {
      final moved = await drag(
        tester,
        _symmetry(),
        const Offset(103, 102),
        const Offset(40, 15),
        shift: false,
      );

      expect(originOf(moved), (143.0, 117.0));
    });

    testWidgets('a vanishing point keeps to one way', (tester) async {
      final moved = await drag(
        tester,
        _perspective(constrainToEyeLevel: false),
        const Offset(400, 100),
        const Offset(5, 30),
      );

      final point =
          _perspectiveOf(moved).vanishingPoints.first as VanishingPointAt;
      expect((point.point.x, point.point.y), (400.0, 130.0));
    });

    testWidgets('an ANGLE\'s handle turns a line, and Shift is not its', (
      tester,
    ) async {
      final guides = _symmetry();
      final turn = guideHandles(guides).firstWhere(
        (handle) => handle.kind == GuideHandleKind.axisAngle,
      );
      final at = Offset(turn.position.x, turn.position.y);

      final held = await drag(tester, guides, at, const Offset(30, 5));
      final free = await drag(
        tester,
        guides,
        at,
        const Offset(30, 5),
        shift: false,
      );

      expect(
        _shapeOf(held).axis.angleDegrees,
        _shapeOf(free).axis.angleDegrees,
      );
    });

    testWidgets('a finger resting beside a PEN\'s drag is its Shift', (
      tester,
    ) async {
      CanvasTouchContacts.noteAppWide(
        const PointerDownEvent(pointer: 90, kind: PointerDeviceKind.touch),
      );

      final moved = await drag(
        tester,
        _symmetry(),
        const Offset(100, 100),
        const Offset(40, 15),
        shift: false,
        kind: PointerDeviceKind.stylus,
      );

      expect(originOf(moved), (140.0, 100.0));
    });
  });
}
