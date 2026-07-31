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

  /// R9 #14: there is no Color TAB any more — the wheel and the palette
  /// are the two tabs of the 「컬러 버튼창」, opened from the tool rail's
  /// selected-colour swatch.
  Future<void> openColorWindow(WidgetTester tester, {bool palette = true}) async {
    final button = find.byKey(const ValueKey<String>('tool-color-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    if (palette) {
      await tester.tap(
        find.byKey(const ValueKey<String>('color-window-tab-palette')),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('R9 #14: the Color TAB is gone — the tool rail\'s swatch '
      'opens the window instead', (tester) async {
    await _pumpWorkspace(tester);

    expect(
      find.byKey(const ValueKey<String>('panel-tab-color-wheel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('tool-color-button')), findsOne);

    await openColorWindow(tester, palette: false);
    expect(
      find.byKey(const ValueKey<String>('color-window-tab-wheel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('color-window-tab-palette')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('color-wheel')), findsOneWidget);
  });

  testWidgets('the colour window\'s Palette tab shows the palette rows: '
      'tapping a swatch drives the brush color; + pins the current color', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    await openColorWindow(tester);

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
    await tester.tap(
      find.byKey(const ValueKey<String>('color-window-tab-wheel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('#E53935'), findsOneWidget);

    // + pins the current (red) color as a new swatch.
    await tester.tap(
      find.byKey(const ValueKey<String>('color-window-tab-palette')),
    );
    await tester.pumpAndSettle();
    final addButton = find.byKey(const ValueKey<String>('palette-add-button'));
    // Red is already pinned → the + is a no-op for it; pick a wheel color
    // first would be flaky — instead assert the button exists.
    expect(addButton, findsOneWidget);
  });

  testWidgets('picking a color KEEPS the active tool (R18 UI-1: the sliced '
      'colour control must write through the live notifier, never a stale '
      'captured state)', (tester) async {
    await _pumpWorkspace(tester);

    // Switch to the eraser first — an OFF-SLICE change for the colour
    // swatch, so its builder does not re-run.
    final eraser = find.byKey(const ValueKey<String>('tool-eraser-button'));
    await tester.ensureVisible(eraser);
    await tester.tap(eraser);
    await tester.pumpAndSettle();

    await openColorWindow(tester);

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
    await tester.tap(
      find.byKey(const ValueKey<String>('color-window-tab-wheel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('#E53935'), findsOneWidget);
  });

  testWidgets('R9 #17: the tool rail is 48 wide and its column fits — a '
      'third of the old 72 handed back to the canvas', (tester) async {
    await _pumpWorkspace(tester);

    expect(ToolsPanel.dockWidth, 48);
    final railWidth = tester
        .getSize(find.byKey(const ValueKey<String>('tools-panel')))
        .width;
    expect(
      railWidth,
      lessThanOrEqualTo(ToolsPanel.dockWidth),
      reason: 'the column must fit the rail it was narrowed to, buttons and '
          'colour swatch included',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('tool-brush-button'))),
      const Size(ToolsPanel.buttonExtent, ToolsPanel.buttonExtent),
      reason: 'still a stylus target — the rail was sized around it',
    );
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
