import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/ui/dialogs/ruler_marker_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/ruler_marker_palette.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/text_finders.dart';

/// 🗣️I-169 — a ruler marker's window. What was told of it and taken
/// (2026-11-13): a one-line text, six colours, a length in frames, and
/// 삭제 / 취소 / 확인 — Enter is 확인, as in an SE block's window (F-584).
/// And of the length (I-169-Q4): 「구간 정하는건 마커 편집창에서만
/// 하도록하고」.
void main() {
  const text = ValueKey<String>('ruler-marker-text-field');
  const length = 'ruler-marker-length-field';
  const ok = ValueKey<String>('instance-edit-ok-button');
  const cancel = ValueKey<String>('instance-edit-cancel-button');
  const delete = ValueKey<String>('instance-edit-delete-button');

  /// Opens the window on [marker] through a real route, and says what it
  /// popped — `(true, result)` once it has closed.
  Future<(bool, RulerMarkerDialogResult?) Function()> open(
    WidgetTester tester,
    RulerMarker marker, {
    bool editing = false,
  }) async {
    var closed = false;
    RulerMarkerDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showDialog<RulerMarkerDialogResult>(
                  context: context,
                  builder: (_) =>
                      RulerMarkerDialog(marker: marker, editing: editing),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => (closed, result);
  }

  /// The colours' strip — the length's field holds a strip of its own (the
  /// way a count is typed).
  PillStrip colours(WidgetTester tester) => tester.widget<PillStrip>(
    find.ancestor(
      of: find.byKey(const ValueKey<String>('ruler-marker-color-yellow')),
      matching: find.byType(PillStrip),
    ),
  );

  PillItem pill(WidgetTester tester, RulerMarkerColor color) =>
      colours(tester).items.singleWhere(
        (item) => item.keyValue == 'ruler-marker-color-${color.name}',
      );

  String shown(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.anyText(),
        ),
      )
      .data!;

  testWidgets('opens on the marker as it stands — its text, its colour lit '
      'among the six, its length — and hands it back unchanged on 확인', (
    tester,
  ) async {
    const marker = RulerMarker(
      start: 12,
      length: 4,
      text: '口パク',
      color: RulerMarkerColor.sky,
    );
    final popped = await open(tester, marker, editing: true);

    expect(find.text(AppText.strings.rulerMarkerEditTitle), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(text)).controller!.text, '口パク');
    expect(shown(tester, length), '4');
    final strip = colours(tester);
    expect(
      [for (final item in strip.items) item.keyValue],
      [
        for (final color in RulerMarkerColor.values)
          'ruler-marker-color-${color.name}',
      ],
      reason: 'ONE strip of the six, in the order they are filed',
    );
    expect(
      [
        for (final item in strip.items)
          if (item.selected) item.keyValue,
      ],
      ['ruler-marker-color-sky'],
    );
    for (final color in RulerMarkerColor.values) {
      final swatch = pill(tester, color).leading! as DecoratedBox;
      expect(
        (swatch.decoration as BoxDecoration).color,
        rulerMarkerRibbon(color),
        reason: 'each pill wears its ribbon\'s colour before its name',
      );
    }

    await tester.tap(find.byKey(ok));
    await tester.pumpAndSettle();
    expect(popped().$2?.marker, marker);
  });

  testWidgets('🚨Enter in the text is the window\'s 확인, and hands back '
      'the text as typed — a space is a glyph\'s place', (tester) async {
    final popped = await open(tester, const RulerMarker(start: 3));
    expect(find.text(AppText.strings.rulerMarkerNewTitle), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(text)).autofocus,
      isTrue,
      reason: 'the window opens with the keyboard on the text',
    );
    expect(tester.widget<TextField>(find.byKey(text)).maxLines, 1);

    await tester.enterText(find.byKey(text), ' A パート ');
    await tester.showKeyboard(find.byKey(text));
    final asked = tester.testTextInput.setClientArgs!['inputAction'] as String;
    await tester.testTextInput.receiveAction(
      TextInputAction.values.firstWhere((action) => '$action' == asked),
    );
    await tester.pumpAndSettle();

    expect(
      popped(),
      isA<(bool, RulerMarkerDialogResult?)>().having(
        (answer) => answer.$1,
        'closed',
        isTrue,
      ),
    );
    expect(
      popped().$2?.marker,
      const RulerMarker(start: 3, text: ' A パート '),
      reason: 'where it was opened, a frame long, yellow — a new one',
    );
  });

  testWidgets('the colour picked and the length typed come back — and a '
      'marker runs a frame at least', (tester) async {
    final popped = await open(tester, const RulerMarker(start: 3, text: 'x'));

    await tester.tap(
      find.byKey(const ValueKey<String>('ruler-marker-color-violet')),
    );
    await tester.pump();
    expect(pill(tester, RulerMarkerColor.violet).selected, isTrue);
    expect(pill(tester, RulerMarkerColor.yellow).selected, isFalse);

    await typeOnThePad(tester, length, '6');
    expect(shown(tester, length), '6');
    await typeOnThePad(tester, length, '0');
    expect(
      shown(tester, length),
      '1',
      reason: 'a marker of no frames is the marker that stands on one',
    );
    await typeOnThePad(tester, length, '6');

    await tester.tap(find.byKey(ok));
    await tester.pumpAndSettle();
    expect(
      popped().$2?.marker,
      const RulerMarker(
        start: 3,
        length: 6,
        text: 'x',
        color: RulerMarkerColor.violet,
      ),
    );
  });

  testWidgets('삭제 is offered on a marker that stands, and takes it off; a '
      'new one is offered none', (tester) async {
    final popped = await open(
      tester,
      const RulerMarker(start: 3, text: 'x'),
      editing: true,
    );
    await tester.tap(find.byKey(delete));
    await tester.pumpAndSettle();
    final (closed, result) = popped();
    expect(closed, isTrue);
    expect(result, isNotNull);
    expect(result!.marker, isNull, reason: 'the answer that takes it off');

    await open(tester, const RulerMarker(start: 3));
    expect(find.byKey(delete), findsNothing);
  });

  testWidgets('취소 hands back nothing', (tester) async {
    final popped = await open(
      tester,
      const RulerMarker(start: 3, text: 'x'),
      editing: true,
    );
    await tester.enterText(find.byKey(text), 'changed');
    await tester.tap(find.byKey(cancel));
    await tester.pumpAndSettle();
    expect(popped(), (true, null));
  });
}
