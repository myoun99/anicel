import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings_row.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/setting_source_button.dart';
import 'package:anicel/src/ui/widgets/tip_direction_popup.dart';

/// 向き behind one button beside the angle (F-176-Q6, 유저 2026-10-21
/// 「클튜처럼 — 각도 옆 버튼 하나」): the base the tip turns from and its
/// random turn, in the window that button opens.
void main() {
  const button = ValueKey<String>(TipDirectionButton.keyValue);
  const jitter = ValueKey<String>('brush-tool-angle-jitter-slider');

  /// The panel the way the workspace drives it: a row's write lands in the
  /// notifier, and the panel is rebuilt from it.
  Future<ValueNotifier<BrushToolState>> pumpPanel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(shown: {BrushSettingsRow.angle}),
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<BrushToolState>(
              valueListenable: notifier,
              builder: (context, state, _) => BrushSettingsPanel(
                state: state,
                onChanged: (next) => notifier.value = next,
              ),
            ),
          ),
        ),
      ),
    );
    return notifier;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(button));
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
  }

  test('every base is offered, each once', () {
    expect(tipDirectionBases.toSet(), BrushTipRotationMode.values.toSet());
    expect(tipDirectionBases, hasLength(BrushTipRotationMode.values.length));
  });

  testWidgets('the angle is one row: the base and the random turn are not '
      'rows of their own, but behind the button in its end slot', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.byKey(button), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('brush-tool-rotation-menu-button')),
      findsNothing,
    );
    expect(find.byKey(jitter), findsNothing);

    await open(tester);
    expect(find.byKey(jitter), findsOneWidget);
    for (final base in BrushTipRotationMode.values) {
      expect(
        find.byKey(ValueKey<String>('brush-tool-rotation-${base.name}')),
        findsOneWidget,
        reason: '${base.name} is offered',
      );
    }
    expect(tester.takeException(), isNull, reason: 'the window fits');
  });

  testWidgets('the button shows the off mark while the angle stands alone, '
      'and lights while a base turns the tip or the random turn is up', (
    tester,
  ) async {
    bool active() => tester
        .widget<SettingSourceButton>(find.byType(SettingSourceButton))
        .active;

    for (final (direction, lit) in [
      ((base: BrushTipRotationMode.fixed, random: 0.0), false),
      ((base: BrushTipRotationMode.penTilt, random: 0.0), true),
      ((base: BrushTipRotationMode.fixed, random: 0.3), true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TipDirectionButton(
                direction: direction,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(active(), lit, reason: '$direction');
    }
  });

  testWidgets('🚨the window hands back the whole setting each time — a base '
      'picked, then the random turn, keeps the base', (tester) async {
    final notifier = await pumpPanel(tester);
    await open(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tool-rotation-penTilt')),
    );
    await tester.pumpAndSettle();
    expect(notifier.value.rotationMode, BrushTipRotationMode.penTilt);

    await tester.drag(find.byKey(jitter), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(notifier.value.angleJitter, greaterThan(0));
    expect(
      notifier.value.rotationMode,
      BrushTipRotationMode.penTilt,
      reason: 'the random turn written off the brush the button was built '
          'over would put the base back',
    );

    // …and the other way round: a base picked after the random turn keeps
    // the random turn.
    final random = notifier.value.angleJitter;
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tool-rotation-direction')),
    );
    await tester.pumpAndSettle();
    expect(notifier.value.rotationMode, BrushTipRotationMode.direction);
    expect(notifier.value.angleJitter, random);

    // The button in the angle row shows the setting the window left — the
    // panel hands a row back only while it shows the same thing.
    expect(
      tester.widget<TipDirectionButton>(find.byType(TipDirectionButton))
          .direction,
      (base: BrushTipRotationMode.direction, random: random),
    );
  });

  testWidgets('a dead source button opens nothing — the angle\'s and the '
      'pressure curve\'s alike', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SettingSourceButton(
              keyValue: 'dead-source-button',
              tooltip: 'dead',
              active: true,
              enabled: false,
              onPressed: (_) => fail('a dead button was pressed'),
              glyph: (ink) => _NoGlyph(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('dead-source-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey<String>('dead-source-button')),
          )
          .onTap,
      isNull,
      reason: 'the well looks dead — no ink, no hover — by having no tap '
          '(`silentPress`)',
    );
  });

  testWidgets('the lit base is the one the tip turns from — 「선택 표시는 '
      '색상만」', (tester) async {
    await pumpPanel(tester);
    await open(tester);
    // The colour the name is drawn in, not a flag beside it: the colour
    // is the whole of the mark.
    bool lit(BrushTipRotationMode base) =>
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(
                  ValueKey<String>('brush-tool-rotation-${base.name}'),
                ),
                matching: find.byType(Text),
              ),
            )
            .style!
            .color ==
        AppColors.accent;

    expect(lit(BrushTipRotationMode.fixed), isTrue);
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tool-rotation-direction')),
    );
    await tester.pumpAndSettle();
    expect([for (final base in tipDirectionBases) lit(base)], [
      for (final base in tipDirectionBases)
        base == BrushTipRotationMode.direction,
    ]);
  });
}

class _NoGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_NoGlyph oldDelegate) => false;
}
