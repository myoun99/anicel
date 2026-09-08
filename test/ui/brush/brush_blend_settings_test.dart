import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// BB-2 (R26 #9/#11): the CSP-grouped brush settings — the retired
/// color/tip rows, and where the blend lives now that R26 #10 is gone.
///
/// The blend DROPDOWN itself is no longer here. It moved to the top strip
/// with size and opacity, so its widget tests live in
/// `test/ui/menu/editor_top_strip_test.dart`.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required BrushToolState state,
    required ValueChanged<BrushToolState> onChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: BrushSettingsPanel(state: state, onChanged: onChanged),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('R26 #11: the color swatches and the tip shape segment are '
      'GONE from the settings panel', (tester) async {
    await pumpPanel(tester, state: BrushToolState.defaults, onChanged: (_) {});
    expect(
      find.byKey(const ValueKey<String>('brush-tool-tip-shape-toggle')),
      findsNothing,
    );
    expect(find.text('Round'), findsNothing);
    expect(find.text('Black'), findsNothing, reason: 'no swatch chips');
  });

  testWidgets('size, opacity and blend LEFT this panel for the strip — one '
      'number, one place to read it (유저 확정)', (tester) async {
    await pumpPanel(tester, state: BrushToolState.defaults, onChanged: (_) {});

    for (final gone in [
      'brush-tool-size-slider',
      'brush-tool-opacity-slider',
      'brush-tool-blend-menu-button',
      // The pressure curves went WITH their values: a curve belongs
      // beside the number it shapes.
      'brush-tool-pressure-size',
      'brush-tool-pressure-opacity',
    ]) {
      expect(
        find.byKey(ValueKey<String>(gone)),
        findsNothing,
        reason: '$gone belongs to the top strip now',
      );
    }

    // What stays: the settings a hand does NOT change mid-stroke.
    expect(
      find.byKey(const ValueKey<String>('brush-tool-flow-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-hardness-slider')),
      findsOneWidget,
    );
  });

  test('⛔R26 #10 IS RETIRED: the blend is the BRUSH\'s, so a preset both '
      'carries it and applies it (유저 2026-09-08)', () {
    // The old law was 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지
    // 않음」 and this test used to pin exactly that. 유저 replaced it:
    // 「툴/손 설정 구분 없애고 모든 설정이 내보낼때 나르도록」.
    final tuned = BrushToolState(size: 42, blendMode: BrushBlendMode.multiply);

    // It travels through the preset payload, both ways...
    expect(tuned.toBrushSettings().blendMode, BrushBlendMode.multiply);
    expect(
      BrushToolState.fromBrushSettings(tuned.toBrushSettings()).blendMode,
      BrushBlendMode.multiply,
    );

    // ...and picking a brush wears the brush's blend, not the hand's.
    final applied = BrushToolState(
      blendMode: BrushBlendMode.screen,
    ).withPresetSettings(tuned.toBrushSettings(), tool: CanvasTool.brush);
    expect(applied.blendMode, BrushBlendMode.multiply);
    expect(applied.size, 42, reason: 'H25: a brush wears its own size too');
  });

  test('the eraser tool and the erase blend both ride the dab erase flag '
      'into the input settings; separable modes pass through', () {
    expect(
      BrushToolState.defaults
          .copyWith(tool: CanvasTool.eraser)
          .toInputSettings()
          .erase,
      isTrue,
    );
    final eraseBlend = BrushToolState.defaults
        .copyWith(blendMode: BrushBlendMode.erase)
        .toInputSettings();
    expect(eraseBlend.erase, isTrue);
    expect(eraseBlend.blendMode, BrushBlendMode.erase);
    final multiply = BrushToolState.defaults
        .copyWith(blendMode: BrushBlendMode.multiply)
        .toInputSettings();
    expect(multiply.erase, isFalse);
    expect(multiply.blendMode, BrushBlendMode.multiply);
  });
}
