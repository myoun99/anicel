import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🚨★★★A BOX THE PARENT PROMISED IS NOT OURS TO ROUND.
///
/// [AppIconButton] quantizes a size TOKEN onto the device grid — that is a
/// style choice about the app's own buttons, and it is what keeps a toolbar
/// row's painted edges on whole device pixels. An [AppIconButtonBox] is a
/// different thing: a number the surrounding layout was built around before
/// the button existed, which is why the four rail files were allowed to
/// hand-roll at all. Rounding one is not a style choice, it is breaking a
/// promise.
///
/// ⛔THE DEFAULT TEST ENVIRONMENT CANNOT SEE THIS. At the ratios a widget
/// test runs at, `position()` is the identity for every number these
/// buttons use — a first attempt at this check mutated the guard away and
/// measured **44 buttons unchanged**, which proves nothing at all. The ratio
/// below is the one the grid's own doc names as the case that bites:
/// `1.5 × 0.7`, where a bare floor moves a correct 20 by a whole pixel.
void main() {
  // Monitor × UI scale, as the compositor computes it.
  const ratio = 1.5 * 0.7;

  Future<Rect> boxOf(
    WidgetTester tester,
    AppIconButtonMetrics metrics,
    String key,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectiveDevicePixelRatio(
            ratio: ratio,
            child: Center(
              child: AppIconButton(
                keyValue: key,
                tooltip: 't',
                size: metrics,
                icon: const Icon(Icons.circle),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(ValueKey<String>(key)));
  }

  test('the grid really does move these numbers', () {
    // ⛔THE CONTROL FOR THE CONTROL. If `position` were the identity here,
    // every assertion below would pass on a broken guard — which is exactly
    // how the first version of this file measured nothing.
    const grid = DeviceGrid(ratio);
    expect(grid.isActive, isTrue);
    expect(
      grid.position(26),
      isNot(26.0),
      reason: 'a 26px rail slot is what the guard is protecting',
    );
  });

  testWidgets('a promised box lands EXACTLY, whatever the grid says', (
    tester,
  ) async {
    final box = await boxOf(
      tester,
      const AppIconButtonBox(width: 20, height: 26, iconSize: 15),
      'promised',
    );
    expect(
      box.width,
      20.0,
      reason: 'the rail promised 20 and the rail gets 20',
    );
    expect(
      box.height,
      26.0,
      reason:
          'the grid would have made this 25.71 — a quarter pixel per row, '
          'which is the slot drift [[widget-between-slot-and-plate]] is the '
          'record of',
    );
  });

  testWidgets('a TOKEN is still quantized — the guard is narrow', (
    tester,
  ) async {
    // ⛔Not a formality. A guard that skipped quantization for everything
    // would pass the test above and quietly undo the reason `grid.position`
    // is called here at all.
    final box = await boxOf(tester, AppIconButtonSize.strip, 'token');
    expect(
      box.width,
      isNot(AppIconButtonSize.strip.maxWidth),
      reason: 'a token still lands on the device grid',
    );
  });
}
