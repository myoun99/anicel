import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/ui/color/color_palettes.dart';
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
            palette: ColorPaletteState.starter('Palette 1'),
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
    final scrollers = find.descendant(
      of: find.byType(ColorPickerPanel),
      matching: find.byType(Scrollable),
    );
    await pump(tester, ColorPickerKind.wheel);
    expect(scrollers, findsNothing);

    await pump(tester, ColorPickerKind.rgb);
    expect(scrollers, findsNothing);

    await pump(tester, ColorPickerKind.palette);
    expect(scrollers, findsOneWidget);
  });

  testWidgets('🚨each kind PUBLISHES what it cannot shrink below, so the dock '
      'that hands out heights can honour it — the RGB bars, and under the '
      'wheel and the bars the default palette (I-131)', (tester) async {
    late BuildContext at1x;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            at1x = context;
            return const SizedBox();
          },
        ),
      ),
    );
    // Its places stop at 24 a side: padding, the recent row, a gap and
    // the palette's three rows.
    const underPicker = 8 + 24 + 8 + (3 * 24 + 2 * 4) + 8;
    expect(PaletteUnderPicker.maxExtent, underPicker);
    expect(
      ColorPickerPanel.contentExtentIn(at1x, ColorPickerKind.rgb),
      ColorRgbPanel.contentHeight + 18 + underPicker + ColorStatusBar.height,
      reason: 'at 1× the status bar is the height it was drawn at',
    );
    expect(
      ColorPickerPanel.contentExtentIn(at1x, ColorPickerKind.wheel),
      2 * ColorWheelPanel.inset + underPicker + ColorStatusBar.height,
    );
    expect(
      ColorPickerPanel.contentExtentIn(at1x, ColorPickerKind.palette),
      isNull,
      reason: 'the palette scrolls its own',
    );
  });

  testWidgets('the default palette stands under the wheel and the RGB bars, '
      'and not in the palette panel, which shows every palette itself', (
    tester,
  ) async {
    for (final kind in ColorPickerKind.values) {
      await pump(tester, kind);
      expect(
        find.byType(PaletteUnderPicker),
        kind == ColorPickerKind.palette ? findsNothing : findsOneWidget,
        reason: '$kind',
      );
    }
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
