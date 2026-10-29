import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings_row.dart';
import 'package:anicel/src/models/brush_shape.dart' show BrushMaskSlot;
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/panels/editor_panel_dock.dart';
import 'package:anicel/src/ui/panels/editor_panel_frame.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:anicel/src/ui/widgets/tip_direction_popup.dart';

import '../helpers/boolean_dot_probe.dart';

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
    final read = await _pumpPanel(tester);

    final spacingSlider = find.byKey(
      const ValueKey<String>('brush-tool-spacing-slider'),
    );
    await tester.ensureVisible(spacingSlider);
    await tester.drag(spacingSlider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(read().spacing, greaterThan(BrushToolState.defaultSpacing));
  });

  testWidgets("the 손떨림 보정 slider sets the brush's own, which its preset "
      'keeps (F-418-Q6)', (tester) async {
    final read = await _pumpPanel(tester);

    final slider = find.byKey(
      const ValueKey<String>('brush-tool-stabilizer-slider'),
    );
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(
      read().correction.stabilization,
      greaterThan(BrushCorrection.defaultStabilization),
    );
    expect(read().toBrushSettings().correction, read().correction);
  });

  testWidgets('손떨림 보정 and 後補正 land on whole numbers, as Clip Studio '
      'sets them (F-435)', (tester) async {
    // 유저 2026-10-21: 「손떨림 보정, 클튜에선 소수점자리가 없음. 거기까지
    // 조절안함. 우리도 정수로만」.
    final read = await _pumpPanel(tester);
    final rows = <String, double Function()>{
      'brush-tool-stabilizer-slider': () => read().correction.stabilization,
      'brush-tool-post-correction-slider': () =>
          read().correction.postStrength,
    };
    for (final MapEntry(key: key, value: valueOf) in rows.entries) {
      final slider = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final box = tester.getRect(slider);
      final seen = <double>[];
      // Deliberately awkward places — taps that landed on whole numbers by
      // luck would prove nothing.
      for (final along in [0.213, 0.347, 0.461, 0.589]) {
        await tester.tapAt(
          Offset(box.left + box.width * along, box.center.dy),
        );
        await tester.pumpAndSettle();
        seen.add(valueOf());
      }
      expect(seen.toSet(), hasLength(4), reason: '⛔premise: $key moved');
      for (final value in seen) {
        expect(value, value.roundToDouble(), reason: '$key held $value');
      }
    }
  });

  // 🗣️유저 2026-10-20 「적용해제면 손떨림보정쪽 다른 버튼 규칙처럼 비활성화」 —
  // the other buttons' rule, which F-478-Q2 (유저 2026-10-27) made 「없앤다 —
  // 패널 안 스위치도 같은 법」.
  testWidgets('손떨림 보정 적용 switched off takes the slider and the speed row '
      'under it away, and keeps what they hold', (tester) async {
    Future<void> press(String key) async {
      final row = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(row);
      await tester.pressRingIn(row);
      await tester.pumpAndSettle();
    }

    final read = await _pumpPanel(
      tester,
      initial: BrushToolState.defaults.copyWith(
        correction: const BrushCorrection(stabilization: 40),
      ),
    );
    final under = [
      find.byKey(const ValueKey<String>('brush-tool-stabilizer-slider')),
      find.byKey(const ValueKey<String>('brush-tool-steadying-by-speed-slow')),
    ];
    for (final row in under) {
      expect(row, findsOneWidget, reason: '⛔premise: steadying, it is there');
    }

    await press('brush-tool-stabilizer-on');
    expect(read().correction, const BrushCorrection(steadies: false, stabilization: 40));
    for (final row in under) {
      expect(row, findsNothing);
    }

    await press('brush-tool-stabilizer-on');
    expect(read().correction, const BrushCorrection(stabilization: 40));
    for (final row in under) {
      expect(row, findsOneWidget, reason: 'back with what it held');
    }
  });

  testWidgets('BrushSettingsPanel updates hardness and flow (the tip '
      'shape segment left with R26 #11 — presets own the tip)', (tester) async {
    final read = await _pumpPanel(tester);

    final hardnessSlider = find.byKey(
      const ValueKey<String>('brush-tool-hardness-slider'),
    );
    await tester.ensureVisible(hardnessSlider);
    await tester.drag(hardnessSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(read().hardness, lessThan(BrushToolState.defaultHardness));

    // ensureVisible before dragging, like the hardness slider above: the
    // scroll position after the previous ensureVisible depends on how much
    // panel there is, so a bare drag silently misses once the panel grows.
    final flowSlider = find.byKey(
      const ValueKey<String>('brush-tool-flow-slider'),
    );
    await tester.ensureVisible(flowSlider);
    await tester.drag(flowSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(read().flow, lessThan(BrushToolState.defaultFlow));

    // The sampled input settings carry every tool option to the canvas.
    final inputSettings = read().toInputSettings();
    expect(inputSettings.hardness, read().hardness);
    expect(inputSettings.flow, read().flow);
  });

  testWidgets('BrushSettingsPanel updates tip roundness and angle', (
    tester,
  ) async {
    final read = await _pumpPanel(tester);

    final roundnessSlider = find.byKey(
      const ValueKey<String>('brush-tool-roundness-slider'),
    );
    await tester.ensureVisible(roundnessSlider);
    await tester.drag(roundnessSlider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(read().roundness, lessThan(BrushToolState.defaultRoundness));
    expect(read().roundness, greaterThanOrEqualTo(BrushToolState.minRoundness));

    final angleSlider = find.byKey(
      const ValueKey<String>('brush-tool-angle-slider'),
    );
    await tester.ensureVisible(angleSlider);
    await tester.drag(angleSlider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(read().angleDegrees, greaterThan(BrushToolState.defaultAngleDegrees));
    expect(read().angleDegrees, lessThanOrEqualTo(180.0));

    // Both reach the sampled canvas input settings.
    final inputSettings = read().toInputSettings();
    expect(inputSettings.roundness, read().roundness);
    expect(inputSettings.angleDegrees, read().angleDegrees);
  });

  testWidgets(
    'BrushSettingsPanel opens the pressure popup and toggles the curve '
    '(BB-3)',
    (tester) async {
      final read = await _pumpPanel(tester);

      expect(read().flowPressureCurve, isNull);

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
      expect(read().flowPressureCurve, BrushPressureCurve.identity());
      expect(read().toInputSettings().flowPressureCurve, isNotNull);

      // Disabling clears it back to null (the copyWith-preserve rule is
      // bypassed through withPressureCurve).
      await tester.tap(
        find.byKey(const ValueKey<String>('curve-source-pressure')),
      );
      await tester.pumpAndSettle();
      expect(read().flowPressureCurve, isNull);
    },
  );

  group('placement dynamics', () {
    // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」.
    // ↩️They stood DEAD with no mask, 「없다가 생기는 UI 금지」: they had been
    // mounted only once a mask was chosen, which shoved four rows into the
    // panel under the finger that had just come back from the popup — the
    // cost the answer took.
    testWidgets('the mask knobs are there only with their mask', (
      tester,
    ) async {
      const dual = [
        'brush-tool-dual-scale-slider',
        'brush-tool-dual-density-slider',
        'brush-tool-dual-blend-menu-button',
        'brush-tool-dual-roundness-slider',
        'brush-tool-dual-angle-slider',
        'brush-tool-dual-spacing-slider',
        'brush-tool-dual-scatter-slider',
        'brush-tool-dual-scatter-count-slider',
        'brush-tool-dual-scatter-both-axes-toggle',
      ];
      const texture = [
        'brush-tool-texture-scale-slider',
        'brush-tool-texture-density-slider',
        'brush-tool-texture-mode-height',
        'brush-tool-texture-invert-toggle',
        'brush-tool-texture-brightness-slider',
        'brush-tool-texture-contrast-slider',
      ];
      void expectRows(List<String> keys, Matcher matcher) {
        for (final key in keys) {
          expect(find.byKey(ValueKey<String>(key)), matcher, reason: key);
        }
      }

      final bare = await _pumpPanel(tester);
      expect(bare().dualMask, isNull, reason: 'fixture premise');
      expect(bare().textureMask, isNull, reason: 'fixture premise');
      expectRows([...dual, ...texture], findsNothing);

      final mask = BrushTipMask(
        id: 'mask-rows-test',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(BrushMaskSlot.dual, mask),
      );
      expectRows(dual, findsOneWidget);
      expectRows(texture, findsNothing);

      await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(BrushMaskSlot.texture, mask),
      );
      expectRows(dual, findsNothing);
      expectRows(texture, findsOneWidget);
    });

    testWidgets('🐛the dual sliders reach the engine WITH a mask picked', (
      tester,
    ) async {
      // 🚨THE TEST ABOVE ONCE ASKED ONLY THE DEAD CASE (↩️the rows stood DEAD
      // with no mask, until F-478-Q2). "Present, and DEAD: with no mask there
      // is nothing for them to scale" was true and it was half the question
      // — a row that is disabled cannot say whether the enabled one writes
      // anywhere. `BrushToolState.copyWith` took a `dualDensity` and did not
      // pass it to the shape, so the density slider moved and nothing
      // changed, and every assertion in this file agreed with it.
      final mask = BrushTipMask(
        id: 'dual-row-test',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      final read = await _pumpPanel(
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

    testWidgets("the second tip's way along the path reaches the shape", (
      tester,
    ) async {
      // The first tip's rows of the same names, written to the second
      // tip's fields — and not the first tip's.
      final mask = BrushTipMask(
        id: 'dual-way-test',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(BrushMaskSlot.dual, mask),
      );
      final first = read().shape;
      Future<void> drag(String key, double dx) async {
        final row = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(row);
        await tester.drag(row, Offset(dx, 0));
        await tester.pumpAndSettle();
      }

      await drag('brush-tool-dual-spacing-slider', 60);
      await drag('brush-tool-dual-roundness-slider', -60);
      await drag('brush-tool-dual-angle-slider', 60);
      await drag('brush-tool-dual-scatter-slider', 60);
      await drag('brush-tool-dual-scatter-count-slider', 60);
      final axes = find.byKey(
        const ValueKey<String>('brush-tool-dual-scatter-both-axes-toggle'),
      );
      await tester.ensureVisible(axes);
      await tester.pressRingIn(axes);
      await tester.pumpAndSettle();

      final now = read();
      expect(now.dualSpacing, greaterThan(first.dualSpacing));
      expect(now.dualRoundness, lessThan(1.0));
      expect(now.dualAngleDegrees, isNot(0.0));
      expect(now.dualScatterRadiusRatio, greaterThan(0));
      expect(now.dualScatterCount, greaterThan(1));
      expect(now.dualScatterBothAxes, isFalse);
      expect(
        (now.spacing, now.roundness, now.angleDegrees, now.scatterCount),
        (
          first.spacing,
          first.roundness,
          first.angleDegrees,
          first.scatterCount,
        ),
        reason: "the first tip's own stay put",
      );
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
      final read = await _pumpPanel(
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

    testWidgets('繰り返し方法 is picked by its row and reaches the shape '
        '(F-176-Q3)', (tester) async {
      BrushTipMask tip(String id) => BrushTipMask(
        id: id,
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.copyWith(tips: [tip('a'), tip('b')]),
      );
      expect(read().tipOrder, BrushTipOrder.repeat);

      final button = find.byKey(
        const ValueKey<String>('brush-tool-tip-order-menu-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-tool-tip-order-pingPong')),
      );
      await tester.pumpAndSettle();

      expect(read().tipOrder, BrushTipOrder.pingPong);
      expect(tester.takeException(), isNull);
    });

    // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」.
    // ↩️It stood DEAD for the round tip (「없다가 생기는 UI 금지」).
    testWidgets('the 繰り返し方法 row is there only with tips to take turns — '
        'one keeps it, its two laps still draw that tip once', (
      tester,
    ) async {
      final button = find.byKey(
        const ValueKey<String>('brush-tool-tip-order-menu-button'),
      );
      final bare = await _pumpPanel(tester);
      expect(bare().tips, isEmpty, reason: 'fixture premise');
      expect(button, findsNothing);

      await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.copyWith(
          tips: [
            BrushTipMask(
              id: 'one',
              size: 2,
              alpha: Uint8List.fromList([0, 128, 200, 255]),
            ),
          ],
        ),
      );
      expect(button, findsOneWidget);
    });

    // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」.
    // ↩️It stood DEAD below two tips (「없다가 생기는 UI 금지」).
    testWidgets('the tips a turn holds are set by their row and reach the '
        'shape — and the row is there only with two tips to throw between '
        '(F-456-Q4)', (tester) async {
      final row = find.byKey(
        const ValueKey<String>('brush-tool-tips-per-turn-slider'),
      );
      BrushTipMask tip(String id) => BrushTipMask(
        id: id,
        size: 2,
        alpha: Uint8List.fromList([0, 128, 200, 255]),
      );
      for (final tips in [<BrushTipMask>[], [tip('a')]]) {
        await _pumpPanel(
          tester,
          initial: BrushToolState.defaults.copyWith(tips: tips),
        );
        expect(row, findsNothing, reason: '${tips.length} tip(s)');
      }

      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.copyWith(
          tips: [tip('a'), tip('b'), tip('c'), tip('d')],
        ),
      );
      expect(read().tipsPerTurn, 1);
      tester.widget<FieldSlider>(row).onChanged!(2.0);
      await tester.pumpAndSettle();
      expect(read().tipsPerTurn, 2);
      expect(tester.takeException(), isNull);
    });

    // With no paper the row is not there — the mask knobs' test above.
    testWidgets('the paper\'s 高さ is picked by its row and reaches the '
        'canvas (F-451)', (tester) async {
      final height = find.byKey(
        const ValueKey<String>('brush-tool-texture-mode-height'),
      );
      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(
          BrushMaskSlot.texture,
          _paper,
        ),
      );
      expect(read().textureMode, BrushTextureMode.multiply);
      await tester.ensureVisible(height);
      await tester.tap(height);
      await tester.pumpAndSettle();

      expect(read().toInputSettings().textureMode, BrushTextureMode.height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the paper\'s density takes a pen curve of its own — the '
        'lead\'s reach into the tooth (F-451)', (tester) async {
      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.withMask(
          BrushMaskSlot.texture,
          _paper,
        ),
      );
      final curveButton = find.byKey(
        const ValueKey<String>('brush-tool-pressure-textureDensity'),
      );
      await tester.ensureVisible(curveButton);
      await tester.tap(curveButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('curve-source-pressure')),
      );
      await tester.pumpAndSettle();

      expect(
        read().toInputSettings().shape.curveFor(
          BrushPressureTarget.textureDensity,
          BrushInputSource.pressure,
        ),
        BrushPressureCurve.identity(),
      );
    });

    testWidgets('the angle\'s random turn reaches the engine — from the '
        'window behind the button beside the angle (F-176-Q6)', (
      tester,
    ) async {
      final read = await _pumpPanel(tester);

      final button = find.byKey(
        const ValueKey<String>(TipDirectionButton.keyValue),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final slider = find.byKey(
        const ValueKey<String>('brush-tool-angle-jitter-slider'),
      );
      await tester.drag(slider, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(read().angleJitter, greaterThan(0));
    });

    testWidgets('🚨no 「무작위」 group — chance is each setting\'s row', (
      tester,
    ) async {
      // F-176-Q2 (유저 2026-10-18 「클튜식 — 팝업에 랜덤 줄, 「무작위」 묶음
      // 없앰」): the jitters are the ランダム row of each setting's curve
      // popup, and roundness and spacing carry that popup like the others.
      await _pumpPanel(tester);

      for (final gone in ['size', 'opacity', 'roundness', 'spacing']) {
        expect(
          find.byKey(ValueKey<String>('brush-tool-$gone-jitter-slider')),
          findsNothing,
          reason: gone,
        );
      }
      for (final target in ['roundness', 'spacing']) {
        expect(
          find.byKey(ValueKey<String>('brush-tool-pressure-$target')),
          findsOneWidget,
          reason: target,
        );
      }
    });

    // The blend lock moved to the top strip with the blend button; its
    // pin/release test went with it (editor_top_strip_test.dart).

    // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」.
    // ↩️The three went DEAD with mixing off (유저, 반복: 「없다가 생기는 UI
    // 금지. 자리는 항상 예약하고 내용만 바꾼다」 — mounted only while mixing
    // was on, the switch had made everything below it jump), until the
    // answer took that cost.
    testWidgets('mixing brings its knobs, and takes them away keeping what '
        'they hold', (tester) async {
      final read = await _pumpPanel(tester);
      const knobs = [
        'brush-tool-paint-amount-slider',
        'brush-tool-paint-density-slider',
        'brush-tool-color-stretch-slider',
      ];
      void expectKnobs(Matcher matcher) {
        for (final key in knobs) {
          expect(find.byKey(ValueKey<String>(key)), matcher, reason: key);
        }
      }

      final toggle = find.byKey(
        const ValueKey<String>('brush-tool-mixing-toggle'),
      );
      Future<void> flip() async {
        await tester.ensureVisible(toggle);
        await tester.pressRingIn(toggle);
        await tester.pumpAndSettle();
      }

      expect(read().mixesGroundColor, isFalse);
      expectKnobs(findsNothing);

      await flip();
      expect(read().mixesGroundColor, isTrue);
      expectKnobs(findsOneWidget);

      // Colour stretch starts at zero, so dragging it right is what proves
      // it is wired. ↩️Zero was 「a brush that lifts nothing」 until the
      // stretch read as Clip Studio's (2026-10-30): it lifts the most now.
      final stretch = find.byKey(
        const ValueKey<String>('brush-tool-color-stretch-slider'),
      );
      await tester.ensureVisible(stretch);
      await tester.drag(stretch, const Offset(60, 0));
      await tester.pumpAndSettle();
      final stretched = read().colorStretch;
      expect(stretched, greaterThan(0));

      await flip();
      expectKnobs(findsNothing);
      await flip();
      expect(
        tester.widget<FieldSlider>(stretch).value,
        stretched,
        reason: 'back with what it held',
      );
    });

    // 🗣️F-478-Q2 (유저 2026-10-27): the method row is one of the rows under
    // the mixing switch, and the reservoir's three are the mix's alone.
    testWidgets('the mixing method is picked by its row and reaches the '
        'canvas — there only while mixing is on, and a blur takes the '
        'reservoir\'s knobs away (I-75)', (tester) async {
      final blur = find.byKey(
        const ValueKey<String>('brush-tool-mixing-method-blur'),
      );
      final bare = await _pumpPanel(tester);
      expect(bare().mixesGroundColor, isFalse, reason: 'fixture premise');
      expect(blur, findsNothing, reason: 'mixing off, nothing to pick');

      final read = await _pumpPanel(
        tester,
        initial: BrushToolState.defaults.copyWith(mixesGroundColor: true),
      );
      const amount = ValueKey<String>('brush-tool-paint-amount-slider');
      expect(find.byKey(amount), findsOneWidget, reason: 'premise: a mix');
      await tester.ensureVisible(blur);
      await tester.tap(blur);
      await tester.pumpAndSettle();

      expect(read().toInputSettings().blurs, isTrue);
      expect(
        find.byKey(amount),
        findsNothing,
        reason: 'a blur picks no colour up',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('scatter carries a radius, a count and an axis choice', (
      tester,
    ) async {
      final read = await _pumpPanel(tester);

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
      await tester.pressRingIn(axes);
      await tester.pumpAndSettle();

      expect(read().scatterRadiusRatio, greaterThan(0));
      expect(read().scatterCount, greaterThan(1));
      // Defaults to both axes, so one tap turns it off.
      expect(read().scatterBothAxes, isFalse);
    });

    testWidgets('the tip can be told to follow the stroke direction', (
      tester,
    ) async {
      final read = await _pumpPanel(tester);
      expect(read().rotationMode, BrushTipRotationMode.fixed);

      final button = find.byKey(
        const ValueKey<String>(TipDirectionButton.keyValue),
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

  testWidgets('the brush edge is the app\'s one grouped choice — a pill per '
      'step, the chosen one lit, a press choosing (board '
      'pill-group-everywhere)', (tester) async {
    final read = await _pumpPanel(tester);
    Finder edge(BrushAntiAlias step) =>
        find.byKey(ValueKey<String>('brush-tool-edge-${step.name}'));
    List<bool> lit() => [
      for (final step in BrushAntiAlias.values)
        tester.widget<Pill>(edge(step)).selected,
    ];
    expect(read().antiAlias, isNot(BrushAntiAlias.none), reason: 'premise');
    expect(lit(), [
      for (final step in BrushAntiAlias.values) step == read().antiAlias,
    ]);

    await tester.ensureVisible(edge(BrushAntiAlias.none));
    await tester.tap(edge(BrushAntiAlias.none));
    await tester.pumpAndSettle();

    expect(read().antiAlias, BrushAntiAlias.none);
    expect(lit(), [
      for (final step in BrushAntiAlias.values) step == BrushAntiAlias.none,
    ]);
  });

  // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」.
  // ↩️What had nothing under it to bend stood DIM (F-418).
  testWidgets("the 보정 group writes the brush's own — the speed row and the "
      '後補正 rows — and has no row for what has nothing under it to bend '
      '(F-418)', (tester) async {
    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> press(String key) async {
      final row = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(row);
      await tester.pressRingIn(row);
      await tester.pumpAndSettle();
    }

    const toggles = [
      'brush-tool-post-by-speed-toggle',
      'brush-tool-post-by-view-scale-toggle',
      'brush-tool-post-bezier-toggle',
    ];

    var read = await _pumpPanel(
      tester,
      initial: BrushToolState.defaults.copyWith(
        correction: BrushCorrection.none,
      ),
    );
    // Nothing taken out: nothing to bend. (Nothing steadied, no speed row —
    // the 손떨림 보정 적용 test above.)
    for (final key in toggles) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
    }
    // 角をとがらせる sits under no switch in Clip Studio's group: it is
    // always there (F-418-Q11).
    await press('brush-tool-sharpen-corners');
    expect(
      read().correction,
      BrushCorrection.none.copyWith(sharpenCorners: true),
    );
    await press('brush-tool-sharpen-corners');
    expect(read().correction, BrushCorrection.none, reason: 'and off again');

    read = await _pumpPanel(
      tester,
      initial: BrushToolState.defaults.copyWith(
        correction: const BrushCorrection(postStrength: 20),
      ),
    );
    await press('brush-tool-sharpen-corners');
    await tap('brush-tool-steadying-by-speed-fast');
    for (final key in toggles) {
      await press(key);
    }
    expect(
      read().correction,
      const BrushCorrection(
        sharpenCorners: true,
        steadyingBySpeed: BrushSteadyingBySpeed.fast,
        postStrength: 20,
        postBySpeed: false,
        postByViewScale: false,
        postBezier: true,
      ),
    );

    final post = find.byKey(
      const ValueKey<String>('brush-tool-post-correction-slider'),
    );
    await tester.ensureVisible(post);
    await tester.drag(post, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(read().correction.postStrength, greaterThan(20));
    expect(read().toBrushSettings().correction, read().correction);
  });
}

/// A paper for the texture slot, whose rows are there only with one.
final _paper = BrushTipMask(
  id: 'paper-row-test',
  size: 2,
  alpha: Uint8List.fromList([0, 128, 200, 255]),
);

/// The settings panel, scrolled, starting from [initial] and kept as each
/// change leaves it: what it holds now is the answer of the function given
/// back.
///
/// The brush shows every row: what these pin is each row, and which rows a
/// brush shows is `a_brush_shows_the_settings_it_chose_test`'s (I-141).
Future<BrushToolState Function()> _pumpPanel(
  WidgetTester tester, {
  BrushToolState? initial,
}) async {
  var state = (initial ?? BrushToolState.defaults).copyWith(
    shown: BrushSettingsRow.values.toSet(),
  );
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
