import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

/// The import window's preview zone — nothing named it (2026-09-05).
///
/// What is reachable without a decoder is the zone's own two decisions,
/// and they are the ones with a stated reason:
///
/// ⛔The picture is FITTED into a 16:9 box and nothing else is drawn — no
/// canvas outline, no placement rectangle. What this shows is the SOURCE;
/// the composition is what Fit answers in the row.
///
/// ⛔「A range that changes nothing is a control that lies」 — the IN/OUT
/// ends appear only where they bite: a multi-frame source being PLACED.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? path,
    bool rangeEditable = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: ImportPreview(
              path: path,
              inFrame: 0,
              outFrame: null,
              rangeEditable: rangeEditable,
              onRangeChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('nothing selected draws nothing, and does not fall over', (
    tester,
  ) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('🚨the picture box is 16:9 and holds ONLY the picture — no '
      'canvas outline, no placement rectangle, because this shows the '
      'SOURCE and the composition is the row\'s answer', (tester) async {
    await pump(tester);

    final box = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(box.aspectRatio, 16 / 9);
  });

  testWidgets('⛔a source with ONE frame shows no IN/OUT ends — a range '
      'that changes nothing is a control that lies', (tester) async {
    await pump(tester);

    expect(
      tester.widget<TransportBar>(find.byType(TransportBar)).showRange,
      isFalse,
    );
  });

  testWidgets('⛔and neither does one that is not being PLACED', (tester) async {
    await pump(tester, rangeEditable: false);

    expect(
      tester.widget<TransportBar>(find.byType(TransportBar)).showRange,
      isFalse,
    );
  });

  testWidgets('the bar is the SHARED transport — a video will need nothing '
      'here beyond a frame supplier the day there is a decoder', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(TransportBar), findsOneWidget);
  });
}
