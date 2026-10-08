// THE CAMERA SIZE DIALOG: A PRESET PICKED FROM ITS LIST FILLS BOTH FIELDS
// AND APPLY POPS THAT SIZE; AN OUT-OF-RANGE DIMENSION LEAVES APPLY DEAD;
// CANCEL POPS NOTHING; 「캔버스에서 조정」 HANDS THE SIZE TO THE CANVAS.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, through the fields and the list it keys.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/dialogs/camera_size_dialog.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

void main() {
  Future<List<CanvasSize?>> open(
    WidgetTester tester, {
    VoidCallback? onAdjustOnCanvas,
  }) async {
    final results = <CanvasSize?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showCameraSizeDialog(
                    context,
                    initialSize: const CanvasSize(width: 1920, height: 1080),
                    onAdjustOnCanvas: onAdjustOnCanvas,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('camera-size-dialog')),
      findsOneWidget,
    );
    return results;
  }

  List<PanelFlyoutEntry> presets(WidgetTester tester) => tester
      .widget<PanelFlyoutButton>(
        find.byKey(const ValueKey<String>('camera-size-presets')),
      )
      .entriesBuilder();

  // 🗣️I-80 (유저 2026-10-06): 「카메라 크기 창도 버튼들 이제 리스트팝오버로서
  // 여러 프리셋 준비해서 거기서 선택하는방식으로. 선택하면 적용되서 숫자
  // 바뀌는느낌」.
  testWidgets('a preset picked from the list fills both fields and apply '
      'pops that size', (tester) async {
    final results = await open(tester);
    expect(
      find.byKey(const ValueKey<String>('camera-size-preset-1280x720')),
      findsNothing,
      reason: 'the presets are a list, not chips on the window',
    );

    await tester.tap(find.byKey(const ValueKey<String>('camera-size-presets')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-preset-1280x720')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('camera-size-width-field')),
          )
          .controller!
          .text,
      '1280',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(results, [const CanvasSize(width: 1280, height: 720)]);
  });

  testWidgets('the list holds qHD, then the screens\' sizes the canvas '
      'window offers, and marks the one the fields hold', (tester) async {
    await open(tester);
    final entries = presets(tester);

    expect(
      [
        for (final entry in entries)
          if (entry is PanelFlyoutItem) (entry.keyValue, entry.label),
      ],
      [
        ('camera-size-preset-960x540', 'qHD 960×540'),
        ('camera-size-preset-1280x720', 'HD 1280×720'),
        ('camera-size-preset-1920x1080', 'FHD 1920×1080'),
        ('camera-size-preset-2560x1440', '2K 2560×1440'),
        ('camera-size-preset-3840x2160', '4K 3840×2160'),
      ],
    );
    expect(
      [
        for (final row in entries.whereType<PanelFlyoutItem>())
          if (row.selected) row.keyValue,
      ],
      ['camera-size-preset-1920x1080'],
      reason: 'the window opened on 1920 × 1080',
    );
  });

  // 🗣️I-80 (유저 2026-10-06): 「캔버스 사이즈 변경하는것처럼 같은 로직 최대한
  // 재사용/법통일하면서 캔버스에서 카메라 사이즈 보면서 변경하게」.
  testWidgets('🚨「캔버스에서 조정」 closes the window and opens the camera\'s '
      'adjust on the canvas — and stays, greyed, where there is nothing to '
      'open', (tester) async {
    var opened = 0;
    final results = await open(tester, onAdjustOnCanvas: () => opened += 1);
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-adjust-on-canvas')),
    );
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(
      find.byKey(const ValueKey<String>('camera-size-dialog')),
      findsNothing,
      reason: 'the window steps aside for the canvas',
    );
    expect(results, [null], reason: 'nothing resized from the window');

    await open(tester);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('camera-size-adjust-on-canvas')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('an out-of-range width leaves apply dead', (tester) async {
    final results = await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('camera-size-width-field')),
      '0',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-apply-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('camera-size-dialog')),
      findsOneWidget,
    );
    expect(results, isEmpty);
  });

  testWidgets('cancel pops nothing', (tester) async {
    final results = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('camera-size-dialog')),
      findsNothing,
    );
    expect(results, [null]);
  });
}
