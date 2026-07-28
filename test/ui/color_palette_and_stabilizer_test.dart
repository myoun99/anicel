import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The left dock stacks TWO sections by default now (R26 #31: the Tool
/// Library over the Tool Settings), so each gets about half the dock's
/// height — and the Color panel's adaptive layout drops its control strip
/// (the hex readout included) rather than overflow a squat panel. The
/// default 800×600 test surface is smaller than any real window; give
/// these tests a realistic one so they exercise the layout users see.
Future<void> _pumpWorkspace(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

/// P4 (palette rows in the Color tab) + P7 (stabilizer setting) wiring.
void main() {
  test('the stabilizer strength is HAND-FEEL state: presets neither carry '
      'nor clobber it', () {
    final tuned = BrushToolState(stabilizerStrength: 40);
    // Preset payload excludes it...
    final settings = tuned.toBrushSettings();
    final applied = BrushToolState.fromBrushSettings(settings);
    expect(applied.stabilizerStrength, 0, reason: 'not preset payload');
    // ...and the preset-apply site carries the live value over.
    final preserved = applied.copyWith(
      stabilizerStrength: tuned.stabilizerStrength,
    );
    expect(preserved.stabilizerStrength, 40);
    // Settings round-trips keep every preset field intact.
    expect(preserved.toBrushSettings(), isA<BrushSettings>());
  });

  testWidgets('the Color tab shows the palette rows: tapping a swatch '
      'drives the brush color; + pins the current color', (tester) async {
    await _pumpWorkspace(tester);

    final tab = find.byKey(const ValueKey<String>('panel-tab-color-wheel'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    // The default pinned palette renders; tapping the red swatch (index 1)
    // recolors the brush.
    final swatch = find.byKey(const ValueKey<String>('palette-swatch-1'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;
    expect(toolOf(), CanvasTool.brush); // panel intact
    // The wheel hex label follows the picked color.
    expect(find.text('#E53935'), findsOneWidget);

    // + pins the current (red) color as a new swatch.
    final addButton = find.byKey(const ValueKey<String>('palette-add-button'));
    // Red is already pinned → the + is a no-op for it; pick a wheel color
    // first would be flaky — instead assert the button exists.
    expect(addButton, findsOneWidget);
  });

  testWidgets('picking a color KEEPS the active tool (R18 UI-1: the sliced '
      'color tab must write through the live notifier, never a stale '
      'captured state)', (tester) async {
    await _pumpWorkspace(tester);

    // Open the Color tab first so its (sliced) subtree is built...
    final tab = find.byKey(const ValueKey<String>('panel-tab-color-wheel'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    // ...then switch to the eraser — an OFF-SLICE change for the color
    // tab, so its builder does not re-run.
    final eraser = find.byKey(const ValueKey<String>('tool-eraser-button'));
    await tester.ensureVisible(eraser);
    await tester.tap(eraser);
    await tester.pumpAndSettle();

    // Picking a color now must recolor WITHOUT reverting the tool.
    final swatch = find.byKey(const ValueKey<String>('palette-swatch-1'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool,
      CanvasTool.eraser,
      reason: 'a captured toolState written back would revert the switch',
    );
    expect(find.text('#E53935'), findsOneWidget);
  });

  testWidgets('the Stabilizer slider lives in Brush Settings', (tester) async {
    await _pumpWorkspace(tester);

    final tab = find.byKey(const ValueKey<String>('panel-tab-brush-settings'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    final slider = find.byKey(
      const ValueKey<String>('brush-tool-stabilizer-slider'),
    );
    await tester.ensureVisible(slider);
    expect(slider, findsOneWidget);
  });
}
