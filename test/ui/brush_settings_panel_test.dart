import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart' show BrushMaskSlot;
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/panels/editor_panel_dock.dart';
import 'package:anicel/src/ui/panels/editor_panel_frame.dart';

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

  testWidgets('BrushSettingsPanel updates spacing (the color swatches left '
      'with R26 #11, and size/opacity left for the top strip)', (
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

      expect(state.flowPressureCurve, isNull);

      // Every pressure-capable row STILL HERE carries its curve button;
      // size and opacity took theirs to the top strip with them.
      for (final target in [
        BrushPressureTarget.flow,
        BrushPressureTarget.hardness,
      ]) {
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

      final flowButton = find.byKey(
        const ValueKey<String>('brush-tool-pressure-flow'),
      );
      await tester.ensureVisible(flowButton);
      await tester.tap(flowButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('pressure-curve-popup')),
        findsOneWidget,
      );

      // Enabling pressure installs the identity curve.
      await tester.tap(
        find.byKey(const ValueKey<String>('curve-source-pressure')),
      );
      await tester.pumpAndSettle();
      expect(state.flowPressureCurve, BrushPressureCurve.identity());
      expect(state.toInputSettings().flowPressureCurve, isNotNull);

      // Disabling clears it back to null (the copyWith-preserve rule is
      // bypassed through withPressureCurve).
      await tester.tap(
        find.byKey(const ValueKey<String>('curve-source-pressure')),
      );
      await tester.pumpAndSettle();
      expect(state.flowPressureCurve, isNull);
    },
  );

  group('placement dynamics', () {
    Future<BrushToolState Function()> pumpPanel(
      WidgetTester tester, {
      BrushToolState? initial,
    }) async {
      var state = initial ?? BrushToolState.defaults;
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

    testWidgets('⛔the mask sliders keep their place with no mask picked', (
      tester,
    ) async {
      // The dual and texture scale/density rows used to be mounted only once
      // a mask was chosen, so picking one in the popup shoved four rows into
      // the panel under the finger that had just come back from it.
      final read = await pumpPanel(tester);

      expect(read().dualMask, isNull);
      expect(read().textureMask, isNull);

      expect(
        find.byKey(const ValueKey<String>('brush-tool-texture-invert-toggle')),
        findsOneWidget,
      );

      for (final key in [
        'brush-tool-dual-scale-slider',
        'brush-tool-dual-density-slider',
        'brush-tool-texture-scale-slider',
        'brush-tool-texture-density-slider',
        'brush-tool-texture-brightness-slider',
        'brush-tool-texture-contrast-slider',
      ]) {
        final slider = find.byKey(ValueKey<String>(key));
        expect(slider, findsOneWidget, reason: '$key must keep its place');
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();
      }

      // Present, and DEAD: with no mask there is nothing for them to scale.
      expect(read().dualMaskScale, 1.0);
      expect(read().dualDensity, 1.0);
      expect(read().textureScale, 1.0);
      expect(read().textureDensity, 1.0);
      expect(read().textureBrightness, 0.0);
      expect(read().textureContrast, 0.0);
    });

    testWidgets('🐛the dual sliders reach the engine WITH a mask picked', (
      tester,
    ) async {
      // 🚨THE TEST ABOVE ONLY EVER ASKED THE DEAD CASE. "Present, and DEAD:
      // with no mask there is nothing for them to scale" is true and it is
      // half the question — a row that is disabled cannot say whether the
      // enabled one writes anywhere. `BrushToolState.copyWith` took a
      // `dualDensity` and did not pass it to the shape, so the density
      // slider moved and nothing changed, and every assertion in this file
      // agreed with it.
      final mask = BrushTipMask(
        id: 'dual-row-test',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      final read = await pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(BrushMaskSlot.dual, mask),
      );
      expect(read().dualMask, isNotNull, reason: 'fixture premise');
      expect(read().dualDensity, 1.0);

      final density = find.byKey(
        const ValueKey<String>('brush-tool-dual-density-slider'),
      );
      await tester.ensureVisible(density);
      await tester.drag(density, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(
        read().dualDensity,
        lessThan(1.0),
        reason: 'the slider must reach the shape, not just move',
      );

      final scale = find.byKey(
        const ValueKey<String>('brush-tool-dual-scale-slider'),
      );
      await tester.ensureVisible(scale);
      await tester.drag(scale, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(read().dualMaskScale, greaterThan(1.0));
    });

    testWidgets('the dual BLEND is pickable, and it is a row like the others',
        (tester) async {
      // v33 gave the dual tip a composite mode and both importers read one;
      // without this row a brush could arrive with a mode and never be
      // edited to one. Its two neighbours — the dual scale and density —
      // have had rows since they existed.
      final mask = BrushTipMask(
        id: 'dual-blend-test',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      final read = await pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(BrushMaskSlot.dual, mask),
      );
      expect(read().dualCompositeMode, SeparableBlendMode.multiply);

      final button = find.byKey(
        const ValueKey<String>('brush-tool-dual-blend-menu-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-tool-dual-blend-add')),
      );
      await tester.pumpAndSettle();

      expect(
        read().dualCompositeMode,
        SeparableBlendMode.add,
        reason: 'the picked mode must reach the shape — 加算 is Clip Studio '
            'index 12, one of the two actually found in a real file',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('⛔the dual blend row keeps its place with no mask picked', (
      tester,
    ) async {
      // 「없다가 생기는 UI 금지」, the same law the mask sliders above obey:
      // the row is here and DEAD, not absent and then suddenly present.
      final read = await pumpPanel(tester);
      expect(read().dualMask, isNull);
      final button = find.byKey(
        const ValueKey<String>('brush-tool-dual-blend-menu-button'),
      );
      expect(button, findsOneWidget, reason: 'the row must keep its place');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('brush-tool-dual-blend-add')),
        findsNothing,
        reason: 'with no dual tip there is nothing for a mode to combine',
      );
      expect(tester.takeException(), isNull);
    });

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

    // The blend lock moved to the top strip with the blend button; its
    // pin/release test went with it (editor_top_strip_test.dart).

    testWidgets('⛔mixing DEADENS its knobs, it does not remove them', (
      tester,
    ) async {
      // 유저, 반복: 「없다가 생기는 UI 금지. 자리는 항상 예약하고 내용만
      // 바꾼다」. The three knobs used to be mounted only while mixing was
      // on, so the switch made everything below it jump.
      final read = await pumpPanel(tester);
      const amount = ValueKey<String>('brush-tool-paint-amount-slider');
      const stretchKey = ValueKey<String>('brush-tool-color-stretch-slider');

      expect(read().mixesGroundColor, isFalse);
      expect(find.byKey(amount), findsOneWidget);

      // Dead means dead: dragging it while mixing is off changes nothing.
      final before = read().colorStretch;
      await tester.ensureVisible(find.byKey(stretchKey));
      await tester.drag(find.byKey(stretchKey), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(read().colorStretch, before);

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
