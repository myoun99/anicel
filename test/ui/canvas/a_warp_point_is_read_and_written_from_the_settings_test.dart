import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

import '../../helpers/transform_tool_on_canvas.dart';

/// 🗣️F-586 (유저 2026-11-12): 「다시말하지만 화면에서 조작하는건 설정쪽에서도
/// 보여야함. 지금 중간 왼쪽아래 사각형 조작했는데 도구설정패널에서 바뀌는게
/// 없는거 보고 확인함. 포인트별로 좌표 둔다거나. 최대한 알기쉽게」 — and
/// F-586-Q1 (11-14) 「모든 점 목록」.
///
/// The canvas's half: a point the hand moves is said on the channel as it
/// moves, a point the settings write moves on the canvas, and the one in
/// hand is told from the rest on both. The list itself is
/// `the_warp_points_are_listed_in_the_settings_test`.
void main() {
  const mesh = TransformToolOptions(mode: TransformMode.mesh);
  const quad = TransformToolOptions(mode: TransformMode.perspective);
  // The grid's first point inside the square, where it rests.
  const inside = transformToolFirstInside;
  const insideAt = Offset(320, 220);

  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);
  final rest = at(0, 0);

  Matcher isAt(Offset where) => predicate<Offset>(
    (drawn) => (drawn - where).distance < 0.01,
    'stands at $where',
  );

  /// Every point of [shown] but [moved], which is to say: at rest.
  List<CanvasPoint> othersOf(WarpPointsShown shown, int moved) => [
    for (final (index, offset) in shown.offsets.indexed)
      if (index != moved) offset,
  ];

  testWidgets('with no box open the channel names no points — the list '
      'reads each at rest', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );

    expect(commands.transformActive, isFalse, reason: 'the premise');
    expect(commands.liveWarpPoints.value, isNull);
    expect(handlesInHandOnScreen(tester), isEmpty);
  });

  testWidgets('🚨a grid point pressed on the canvas is in hand at the press, '
      'and where the hand carries it is said as it goes', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    final origin = tester.getTopLeft(find.byKey(transformToolLayerKey));

    final hand = await pressOnTransformLayer(tester, insideAt);
    final pressed = commands.liveWarpPoints.value!;
    expect(pressed.offsets, hasLength(16));
    expect(pressed.offsets, everyElement(rest), reason: 'nothing moved yet');
    expect(pressed.inHand, [inside], reason: 'the point under the press');
    expect(handlesInHandOnScreen(tester), [inside], reason: 'lit where drawn');

    await hand.moveTo(origin + const Offset(332, 215));
    final carried = commands.liveWarpPoints.value!;
    expect(carried.offsets[inside].x, closeTo(12, 0.01));
    expect(carried.offsets[inside].y, closeTo(-5, 0.01));
    expect(othersOf(carried, inside), everyElement(rest));

    await hand.up();
    await tester.pump();
    final letGo = commands.liveWarpPoints.value!;
    expect(letGo.offsets[inside].x, closeTo(12, 0.01));
    expect(letGo.inHand, [inside], reason: 'still the point last moved');
    expect(handlesInHandOnScreen(tester), [inside]);
  });

  /// 🗣️F-164 (유저 2026-09-18): 「변형중에 툴도구의 X,Y값같은거 실시간으로
  /// 바뀌게해주고. 무겁지 않을 구조로 패널리빌드하지말고 글자만 바꾸게」. The
  /// channel's own ping is what rebuilds the settings panel whole.
  testWidgets('🚨a point carried across the canvas says its numbers and '
      'nothing else: the channel does not ping once a move', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    final origin = tester.getTopLeft(find.byKey(transformToolLayerKey));
    final hand = await pressOnTransformLayer(tester, insideAt);
    await tester.pump();
    var pings = 0;
    var numbers = 0;
    commands.addListener(() => pings += 1);
    commands.liveWarpPoints.addListener(() => numbers += 1);

    for (final to in const [
      Offset(324, 220),
      Offset(328, 222),
      Offset(333, 226),
    ]) {
      await hand.moveTo(origin + to);
      await tester.pump();
    }

    expect(numbers, 3, reason: 'each move said where the point is');
    expect(pings, 0, reason: '⛔a ping a move rebuilds the whole panel');

    await hand.up();
    await tester.pump();
    expect(pings, greaterThan(0), reason: 'the release is what pings');
  });

  testWidgets('🚨a point written from the settings moves on the canvas, in '
      'hand — and opens the box, as a typed X does', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    final atRest = transformChromeOnScreen(tester)!.handles;
    expect(commands.transformActive, isFalse, reason: 'the premise');

    commands.editWarpPoint(inside, (now) => at(now.x + 12, now.y - 5));
    await tester.pump();

    expect(commands.transformActive, isTrue, reason: 'the write opened it');
    final drawn = transformChromeOnScreen(tester)!.handles;
    expect(drawn[inside], isAt(atRest[inside] + const Offset(12, -5)));
    expect(
      [
        for (final (index, handle) in drawn.indexed)
          if (index != inside) handle,
      ],
      [
        for (final (index, handle) in atRest.indexed)
          if (index != inside) handle,
      ],
      reason: 'every other point where it stood',
    );
    final shown = commands.liveWarpPoints.value!;
    expect(shown.offsets[inside], at(12, -5));
    expect(othersOf(shown, inside), everyElement(rest));
    expect(shown.inHand, [inside]);
    expect(handlesInHandOnScreen(tester), [inside]);

    // A second write goes on from the first: the writer is handed where
    // the point stands now.
    commands.editWarpPoint(inside, (now) => at(now.x + 1, now.y));
    await tester.pump();
    expect(commands.liveWarpPoints.value!.offsets[inside], at(13, -5));
  });

  testWidgets('🚨the 퍼스 quad\'s corners read as two rows of two: the third '
      'the list names is the bottom left', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: quad,
    );
    // The quad as drawn: its four corners first — top left, top right,
    // bottom right, bottom left — then the edges' grips.
    final atRest = transformChromeOnScreen(tester)!.handles;
    expect(atRest[3], isAt(const Offset(300, 260)), reason: 'the premise');

    commands.editWarpPoint(2, (now) => at(now.x + 10, now.y + 4));
    await tester.pump();

    final drawn = transformChromeOnScreen(tester)!.handles;
    expect(drawn[3], isAt(const Offset(310, 264)), reason: 'the bottom left');
    expect(drawn.sublist(0, 3), atRest.sublist(0, 3));
    final shown = commands.liveWarpPoints.value!;
    expect(shown.offsets, [rest, rest, at(10, 4), rest]);
    expect(shown.inHand, [2], reason: 'its place in the list');
    expect(handlesInHandOnScreen(tester), [3], reason: 'and among the handles');
  });

  testWidgets('a 퍼스 corner pressed on the canvas is in hand by its place '
      'in the list, and an edge\'s grip takes both its corners', (
    tester,
  ) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: quad,
    );

    // The bottom right corner: third round the quad, fourth down the list.
    await dragOnTransformLayer(
      tester,
      const Offset(360, 260),
      const Offset(366, 262),
    );
    final corner = commands.liveWarpPoints.value!;
    expect(corner.inHand, [3]);
    expect(corner.offsets[3].x, closeTo(6, 0.01));
    expect(corner.offsets[3].y, closeTo(2, 0.01));
    expect(handlesInHandOnScreen(tester), [2]);

    // The top edge's grip, midway between the two corners it carries.
    await dragOnTransformLayer(
      tester,
      const Offset(330, 200),
      const Offset(330, 190),
    );
    final edge = commands.liveWarpPoints.value!;
    expect(edge.inHand, [0, 1], reason: 'the top left and the top right');
    expect(edge.offsets[0].y, closeTo(-10, 0.01));
    expect(edge.offsets[1].y, closeTo(-10, 0.01));
    expect(handlesInHandOnScreen(tester), [0, 1]);
  });

  testWidgets('초기화 puts every point back where it rests, with none in '
      'hand', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    commands.editWarpPoint(inside, (_) => at(12, -5));
    await tester.pump();
    expect(commands.liveWarpPoints.value!.inHand, [inside], reason: 'premise');

    commands.resetTransform();
    await tester.pump();

    final shown = commands.liveWarpPoints.value!;
    expect(shown.offsets, everyElement(rest));
    expect(shown.inHand, isEmpty);
    expect(handlesInHandOnScreen(tester), isEmpty);
  });

  testWidgets('a point written is one operation to step back from', (
    tester,
  ) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    commands.beginTransform();
    await tester.pump();

    // As the settings' number box announces a scrub, then writes it.
    commands.beginTransformStep();
    commands.editWarpPoint(inside, (_) => at(12, -5));
    commands.editWarpPoint(inside, (now) => at(now.x + 3, now.y));
    await tester.pump();
    expect(commands.liveWarpPoints.value!.offsets[inside], at(15, -5));

    expect(commands.undoTransformStep(), isTrue);
    await tester.pump();

    expect(commands.liveWarpPoints.value!.offsets, everyElement(rest));
  });

  /// 🗣️F-586-Q2 (유저 2026-11-14): 「필요없는게 없다면 안빼도됨. 있으면 빼라는
  /// 얘기였으니 문제없음」 — the settings' 배율 stays in 메쉬 because the grid
  /// answers to it.
  testWidgets('the settings\' scale reaches a 메쉬 box: the grid spreads '
      'with it, a pulled point included', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    commands.editWarpPoint(inside, (_) => at(6, 0));
    await tester.pump();

    commands.editTransformValues((now) => now.copyWith(sx: 2));
    await tester.pump();

    // About the square's centre (330,230): the corners twice as far out,
    // and the point's pull twice as long.
    final drawn = transformChromeOnScreen(tester)!.handles;
    expect(drawn.first, isAt(const Offset(270, 200)));
    expect(drawn[3], isAt(const Offset(390, 200)));
    expect(drawn[inside], isAt(const Offset(322, 220)));
    expect(
      commands.liveWarpPoints.value!.offsets[inside],
      at(6, 0),
      reason: 'the point\'s own number is the box\'s, before the scale',
    );
  });

  /// The layer is handed its mode and its grid inside a build
  /// (`didUpdateWidget`), and the list that reads the points is another
  /// subtree: news said there and then is the framework's 「setState called
  /// during build」.
  testWidgets('🚨another grid under an open box is said once the frame is '
      'built, and leaves no point in hand', (tester) async {
    final (:commands, :options, tool: _) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    commands.editWarpPoint(inside, (_) => at(12, -5));
    await tester.pump();
    final saidIn = <SchedulerPhase>[];
    commands.liveWarpPoints.addListener(
      () => saidIn.add(SchedulerBinding.instance.schedulerPhase),
    );

    options.value = options.value.copyWith(meshColumns: 4);
    await tester.pump();

    expect(saidIn, isNotEmpty, reason: 'the points changed, and it was said');
    expect(saidIn, isNot(contains(SchedulerPhase.persistentCallbacks)));
    final shown = commands.liveWarpPoints.value!;
    expect(shown.offsets, hasLength(20), reason: '4×3 cells: 5×4 points');
    expect(shown.inHand, isEmpty);
    await tester.pump();
    expect(handlesInHandOnScreen(tester), isEmpty);
  });

  testWidgets('🚨a box another tool\'s pick lands leaves no numbers behind '
      'it — the settings read none of a box that is gone', (tester) async {
    final (:commands, options: _, :tool) = await pumpTransformTool(
      tester,
      options: mesh,
    );
    commands.editTransformValues((now) => now.copyWith(tx: 15));
    commands.editWarpPoint(inside, (_) => at(12, -5));
    await tester.pump();
    expect(commands.liveTransformValues.value?.tx, 15, reason: 'the premise');
    expect(commands.liveWarpPoints.value, isNotNull, reason: 'the premise');

    // The brush: the selection layer goes, and its box lands on the way.
    tool.value = tool.value.copyWith(tool: CanvasTool.brush);
    await tester.pump();
    await tester.pump();

    expect(commands.transformActive, isFalse, reason: 'the premise');
    expect(commands.liveTransformValues.value, isNull);
    expect(commands.liveWarpPoints.value, isNull);
  });
}
