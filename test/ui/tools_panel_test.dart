import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';

Widget _panel({
  CanvasTool tool = CanvasTool.brush,
  CanvasTool selectionVariant = CanvasTool.selectRect,
  ValueChanged<CanvasTool>? onToolChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ToolsPanel(
        tool: tool,
        selectionVariant: selectionVariant,
        onToolChanged: onToolChanged ?? (_) {},
      ),
    ),
  );
}

void main() {
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

    testWidgets('ONE Select button (R17-U): activates the remembered '
        'variant and highlights for both variants', (tester) async {
      final selected = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(selectionVariant: CanvasTool.lasso, onToolChanged: selected.add),
      );

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
      expect(selected, [CanvasTool.lasso], reason: 'remembered variant');

      // Selected state covers BOTH variants.
      await tester.pumpWidget(_panel(tool: CanvasTool.lasso));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('tool-select-button')),
            )
            .isSelected,
        isTrue,
      );
    });

    testWidgets('pressing Select while a variant is ACTIVE keeps it', (
      tester,
    ) async {
      final selected = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.lasso,
          selectionVariant: CanvasTool.selectRect,
          onToolChanged: selected.add,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-select-button')),
      );

      expect(selected, [CanvasTool.lasso]);
    });
  });
}
