import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/sliced_value_listenable_builder.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/text_finders.dart';

/// 🗣️F-586 (유저 2026-11-12): 「다시말하지만 화면에서 조작하는건 설정쪽에서도
/// 보여야함. 지금 중간 왼쪽아래 사각형 조작했는데 도구설정패널에서 바뀌는게
/// 없는거 보고 확인함. 포인트별로 좌표 둔다거나. 최대한 알기쉽게. 매쉬변형에서
/// 안쓰는 항목은 없애고. 그걸 도구설정 기본값으로」.
///
/// 🗣️F-586-Q1 (유저 2026-11-14): 「모든 점 목록」 — 「ae같은 메쉬변형? 대로
/// 하고싶음. 모든 점 목록이긴할것임」; and F-586-Q2: 「필요없는게 없다면
/// 안빼도됨. 있으면 빼라는 얘기였으니 문제없음」.
///
/// The list's half: every point of the armed mode's warp a pair of lines in
/// the Transform tool's settings, live both ways, the one in hand told from
/// the rest and brought into view. The canvas's half is
/// `a_warp_point_is_read_and_written_from_the_settings_test`.
void main() {
  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);
  final rest = at(0, 0);

  /// The warp a stand-in box holds: its points as the list reads them, and
  /// every write it was handed.
  ({List<CanvasPoint> Function() offsets, List<int> written}) bindBox(
    CanvasSelectionCommands commands, {
    required int count,
    VoidCallback? beginTransformStep,
  }) {
    var offsets = List.filled(count, rest);
    final written = <int>[];
    commands.bind(
      Object(),
      hasSelection: () => false,
      canEditTransform: () => true,
      deselect: () {},
      beginTransformStep: beginTransformStep,
      editWarpPoint: (index, change) {
        offsets = [...offsets]..[index] = change(offsets[index]);
        written.add(index);
        // As the layer does after every edit: the point is in hand, and
        // the list reads this.
        commands.publishWarpPoints(
          WarpPointsShown(offsets: offsets, inHand: [index]),
        );
      },
    );
    return (offsets: () => offsets, written: written);
  }

  Future<CanvasSelectionCommands> pumpMoveSettings(
    WidgetTester tester, {
    required TransformToolOptions options,
    Size size = const Size(320, 480),
    CanvasSelectionCommands? handed,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final commands = handed ?? CanvasSelectionCommands();
    if (handed == null) {
      addTearDown(commands.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(tool: CanvasTool.move),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
            selectionCommands: commands,
            transformOptions: options,
            onTransformOptionsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    return commands;
  }

  // Tall enough for every line of a 3×3 grid's settings to be built.
  const whole = Size(320, 1800);
  const mesh = TransformToolOptions(mode: TransformMode.mesh);
  const quad = TransformToolOptions(mode: TransformMode.perspective);

  Finder field(int point, String axis) =>
      find.byKey(ValueKey<String>('move-point-$point-$axis-field'));

  /// The number a point's box shows, beside the X or the Y that names it.
  String shownIn(WidgetTester tester, Finder box) => tester
      .widgetList<Text>(find.descendant(of: box, matching: find.anyText()))
      .map((text) => text.data!)
      .firstWhere((text) => text != 'X' && text != 'Y');

  Color? inkOf(WidgetTester tester, String name) =>
      tester.widget<Text>(find.text(name)).style?.color;

  testWidgets('🚨메쉬 lists every point of its grid — named across · down '
      'from the top left, X over Y — between 메시\'s two rows and 마무리', (
    tester,
  ) async {
    await pumpMoveSettings(tester, options: mesh, size: whole);

    final names = [
      for (var down = 1; down <= 4; down += 1)
        for (var across = 1; across <= 4; across += 1) '$across · $down',
    ];
    var above = tester.getRect(
      find.byKey(const ValueKey<String>('move-mesh-rows-field')),
    );
    for (final (point, name) in names.indexed) {
      final x = tester.getRect(field(point, 'x'));
      final y = tester.getRect(field(point, 'y'));
      expect(x.top, greaterThan(above.bottom), reason: '$name under the last');
      expect(y.top, greaterThan(x.bottom), reason: '$name: Y under X');
      expect(y.left, x.left, reason: '$name: the one column');
      expect(
        tester.getRect(find.text(name)).center.dy,
        closeTo(x.center.dy, 0.5),
        reason: '$name: its name on X\'s line',
      );
      expect(shownIn(tester, field(point, 'x')), '0.00', reason: name);
      expect(shownIn(tester, field(point, 'y')), '0.00', reason: name);
      above = y;
    }
    expect(field(16, 'x'), findsNothing, reason: 'sixteen points and no more');
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('move-reset-button')))
          .top,
      greaterThan(above.bottom),
      reason: 'the actions end the settings',
    );
  });

  testWidgets('퍼스 lists its quad\'s four corners the same way, and 일반 '
      'lists none', (tester) async {
    await pumpMoveSettings(tester, options: quad, size: whole);
    for (final (point, name) in ['1 · 1', '2 · 1', '1 · 2', '2 · 2'].indexed) {
      expect(field(point, 'x'), findsOneWidget, reason: name);
      expect(field(point, 'y'), findsOneWidget, reason: name);
      expect(find.text(name), findsOneWidget);
    }
    expect(field(4, 'x'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      options: TransformToolOptions.defaults,
      size: whole,
    );
    expect(field(0, 'x'), findsNothing, reason: '일반 holds no points');
    expect(find.text('1 · 1'), findsNothing);
  });

  /// 🗣️F-586-Q2: nothing leaves 메쉬 — each of the box's rows is a number
  /// the grid answers to (the canvas's half pins that the scale does).
  testWidgets('every row the box has in 일반 stands in 메쉬 too', (
    tester,
  ) async {
    await pumpMoveSettings(tester, options: mesh, size: whole);

    for (final key in const [
      'move-x-field',
      'move-y-field',
      'move-scale-x-field',
      'move-scale-y-field',
      'move-scale-link-switch',
      'move-angle-field',
      'move-flip-horizontal-button',
      'move-flip-vertical-button',
      'move-anchor-x-field',
      'move-anchor-y-field',
      'move-antialias-switch',
      'move-reset-button',
      'move-apply-button',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('🚨a point\'s two numbers follow the live box — its own, and '
      'no other line\'s', (tester) async {
    final commands = await pumpMoveSettings(
      tester,
      options: mesh,
      size: whole,
    );

    // What the layer publishes while a point is dragged on the canvas.
    commands.publishWarpPoints(
      WarpPointsShown(
        offsets: List.filled(16, rest)..[9] = at(12, -5),
        inHand: const [9],
      ),
    );
    await tester.pump();

    expect(shownIn(tester, field(9, 'x')), '12.00');
    expect(shownIn(tester, field(9, 'y')), '-5.00');
    expect(find.text('12.00'), findsOneWidget, reason: 'and nowhere else');
    expect(find.text('-5.00'), findsOneWidget);

    // With no box open again, every point reads at rest.
    commands.publishWarpPoints(null);
    await tester.pump();
    expect(shownIn(tester, field(9, 'x')), '0.00');
    expect(shownIn(tester, field(9, 'y')), '0.00');
  });

  testWidgets('⛔and each number listens for itself: nothing wrapped round '
      'the panel rebuilds on a point', (tester) async {
    // The structural half of F-164, as the box's own digits pin theirs
    // (`move_settings_drag_values_test`): a point dragged is a pointer-rate
    // event, and 289 points are 578 lines.
    await pumpMoveSettings(tester, options: mesh, size: whole);

    expect(
      find.ancestor(
        of: field(9, 'x'),
        matching: find.byType(SlicedListenableBuilder<CanvasPoint>),
      ),
      findsOneWidget,
      reason: 'the number reads its own point',
    );
    for (final builder in [
      find.byType(SlicedListenableBuilder<CanvasPoint>),
      find.byType(SlicedListenableBuilder<bool>),
    ]) {
      expect(
        find.descendant(
          of: builder,
          matching: find.byKey(ToolSettingsSection.keyFor('move')),
        ),
        findsNothing,
        reason: '⛔a builder round the whole list is the thing avoided',
      );
    }
  });

  testWidgets('🚨a scrub on a point\'s X moves that point\'s X and nothing '
      'else, and a typed Y takes its place', (tester) async {
    final commands = await pumpMoveSettings(
      tester,
      options: mesh,
      size: whole,
    );
    final box = bindBox(commands, count: 16);
    await tester.pump();

    await tester.drag(
      field(5, 'x'),
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(box.written, isNotEmpty, reason: 'the scrub writes live');
    expect(box.written.toSet(), {5}, reason: 'and names the one point');
    final scrubbed = box.offsets()[5];
    expect(scrubbed.x, greaterThan(20));
    expect(scrubbed.y, 0, reason: '⛔its Y is not the scrub\'s');
    expect(
      [
        for (final (point, offset) in box.offsets().indexed)
          if (point != 5) offset,
      ],
      everyElement(rest),
    );

    await typeOnThePad(tester, 'move-point-5-y-field', '-7.5');

    expect(box.offsets()[5], at(scrubbed.x, -7.5));
    expect(shownIn(tester, field(5, 'y')), '-7.50');

    // A typed number takes the place of the one that was there.
    await typeOnThePad(tester, 'move-point-5-x-field', '3.25');
    expect(box.offsets()[5], at(3.25, -7.5));
  });

  testWidgets('a scrub on a point is ONE operation to step back from', (
    tester,
  ) async {
    final commands = await pumpMoveSettings(
      tester,
      options: mesh,
      size: whole,
    );
    var steps = 0;
    final box = bindBox(
      commands,
      count: 16,
      beginTransformStep: () => steps += 1,
    );
    await tester.pump();

    // ⚠️By hand: `tester.drag` delivers its travel as one update.
    final scrub = await tester.startGesture(
      tester.getCenter(field(5, 'x')),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 4; i += 1) {
      await scrub.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await scrub.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(box.written.length, greaterThan(1), reason: '⛔premise: many writes');
    expect(steps, 1);
  });

  testWidgets('🚨the point in hand is told from the rest by its name\'s '
      'colour, and by nothing else', (tester) async {
    final commands = await pumpMoveSettings(
      tester,
      options: mesh,
      size: whole,
    );
    final plain = inkOf(tester, '2 · 3');
    expect(plain, isNot(AppColors.accent), reason: 'the premise');
    final xAtRest = tester.getRect(field(9, 'x'));

    commands.publishWarpPoints(
      WarpPointsShown(offsets: List.filled(16, rest), inHand: const [9]),
    );
    await tester.pump();

    expect(inkOf(tester, '2 · 3'), AppColors.accent);
    expect(inkOf(tester, '1 · 3'), plain, reason: 'the point before it');
    expect(inkOf(tester, '3 · 3'), plain, reason: 'and the one after');
    expect(tester.getRect(field(9, 'x')), xAtRest, reason: 'nothing moved');

    // Another point taken: the first one is as the rest again.
    commands.publishWarpPoints(
      WarpPointsShown(offsets: List.filled(16, rest), inHand: const [0, 1]),
    );
    await tester.pump();
    expect(inkOf(tester, '2 · 3'), plain);
    expect(inkOf(tester, '1 · 1'), AppColors.accent);
    expect(inkOf(tester, '2 · 1'), AppColors.accent, reason: 'an edge\'s two');
  });

  group('🚨the list goes to the point taken in hand', () {
    // The densest grid: 17×17 points, 578 lines in a panel 480 tall.
    const dense = TransformToolOptions(
      mode: TransformMode.mesh,
      meshColumns: TransformToolOptions.maxMeshCells,
      meshRows: TransformToolOptions.maxMeshCells,
    );
    const points = 17 * 17;
    final list = find.byKey(ToolSettingsSection.keyFor('move'));

    Future<void> takeInHand(
      WidgetTester tester,
      CanvasSelectionCommands commands,
      int point,
    ) async {
      commands.publishWarpPoints(
        WarpPointsShown(offsets: List.filled(points, rest), inHand: [point]),
      );
      // The list is put near the point, builds its lines, and is brought
      // to them — a frame a move, and a far point can take two moves.
      for (var frame = 0; frame < 5; frame += 1) {
        await tester.pump();
      }
    }

    void expectInView(WidgetTester tester, int point) {
      final view = tester.getRect(list);
      for (final axis in ['x', 'y']) {
        expect(field(point, axis), findsOneWidget, reason: 'point $point');
        final line = tester.getRect(field(point, axis));
        expect(
          line.top,
          greaterThanOrEqualTo(view.top),
          reason: '$point $axis',
        );
        expect(
          line.bottom,
          lessThanOrEqualTo(view.bottom),
          reason: '$point $axis',
        );
      }
    }

    testWidgets('one far down the list, one back up it, and the last of '
        'all', (tester) async {
      final commands = await pumpMoveSettings(tester, options: dense);
      expect(field(200, 'x'), findsNothing, reason: '⛔premise: not built');

      await takeInHand(tester, commands, 200);
      expectInView(tester, 200);

      await takeInHand(tester, commands, 3);
      expectInView(tester, 3);

      await takeInHand(tester, commands, points - 1);
      expectInView(tester, points - 1);
    });

    testWidgets('a point already in view leaves the list where it is, and '
        'the list is the reader\'s to scroll after', (tester) async {
      final commands = await pumpMoveSettings(tester, options: dense);
      await takeInHand(tester, commands, 200);
      final position = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      ).position;
      final broughtTo = position.pixels;

      // Its neighbour down the list, whose lines are on the screen.
      expect(
        tester.getRect(field(201, 'y')).bottom,
        lessThanOrEqualTo(tester.getRect(list).bottom),
        reason: '⛔premise: 201 is in view',
      );
      await takeInHand(tester, commands, 201);
      expect(position.pixels, broughtTo);

      // The reader scrolls away; the point moving on does not call it back.
      position.jumpTo(0);
      commands.publishWarpPoints(
        WarpPointsShown(
          offsets: List.filled(points, rest)..[201] = at(4, 4),
          inHand: const [201],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(position.pixels, 0);
    });

    testWidgets('lines just off the view come in by no more than it takes '
        '— up from under it, down from over it', (tester) async {
      final commands = await pumpMoveSettings(tester, options: dense);
      final view = tester.getRect(list);
      expect(
        tester.getRect(field(2, 'y')).bottom,
        greaterThan(view.bottom),
        reason: '⛔premise: built, and under the view',
      );

      await takeInHand(tester, commands, 2);
      expect(
        tester.getRect(field(2, 'y')).bottom,
        closeTo(view.bottom - ToolSettingsSection.rowGap, 1),
        reason: 'its last line stands on the view\'s last',
      );

      await takeInHand(tester, commands, 200);
      // The point over the first one on the view: off it whole, and built
      // all the same — the list keeps a little more than it shows.
      final first = [
        for (var point = 180; point <= 200; point += 1) point,
      ].firstWhere((point) => field(point, 'y').evaluate().isNotEmpty);
      final over = first - 1;
      expect(field(over, 'y'), findsNothing, reason: '⛔premise: off the view');
      expect(
        find.byKey(
          ValueKey<String>('move-point-$over-x-field'),
          skipOffstage: false,
        ),
        findsOneWidget,
        reason: '⛔premise: and built',
      );

      await takeInHand(tester, commands, over);
      expect(
        tester.getRect(field(over, 'x')).top,
        closeTo(view.top, 1),
        reason: 'its first line stands on the view\'s first',
      );
    });

    testWidgets('settings handed another project\'s channel read its points '
        'and go to its point in hand — the one before is heard no more, nor '
        'either once the settings are gone', (tester) async {
      final before = await pumpMoveSettings(tester, options: dense);
      final handed = CanvasSelectionCommands();
      addTearDown(handed.dispose);
      await pumpMoveSettings(tester, options: dense, handed: handed);

      await takeInHand(tester, handed, 200);
      expectInView(tester, 200);
      handed.publishWarpPoints(
        WarpPointsShown(
          offsets: List.filled(points, rest)..[200] = at(7, -3),
          inHand: const [200],
        ),
      );
      await tester.pump();
      expect(shownIn(tester, field(200, 'x')), '7.00');

      final position = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      ).position;
      final broughtTo = position.pixels;
      await takeInHand(tester, before, 3);
      expect(position.pixels, broughtTo, reason: 'it calls the list nowhere');
      expect(
        shownIn(tester, field(200, 'x')),
        '7.00',
        reason: 'and none of its numbers are read',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      for (final channel in [before, handed]) {
        expect(
          // ignore: invalid_use_of_protected_member
          channel.liveWarpPoints.hasListeners,
          isFalse,
          reason: 'settings that are gone hear no channel',
        );
      }
    });

    testWidgets('in a panel a line tall, from the top of the list', (
      tester,
    ) async {
      // No point's lines are built here, on the view or kept beside it: the
      // list is put where the points before it reach — short of it by the
      // lines over the first point, more than this view keeps — and then
      // measured from lines it built on the way.
      final commands = await pumpMoveSettings(
        tester,
        options: dense,
        size: const Size(320, 50),
      );
      expect(
        find.byKey(
          const ValueKey<String>('move-point-0-x-field'),
          skipOffstage: false,
        ),
        findsNothing,
        reason: '⛔premise: none built',
      );

      await takeInHand(tester, commands, 200);

      // The view holds less than a point's two lines: its first is brought
      // to the view's first.
      expect(
        tester.getRect(field(200, 'x')).top,
        closeTo(tester.getRect(list).top, 1),
      );
    });
  });
}
