import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/dialogs/canvas_size_dialog.dart';

void main() {
  CanvasResizeRequest? dialogResult;

  Future<void> pumpOpenDialog(
    WidgetTester tester, {
    CanvasSize initialSize = const CanvasSize(width: 1920, height: 1080),
  }) async {
    dialogResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                dialogResult = await showDialog<CanvasResizeRequest>(
                  context: context,
                  builder: (context) =>
                      CanvasSizeDialog(initialSize: initialSize),
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
  }

  TextField fieldByKey(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey<String>(key)));

  // ButtonStyleButton, not a concrete kind: the window shell decides
  // whether the confirm action renders filled or quiet, and the test only
  // cares whether it is enabled.
  ButtonStyleButton confirmButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
      );

  testWidgets('prefills the current canvas size', (tester) async {
    await pumpOpenDialog(tester);

    expect(
      fieldByKey(tester, 'canvas-size-width-field').controller!.text,
      '1920',
    );
    expect(
      fieldByKey(tester, 'canvas-size-height-field').controller!.text,
      '1080',
    );
  });

  testWidgets('confirms with the entered size and the center anchor default', (
    tester,
  ) async {
    await pumpOpenDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '640',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-height-field')),
      '480',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(
      dialogResult,
      const CanvasResizeRequest(
        size: CanvasSize(width: 640, height: 480),
        anchor: CanvasResizeAnchor.center,
      ),
    );
  });

  testWidgets('confirms with a picked anchor', (tester) async {
    await pumpOpenDialog(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-anchor-bottomRight')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(dialogResult!.anchor, CanvasResizeAnchor.bottomRight);
    expect(dialogResult!.size, const CanvasSize(width: 1920, height: 1080));
  });

  testWidgets('disables confirm for empty or out-of-range input', (
    tester,
  ) async {
    await pumpOpenDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '',
    );
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '99999',
    );
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '800',
    );
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  // Pins the ceiling itself, not just "some big number is refused": the
  // number moved once (8192 -> 16384, user decision D4) and the old test
  // above stayed green through the move, because 99999 is out of range
  // either way. The numbers here are LITERAL on purpose: written as
  // ${CanvasSizeDialog.maxDimension} the test moves with the constant and
  // proves nothing about which number was agreed (verified -- it stayed
  // green when the constant was mutated back to 8192).
  testWidgets('confirm accepts 16384 and refuses 16385', (tester) async {
    await pumpOpenDialog(tester);

    for (final field in const <String>[
      'canvas-size-width-field',
      'canvas-size-height-field',
    ]) {
      await tester.enterText(find.byKey(ValueKey<String>(field)), '16384');
      await tester.pump();
      expect(
        confirmButton(tester).onPressed,
        isNotNull,
        reason: '$field must accept the agreed ceiling 16384',
      );

      await tester.enterText(find.byKey(ValueKey<String>(field)), '16385');
      await tester.pump();
      expect(
        confirmButton(tester).onPressed,
        isNull,
        reason: '$field must refuse 16385, one past the ceiling',
      );

      await tester.enterText(find.byKey(ValueKey<String>(field)), '800');
      await tester.pump();
    }
  });

  testWidgets('preset chip fills both fields', (tester) async {
    await pumpOpenDialog(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-preset-1280x720')),
    );
    await tester.pump();

    expect(
      fieldByKey(tester, 'canvas-size-width-field').controller!.text,
      '1280',
    );
    expect(
      fieldByKey(tester, 'canvas-size-height-field').controller!.text,
      '720',
    );
  });

  testWidgets('cancel pops without a result', (tester) async {
    await pumpOpenDialog(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(dialogResult, isNull);
  });
}
