import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_pressure_curve.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_rotation_mode.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_shape.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_preset_panel.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_settings_panel.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_tool_state.dart';
import 'package:quick_animaker_v2/src/ui/panels/editor_panel_dock.dart';
import 'package:quick_animaker_v2/src/ui/panels/editor_panel_frame.dart';

void main() {
  testWidgets('EditorPanelFrame renders toolbar and body at small sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 120,
          height: 80,
          child: EditorPanelFrame(
            title: 'Test Panel',
            trailing: Icon(Icons.tune, size: 16),
            child: Text('Body'),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('editor-panel-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('editor-panel-body')),
      findsOneWidget,
    );
    // The tab names the panel — the frame renders no title of its own.
    expect(find.text('Test Panel'), findsNothing);
    expect(find.text('Body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EditorPanelFrame without trailing controls skips the toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 120,
          height: 80,
          child: EditorPanelFrame(title: 'Test Panel', child: Text('Body')),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('editor-panel-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('editor-panel-body')),
      findsOneWidget,
    );
    expect(find.text('Body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right dock hosts the preset and settings panels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPanelDock(
            children: [
              const BrushPresetPanel(presets: []),
              BrushSettingsPanel(
                state: BrushToolState.defaults,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('editor-panel-dock-right')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('editor-panel-frame-Brushes')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('editor-panel-frame-Brush Settings')),
      findsOneWidget,
    );
  });

  testWidgets('BrushSettingsPanel updates size opacity and spacing (the '
      'color swatches left with R26 #11 — the color wheel owns color)', (
    tester,
  ) async {
    var state = BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => BrushSettingsPanel(
                state: state,
                onChanged: (next) => setState(() => state = next),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('brush-tool-size-slider')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(state.size, greaterThan(BrushToolState.defaultSize));

    await tester.drag(
      find.byKey(const ValueKey<String>('brush-tool-opacity-slider')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    expect(state.opacity, lessThan(BrushToolState.defaultOpacity));

    final spacingSlider = find.byKey(
      const ValueKey<String>('brush-tool-spacing-slider'),
    );
    await tester.ensureVisible(spacingSlider);
    await tester.drag(spacingSlider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(state.spacing, greaterThan(BrushToolState.defaultSpacing));
  });

  testWidgets('BrushSettingsPanel updates hardness and flow (the tip '
      'shape segment left with R26 #11 — presets own the tip)', (tester) async {
    var state = BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => BrushSettingsPanel(
                state: state,
                onChanged: (next) => setState(() => state = next),
              ),
            ),
          ),
        ),
      ),
    );

    final hardnessSlider = find.byKey(
      const ValueKey<String>('brush-tool-hardness-slider'),
    );
    await tester.ensureVisible(hardnessSlider);
    await tester.drag(hardnessSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(state.hardness, lessThan(BrushToolState.defaultHardness));

    // ensureVisible before dragging, like the hardness slider above: the
    // scroll position after the previous ensureVisible depends on how much
    // panel there is, so a bare drag silently misses once the panel grows.
    final flowSlider = find.byKey(
      const ValueKey<String>('brush-tool-flow-slider'),
    );
    await tester.ensureVisible(flowSlider);
    await tester.drag(flowSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(state.flow, lessThan(BrushToolState.defaultFlow));

    // The sampled input settings carry every tool option to the canvas.
    final inputSettings = state.toInputSettings();
    expect(inputSettings.hardness, state.hardness);
    expect(inputSettings.flow, state.flow);
    expect(inputSettings.tipShape, BrushTipShape.round);
  });

  testWidgets('BrushSettingsPanel updates tip roundness and angle', (
    tester,
  ) async {
    var state = BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => BrushSettingsPanel(
                state: state,
                onChanged: (next) => setState(() => state = next),
              ),
            ),
          ),
        ),
      ),
    );

    final roundnessSlider = find.byKey(
      const ValueKey<String>('brush-tool-roundness-slider'),
    );
    await tester.ensureVisible(roundnessSlider);
    await tester.drag(roundnessSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(state.roundness, lessThan(BrushToolState.defaultRoundness));
    expect(state.roundness, greaterThanOrEqualTo(BrushToolState.minRoundness));

    final angleSlider = find.byKey(
      const ValueKey<String>('brush-tool-angle-slider'),
    );
    await tester.ensureVisible(angleSlider);
    await tester.drag(angleSlider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(state.angleDegrees, greaterThan(BrushToolState.defaultAngleDegrees));
    expect(state.angleDegrees, lessThanOrEqualTo(180.0));

    // Both reach the sampled canvas input settings.
    final inputSettings = state.toInputSettings();
    expect(inputSettings.roundness, state.roundness);
    expect(inputSettings.angleDegrees, state.angleDegrees);
  });

  testWidgets(
    'BrushSettingsPanel opens the pressure popup and toggles the curve '
    '(BB-3)',
    (tester) async {
      var state = BrushToolState.defaults;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => BrushSettingsPanel(
                  state: state,
                  onChanged: (next) => setState(() => state = next),
                ),
              ),
            ),
          ),
        ),
      );

      expect(state.sizePressureCurve, isNull);

      // Every pressure-capable row carries its curve button.
      for (final target in BrushPressureTarget.values) {
        expect(
          find.byKey(ValueKey<String>('brush-tool-pressure-${target.name}')),
          findsOneWidget,
        );
      }
      // The legacy toggle group is gone.
      expect(
        find.byKey(const ValueKey<String>('brush-tool-pressure-size-toggle')),
        findsNothing,
      );

      final sizeButton = find.byKey(
        const ValueKey<String>('brush-tool-pressure-size'),
      );
      await tester.ensureVisible(sizeButton);
      await tester.tap(sizeButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('pressure-curve-popup')),
        findsOneWidget,
      );

      // Enabling pressure installs the identity curve.
      await tester.tap(
        find.byKey(const ValueKey<String>('pressure-curve-enable-switch')),
      );
      await tester.pumpAndSettle();
      expect(state.sizePressureCurve, BrushPressureCurve.identity());
      expect(state.toInputSettings().sizePressureCurve, isNotNull);

      // Disabling clears it back to null (the copyWith-preserve rule is
      // bypassed through withPressureCurve).
      await tester.tap(
        find.byKey(const ValueKey<String>('pressure-curve-enable-switch')),
      );
      await tester.pumpAndSettle();
      expect(state.sizePressureCurve, isNull);
    },
  );

  group('placement dynamics', () {
    Future<BrushToolState Function()> pumpPanel(WidgetTester tester) async {
      var state = BrushToolState.defaults;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => BrushSettingsPanel(
                  state: state,
                  onChanged: (next) => setState(() => state = next),
                ),
              ),
            ),
          ),
        ),
      );
      return () => state;
    }

    testWidgets('the jitter sliders reach the engine', (tester) async {
      // These have existed in the engine since P20 with no way to touch
      // them: only a preset or an import could turn them on.
      final read = await pumpPanel(tester);

      for (final key in [
        'brush-tool-size-jitter-slider',
        'brush-tool-opacity-jitter-slider',
        'brush-tool-angle-jitter-slider',
      ]) {
        final slider = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();
      }

      expect(read().sizeJitter, greaterThan(0));
      expect(read().opacityJitter, greaterThan(0));
      expect(read().angleJitter, greaterThan(0));
    });

    testWidgets('the roundness and spacing jitters reach the engine', (
      tester,
    ) async {
      final read = await pumpPanel(tester);

      for (final key in [
        'brush-tool-roundness-jitter-slider',
        'brush-tool-spacing-jitter-slider',
      ]) {
        final slider = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();
      }

      expect(read().roundnessJitter, greaterThan(0));
      expect(read().spacingJitter, greaterThan(0));
    });

    testWidgets('mixing hides its knobs until it is switched on', (
      tester,
    ) async {
      final read = await pumpPanel(tester);
      const amount = ValueKey<String>('brush-tool-paint-amount-slider');

      expect(read().mixesGroundColor, isFalse);
      expect(find.byKey(amount), findsNothing);

      final toggle = find.byKey(
        const ValueKey<String>('brush-tool-mixing-toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(read().mixesGroundColor, isTrue);
      expect(find.byKey(amount), findsOneWidget);

      // Colour stretch starts at zero — a brush that lifts nothing is the
      // safe default — so dragging it right is what proves it is wired.
      final stretch = find.byKey(
        const ValueKey<String>('brush-tool-color-stretch-slider'),
      );
      await tester.ensureVisible(stretch);
      await tester.drag(stretch, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(read().colorStretch, greaterThan(0));
    });

    testWidgets('scatter carries a radius, a count and an axis choice', (
      tester,
    ) async {
      final read = await pumpPanel(tester);

      final radius = find.byKey(
        const ValueKey<String>('brush-tool-scatter-slider'),
      );
      await tester.ensureVisible(radius);
      await tester.drag(radius, const Offset(60, 0));
      await tester.pumpAndSettle();

      final count = find.byKey(
        const ValueKey<String>('brush-tool-scatter-count-slider'),
      );
      await tester.ensureVisible(count);
      await tester.drag(count, const Offset(60, 0));
      await tester.pumpAndSettle();

      final axes = find.byKey(
        const ValueKey<String>('brush-tool-scatter-both-axes-toggle'),
      );
      await tester.ensureVisible(axes);
      await tester.tap(axes);
      await tester.pumpAndSettle();

      expect(read().scatterRadiusRatio, greaterThan(0));
      expect(read().scatterCount, greaterThan(1));
      // Defaults to both axes, so one tap turns it off.
      expect(read().scatterBothAxes, isFalse);
    });

    testWidgets('the tip can be told to follow the stroke direction', (
      tester,
    ) async {
      final read = await pumpPanel(tester);
      expect(read().rotationMode, BrushTipRotationMode.fixed);

      final button = find.byKey(
        const ValueKey<String>('brush-tool-rotation-menu-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-tool-rotation-direction')),
      );
      await tester.pumpAndSettle();

      expect(read().rotationMode, BrushTipRotationMode.direction);
    });
  });
}
