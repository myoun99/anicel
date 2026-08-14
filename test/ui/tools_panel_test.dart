import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';

Widget _panel({
  CanvasTool tool = CanvasTool.brush,
  ValueChanged<CanvasTool>? onToolChanged,
  CanvasTool Function(CanvasTool group)? groupEntry,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ToolsPanel(
        tool: tool,
        onToolChanged: onToolChanged ?? (_) {},
        groupEntry: groupEntry,
      ),
    ),
  );
}

void main() {
  group('ToolsPanel cut button', () {
    testWidgets('the rail carries one Cut button', (tester) async {
      await tester.pumpWidget(_panel());
      expect(
        find.byKey(const ValueKey<String>('tool-cut-button')),
        findsOneWidget,
      );
      expect(find.byTooltip('Cut Tool'), findsOneWidget);
    });

    testWidgets('it lights up for both cut verbs', (tester) async {
      // One button, several tiles: the rail must not go dark just because
      // the user is on the stamp tile rather than the grab.
      for (final verb in [CanvasTool.cut, CanvasTool.cutStamp]) {
        await tester.pumpWidget(_panel(tool: verb));
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey<String>('tool-cut-button')),
              )
              .isSelected,
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
      final picked = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.brush, onToolChanged: picked.add),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      expect(picked, [CanvasTool.cut]);
    });

    testWidgets('pressing it while already cutting keeps the current tile', (
      tester,
    ) async {
      // Re-pressing must not throw the user off the stamp and back onto the
      // grab — the button re-activates the tool, it does not reset the tile.
      final picked = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.cutStamp, onToolChanged: picked.add),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      expect(picked, [CanvasTool.cutStamp]);
    });

    testWidgets('the Select button stays dark while the cut tool is armed', (
      tester,
    ) async {
      // The two buttons share a grammar; they must not share a highlight.
      await tester.pumpWidget(_panel(tool: CanvasTool.cut));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('tool-select-button')),
            )
            .isSelected,
        isFalse,
      );
    });
  });

  group('ToolsPanel', () {
    testWidgets('exposes brush and eraser buttons with tooltips', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());

      expect(
        find.byKey(const ValueKey<String>('tool-brush-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('tool-eraser-button')),
        findsOneWidget,
      );
      expect(find.byTooltip('Brush Tool'), findsOneWidget);
      expect(find.byTooltip('Eraser Tool'), findsOneWidget);
    });

    testWidgets('exposes eyedropper and fill buttons (P5/P6)', (tester) async {
      final selected = <CanvasTool>[];
      await tester.pumpWidget(_panel(onToolChanged: selected.add));

      expect(find.byTooltip('Eyedropper Tool'), findsOneWidget);
      expect(find.byTooltip('Fill Tool'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-eyedropper-button')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));

      expect(selected, [CanvasTool.eyedropper, CanvasTool.fill]);
    });

    testWidgets('tapping the eraser reports the tool change', (tester) async {
      CanvasTool? selected;
      await tester.pumpWidget(_panel(onToolChanged: (tool) => selected = tool));

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-eraser-button')),
      );

      expect(selected, CanvasTool.eraser);
    });

    testWidgets('tapping the brush reports the tool change', (tester) async {
      CanvasTool? selected;
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.eraser,
          onToolChanged: (tool) => selected = tool,
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));

      expect(selected, CanvasTool.brush);
    });

    testWidgets('marks the active tool as selected', (tester) async {
      await tester.pumpWidget(_panel(tool: CanvasTool.eraser));

      final eraser = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('tool-eraser-button')),
      );
      final brush = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('tool-brush-button')),
      );
      expect(eraser.isSelected, isTrue);
      expect(brush.isSelected, isFalse);
    });

    testWidgets('ONE Select button (R17-U): emits the select VERB, whatever '
        'outline it is wearing', (tester) async {
      final selected = <CanvasTool>[];
      await tester.pumpWidget(_panel(onToolChanged: selected.add));

      // The old per-variant buttons are gone.
      expect(
        find.byKey(const ValueKey<String>('tool-select-rect-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('tool-lasso-button')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-select-button')),
      );
      expect(selected, [CanvasTool.select]);

      await tester.pumpWidget(_panel(tool: CanvasTool.select));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('tool-select-button')),
            )
            .isSelected,
        isTrue,
      );
    });

    testWidgets('ONE Fill button for the bucket and the shapes', (
      tester,
    ) async {
      for (final verb in [CanvasTool.fill, CanvasTool.fillShape]) {
        await tester.pumpWidget(_panel(tool: verb));
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey<String>('tool-fill-button')),
              )
              .isSelected,
          isTrue,
          reason: '$verb',
        );
      }

      // Pressing it from elsewhere lands on the bucket; pressing it while
      // already on a shape tile leaves that tile alone.
      final picked = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.brush, onToolChanged: picked.add),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      await tester.pumpWidget(
        _panel(tool: CanvasTool.fillShape, onToolChanged: picked.add),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      expect(picked, [CanvasTool.fill, CanvasTool.fillShape]);
    });

    testWidgets('a multi-tile button re-enters on the tile it was left on', (
      tester,
    ) async {
      // 유저 2026-08-15: "필 툴은 아직도 다른 툴 이동하면 모드 선택한게
      // 초기화됨. 도대체 왜 다른거랑 공통로직안할까?" — the button asks its
      // group's memory instead of carrying a rule per button, so the fill
      // and the cut answer the same way and a third group would too.
      final picked = <CanvasTool>[];
      const memory = <CanvasTool, CanvasTool>{
        CanvasTool.fill: CanvasTool.fillShape,
        CanvasTool.cut: CanvasTool.cutStamp,
      };
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.brush,
          onToolChanged: picked.add,
          groupEntry: (group) => memory[group] ?? group,
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      expect(picked, [CanvasTool.fillShape, CanvasTool.cutStamp]);

      // A group with nothing remembered still lands on its default tile.
      picked.clear();
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.brush,
          onToolChanged: picked.add,
          groupEntry: (group) => group,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      expect(picked, [CanvasTool.fill]);
    });

    testWidgets('the rail never names a SHAPE', (tester) async {
      // The whole point of the split: the rail speaks verbs, and a new
      // outline must never have to add a rail button. Whatever the tool
      // state is wearing, pressing Select emits exactly one value.
      final selected = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(tool: CanvasTool.select, onToolChanged: selected.add),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-select-button')),
      );

      expect(selected, [CanvasTool.select]);
    });
  });
}
