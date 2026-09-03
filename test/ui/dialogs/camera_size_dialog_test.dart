// THE CAMERA SIZE DIALOG: A PRESET FILLS BOTH FIELDS AND APPLY POPS THAT
// SIZE; AN OUT-OF-RANGE DIMENSION LEAVES APPLY DEAD; CANCEL POPS NOTHING.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, through the fields and chips it keys.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/dialogs/camera_size_dialog.dart';

void main() {
  Future<List<CanvasSize?>> open(WidgetTester tester) async {
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

  testWidgets('a preset fills both fields and apply pops that size', (
    tester,
  ) async {
    final results = await open(tester);
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
