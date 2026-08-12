import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// R11-④: the Tool Library / Tool Settings panels follow the active tool.
void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ToolLibraryPanel', () {
    testWidgets('painting tools show the brush library', (tester) async {
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.eraser,
            onToolChanged: (_) {},
            brushLibrary: const Text('library-content'),
          ),
        ),
      );
      expect(find.text('library-content'), findsOneWidget);
    });

    testWidgets('selection tools list their variants and switch on tap', (
      tester,
    ) async {
      final switched = <CanvasTool>[];
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.selectRect,
            onToolChanged: switched.add,
            brushLibrary: const SizedBox.shrink(),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-select-rect')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-lasso')));
      expect(switched, [CanvasTool.lasso]);
    });

    testWidgets('the transform tool lists 일반/퍼스/메쉬 and picking one '
        'writes the MODE, not the tool', (tester) async {
      final options = ValueNotifier(TransformToolOptions.defaults);
      addTearDown(options.dispose);
      final switched = <CanvasTool>[];
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.move,
            onToolChanged: switched.add,
            brushLibrary: const SizedBox.shrink(),
            transformOptions: options,
            onTransformOptionsChanged: (value) => options.value = value,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-transform-normal')),
        findsOneWidget,
      );

      // The mesh's only entrance. It used to be a button in Tool Settings
      // that needed no selection to work; the tile inherits that — nothing
      // here knows or cares whether anything is selected.
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-transform-mesh')),
      );
      await tester.pump();
      expect(options.value.mode, TransformMode.mesh);
      expect(
        switched,
        isEmpty,
        reason:
            'a mode is a setting — routing it through onToolChanged would '
            'confirm the open box on the way past',
      );
    });
  });

  group('ToolSettingsPanel', () {
    testWidgets('fill shows the flood knobs and reports edits', (tester) async {
      final changes = <FloodFillOptions>[];
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: changes.add,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('fill-tolerance-slider')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('fill-anti-alias-switch')),
      );
      await tester.pump();
      expect(changes, hasLength(1));
      expect(changes.single.antiAlias, isFalse);
      expect(changes.single.tolerance, 32, reason: 'other knobs untouched');
    });

    testWidgets('painting tools keep the brush settings panel', (tester) async {
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults,
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
          ),
        ),
      );
      // Size left for the top strip, so the signature control is now the
      // first knob a preset DOES carry and a hand does not reach for
      // mid-stroke.
      expect(
        find.byKey(const ValueKey<String>('brush-tool-flow-slider')),
        findsOneWidget,
      );
    });
  });
}
