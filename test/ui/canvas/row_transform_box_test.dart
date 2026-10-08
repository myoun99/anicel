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

  /// BOTH of a row's scales at [scale] — what a corner makes of a row whose
  /// two are alike.
  Matcher bothAt(double scale, double tolerance) => isA<CanvasPoint>()
      .having((point) => point.x, 'across', closeTo(scale, tolerance))
      .having((point) => point.y, 'down', closeTo(scale, tolerance));

  /// [scales] makes it a box of TWO scales (a layer's), [zooms] of ONE (a
  /// camera's); [at] stands it on other corners than the picture's.
  Widget box({
    TransformPose? pose,
    List<CanvasPoint>? at,
    CanvasSize size = canvasSize,
    CanvasViewport? viewport,
    bool claimsCanvas = true,
    List<CanvasPoint>? moves,
    List<CanvasPoint>? scales,
    List<double>? zooms,
    List<double>? turns,
    CanvasPoint Function(CanvasPoint onCanvas)? turnSpace,
    List<CanvasPoint>? anchors,
    VoidCallback? onCancelled,
  }) => RowTransformBox(
    corners: at ?? corners,
    pose: pose ?? TransformPose(center: anchor),
    canvasSize: size,
    viewport: viewport ?? CanvasViewport(),
    claimsCanvas: claimsCanvas,
    onCancelled: onCancelled ?? () {},
    move: moves == null ? null : into(moves),
    scale: scales != null
        ? RowBoxTwoScales(into(scales))
        : zooms != null
        ? RowBoxOneScale(into(zooms))
        : null,
    turn: turns == null ? null : into(turns),
    turnSpace: turnSpace,
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
    final scales = <CanvasPoint>[];
    final turns = <double>[];
    await pumpBox(tester, box(moves: moves, scales: scales, turns: turns));

    // The bottom-right corner is (300, 250); the pivot (the anchor) is at
    // (200, 150), so it starts 100√2 away. Dragging it to (400, 350)
    // doubles that distance.
    await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(scales, hasLength(1));
    expect(scales.single, bothAt(2.0, 0.01));
    expect(moves, isEmpty, reason: 'a corner is a statement about scale');
    expect(turns, isEmpty);
  });

  testWidgets('dragging a corner INTO the anchor scales down rather than '
      'flipping', (tester) async {
    final scales = <CanvasPoint>[];
    await pumpBox(tester, box(scales: scales));
    // Halfway in from (300, 250) toward the pivot at (200, 150).
    await tester.dragFrom(const Offset(300, 250), const Offset(-50, -50));
    await tester.pumpAndSettle();
    expect(scales.single, bothAt(0.5, 0.01));
  });

  // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
  // 반전)」. A row's Scale lane keys two scales that may differ, and the box
  // has corners alone.
  testWidgets("a corner scales BOTH of the row's scales by one factor — a "
      'flip and a stretch the lane keyed are kept', (tester) async {
    final scales = <CanvasPoint>[];
    await pumpBox(
      tester,
      box(
        pose: TransformPose(center: anchor, scaleX: -1, scaleY: 0.5),
        scales: scales,
      ),
    );
    // (300, 250) → (400, 350): twice as far from the pivot.
    await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(scales, hasLength(1));
    expect(scales.single.x, closeTo(-2, 0.02), reason: 'still flipped');
    expect(scales.single.y, closeTo(1, 0.01), reason: 'still half as tall');
  });

  testWidgets('a corner dragged INTO the anchor keeps the row the way round '
      'it is: the factor is a distance, never a minus', (tester) async {
    final scales = <CanvasPoint>[];
    await pumpBox(
      tester,
      box(pose: TransformPose(center: anchor, scaleX: -1), scales: scales),
    );
    await tester.dragFrom(const Offset(300, 250), const Offset(-50, -50));
    await tester.pumpAndSettle();

    expect(scales.single.x, closeTo(-0.5, 0.01));
    expect(scales.single.y, closeTo(0.5, 0.01));
  });

  testWidgets('a row shown as NOTHING on one axis stays so under a corner: '
      'zero has no size to scale', (tester) async {
    final scales = <CanvasPoint>[];
    await pumpBox(
      tester,
      box(pose: TransformPose(center: anchor, scaleX: 0), scales: scales),
    );
    await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(scales.single.x, 0);
    expect(scales.single.y, closeTo(2, 0.02));
  });

  // 🗣️F-256-Q1 (유저 2026-10-06) chose 「가른다 — AE 처럼 Scale X · Y(마이너스
  // = 반전)」, the option whose terms were 「캔버스의 트랜스폼 상자에도 변 중앙
  // 손잡이가 생긴다. 카메라는 줌 하나 그대로」.
  group("an EDGE's middle drives its one axis", () {
    Matcher scaled(double across, double down) => isA<CanvasPoint>()
        .having((point) => point.x, 'across', closeTo(across, 1e-6))
        .having((point) => point.y, 'down', closeTo(down, 1e-6));

    /// What a drag of [by] from [from] lands on a box of two scales.
    Future<List<CanvasPoint>> dragged(
      WidgetTester tester,
      Offset from,
      Offset by, {
      TransformPose? pose,
      List<CanvasPoint>? at,
    }) async {
      final scales = <CanvasPoint>[];
      await pumpBox(tester, box(pose: pose, at: at, scales: scales));
      await tester.dragFrom(from, by);
      await tester.pumpAndSettle();
      return scales;
    }

    // The picture's box is (100, 50)–(300, 250) about the pivot (200, 150):
    // each edge stands 100 from the pivot along its own axis.
    testWidgets('the RIGHT edge, carried out, stretches the row across and '
        'leaves down alone', (tester) async {
      expect(
        await dragged(tester, const Offset(300, 150), const Offset(100, 0)),
        [scaled(2, 1)],
      );
    });

    testWidgets('the BOTTOM edge drives the scale down', (tester) async {
      expect(
        await dragged(tester, const Offset(200, 250), const Offset(0, -50)),
        [scaled(1, 0.5)],
      );
    });

    testWidgets('the LEFT and the TOP edges read their travel from their own '
        'side: away from the pivot is larger', (tester) async {
      expect(
        await dragged(tester, const Offset(100, 150), const Offset(-50, 0)),
        [scaled(1.5, 1)],
      );
      expect(
        await dragged(tester, const Offset(200, 50), const Offset(0, -50)),
        [scaled(1, 1.5)],
      );
    });

    testWidgets("travel ALONG the edge is not a scale: the hand's drift up "
        'or down a side edge changes nothing', (tester) async {
      expect(
        await dragged(tester, const Offset(300, 150), const Offset(100, 37)),
        [scaled(2, 1)],
      );
    });

    testWidgets('carried ONTO the pivot the row is shown as nothing, and past '
        'it the axis flips', (tester) async {
      expect(
        await dragged(tester, const Offset(100, 150), const Offset(100, 0)),
        [scaled(0, 1)],
      );
      expect(
        await dragged(tester, const Offset(100, 150), const Offset(150, 0)),
        [scaled(-0.5, 1)],
      );
    });

    testWidgets("the edge multiplies the row's own scale — a flip and a "
        'stretch it already had are kept', (tester) async {
      expect(
        await dragged(
          tester,
          const Offset(300, 150),
          const Offset(100, 0),
          pose: TransformPose(center: anchor, scaleX: -1.5, scaleY: 0.25),
        ),
        [scaled(-3, 0.25)],
      );
    });

    testWidgets('an edge moves its ONE axis wherever the anchor stands — off '
        "the box's centre, up and to the left", (tester) async {
      // The pivot at (150, 100): the right edge stands 150 from it across,
      // and its middle 50 below it — which is not its axis.
      expect(
        await dragged(
          tester,
          const Offset(300, 150),
          const Offset(75, 20),
          pose: TransformPose(center: CanvasPoint(x: 150, y: 100)),
        ),
        [scaled(1.5, 1)],
      );
    });

    testWidgets('in a box the folders above have SHEARED, an edge reads its '
        "travel in the box's own two sides", (tester) async {
      // Across (200, 100), down (-50, 200), about the centre (175, 200):
      // the right edge's middle is (275, 250), half an across from it.
      final sheared = [
        CanvasPoint(x: 100, y: 50),
        CanvasPoint(x: 300, y: 150),
        CanvasPoint(x: 250, y: 350),
        CanvasPoint(x: 50, y: 250),
      ];
      final pose = TransformPose(center: CanvasPoint(x: 175, y: 200));

      // A quarter of the across side further out.
      expect(
        await dragged(
          tester,
          const Offset(275, 250),
          const Offset(50, 25),
          pose: pose,
          at: sheared,
        ),
        [scaled(1.5, 1)],
      );
      // Along the down side — the edge's own run — nothing is scaled.
      expect(
        await dragged(
          tester,
          const Offset(275, 250),
          const Offset(-5, 20),
          pose: pose,
          at: sheared,
        ),
        isEmpty,
      );
    });

    testWidgets('an edge that stands ON the pivot has no distance to take a '
        'ratio of: nothing lands', (tester) async {
      // The pivot on the right edge's own line.
      expect(
        await dragged(
          tester,
          const Offset(300, 100),
          const Offset(60, 0),
          pose: TransformPose(center: CanvasPoint(x: 300, y: 200)),
          at: [
            CanvasPoint(x: 100, y: 50),
            CanvasPoint(x: 300, y: 50),
            CanvasPoint(x: 300, y: 150),
            CanvasPoint(x: 100, y: 150),
          ],
        ),
        isEmpty,
      );
    });

    testWidgets('a box shown as NOTHING has no side to read an edge against: '
        'nothing lands, and what the grab showed is dropped', (tester) async {
      final scales = <CanvasPoint>[];
      var cancels = 0;
      await pumpBox(
        tester,
        box(
          pose: TransformPose(center: anchor, scaleX: 0),
          // No width: the left and right edges are one line.
          at: [
            CanvasPoint(x: 200, y: 50),
            CanvasPoint(x: 200, y: 50),
            CanvasPoint(x: 200, y: 250),
            CanvasPoint(x: 200, y: 250),
          ],
          scales: scales,
          onCancelled: () => cancels += 1,
        ),
      );
      // The right edge's middle — the left's stands on the same spot.
      await tester.dragFrom(const Offset(200, 150), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(scales, isEmpty);
      expect(cancels, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('F-195: the grabbed edge stays under the pointer while the '
        'host hands the stretched box back per move — its travel is read '
        'against the box as it was grabbed', (tester) async {
      final shown = ValueNotifier<double>(1);
      addTearDown(shown.dispose);
      await pumpBox(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: shown,
          builder: (context, across, _) => RowTransformBox(
            // The corners ride the scale the host hands back.
            corners: [
              for (final corner in corners)
                CanvasPoint(x: 200 + (corner.x - 200) * across, y: corner.y),
            ],
            pose: TransformPose(center: anchor, scaleX: across),
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
            claimsCanvas: true,
            onCancelled: () {},
            scale: RowBoxTwoScales((
              changed: (next) => shown.value = next.x,
              committed: (_) {},
            )),
          ),
        ),
      );
      const start = Offset(300, 150);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      var pointer = start;
      for (var step = 0; step < 4; step += 1) {
        await gesture.moveBy(const Offset(25, 0));
        pointer += const Offset(25, 0);
        await tester.pump();
      }

      expect(
        200 + 100 * shown.value,
        closeTo(pointer.dx, 1e-6),
        reason: 'read against the box handed back, each move would compound '
            'and the edge would run away from the hand',
      );
      await gesture.up();
    });

    testWidgets('the middles are DRAWN where they are grabbed: a box of two '
        'scales wears eight squares, a box of one its four corners', (
      tester,
    ) async {
      Finder chrome() => find.descendant(
        of: find.byKey(const ValueKey<String>('row-transform-box')),
        matching: find.byType(CustomPaint),
      );
      PaintPattern drawsASquareAt(Offset at) => paints
        ..something(
          (method, arguments) =>
              method == #drawRect && (arguments[0] as Rect).center == at,
        );
      const middles = [
        Offset(200, 50),
        Offset(300, 150),
        Offset(200, 250),
        Offset(100, 150),
      ];

      await pumpBox(tester, box(scales: []));
      for (final middle in middles) {
        expect(chrome(), drawsASquareAt(middle), reason: '$middle');
      }

      await pumpBox(tester, box(zooms: []));
      expect(
        chrome(),
        drawsASquareAt(const Offset(300, 250)),
        reason: 'LIVENESS — its corners are drawn',
      );
      for (final middle in middles) {
        expect(chrome(), isNot(drawsASquareAt(middle)), reason: '$middle');
      }
    });
  });

  group('a box of ONE scale — the camera\'s frame', () {
    testWidgets('a corner lands the one number', (tester) async {
      final zooms = <double>[];
      await pumpBox(
        tester,
        box(
          pose: TransformPose.uniform(center: anchor, zoom: 0.5),
          zooms: zooms,
        ),
      );
      await tester.dragFrom(const Offset(300, 250), const Offset(100, 100));
      await tester.pumpAndSettle();

      expect(zooms, [closeTo(1, 0.01)]);
    });

    testWidgets('a grab that comes back to where it began writes nothing', (
      tester,
    ) async {
      final zooms = <double>[];
      var cancels = 0;
      await pumpBox(
        tester,
        box(
          pose: TransformPose.uniform(center: anchor, zoom: 0.5),
          zooms: zooms,
          onCancelled: () => cancels += 1,
        ),
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

      expect(zooms, isEmpty);
      expect(cancels, 1);
    });

    testWidgets('it wears its corners ALONE: where an edge\'s middle would '
        'stand, the press is the inside\'s', (tester) async {
      final zooms = <double>[];
      final moves = <CanvasPoint>[];
      await pumpBox(tester, box(zooms: zooms, moves: moves));
      // Just inside the right edge, on the square its middle would wear.
      await tester.dragFrom(const Offset(298, 150), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(zooms, isEmpty);
      expect(moves, [CanvasPoint(x: 240, y: 150)]);
    });

    testWidgets('…and on a box of two scales that same press is the edge\'s', (
      tester,
    ) async {
      final scales = <CanvasPoint>[];
      final moves = <CanvasPoint>[];
      await pumpBox(tester, box(scales: scales, moves: moves));
      await tester.dragFrom(const Offset(298, 150), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
      expect(scales, hasLength(1));
      expect(scales.single.x, closeTo(1.4, 1e-6));
      expect(scales.single.y, 1);
    });
  });

  group("a TURN is measured where the row's rotation lives", () {
    // Straight above the pivot, past the box's top edge.
    const above = Offset(200, 20);

    testWidgets('in a folder stretched across, the hand\'s angle on the '
        'canvas is not the row\'s: the row turns by the angle its parent '
        'sees', (tester) async {
      final turns = <double>[];
      await pumpBox(
        tester,
        box(
          turns: turns,
          // The folder shows everything twice as wide.
          turnSpace: (onCanvas) =>
              CanvasPoint(x: onCanvas.x / 2, y: onCanvas.y),
        ),
      );
      // From the upper right — as far across as up, 45° off the vertical on
      // the canvas — straight down to the pivot's right. In the folder the
      // press stood half as far across: atan(130 / 65) off the horizontal.
      await tester.dragFrom(const Offset(330, 20), const Offset(0, 130));
      await tester.pumpAndSettle();

      expect(
        turns.single,
        closeTo(math.atan2(130, 65) * 180 / math.pi, 0.01),
        reason: '↩️measured on the canvas it read 45',
      );
    });

    testWidgets('in a FLIPPED folder the row turns the other way round — '
        'which is what brings the picture under the hand', (tester) async {
      final turns = <double>[];
      await pumpBox(
        tester,
        box(
          turns: turns,
          turnSpace: (onCanvas) => CanvasPoint(x: -onCanvas.x, y: onCanvas.y),
        ),
      );
      final radius = (above - pivot).distance;
      // A quarter turn clockwise on the canvas.
      await tester.dragFrom(above, Offset(200 + radius, 150) - above);
      await tester.pumpAndSettle();

      expect(turns.single, closeTo(-90, 0.5));
    });
  });

  testWidgets('the INSIDE moves the position in whole pixels, and commits '
      'position ALONE', (tester) async {
    final moves = <CanvasPoint>[];
    final scales = <CanvasPoint>[];
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
      required List<CanvasPoint> scales,
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
      final scales = <CanvasPoint>[];
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
      final scales = <CanvasPoint>[];
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
    final scales = <CanvasPoint>[];
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
    final scales = <CanvasPoint>[];
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
    expect(scales.single, bothAt(2, 1e-6));
  });

  testWidgets('a drag that never moves commits nothing', (tester) async {
    final scales = <CanvasPoint>[];
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
        scale: PropertyTrack<CanvasPoint>().withKey(
          2,
          uniformScale(1.5),
          interpolation: PropertyKeyInterpolation.hold,
        ),
        rotation: PropertyTrack<double>().withKey(2, 30),
      );
      final next = transformTrackWithScaleDragged(
        track,
        frameIndex: 2,
        scale: CanvasPoint(x: 2.5, y: -0.5),
      );
      expect(next.scale.keyAt(2)!.value, CanvasPoint(x: 2.5, y: -0.5));
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
          pose: TransformPose.uniform(center: anchor, zoom: zoom),
          canvasSize: canvasSize,
          viewport: CanvasViewport(),
          claimsCanvas: true,
          onCancelled: () {},
          // The app's loop: the value in flight comes back as the pose.
          scale: RowBoxTwoScales((
            changed: (next) => shown.value = next.x,
            committed: (_) {},
          )),
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
    final scales = <CanvasPoint>[];
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
