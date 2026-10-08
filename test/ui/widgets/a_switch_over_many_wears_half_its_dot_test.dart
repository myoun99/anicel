import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

/// 🗣️유저 2026-10-06 (F-289-Q13): 「폴더줄의 스위치는 섞임모양 넣는게
/// 나을거같아. 새로운 타입으로 두자. 다른곳에서도 이용가능하게」.
///
/// The switch over SEVERAL things: the app's one boolean while they agree,
/// and the same ring with half its dot while they do not.
void main() {
  Future<void> pumpDot(
    WidgetTester tester,
    BooleanMix value, {
    bool enabled = true,
    double? size,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: BooleanMixDot(value: value, enabled: enabled, size: size),
        ),
      ),
    ),
  );

  /// What the mixed glyph draws on a canvas [side] wide, each call with the
  /// colour a screen shows — a paint hands its colour back through the
  /// engine's floats.
  ({
    ({Offset centre, double radius, double stroke, int color}) ring,
    ({Rect box, double start, double sweep, bool wedge, int color}) dot,
  })
  drawn(WidgetTester tester, double side) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(BooleanMixDot),
        matching: find.byType(CustomPaint),
      ),
    );
    final canvas = TestRecordingCanvas();
    paint.painter!.paint(canvas, Size.square(side));
    final calls = canvas.invocations.map((call) => call.invocation).toList();
    final ring = calls.singleWhere((call) => call.memberName == #drawCircle);
    final dot = calls.singleWhere((call) => call.memberName == #drawArc);
    expect(calls, hasLength(2), reason: 'a ring and a half dot, nothing else');
    final ringPaint = ring.positionalArguments[2] as Paint;
    expect(ringPaint.style, PaintingStyle.stroke);
    final dotPaint = dot.positionalArguments[4] as Paint;
    expect(dotPaint.style, PaintingStyle.fill);
    return (
      ring: (
        centre: ring.positionalArguments[0] as Offset,
        radius: ring.positionalArguments[1] as double,
        stroke: ringPaint.strokeWidth,
        color: ringPaint.color.toARGB32(),
      ),
      dot: (
        box: dot.positionalArguments[0] as Rect,
        start: dot.positionalArguments[1] as double,
        sweep: dot.positionalArguments[2] as double,
        wedge: dot.positionalArguments[3] as bool,
        color: dotPaint.color.toARGB32(),
      ),
    );
  }

  test('what several things say together: all on, all off, or mixed — and '
      'nothing at all says off', () {
    expect(BooleanMix.of([true, true]), BooleanMix.on);
    expect(BooleanMix.of([false, false, false]), BooleanMix.off);
    expect(BooleanMix.of([true, false]), BooleanMix.mixed);
    expect(BooleanMix.of([false, true, true]), BooleanMix.mixed);
    expect(BooleanMix.of([true]), BooleanMix.on);
    expect(BooleanMix.of(const []), BooleanMix.off);
  });

  test('a press turns every one of them on — unless they all are, and then '
      'off', () {
    expect(BooleanMix.off.pressTurnsOn, isTrue);
    expect(BooleanMix.mixed.pressTurnsOn, isTrue);
    expect(BooleanMix.on.pressTurnsOn, isFalse);
  });

  testWidgets('🚨on and off ARE the app\'s boolean — the same control, not a '
      'likeness of it', (tester) async {
    for (final (mix, value) in [
      (BooleanMix.on, true),
      (BooleanMix.off, false),
    ]) {
      for (final enabled in [true, false]) {
        await pumpDot(tester, mix, enabled: enabled, size: 16);
        final dot = tester.widget<BooleanDot>(find.byType(BooleanDot));
        expect(
          (dot.value, dot.enabled, dot.inPickOneGroup, dot.size),
          (value, enabled, false, 16),
          reason: '$mix, enabled: $enabled',
        );
        expect(
          find.descendant(
            of: find.byType(BooleanMixDot),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
          reason: 'nothing of its own is drawn while they agree',
        );
      }
    }
  });

  testWidgets('mixed is the SAME ring on the same grid with the left half '
      'of the same dot, in the accent', (tester) async {
    await pumpDot(tester, BooleanMix.mixed);
    expect(find.byType(BooleanDot), findsNothing);
    final glyph = drawn(tester, 24);
    // Material's radio glyphs on their 24-unit grid: a ring two units thick
    // whose outside is ten from the centre, a dot of radius five.
    expect(glyph.ring.centre, const Offset(12, 12));
    expect(glyph.ring.radius + glyph.ring.stroke / 2, 10);
    expect(glyph.ring.stroke, 2);
    expect(
      glyph.dot.box,
      Rect.fromCircle(center: const Offset(12, 12), radius: 5),
    );
    expect(glyph.dot.wedge, isTrue);
    // From straight down, half a turn clockwise: the LEFT half.
    expect(glyph.dot.start, math.pi / 2);
    expect(glyph.dot.sweep, math.pi);
    expect(glyph.ring.color, AppColors.accent.toARGB32());
    expect(glyph.dot.color, AppColors.accent.toARGB32());

    // It scales with the size it is given, as the icons do.
    final small = drawn(tester, 12);
    expect(small.ring.radius, glyph.ring.radius / 2);
    expect(small.ring.stroke, 1);
    expect(small.dot.box.width, 5);
  });

  testWidgets('it takes the size it is handed, or the icon theme\'s', (
    tester,
  ) async {
    Size glyphSize() => tester.getSize(
      find.descendant(
        of: find.byType(BooleanMixDot),
        matching: find.byType(CustomPaint),
      ),
    );
    await pumpDot(tester, BooleanMix.mixed, size: 14);
    expect(glyphSize(), const Size.square(14));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(
            child: IconTheme(
              data: IconThemeData(size: 18),
              child: BooleanMixDot(value: BooleanMix.mixed),
            ),
          ),
        ),
      ),
    );
    expect(glyphSize(), const Size.square(18));
  });

  testWidgets('a dead one is the app\'s disabled glyph — the GLYPH still '
      'says it is mixed', (tester) async {
    await pumpDot(tester, BooleanMix.mixed, enabled: false);
    final glyph = drawn(tester, 24);
    expect(glyph.ring.color, AppColors.glyphDisabled.toARGB32());
    expect(glyph.dot.color, AppColors.glyphDisabled.toARGB32());
  });

  testWidgets('it tells a screen reader its state: mixed, or toggled on or '
      'off', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDot(tester, BooleanMix.mixed);
    expect(
      tester.getSemantics(find.byType(BooleanMixDot)),
      isSemantics(hasCheckedState: true, isCheckStateMixed: true),
    );
    for (final (mix, value) in [
      (BooleanMix.on, true),
      (BooleanMix.off, false),
    ]) {
      await pumpDot(tester, mix);
      expect(
        tester.getSemantics(find.byType(BooleanDot)),
        isSemantics(hasToggledState: true, isToggled: value),
        reason: '$mix',
      );
    }
    semantics.dispose();
  });

  group('BooleanMixDotButton', () {
    Future<List<bool>> pumpButton(
      WidgetTester tester,
      BooleanMix value, {
      bool live = true,
    }) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: BooleanMixDotButton(
                keyValue: 'probe',
                tooltip: 'Probe',
                value: value,
                onChanged: live ? changes.add : null,
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('a press asks for all on from mixed and from off, and for '
        'all off from on', (tester) async {
      for (final (value, asked) in [
        (BooleanMix.mixed, true),
        (BooleanMix.off, true),
        (BooleanMix.on, false),
      ]) {
        final changes = await pumpButton(tester, value);
        await tester.tap(find.byKey(const ValueKey<String>('probe')));
        await tester.pumpAndSettle();
        expect(changes, [asked], reason: 'from $value');
      }
    });

    testWidgets('a null onChanged is a dead button, and its glyph says so', (
      tester,
    ) async {
      final changes = await pumpButton(tester, BooleanMix.mixed, live: false);
      await tester.tap(
        find.byKey(const ValueKey<String>('probe')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(
        tester.widget<BooleanMixDot>(find.byType(BooleanMixDot)).enabled,
        isFalse,
      );
    });

    testWidgets('🚨NO `Opacity` in it, in any state, live or dead (board '
        '`a-panel-with-a-switch-can-never-bake`)', (tester) async {
      for (final value in BooleanMix.values) {
        for (final live in [false, true]) {
          await pumpButton(tester, value, live: live);
          expect(
            find.descendant(
              of: find.byType(BooleanMixDotButton),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Opacity ||
                    widget is AnimatedOpacity ||
                    widget is FadeTransition,
              ),
            ),
            findsNothing,
            reason: '$value, live: $live',
          );
        }
      }
    });
  });
}
