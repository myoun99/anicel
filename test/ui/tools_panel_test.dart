import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';

Widget _panel({
  CanvasTool tool = CanvasTool.brush,
  CanvasTool selectionVariant = CanvasTool.selectRect,
  CanvasTool cutVariant = CanvasTool.cutRect,
  ValueChanged<CanvasTool>? onToolChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ToolsPanel(
        tool: tool,
        selectionVariant: selectionVariant,
        cutVariant: cutVariant,
        onToolChanged: onToolChanged ?? (_) {},
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

    testWidgets('it lights up for every cut variant', (tester) async {
      // One button, three tiles: the rail must not go dark just because the
      // user is on the stamp tile rather than a grab tile.
      for (final variant in [
        CanvasTool.cutRect,
        CanvasTool.cutLasso,
        CanvasTool.cutStamp,
      ]) {
        await tester.pumpWidget(_panel(tool: variant));
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey<String>('tool-cut-button')),
              )
              .isSelected,
          isTrue,
          reason: '$variant',
        );
      }
    });

    testWidgets('pressing it from another tool activates the remembered '
        'variant', (tester) async {
      final picked = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.brush,
          cutVariant: CanvasTool.cutLasso,
          onToolChanged: picked.add,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      expect(picked, [CanvasTool.cutLasso]);
    });

    testWidgets('pressing it while already cutting keeps the current tile', (
      tester,
    ) async {
      // Re-pressing must not throw the user back to the rectangle — the
      // button re-activates the tool, it does not reset the variant.
      final picked = <CanvasTool>[];
      await tester.pumpWidget(
        _panel(
          tool: CanvasTool.cutStamp,
          cutVariant: CanvasTool.cutRect,
          onToolChanged: picked.add,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      expect(picked, [CanvasTool.cutStamp]);
    });

    testWidgets('the Select button stays dark while a cut variant is armed', (
      tester,
    ) async {
      // The two buttons share a grammar; they must not share a highlight.
      await tester.pumpWidget(_panel(tool: CanvasTool.cutRect));
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
