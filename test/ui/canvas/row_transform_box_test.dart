import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart'
    show SurfaceDragClaim;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// F-222 — a ROW's box (a layer's fx, the camera's frame, an SE tag) keeps
/// the one law every box keeps: the cross, a corner, the inside, and
/// outside on stage the turn — each grab driving ONE value (R5 #10b, 유저
/// 2026-10-01 「기본적으로 ui는 각 대응하는것으로 변환,삭제 등」).
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);
  // The anchor at the canvas centre, landed on the same point: the
  // identity pose, so artwork, canvas and screen coordinates agree at zoom
  // 1 and the arithmetic below is readable.
  final anchor = CanvasPoint(x: 200, y: 150);
  const pivot = Offset(200, 150);

  /// The picture's box, (100, 50)–(300, 250).
  final corners = [
    CanvasPoint(x: 100, y: 50),
    CanvasPoint(x: 300, y: 50),
    CanvasPoint(x: 300, y: 250),
    CanvasPoint(x: 100, y: 250),
  ];

  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  RowBoxLanding<T> into<T>(List<T> committed, {List<T>? shown}) =>
      (changed: (value) => shown?.add(value), committed: committed.add);

  Widget box({
    TransformPose? pose,
    CanvasSize size = canvasSize,
    CanvasViewport? viewport,
    bool claimsCanvas = true,
    List<CanvasPoint>? moves,
    List<double>? scales,
    List<double>? turns,
    List<CanvasPoint>? anchors,
    VoidCallback? onCancelled,
  }) => RowTransformBox(
    corners: corners,
    pose: pose ?? TransformPose(center: anchor),
    canvasSize: size,
    viewport: viewport ?? CanvasViewport(),
    claimsCanvas: claimsCanvas,
    onCancelled: onCancelled ?? () {},
    move: moves == null ? null : into(moves),
    scale: scales == null ? null : into(scales),
    turn: turns == null ? null : into(turns),
    cross: anchors == null
        ? null
        : (at: anchor, value: anchor, landing: into(anchors)),
  );

  Future<void> pumpBox(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('a corner of the PICTURE scales — dragged away from the anchor '
      'it scales up, and commits scale ALONE', (tester) async {
    final moves = <CanvasPoint>[];
    final scales = <double>[];
    final turns = <double>[];
    await pumpBox(tester, box(moves: moves, scales: scales, turns: turns));

    // The bottom-right corner is (300, 250); the pivot (the anchor) is at
    // (200, 150), so it starts 100√2 away. Dragging it to (400, 350)
    // doubles that distance.
    await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(scales, hasLength(1));
    expect(scales.single, closeTo(2.0, 0.01));
    expect(moves, isEmpty, reason: 'a corner is a statement about scale');
    expect(turns, isEmpty);
  });

  testWidgets('dragging a corner INTO the anchor scales down rather than '
      'flipping', (tester) async {
    final scales = <double>[];
    await pumpBox(tester, box(scales: scales));
    // Halfway in from (300, 250) toward the pivot at (200, 150).
    await tester.dragFrom(const Offset(300, 250), const Offset(-50, -50));
    await tester.pumpAndSettle();
    expect(scales.single, closeTo(0.5, 0.01));
    expect(scales.single, greaterThan(0), reason: 'zoom must stay positive');
  });

  testWidgets('the INSIDE moves the position in whole pixels, and commits '
      'position ALONE', (tester) async {
    final moves = <CanvasPoint>[];
    final scales = <double>[];
    await pumpBox(tester, box(moves: moves, scales: scales));

    await tester.dragFrom(const Offset(150, 100), const Offset(30.4, -20.6));
    await tester.pumpAndSettle();

    expect(moves, [CanvasPoint(x: 230, y: 129)], reason: '09-22 ⑭');
    expect(scales, isEmpty);
  });

  testWidgets('OUTSIDE the box, on stage, turns it about the anchor — and '
      'commits rotation ALONE', (tester) async {
    final moves = <CanvasPoint>[];
    final turns = <double>[];
    await pumpBox(tester, box(moves: moves, turns: turns));

    // Straight above the pivot, past the box's top edge; swung to the
    // pivot's RIGHT at the same radius: a quarter turn clockwise.
    const start = Offset(200, 20);
    final radius = (start - pivot).distance;
    await tester.dragFrom(start, Offset(200 + radius, 150) - start);
    await tester.pumpAndSettle();

    expect(turns, hasLength(1));
    expect(turns.single, closeTo(90, 0.5));
    expect(moves, isEmpty, reason: 'outside is about rotation');
  });

  testWidgets('OFF the stage a press is nobody\'s turn (F-222-box-Q6 '
      '「페이스트보드 안 — 변형 도구와 같게」)', (tester) async {
    final turns = <double>[];
    // A 200×100 canvas: its pasteboard ends at y = 200, so the press below
    // stands off the stage while the box still crosses into it.
    await pumpBox(
      tester,
      box(size: const CanvasSize(width: 200, height: 100), turns: turns),
    );

    await tester.dragFrom(const Offset(350, 280), const Offset(-60, -60));
    await tester.pumpAndSettle();

    expect(turns, isEmpty);
  });

  // F-222 ①: the box turns by the one turn law — canvas angles, folded step
  // by step.
  testWidgets('a turn through the ±180° seam keeps going the way the hand '
      'went', (tester) async {
    final turns = <double>[];
    await pumpBox(tester, box(turns: turns));
    const start = Offset(200, 20);
    final radius = (start - pivot).distance;

    // Three quarters ANTI-clockwise from straight above, through the pivot's
    // left — where the screen angle flips from −180° to 180°.
    final gesture = await tester.startGesture(start);
    for (final degrees in const [-135.0, 180.0, 135.0, 90.0, 45.0, 0.0]) {
      final radians = degrees * math.pi / 180;
      await gesture.moveTo(
        pivot + Offset(math.cos(radians), math.sin(radians)) * radius,
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      turns.single,
      closeTo(-270, 0.5),
      reason: '↩️the whole sweep from the press read +90 here: the same '
          'picture, keyed a quarter turn the other way',
    );
  });

  testWidgets('under a flipped view the turn follows the hand', (
    tester,
  ) async {
    final turns = <double>[];
    // Mirrored about the canvas's x = 0, then panned back: the pivot and
    // the box stand where they stood unflipped.
    await pumpBox(
      tester,
      box(
        turns: turns,
        viewport: CanvasViewport(panX: 400, flipHorizontal: true),
      ),
    );
    const start = Offset(200, 20);
    final radius = (start - pivot).distance;

    // To the pivot's right ON SCREEN — the canvas's left: a quarter turn
    // back on the canvas is what brings the box under the hand.
    await tester.dragFrom(start, Offset(200 + radius, 150) - start);
    await tester.pumpAndSettle();

    expect(turns.single, closeTo(-90, 0.5));
  });

  testWidgets('the CROSS is grabbed first and keys the anchor point ALONE — '
      'it stands inside the box, and the move does not get it', (
    tester,
  ) async {
    final moves = <CanvasPoint>[];
    final anchors = <CanvasPoint>[];
    await pumpBox(tester, box(moves: moves, anchors: anchors));

    await tester.dragFrom(pivot, const Offset(30, -10));
    await tester.pumpAndSettle();

    expect(anchors, [CanvasPoint(x: 230, y: 140)]);
    expect(moves, isEmpty);
  });

  testWidgets('a cross that stands apart from the value it carries — a '
      'moved layer\'s, AE\'s mark — is grabbed where it STANDS and moves the '
      'VALUE by the drag', (tester) async {
    final anchors = <CanvasPoint>[];
    await pumpBox(
      tester,
      RowTransformBox(
        corners: corners,
        pose: TransformPose(center: anchor),
        canvasSize: canvasSize,
        viewport: CanvasViewport(),
        claimsCanvas: true,
        onCancelled: () {},
        cross: (
          at: anchor,
          value: CanvasPoint(x: 260, y: 150),
          landing: into(anchors),
        ),
      ),
    );

    await tester.dragFrom(pivot, const Offset(30, -10));
    await tester.pumpAndSettle();

    expect(anchors, [CanvasPoint(x: 290, y: 140)]);
  });

  testWidgets('a box that does not scale has no corners to grab — an SE '
      'tag\'s: the press on its corner is the move', (tester) async {
    final moves = <CanvasPoint>[];
    await pumpBox(tester, box(moves: moves));

    // Just inside the corner, as a corner grab would be pressed.
    await tester.dragFrom(const Offset(298, 248), const Offset(-20, -20));
    await tester.pumpAndSettle();

    expect(moves, [CanvasPoint(x: 180, y: 130)]);
  });

  testWidgets('a box with no cross gives the same press to the move', (
    tester,
  ) async {
    final moves = <CanvasPoint>[];
    await pumpBox(tester, box(moves: moves));

    await tester.dragFrom(pivot, const Offset(30, -10));
    await tester.pumpAndSettle();

    expect(moves, [CanvasPoint(x: 230, y: 140)]);
  });

  group('whose press it is (F-222-box-Q4 「선택 · 잘라내기만 빼고 모든 '
      '도구」)', () {
    Future<List<Offset>> pumpOverATool(
      WidgetTester tester, {
      required bool claimsCanvas,
      required List<CanvasPoint> moves,
      required List<double> scales,
    }) async {
      final toolPresses = <Offset>[];
      await pumpBox(
        tester,
        Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => toolPresses.add(event.position),
              ),
            ),
            Positioned.fill(
              child: box(
                claimsCanvas: claimsCanvas,
                moves: moves,
                scales: scales,
              ),
            ),
          ],
        ),
      );
      return toolPresses;
    }

    testWidgets('claiming the canvas, every press is the box\'s — the tool '
        'beneath hears none, an empty one included', (tester) async {
      final moves = <CanvasPoint>[];
      final scales = <double>[];
      final toolPresses = await pumpOverATool(
        tester,
        claimsCanvas: true,
        moves: moves,
        scales: scales,
      );

      await tester.dragFrom(const Offset(150, 100), const Offset(20, 0));
      await tester.dragFrom(const Offset(380, 20), const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(moves, hasLength(1));
      expect(toolPresses, isEmpty);
    });

    testWidgets('not claiming it, the box keeps its corners and the cross — '
        'the inside falls to the tool', (tester) async {
      final moves = <CanvasPoint>[];
      final scales = <double>[];
      final toolPresses = await pumpOverATool(
        tester,
        claimsCanvas: false,
        moves: moves,
        scales: scales,
      );

      await tester.dragFrom(const Offset(150, 100), const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(moves, isEmpty, reason: 'a marquee starts there');
      expect(toolPresses, hasLength(1));

      await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(scales, hasLength(1));
      expect(toolPresses, hasLength(1), reason: 'the corner was the box\'s');
    });
  });

  // finger-mode-reaches-canvas-handles (2026-09-29): a handle took its
  // devices when its recognizer was MADE, which no rebuild runs again — so
  // the mode changes here with the box already up, and nothing else.
  testWidgets('switching the one-finger slot to DRAWING with the box up '
      'reaches it at once', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    final scales = <double>[];
    await pumpBox(tester, box(scales: scales));

    await tester.dragFrom(
      const Offset(300, 250),
      const Offset(100, 100),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(scales, isEmpty, reason: 'TS9: a flipping finger drives no tool');

    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await tester.pump();
    await tester.dragFrom(
      const Offset(300, 250),
      const Offset(100, 100),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    expect(scales, hasLength(1), reason: 'the finger draws now');
  });

  testWidgets('PEN-13: a second finger during a SUB-SLOP touch drag aborts '
      'it (a screen gesture); a committed drag survives', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    final moves = <CanvasPoint>[];
    var cancels = 0;
    await pumpBox(
      tester,
      box(moves: moves, onCancelled: () => cancels += 1),
    );

    // Sub-slop: 8px of travel, then a second finger lands — aborted.
    final first = await tester.startGesture(
      const Offset(150, 100),
      kind: PointerDeviceKind.touch,
    );
    await first.moveBy(const Offset(8, 0));
    await tester.pump();
    final second = await tester.startGesture(
      const Offset(250, 200),
      kind: PointerDeviceKind.touch,
      pointer: 9,
    );
    await tester.pump();
    await first.moveBy(const Offset(60, 0));
    await first.up();
    await second.up();
    await tester.pump();
    expect(moves, isEmpty, reason: 'the pair is a screen gesture');
    expect(cancels, 1, reason: 'what it showed snaps back');

    // Committed: 40px of travel first — the late finger changes nothing.
    final third = await tester.startGesture(
      const Offset(150, 100),
      kind: PointerDeviceKind.touch,
      pointer: 11,
    );
    await third.moveBy(const Offset(40, 0));
    await tester.pump();
    final fourth = await tester.startGesture(
      const Offset(250, 200),
      kind: PointerDeviceKind.touch,
      pointer: 12,
    );
    await tester.pump();
    await third.moveBy(const Offset(20, 0));
    await third.up();
    await fourth.up();
    await tester.pump();
    expect(moves, [CanvasPoint(x: 260, y: 150)], reason: 'the drag lives');
  });

  testWidgets('F-194: a PEN takes a corner on the canvas — the surface under '
      'it holds from the first movement, and so does the box', (
    tester,
  ) async {
    final scales = <double>[];
    // The canvas's claim, as `CanvasViewportGestureLayer` wears it around
    // everything on the canvas.
    await pumpBox(tester, SurfaceDragClaim(child: box(scales: scales)));

    // The corner drag, in the small steps a hand makes — each shorter than
    // a pen's pan slop.
    final gesture = await tester.startGesture(
      const Offset(300, 250),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 1; step <= 20; step += 1) {
      await gesture.moveTo(Offset(300 + 5.0 * step, 250 + 5.0 * step));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(scales, hasLength(1), reason: 'the pen drove the box');
    expect(scales.single, closeTo(2, 1e-6));
  });

  testWidgets('a drag that never moves commits nothing', (tester) async {
    final scales = <double>[];
    final turns = <double>[];
    await pumpBox(tester, box(scales: scales, turns: turns));
    await tester.dragFrom(const Offset(100, 50), Offset.zero);
    await tester.pumpAndSettle();
    expect(scales, isEmpty);
    expect(turns, isEmpty);
  });

  group('the commit helpers touch one lane', () {
    test('scale keys scale, keeping its interpolation and the other lanes',
        () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<double>().withKey(
          2,
          1.5,
          interpolation: PropertyKeyInterpolation.hold,
        ),
        rotation: PropertyTrack<double>().withKey(2, 30),
      );
      final next = transformTrackWithScaleDragged(
        track,
        frameIndex: 2,
        zoom: 2.5,
      );
      expect(next.scale.keyAt(2)!.value, 2.5);
      expect(
        next.scale.keyAt(2)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
      expect(next.rotation.keyAt(2)!.value, 30, reason: 'untouched');
      expect(next.position.isEmpty, isTrue);
    });

    test('rotation keys rotation alone', () {
      final next = transformTrackWithRotationDragged(
        TransformTrack.empty(),
        frameIndex: 4,
        rotationDegrees: -45,
      );
      expect(next.rotation.keyAt(4)!.value, -45);
      expect(next.scale.isEmpty, isTrue);
      expect(next.position.isEmpty, isTrue);
    });
  });

  testWidgets('F-195: the grabbed corner stays under the pointer while the '
      'host hands the scaled pose back per move — the scale is measured from '
      'where the grab began', (tester) async {
    final shown = ValueNotifier<double>(1);
    addTearDown(shown.dispose);
    await pumpBox(
      tester,
      ValueListenableBuilder<double>(
        valueListenable: shown,
        builder: (context, zoom, _) => RowTransformBox(
          // The corners ride the pose the host hands back, as the canvas's
          // box draws them through it.
          corners: [
            for (final corner in corners)
              CanvasPoint(
                x: 200 + (corner.x - 200) * zoom,
                y: 150 + (corner.y - 150) * zoom,
              ),
          ],
          pose: TransformPose(center: anchor, zoom: zoom),
          canvasSize: canvasSize,
          viewport: CanvasViewport(),
          claimsCanvas: true,
          onCancelled: () {},
          // The app's loop: the value in flight comes back as the pose.
          scale: (changed: (next) => shown.value = next, committed: (_) {}),
        ),
      ),
    );
    const start = Offset(300, 250);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    // The grab is measured from the press, so the corner rides the hand.
    var pointer = start;
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(20, 20));
      pointer += const Offset(20, 20);
      await tester.pump();
    }

    final corner = Offset(
      200 + (300 - 200) * shown.value,
      150 + (250 - 150) * shown.value,
    );
    expect(
      (corner - pointer).distance,
      lessThan(2),
      reason: 'measured from the pose handed back, each move would compound '
          'and the corner would run away from the hand',
    );
    await gesture.up();
  });

  testWidgets('a grab that comes back to where it began writes nothing and '
      'drops what it showed', (tester) async {
    final scales = <double>[];
    var cancels = 0;
    await pumpBox(
      tester,
      box(scales: scales, onCancelled: () => cancels += 1),
    );

    final gesture = await tester.startGesture(
      const Offset(300, 250),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, -40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(scales, isEmpty, reason: 'the same zoom is no edit');
    expect(cancels, 1, reason: 'what the grab showed is dropped');
  });

  testWidgets('a box taken away mid-grab drops what it showed once the tree '
      'settles', (tester) async {
    var cancels = 0;
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await pumpBox(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, visible, _) => visible
            ? box(scales: [], onCancelled: () => cancels += 1)
            : const SizedBox.shrink(),
      ),
    );
    final gesture = await tester.startGesture(
      const Offset(300, 250),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();

    shown.value = false;
    await tester.pump();
    await tester.pump();

    expect(cancels, 1, reason: 'no release will come to drop it');
    await gesture.up();
  });
}
