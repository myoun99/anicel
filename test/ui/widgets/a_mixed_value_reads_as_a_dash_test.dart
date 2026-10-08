import 'package:anicel/src/ui/color/color_status_bar.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️R9-rest, the tool settings 유저 took on 2026-10-06: 「고른 범위에 값이
/// 섞여 있으면 그 칸은 「—」로 보입니다」 — letters some bold and some not,
/// letters of several colours.
///
/// A number writes the dash in its bar and a face in its button; these are
/// the two controls that had no way to say it: the app's boolean, and its
/// colour swatch. Each wears a dash and stays the control it was.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('the boolean', () {
    testWidgets('🚨mixed, it is a ring with a DASH — neither state\'s glyph, '
        'and still a ring', (tester) async {
      await pump(tester, const BooleanDot(value: false, mixed: true));

      final glyph = tester.widget<Icon>(find.byType(Icon));
      expect(glyph.icon, Icons.remove_circle_outline);
      // The ink of a ring that is off: nothing here is ON.
      expect(glyph.color, AppColors.text);
    });

    testWidgets('it says so to a screen reader, and says no state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const BooleanDot(value: false, mixed: true));

      expect(
        tester.getSemantics(find.byType(BooleanDot)),
        isSemantics(isCheckStateMixed: true, hasToggledState: false),
      );
      semantics.dispose();
    });

    testWidgets('⛔a ring that is not mixed is the ring it always was', (
      tester,
    ) async {
      for (final (value, glyph) in [
        (true, Icons.radio_button_checked),
        (false, Icons.radio_button_unchecked),
      ]) {
        await pump(tester, BooleanDot(value: value));
        expect(tester.widget<Icon>(find.byType(Icon)).icon, glyph);
      }
    });

    test('a mixed ring is never also on', () {
      expect(
        () => BooleanDot(value: true, mixed: true),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets('🚨a settings row that is mixed shows the dash, and a press '
        'on it turns every one ON', (tester) async {
      final heard = <bool>[];
      await pump(
        tester,
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('probe-row'),
          label: 'Bold',
          value: false,
          mixed: true,
          onChanged: heard.add,
        ),
      );

      expect(
        tester.widget<BooleanDot>(find.byType(BooleanDot)).mixed,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey<String>('probe-row')));
      await tester.pump();

      expect(heard, [true]);
    });
  });

  group('the colour swatch', () {
    const key = ValueKey<String>('probe-swatch');

    Future<void> pumpSwatch(
      WidgetTester tester, {
      required bool mixed,
      VoidCallback? onSettled,
      ValueChanged<int>? onChanged,
    }) => pump(
      tester,
      ColorSwatchButton(
        keyValue: 'probe-swatch',
        color: 0xFF336699,
        mixed: mixed,
        onChanged: onChanged ?? (_) {},
        onSettled: onSettled,
      ),
    );

    RenderObject face(WidgetTester tester) => tester.renderObject(
      find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)),
    );

    testWidgets('🚨mixed, its face shows NONE of the colours: the ring, and a '
        'level dash across it', (tester) async {
      await pumpSwatch(tester, mixed: true);

      // The ring alone is a circle: nothing is filled.
      expect(face(tester), paintsExactlyCountTimes(#drawCircle, 1));
      expect(face(tester), paintsExactlyCountTimes(#drawLine, 1));
      final ends = <Offset>[];
      expect(
        face(tester),
        paints..something((method, arguments) {
          if (method != #drawLine) {
            return false;
          }
          ends
            ..add(arguments[0] as Offset)
            ..add(arguments[1] as Offset);
          return true;
        }),
      );
      // Level, through the middle of an 18 pixel face.
      expect(ends.first.dy, 9);
      expect(ends.last.dy, 9);
      expect(ends.first.dx, lessThan(9));
      expect(ends.last.dx, greaterThan(9));
    });

    testWidgets('⛔one colour is that colour, filled — no mark on it', (
      tester,
    ) async {
      await pumpSwatch(tester, mixed: false);

      expect(face(tester), paintsExactlyCountTimes(#drawCircle, 2));
      expect(face(tester), paintsExactlyCountTimes(#drawLine, 0));
      expect(
        face(tester),
        paints..circle(color: const Color(0xFF336699), style: PaintingStyle.fill),
      );
    });

    testWidgets('🚨the face is drawn AGAIN when only whether it is mixed '
        'changes — and not when nothing does', (tester) async {
      CustomPainter painterNow() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;

      await pumpSwatch(tester, mixed: false);
      final plain = painterNow();
      await pumpSwatch(tester, mixed: true);
      final mixed = painterNow();

      expect(mixed.shouldRepaint(plain), isTrue);

      await pumpSwatch(tester, mixed: true);

      expect(painterNow().shouldRepaint(mixed), isFalse);
    });

    testWidgets('a mixed swatch opens on the colour it was handed — where a '
        'pick starts from', (tester) async {
      final picked = <int>[];
      await pumpSwatch(tester, mixed: true, onChanged: picked.add);

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ColorStatusBar>(
              find.byKey(const ValueKey<String>('color-picker-status')),
            )
            .color,
        0xFF336699,
      );
    });

    testWidgets('🚨it says when its window CLOSED — once, and not while a '
        'colour is still being picked', (tester) async {
      var settled = 0;
      final picked = <int>[];
      await pumpSwatch(
        tester,
        mixed: false,
        onChanged: picked.add,
        onSettled: () => settled += 1,
      );

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(settled, 0);

      // A colour picked: the wheel's own centre is a press on the triangle.
      await tester.tap(
        find.byKey(const ValueKey<String>('color-picker-wheel')),
      );
      await tester.pumpAndSettle();
      expect(picked, isNotEmpty, reason: '⛔fixture: a colour was picked');
      expect(settled, 0, reason: 'the window is still open');

      // A press anywhere else closes the window.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('color-picker-wheel')),
        findsNothing,
        reason: '⛔fixture: the window closed',
      );
      expect(settled, 1);
    });

    testWidgets('a swatch nobody asked to hear from closes in silence', (
      tester,
    ) async {
      await pumpSwatch(tester, mixed: false);

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
