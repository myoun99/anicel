import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// BB-2 (R26 #9/#10/#11): the CSP-grouped brush settings — the ink
/// group's blend dropdown, the eraser lock, the retired color/tip rows,
/// and the hand-setting independence of size + blend.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required BrushToolState state,
    required ValueChanged<BrushToolState> onChanged,
    AppLanguage language = AppLanguage.en,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: BrushSettingsPanel(
                state: state,
                onChanged: onChanged,
                language: language,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the ink group carries the blend dropdown: picking 乗算 '
      'commits multiply, and ja reads the CSP term', (tester) async {
    var state = BrushToolState.defaults;
    await pumpPanel(
      tester,
      state: state,
      onChanged: (next) => state = next,
      language: AppLanguage.ja,
    );

    final button = find.byKey(
      const ValueKey<String>('brush-tool-blend-menu-button'),
    );
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('通常')),
      findsOneWidget,
      reason: 'the resting label IS the current mode, CSP Japanese',
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tool-blend-multiply')),
    );
    await tester.pumpAndSettle();
    expect(state.brushBlendMode, BrushBlendMode.multiply);
  });

  testWidgets('the ERASER locks the blend to 消去 — no flyout, a lock '
      'chip instead', (tester) async {
    await pumpPanel(
      tester,
      state: BrushToolState.defaults.copyWith(tool: CanvasTool.eraser),
      onChanged: (_) {},
      language: AppLanguage.ja,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-blend-locked')),
      findsOneWidget,
    );
    expect(find.text('消去'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('brush-tool-blend-menu-button')),
      findsNothing,
    );
  });

  testWidgets('R26 #11: the color swatches and the tip shape segment are '
      'GONE from the settings panel', (tester) async {
    await pumpPanel(
      tester,
      state: BrushToolState.defaults,
      onChanged: (_) {},
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-tip-shape-toggle')),
      findsNothing,
    );
    expect(find.text('Round'), findsNothing);
    expect(find.text('Black'), findsNothing, reason: 'no swatch chips');
  });

  test('R26 #10: size and the brush blend are HAND settings — presets '
      'neither carry nor overwrite them', () {
    final tuned = BrushToolState(
      size: 42,
      brushBlendMode: BrushBlendMode.multiply,
    );
    // A preset built from someone else's settings...
    final applied = BrushToolState.fromBrushSettings(
      BrushToolState(size: 3).toBrushSettings(),
    );
    expect(
      applied.brushBlendMode,
      BrushBlendMode.color,
      reason: 'not preset payload',
    );
    // ...and the preset-apply site carries the live values over.
    final preserved = applied.copyWith(
      size: tuned.size,
      brushBlendMode: tuned.brushBlendMode,
    );
    expect(preserved.size, 42);
    expect(preserved.brushBlendMode, BrushBlendMode.multiply);
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
        .copyWith(brushBlendMode: BrushBlendMode.erase)
        .toInputSettings();
    expect(eraseBlend.erase, isTrue);
    expect(eraseBlend.blendMode, BrushBlendMode.erase);
    final multiply = BrushToolState.defaults
        .copyWith(brushBlendMode: BrushBlendMode.multiply)
        .toInputSettings();
    expect(multiply.erase, isFalse);
    expect(multiply.blendMode, BrushBlendMode.multiply);
  });
}
