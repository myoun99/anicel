import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/rail_group_button.dart';

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
  test("the stabilizer is the brush's own: its preset carries it (F-418-Q6; "
      '↩️P7 kept it out as hand feel)', () {
    final tuned = BrushToolState(
      correction: const BrushCorrection(stabilization: 40),
    );
    final settings = tuned.toBrushSettings();
    expect(settings.correction, const BrushCorrection(stabilization: 40));
    final applied = BrushToolState.fromBrushSettings(settings);
    expect(applied.correction.stabilization, 40);
  });

  test('the tool state clamps it onto the scale', () {
    expect(
      BrushToolState(
        correction: const BrushCorrection(stabilization: 140),
      ).correction.stabilization,
      100,
    );
    expect(
      BrushToolState()
          .copyWith(correction: const BrushCorrection(stabilization: -5))
          .correction,
      const BrushCorrection(stabilization: 0),
      reason: "the scale's foot is Clip Studio's 0, still on",
    );
  });

  /// The colour GROUP: the wheel, the RGB bars and the palette are three
  /// panels of it (R2 #8), opened from the sub-strip button that IS the
  /// selected-colour swatch.
  Future<void> openColorWindow(
    WidgetTester tester, {
    bool palette = true,
  }) async {
    final button = find.byKey(const ValueKey<String>('tool-color-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    if (palette) {
      await tester.tap(
        find.byKey(const ValueKey<String>('panel-tab-color-palette')),
      );
      await tester.pumpAndSettle();
    }
  }

  /// The colour group's tab [id], brought on screen first: a place pressed
  /// lower down scrolls the dock, and the strip with it.
  Future<void> showTab(WidgetTester tester, String id) async {
    final tab = find.byKey(ValueKey<String>('panel-tab-$id'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('the swatch button opens the colour GROUP, and its panels are '
      'the group\'s own tabs', (tester) async {
    await _pumpWorkspace(tester);

    expect(
      find.byKey(const ValueKey<String>('panel-tab-color-wheel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('tool-color-button')), findsOne);

    await openColorWindow(tester, palette: false);
    expect(
      find.byKey(const ValueKey<String>('panel-tab-color-wheel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('panel-tab-color-rgb')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('panel-tab-color-palette')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('color-wheel')), findsOneWidget);
  });

  testWidgets('the colour window\'s Palette tab shows the palettes: '
      'pressing a place drives the brush color; ＋ makes a new palette, '
      'and the wheel then shows it under itself', (tester) async {
    await _pumpWorkspace(tester);
    await openColorWindow(tester);

    // The starter palette renders; pressing the red place (index 1)
    // recolors the brush.
    final place = find.byKey(const ValueKey<String>('palette-p1-slot-1'));
    await tester.ensureVisible(place);
    await tester.tap(place);
    await tester.pumpAndSettle();
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;
    expect(toolOf(), CanvasTool.brush); // panel intact
    // The wheel hex label follows the picked color.
    await showTab(tester, 'color-wheel');
    expect(find.byKey(const ValueKey<String>('color-wheel')), findsOneWidget);
    expect(find.text('#E53935'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('palette-p1-slot-1')),
      findsOneWidget,
      reason: 'the default palette stands under the wheel',
    );

    await showTab(tester, 'color-palette');
    final make = find.byKey(const ValueKey<String>('palette-new'));
    await tester.ensureVisible(make);
    await tester.tap(make);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('palette-p2-name')), findsOne);

    await showTab(tester, 'color-wheel');
    expect(find.byKey(const ValueKey<String>('color-wheel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('palette-p2-slot-0')),
      findsOneWidget,
      reason: 'a new palette is the default (I-131-Q2)',
    );
    expect(
      find.byKey(const ValueKey<String>('palette-p1-slot-1')),
      findsNothing,
    );
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
    final swatch = find.byKey(const ValueKey<String>('palette-p1-slot-1'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool,
      CanvasTool.eraser,
      reason: 'a captured toolState written back would revert the switch',
    );
    await showTab(tester, 'color-wheel');
    expect(find.byKey(const ValueKey<String>('color-wheel')), findsOneWidget);
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
      reason:
          'the column must fit the rail it was narrowed to, buttons and '
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

    // The tool settings are their own sub-strip button now (유저, R3 #10),
    // under the library's, and they ship closed.
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
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
