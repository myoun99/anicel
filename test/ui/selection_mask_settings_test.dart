import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';

/// R26 (C2): the Select tool's mask knobs — sliders/switch render and
/// plumb SelectionMaskOptions changes back out.
void main() {
  testWidgets('select tool settings expose grow/feather/AA and plumb '
      'changes', (tester) async {
    final changes = <SelectionMaskOptions>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(
              tool: CanvasTool.select,
            ),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
            selectionMaskOptions: const SelectionMaskOptions(growPx: 3),
            onSelectionMaskOptionsChanged: changes.add,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('selection-grow-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('selection-feather-slider')),
      findsOneWidget,
    );
    expect(find.textContaining('+3 px'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-anti-alias-switch')),
    );
    await tester.pump();
    expect(changes, hasLength(1));
    expect(changes.single.antiAlias, isTrue);
    expect(changes.single.growPx, 3, reason: 'other knobs carry over');
  });

  testWidgets('without a mask-options listener the knobs stay hidden '
      '(hosts that predate R26)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolSettingsPanel(
            state: BrushToolState.defaults.withShapeKind(
              CanvasShapeKind.lasso,
              forTool: CanvasTool.select,
            ),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('selection-grow-slider')),
      findsNothing,
    );
  });
}
