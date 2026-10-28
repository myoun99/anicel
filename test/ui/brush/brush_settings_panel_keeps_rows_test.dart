import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings_row.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🔬H40 (유저 2026-09-11): 「고르는 프레임에서 끝나더라도 지금 안그래도 고를때
/// 렉있어서 그부분도 효율적으로 가볍게 하고싶어」 — with the settings open, a
/// pick rebuilt every row of this panel, the ones two brushes share included.
void main() {
  const flowKey = ValueKey<String>('brush-tool-flow-slider');
  const angleKey = ValueKey<String>('brush-tool-angle-slider');

  // Every row shown: what this pins is the rows, not which a brush shows.
  final a = BrushToolState.defaults.copyWith(
    flow: 0.5,
    angleJitter: 0.2,
    shown: BrushSettingsRow.values.toSet(),
  );

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
    final angle = tester.widget(find.byKey(angleKey));
    final flow = tester.widget(find.byKey(flowKey));

    notifier.value = a.copyWith(flow: 0.9);
    await tester.pump();

    expect(
      identical(tester.widget(find.byKey(angleKey)), angle),
      isTrue,
      reason: 'the angle row shows what it showed — the very instance, '
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
    final angle = tester.widget<FieldSlider>(find.byKey(angleKey));

    angle.onChanged!(40);

    expect(written.last.angleDegrees, 40);
    expect(
      written.last.flow,
      0.9,
      reason: 'the row was built under a brush with flow 0.5; writing that '
          'brush back would undo the pick',
    );
  });

  testWidgets('🚨rows that come with the new brush are built — and the rows '
      'between them are still kept, though their places moved', (
    tester,
  ) async {
    // 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」 —
    // the mixing rows are there only while the brush mixes, and the 後補正's
    // switches only while it corrects. Two places at once: the framework
    // matches what stands between them by key alone. ↩️The rows stood DEAD
    // and this asked that a row coming ALIVE was rebuilt.
    final (notifier, _) = await pumpPanel(tester);
    const amountKey = ValueKey<String>('brush-tool-paint-amount-slider');
    const bezierKey = ValueKey<String>('brush-tool-post-bezier-toggle');
    const scatterKey = ValueKey<String>('brush-tool-scatter-slider');
    expect(find.byKey(amountKey), findsNothing, reason: '⛔premise');
    expect(find.byKey(bezierKey), findsNothing, reason: '⛔premise');
    final scatter = tester.widget(find.byKey(scatterKey));

    notifier.value = a.copyWith(
      mixesGroundColor: true,
      correction: const BrushCorrection(postStrength: 20),
    );
    await tester.pump();

    expect(find.byKey(amountKey), findsOneWidget);
    expect(find.byKey(bezierKey), findsOneWidget);
    expect(
      identical(tester.widget(find.byKey(scatterKey)), scatter),
      isTrue,
      reason: 'the scatter row shows what it showed — the very instance, '
          'skipped whole where it stands now',
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
}
