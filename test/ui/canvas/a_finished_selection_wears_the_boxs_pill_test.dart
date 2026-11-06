import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart'
    show InputInspectorHost;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// 🗣️I-165 (유저 2026-11-05): 「선택된 상태. 도구에서 선택도구사용해서 선택이
/// 완료된 상태에서 변형도구처럼 아래에 알약으로 버튼배치. 내용은
/// 선택해제버튼, 캔버스 안/밖 선택반전, 안티앨리어스 적용/미적용 버튼.
/// 그리고 변형도구도 이제부터 알약에 추가로 안티앨리어스,좌우반전,상하반전
/// 버튼 배치.」
void main() {
  const selectionPill = ValueKey<String>('selection-pill');
  const boxPill = ValueKey<String>('selection-confirm-pill');
  const deselect = 'selection-pill-deselect';
  const invertInCanvas = 'selection-pill-invert-in-canvas';
  const invertPastIt = 'selection-pill-invert';
  const selectionAntiAlias = 'selection-pill-anti-alias';
  const boxAntiAlias = 'selection-move-anti-alias';
  const flipAcross = 'selection-move-flip-horizontal';
  const flipUpDown = 'selection-move-flip-vertical';
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  // Far enough in that the pill under it is on the 800-wide view whole.
  final square = CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      CanvasPoint(x: 300, y: 200),
      CanvasPoint(x: 360, y: 200),
      CanvasPoint(x: 360, y: 260),
      CanvasPoint(x: 300, y: 260),
    ]),
  );

  Future<
    ({
      CanvasSelectionCommands commands,
      ValueNotifier<SelectionMaskOptions> mask,
      ValueNotifier<TransformToolOptions> transform,
      Future<void> Function(CanvasTool tool) setTool,
    })
  >
  pumpPanel(WidgetTester tester, {CanvasTool tool = CanvasTool.select}) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    coordinator.commitSourceStroke(
      sourceDabs: [dab(310, 210), dab(330, 230), dab(350, 250)],
    );
    final history = HistoryManager();
    final sink = BrushEditCacheInvalidationSink();
    final commands = CanvasSelectionCommands();
    final mask = ValueNotifier(SelectionMaskOptions.none);
    final transform = ValueNotifier(TransformToolOptions.defaults);
    final brush = ValueNotifier(BrushToolState.defaults.copyWith(tool: tool));
    addTearDown(mask.dispose);
    addTearDown(transform.dispose);
    addTearDown(brush.dispose);
    final viewport = seedFromRender(tester, CanvasViewport());
    Future<void> pumpWith(CanvasTool tool) async {
      brush.value = brush.value.copyWith(tool: tool);
      await tester.pumpWidget(
        MaterialApp(
          home: InputInspectorHost(
            child: Scaffold(
              body: BrushCanvasPanel(
                coordinator: coordinator,
                canvasSize: BrushCanvasFixture.canvasSize,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: sink,
                historyManager: history,
                brushToolState: brush,
                selectionCommands: commands,
                viewport: viewport,
                selectionMaskOptions: mask,
                transformOptions: transform,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith(tool);
    return (
      commands: commands,
      mask: mask,
      transform: transform,
      setTool: pumpWith,
    );
  }

  List<String> actionsOf(WidgetTester tester, String key) => tester
      .widget<AppIconButton>(
        find.ancestor(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(AppIconButton),
        ),
      )
      .shortcuts;

  bool lit(WidgetTester tester, String key) =>
      tester.appIconButton(find.byKey(ValueKey<String>(key))).isSelected;

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
  }

  /// [square] put on the channel as the app puts a selection there — it
  /// tells the layer in a microtask, so the layer builds a frame later.
  Future<void> select(
    WidgetTester tester,
    CanvasSelectionCommands commands,
  ) async {
    commands.setRegion(square);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a finished selection wears the pill under it — 선택 해제, '
      '캔버스 안 · 밖 반전, 안티앨리어스 — and only the Select tool\'s', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    expect(find.byKey(selectionPill), findsNothing, reason: 'none selected');

    await select(tester, env.commands);

    for (final key in const [
      deselect,
      invertInCanvas,
      invertPastIt,
      selectionAntiAlias,
    ]) {
      expect(
        find.descendant(
          of: find.byKey(selectionPill),
          matching: find.byKey(ValueKey<String>(key)),
        ),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.byKey(boxPill), findsNothing);

    await env.setTool(CanvasTool.move);
    expect(
      find.byKey(selectionPill),
      findsNothing,
      reason: 'the Transform tool wears its box\'s pill instead',
    );
  });

  testWidgets('a picture held whole for a box is no selection, and wears no '
      'pill', (tester) async {
    final env = await pumpPanel(tester);
    env.commands.setRegion(square, implicit: true);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(selectionPill), findsNothing);
  });

  testWidgets('a box opened under the Select tool wears its own pill alone', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    env.commands.beginTransform();
    await tester.pump();
    expect(find.byKey(boxPill), findsOneWidget, reason: 'the premise');
    expect(find.byKey(selectionPill), findsNothing);
  });

  testWidgets('an outline clicked in a vertex at a time is not finished '
      'either', (tester) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    env.commands.addPolygonPoint(CanvasPoint(x: 500, y: 400));
    await tester.pump();
    await tester.pump();
    expect(env.commands.polygonPoints, isNotEmpty, reason: 'the premise');
    expect(find.byKey(selectionPill), findsNothing);
  });

  testWidgets('it stands where the box\'s pill stands over the same '
      'selection — under its middle', (tester) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    final ours = tester.getRect(find.byKey(selectionPill));

    await env.setTool(CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();
    final box = tester.getRect(find.byKey(boxPill));

    expect(ours.center.dx, closeTo(box.center.dx, 0.01));
    expect(ours.top, closeTo(box.top, 0.01));
  });

  testWidgets('while an outline is being traced the selection is not '
      'finished, and the pill waits for the release', (tester) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    final origin = tester.getTopLeft(find.byKey(layerKey));

    final drag = await tester.startGesture(origin + const Offset(120, 120));
    await tester.pump();
    await drag.moveBy(const Offset(30, 30));
    await tester.pump();
    expect(find.byKey(selectionPill), findsNothing);

    await drag.up();
    await tester.pump();
    expect(find.byKey(selectionPill), findsOneWidget);
  });

  testWidgets('its buttons press the doors the app already has — the rail\'s '
      '선택 해제 and the Select tool\'s two inverts, under their keys', (
    tester,
  ) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    expect(actionsOf(tester, deselect), [EditorActionIds.selectionDeselect]);
    expect(actionsOf(tester, invertInCanvas), [
      EditorActionIds.selectionInvertInCanvas,
    ]);
    expect(actionsOf(tester, invertPastIt), [EditorActionIds.selectionInvert]);
    final wall = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer))
        .pasteboard;

    await press(tester, invertInCanvas);
    final inside = env.commands.region!.selectedBounds;
    expect((inside.left, inside.top, inside.right, inside.bottom), (
      0,
      0,
      wall.canvas.width,
      wall.canvas.height,
    ), reason: 'out to the canvas');

    await select(tester, env.commands);
    await press(tester, invertPastIt);
    final past = env.commands.region!.selectedBounds;
    expect((past.left, past.top, past.right, past.bottom), (
      wall.left,
      wall.top,
      wall.rightExclusive,
      wall.bottomExclusive,
    ), reason: 'out to the pasteboard\'s wall');

    // Its pill stands under the wall now, off the view (F-332).
    await select(tester, env.commands);
    await press(tester, deselect);
    expect(env.commands.region, isNull);
    expect(find.byKey(selectionPill), findsNothing);
  });

  testWidgets('its 안티앨리어스 is the Select tool settings\' switch, lit '
      'while on', (tester) async {
    final env = await pumpPanel(tester);
    await select(tester, env.commands);
    expect(lit(tester, selectionAntiAlias), isFalse);

    await press(tester, selectionAntiAlias);
    expect(env.mask.value.antiAlias, isTrue);
    expect(lit(tester, selectionAntiAlias), isTrue);

    env.mask.value = env.mask.value.copyWith(antiAlias: false);
    await tester.pump();
    expect(lit(tester, selectionAntiAlias), isFalse, reason: 'the switch');
  });

  testWidgets('the box\'s pill wears 안티앨리어스 · 좌우 · 상하 반전 before 확정 · '
      '취소, pressed as the transform settings press them', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.move);
    await select(tester, env.commands);
    env.commands.beginTransform();
    await tester.pump();

    const order = [
      boxAntiAlias,
      flipAcross,
      flipUpDown,
      'selection-move-confirm',
      'selection-move-cancel',
    ];
    final lefts = [
      for (final key in order)
        tester
            .getRect(
              find.descendant(
                of: find.byKey(boxPill),
                matching: find.byKey(ValueKey<String>(key)),
              ),
            )
            .left,
    ];
    expect(lefts, [...lefts]..sort(), reason: 'in that order');
    expect(actionsOf(tester, flipAcross), [
      EditorActionIds.transformFlipHorizontal,
    ]);
    expect(actionsOf(tester, flipUpDown), [
      EditorActionIds.transformFlipVertical,
    ]);

    await press(tester, flipAcross);
    expect(env.commands.transformValues?.sx, -1);
    await press(tester, flipUpDown);
    expect(env.commands.transformValues?.sy, -1);

    expect(lit(tester, boxAntiAlias), isTrue, reason: 'smoothing by default');
    await press(tester, boxAntiAlias);
    expect(env.transform.value.antiAlias, isFalse);
    expect(lit(tester, boxAntiAlias), isFalse);
  });
}
