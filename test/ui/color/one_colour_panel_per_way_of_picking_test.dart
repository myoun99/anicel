import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/ui/color/color_panels.dart';
import 'package:anicel/src/ui/color/color_rgb_panel.dart';
import 'package:anicel/src/ui/color/color_status_bar.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart';

/// One colour panel: a way of picking, over the reading they all share.
/// Nothing named it (2026-09-05).
///
/// ⛔These are PANELS, not tabs of a panel (유저, R2 #8): a rail group's
/// icon strip used to sit directly above a second strip belonging to the
/// thing inside it, asking "which panel am I in" and "how am I picking" in
/// the same place twice.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ColorPickerKind kind, {
    int color = 0xFF1A2B3C,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: ColorPickerPanel(
            kind: kind,
            color: color,
            palette: const ColorPaletteState(),
            onColorChanged: (_) {},
            onPaletteChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('🚨the status bar is the SAME widget under every kind — "what '
      'colour am I on" never moves when you switch panels', (tester) async {
    for (final kind in ColorPickerKind.values) {
      await pump(tester, kind);
      expect(find.byType(ColorStatusBar), findsOneWidget, reason: '$kind');
    }
  });

  testWidgets('each kind shows its OWN picker and only that one', (
    tester,
  ) async {
    await pump(tester, ColorPickerKind.wheel);
    expect(find.byType(ColorWheelPanel), findsOneWidget);
    expect(find.byType(ColorRgbPanel), findsNothing);

    await pump(tester, ColorPickerKind.rgb);
    expect(find.byType(ColorRgbPanel), findsOneWidget);
    expect(find.byType(ColorWheelPanel), findsNothing);
  });

  testWidgets('⛔the wheel and the RGB bars do NOT scroll — the scroll view '
      'belongs to the palette', (tester) async {
    await pump(tester, ColorPickerKind.wheel);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await pump(tester, ColorPickerKind.rgb);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await pump(tester, ColorPickerKind.palette);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  test('🚨the RGB extent PUBLISHES what the panel costs, so the dock that '
      'hands out heights can honour it — the bars are the one picker with '
      'nothing that can shrink', () {
    expect(
      ColorPickerPanel.rgbContentExtent,
      ColorRgbPanel.contentHeight + 18 + ColorStatusBar.height,
    );
  });

  test('the three kinds are the three ways of picking', () {
    expect(ColorPickerKind.values, [
      ColorPickerKind.wheel,
      ColorPickerKind.rgb,
      ColorPickerKind.palette,
    ]);
  });

  testWidgets('the colour is CONTROLLED — an eyedropper landing while the '
      'panel is open moves what it shows', (tester) async {
    await pump(tester, ColorPickerKind.rgb, color: 0xFF102030);
    expect(
      tester.widget<ColorRgbPanel>(find.byType(ColorRgbPanel)).color,
      0xFF102030,
    );

    await pump(tester, ColorPickerKind.rgb, color: 0xFF405060);
    expect(
      tester.widget<ColorRgbPanel>(find.byType(ColorRgbPanel)).color,
      0xFF405060,
    );
  });
}
