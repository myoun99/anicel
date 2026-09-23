import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// 🔬H40 (유저 2026-09-11): 「고르는 프레임에서 끝나더라도 지금 안그래도 고를때
/// 렉있어서 그부분도 효율적으로 가볍게 하고싶어」 — with the settings open, a
/// pick rebuilt every row of this panel, the ones two brushes share included.
void main() {
  const flowKey = ValueKey<String>('brush-tool-flow-slider');
  const jitterKey = ValueKey<String>('brush-tool-size-jitter-slider');

  final a = BrushToolState.defaults.copyWith(flow: 0.5, sizeJitter: 0.2);

  /// The panel the way the workspace drives it: the state it is handed is
  /// whatever the notifier holds, and a row's write lands in the notifier.
  Future<(ValueNotifier<BrushToolState>, List<BrushToolState>)> pumpPanel(
    WidgetTester tester, {
    bool libraryCallbacks = false,
  }) async {
    final notifier = ValueNotifier<BrushToolState>(a);
    addTearDown(notifier.dispose);
    final written = <BrushToolState>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<BrushToolState>(
              valueListenable: notifier,
              builder: (context, state, _) => BrushSettingsPanel(
                state: state,
                onChanged: (next) {
                  written.add(next);
                  notifier.value = next;
                },
                // NEW closures on every build, the way the workspace hands
                // them over.
                onTipImportRequested: libraryCallbacks ? () {} : null,
                onRenameTip: libraryCallbacks ? (_) {} : null,
                onDeleteTip: libraryCallbacks ? (_) {} : null,
              ),
            ),
          ),
        ),
      ),
    );
    return (notifier, written);
  }

  testWidgets('🚨a new brush keeps the rows whose numbers did not change — '
      'and rebuilds the ones that did', (tester) async {
    final (notifier, _) = await pumpPanel(tester);
    final jitter = tester.widget(find.byKey(jitterKey));
    final flow = tester.widget(find.byKey(flowKey));

    notifier.value = a.copyWith(flow: 0.9);
    await tester.pump();

    expect(
      identical(tester.widget(find.byKey(jitterKey)), jitter),
      isTrue,
      reason: 'the jitter row shows what it showed — the very instance, '
          'skipped whole',
    );
    expect(identical(tester.widget(find.byKey(flowKey)), flow), isFalse);
    expect(tester.widget<FieldSlider>(find.byKey(flowKey)).value, 0.9);
  });

  testWidgets('🚨a KEPT row writes the brush in hand NOW, not the one it was '
      'built with', (tester) async {
    final (notifier, written) = await pumpPanel(tester);
    notifier.value = a.copyWith(flow: 0.9);
    await tester.pump();
    final jitter = tester.widget<FieldSlider>(find.byKey(jitterKey));

    jitter.onChanged!(0.4);

    expect(written.last.sizeJitter, 0.4);
    expect(
      written.last.flow,
      0.9,
      reason: 'the row was built under a brush with flow 0.5; writing that '
          'brush back would undo the pick',
    );
  });

  testWidgets('a row that comes ALIVE with the new brush is rebuilt — the '
      'mixing rows follow the mixing switch', (tester) async {
    // The paint-amount row keeps its number between these two brushes; only
    // whether it takes the gesture changes, and a kept dead row would stay
    // dead under a brush that mixes.
    final (notifier, _) = await pumpPanel(tester);
    const amountKey = ValueKey<String>('brush-tool-paint-amount-slider');
    expect(
      tester.widget<FieldSlider>(find.byKey(amountKey)).onChanged,
      isNull,
      reason: 'premise: dead while the brush does not mix',
    );

    notifier.value = a.copyWith(mixesGroundColor: true);
    await tester.pump();

    expect(
      tester.widget<FieldSlider>(find.byKey(amountKey)).onChanged,
      isNotNull,
    );
  });

  testWidgets('🚨the tip rows are kept too — though the library hands the '
      'panel new callbacks on every build', (tester) async {
    final (notifier, _) = await pumpPanel(tester, libraryCallbacks: true);
    const tipKey = ValueKey<String>('brush-tip-picker-tip');
    final tip = tester.widget(find.byKey(tipKey));

    notifier.value = a.copyWith(flow: 0.9);
    await tester.pump();

    expect(identical(tester.widget(find.byKey(tipKey)), tip), isTrue);
  });

  testWidgets('a row whose pressure curve changed is rebuilt — its button '
      'draws the curve', (tester) async {
    final (notifier, _) = await pumpPanel(tester);
    final flow = tester.widget(find.byKey(flowKey));

    notifier.value = a.copyWith(
      flowPressureCurve: BrushPressureCurve.linearFrom(0.3),
    );
    await tester.pump();

    expect(identical(tester.widget(find.byKey(flowKey)), flow), isFalse);
  });

  testWidgets('🚨a new brush re-bakes the rows whose numbers changed and no '
      'other — every row is its own zone (H40, 2026-09-24)', (tester) async {
    final (notifier, _) = await pumpPanel(tester);
    RenderStaticRaster zoneOf(Key key) =>
        tester.renderObject<RenderStaticRaster>(
          find
              .ancestor(of: find.byKey(key), matching: find.byType(StaticRaster))
              .first,
        );
    final flow = zoneOf(flowKey);
    final jitter = zoneOf(jitterKey);
    expect(
      identical(flow, jitter),
      isFalse,
      reason: 'two rows, two zones — not one bake over the column',
    );
    final flowBakes = flow.captureCount;
    final jitterBakes = jitter.captureCount;
    expect(flowBakes, greaterThan(0), reason: 'fixture: the zones bake here');

    notifier.value = a.copyWith(flow: 0.9);
    await tester.pump();

    expect(flow.captureCount, flowBakes + 1, reason: 'the flow row changed');
    expect(
      jitter.captureCount,
      jitterBakes,
      reason: 'the jitter row shows the same number, so it is not painted '
          'or baked again',
    );
  });
}
