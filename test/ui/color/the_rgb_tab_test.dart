import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/color/color_rgb_panel.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// The RGB tab — the same colour said in the three numbers a spec sheet, a
/// client's note and a paint bucket all speak. Nothing named it
/// (2026-09-05).
///
/// ⛔The bars carry NO numeric entry of their own: typing a channel is the
/// status bar's job, one tap on the number itself, so the window has one
/// place where numbers are typed rather than three.
void main() {
  Future<int?> pumpPanel(WidgetTester tester, int color) async {
    int? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ColorRgbPanel(
              color: color,
              onColorChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );
    return changed;
  }

  FieldSlider sliderAt(WidgetTester tester, String channel) => tester
      .widget<FieldSlider>(find.byKey(ValueKey<String>('color-rgb-$channel')));

  testWidgets('the three bars show the colour\'s own channels', (tester) async {
    await pumpPanel(tester, 0xFF1A2B3C);

    expect(sliderAt(tester, 'r').value, 0x1A.toDouble());
    expect(sliderAt(tester, 'g').value, 0x2B.toDouble());
    expect(sliderAt(tester, 'b').value, 0x3C.toDouble());
  });

  testWidgets('🚨each bar is 0..255 in WHOLE steps — a channel is a byte, '
      'so the bar must not hand 137.4 to one', (tester) async {
    await pumpPanel(tester, 0xFF000000);

    for (final channel in ['r', 'g', 'b']) {
      final slider = sliderAt(tester, channel);
      expect(slider.min, 0, reason: channel);
      expect(slider.max, 255, reason: channel);
      expect(slider.divisions, 255, reason: channel);
    }
  });

  testWidgets('⛔no bar carries its own numeric FIELD — the window types '
      'numbers in one place', (tester) async {
    await pumpPanel(tester, 0xFF1A2B3C);

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('🚨moving ONE bar leaves the other two channels alone', (
    tester,
  ) async {
    int? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ColorRgbPanel(
              color: 0xFF1A2B3C,
              onColorChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );

    final slider = sliderAt(tester, 'g');
    slider.onChanged!(200);
    await tester.pump();

    expect(changed, isNotNull);
    expect((changed! >> 16) & 0xFF, 0x1A, reason: 'red untouched');
    expect((changed! >> 8) & 0xFF, 200, reason: 'green is what moved');
    expect(changed! & 0xFF, 0x3C, reason: 'blue untouched');
  });

  testWidgets('a moved bar always reports an OPAQUE colour — this app\'s '
      'colours are opaque and alpha lives on the layer', (tester) async {
    int? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ColorRgbPanel(
              color: 0x00000000,
              onColorChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );

    sliderAt(tester, 'r').onChanged!(10);
    await tester.pump();

    expect(changed! >>> 24, 0xFF);
  });

  test('🚨the panel PROMISES its height, so the host can hand it the room — '
      'three fixed bars and the two gaps between them, with nothing here '
      'that can shrink', () {
    expect(ColorRgbPanel.contentHeight, 3 * 24 + 2 * 8);
  });

  testWidgets('🐛the gap is BETWEEN the bars, not under the last — the '
      'trailing 8px used to pad the panel\'s own padding and overflow the '
      'box by 7', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: ColorRgbPanel.contentHeight,
            child: ColorRgbPanel(color: 0xFF000000, onColorChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'the stack fits its promised height exactly',
    );
  });
}
