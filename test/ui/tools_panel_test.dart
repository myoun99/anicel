import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import '../helpers/app_icon_button_probe.dart';

Widget _panel({
  CanvasTool tool = CanvasTool.brush,
  ValueChanged<ToolPress>? onPress,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ToolsPanel(tool: tool, onPress: onPress ?? (_) {}),
    ),
  );
}

/// The rail over a REAL tool notifier, the way the workspace hosts it: every
/// press applied through [pressTool], so which tile a group re-enters on is
/// the notifier's memory, measured rather than stubbed.
Future<PaintToolStateNotifier> _pumpRail(
  WidgetTester tester,
  CanvasTool start,
) async {
  final tool = PaintToolStateNotifier(
    BrushToolState.defaults.copyWith(tool: start),
  );
  final transform = ValueNotifier(TransformToolOptions.defaults);
  addTearDown(tool.dispose);
  addTearDown(transform.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<BrushToolState>(
          valueListenable: tool,
          builder: (context, state, _) => ToolsPanel(
            tool: state.tool,
            onPress: (press) =>
                pressTool(press, tool: tool, transform: transform),
          ),
        ),
      ),
    ),
  );
  return tool;
}

Finder _button(String key) => find.byKey(ValueKey<String>(key));

void main() {
  group('ToolsPanel cut button', () {
    testWidgets('the rail carries one Cut button', (tester) async {
      await tester.pumpWidget(_panel());
      expect(_button('tool-cut-button'), findsOneWidget);
      expect(find.byTooltip('Cut Tool'), findsOneWidget);
    });

    testWidgets('it lights up for both cut verbs', (tester) async {
      // One button, several tiles: the rail must not go dark just because
      // the user is on the stamp tile rather than the grab.
      for (final verb in [CanvasTool.cut, CanvasTool.cutStamp]) {
        await tester.pumpWidget(_panel(tool: verb));
        expect(
          tester.appIconButton(_button('tool-cut-button')).isSelected,
          isTrue,
          reason: '$verb',
        );
      }
    });

    testWidgets('pressing it from another tool lands on the grab verb', (
      tester,
    ) async {
      // Which OUTLINE the grab then wears is the tool state's memory, not
      // the button's — the button no longer has to be told.
      final tool = await _pumpRail(tester, CanvasTool.brush);
      await tester.tap(_button('tool-cut-button'));
      expect(tool.value.tool, CanvasTool.cut);
    });

    testWidgets('pressing it while already cutting keeps the current tile', (
      tester,
    ) async {
      // Re-pressing must not throw the user off the stamp and back onto the
      // grab — the button re-activates the tool, it does not reset the tile.
      final tool = await _pumpRail(tester, CanvasTool.cutStamp);
      await tester.tap(_button('tool-cut-button'));
      expect(tool.value.tool, CanvasTool.cutStamp);
    });

    testWidgets('the Select button stays dark while the cut tool is armed', (
      tester,
    ) async {
      // The two buttons share a grammar; they must not share a highlight.
      await tester.pumpWidget(_panel(tool: CanvasTool.cut));
      expect(
        tester.appIconButton(_button('tool-select-button')).isSelected,
        isFalse,
      );
    });
  });

  group('ToolsPanel', () {
    testWidgets('exposes brush and eraser buttons with tooltips', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());

      expect(_button('tool-brush-button'), findsOneWidget);
      expect(_button('tool-eraser-button'), findsOneWidget);
      expect(find.byTooltip('Brush Tool'), findsOneWidget);
      expect(find.byTooltip('Eraser Tool'), findsOneWidget);
    });

    testWidgets('exposes eyedropper and fill buttons (P5/P6)', (tester) async {
      final pressed = <ToolPress>[];
      await tester.pumpWidget(_panel(onPress: pressed.add));

      expect(find.byTooltip('Eyedropper Tool'), findsOneWidget);
      expect(find.byTooltip('Fill Tool'), findsOneWidget);

      await tester.tap(_button('tool-eyedropper-button'));
      await tester.tap(_button('tool-fill-button'));

      expect(pressed, [
        const RailToolPress(CanvasTool.eyedropper),
        const RailToolPress(CanvasTool.fill),
      ]);
    });

    testWidgets('tapping the eraser presses the eraser', (tester) async {
      final pressed = <ToolPress>[];
      await tester.pumpWidget(_panel(onPress: pressed.add));

      await tester.tap(_button('tool-eraser-button'));

      expect(pressed, [const RailToolPress(CanvasTool.eraser)]);
    });

    testWidgets('tapping the brush presses the brush', (tester) async {
      final pressed = <ToolPress>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.eraser, onPress: pressed.add),
      );

      await tester.tap(_button('tool-brush-button'));

      expect(pressed, [const RailToolPress(CanvasTool.brush)]);
    });

    testWidgets('marks the active tool as selected', (tester) async {
      await tester.pumpWidget(_panel(tool: CanvasTool.eraser));

      expect(
        tester.appIconButton(_button('tool-eraser-button')).isSelected,
        isTrue,
      );
      expect(
        tester.appIconButton(_button('tool-brush-button')).isSelected,
        isFalse,
      );
    });

    testWidgets('ONE Select button (R17-U): presses the select TOOL, '
        'whatever outline it is wearing', (tester) async {
      final pressed = <ToolPress>[];
      await tester.pumpWidget(_panel(onPress: pressed.add));

      // The old per-variant buttons are gone.
      expect(_button('tool-select-rect-button'), findsNothing);
      expect(_button('tool-lasso-button'), findsNothing);

      await tester.tap(_button('tool-select-button'));
      expect(pressed, [const RailToolPress(CanvasTool.select)]);

      await tester.pumpWidget(_panel(tool: CanvasTool.select));
      expect(
        tester.appIconButton(_button('tool-select-button')).isSelected,
        isTrue,
      );
    });

    testWidgets('ONE Fill button for the bucket and the shapes', (
      tester,
    ) async {
      for (final verb in [CanvasTool.fill, CanvasTool.fillShape]) {
        await tester.pumpWidget(_panel(tool: verb));
        expect(
          tester.appIconButton(_button('tool-fill-button')).isSelected,
          isTrue,
          reason: '$verb',
        );
      }

      // Pressing it from elsewhere lands on the bucket; pressing it while
      // already on a shape tile leaves that tile alone.
      final fromBrush = await _pumpRail(tester, CanvasTool.brush);
      await tester.tap(_button('tool-fill-button'));
      expect(fromBrush.value.tool, CanvasTool.fill);

      final onShape = await _pumpRail(tester, CanvasTool.fillShape);
      await tester.tap(_button('tool-fill-button'));
      expect(onShape.value.tool, CanvasTool.fillShape);
    });

    testWidgets('a multi-tile button re-enters on the tile it was left on', (
      tester,
    ) async {
      // 유저 2026-08-15: "필 툴은 아직도 다른 툴 이동하면 모드 선택한게
      // 초기화됨. 도대체 왜 다른거랑 공통로직안할까?" — the button asks its
      // group's memory instead of carrying a rule per button, so the fill
      // and the cut answer the same way and a third group would too.
      final tool = await _pumpRail(tester, CanvasTool.fillShape);

      await tester.tap(_button('tool-brush-button'));
      expect(tool.value.tool, CanvasTool.brush);
      await tester.tap(_button('tool-fill-button'));
      expect(
        tool.value.tool,
        CanvasTool.fillShape,
        reason: 'the fill was left on its shape tile',
      );

      // A group with nothing remembered still lands on its default tile.
      await tester.tap(_button('tool-cut-button'));
      expect(tool.value.tool, CanvasTool.cut);
    });

    testWidgets('the rail never names a SHAPE', (tester) async {
      // The whole point of the split: the rail speaks verbs, and a new
      // outline must never have to add a rail button. Whatever the tool
      // state is wearing, pressing Select makes exactly one press.
      final pressed = <ToolPress>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.select, onPress: pressed.add),
      );

      await tester.tap(_button('tool-select-button'));

      expect(pressed, [const RailToolPress(CanvasTool.select)]);
    });
  });
}
