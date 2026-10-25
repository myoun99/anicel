// The frame pill's comma buttons (1 · 2 · 3 · 4 · N) wear the light face
// (card frame-panels-build-in-one-frame, 2026-10-25), where each was a
// Material TextButton of ~40 elements. ⛔Nothing on the screen was to
// change: these hold the face against the TextButton it replaced, driven by
// real input — the pointer, the mouse, the keyboard — pixel for pixel.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/comma_button.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';

/// The comma button as master `ae6592342` built it
/// (`TimelineActionToolbar._commaButton`).
Widget _oldComma({
  required String label,
  required VoidCallback? onPressed,
}) => ShortcutTooltip(
  label: 'Set $label',
  shortcuts: const [],
  child: ControlPressClaim(
    onPressed: onPressed,
    child: Builder(
      builder: (context) => TextButton(
        onPressed: silentPress(onPressed),
        style: TextButton.styleFrom(
          minimumSize: Size(21, CommandPill.heightIn(context) - 4),
          maximumSize: Size(24, CommandPill.heightIn(context) - 4),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          animationDuration: Duration.zero,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: CommandPill.verbFontSize),
        ),
      ),
    ),
  ),
);

Widget _newComma({
  required String label,
  required VoidCallback? onPressed,
}) => CommaButton(
  label: label,
  tooltip: 'Set $label',
  shortcuts: const [],
  onPressed: onPressed,
);

/// The app's theme with a text button that asks more of the chain than the
/// app's own does, so each step shows: a square corner, a word of its own
/// under focus, and no state layer — M3's defaults answer that.
ThemeData _askingTheme() => buildAppTheme().copyWith(
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      shape: WidgetStatePropertyAll(AppShapes.container(0)),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.textDim
            : states.contains(WidgetState.focused)
            ? const Color(0xFFE0A030)
            : AppColors.text,
      ),
    ),
  ),
);

const _boundary = ValueKey<String>('boundary');
const _button = ValueKey<String>('button');

/// The cursor a mouse at [position] is shown: the first answer on the hit
/// path that does not defer, as the mouse tracker picks it — asked of the
/// tree, so no test mouse's bookkeeping stands in between.
MouseCursor _cursorAt(WidgetTester tester, Offset position) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, position, tester.view.viewId);
  for (final entry in result.path) {
    if (entry.target case final MouseTrackerAnnotation annotation
        when annotation.cursor != MouseCursor.defer) {
      return annotation.cursor;
    }
  }
  return SystemMouseCursors.basic;
}

/// One button as the pill holds it — in a row of the pill's height, on the
/// panel's surface — under [scale] of the OS text size.
Future<void> _pump(
  WidgetTester tester,
  Widget button, {
  double scale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Material(
          child: Center(
            child: RepaintBoundary(
              key: _boundary,
              child: ColoredBox(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Builder(
                    builder: (context) => SizedBox(
                      height: CommandPill.heightIn(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [KeyedSubtree(key: _button, child: button)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Lets whatever a change started run to its end — an ink fades in over a
/// few frames, and its animation starts on the first of them.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  return pixels;
}

/// What one button shows in every state a hand can put it in — and what
/// it measures, says and points with.
typedef _Reading = ({
  Size size,
  List<double> intrinsics,
  Map<String, Uint8List> pixels,
  MouseCursor cursor,
  ({bool button, Object enabled, String label, bool taps}) node,
  String tooltip,
});

Future<_Reading> _read(
  WidgetTester tester,
  Widget Function({required String label, required VoidCallback? onPressed})
  make, {
  required bool enabled,
  String label = '3',
  double scale = 1,
  ThemeData? theme,
}) async {
  await _pump(
    tester,
    make(label: label, onPressed: enabled ? () {} : null),
    scale: scale,
    theme: theme,
  );
  final box = tester.renderObject<RenderBox>(find.byKey(_button));
  final center = tester.getCenter(find.byKey(_button));
  final pixels = <String, Uint8List>{'rest': await _pixels(tester)};

  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
  );
  await mouse.addPointer(location: Offset.zero);
  await tester.pump();
  await mouse.moveTo(center);
  await _settle(tester);
  pixels['hovered'] = await _pixels(tester);
  if (enabled) {
    await mouse.down(center);
    await _settle(tester);
    pixels['pressed'] = await _pixels(tester);
    await mouse.up();
    await _settle(tester);
  }
  await mouse.moveTo(Offset.zero);
  await _settle(tester);
  pixels['left'] = await _pixels(tester);
  await mouse.removePointer();

  if (enabled) {
    final node = Focus.of(tester.element(find.text(label)));
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    node.requestFocus();
    await _settle(tester);
    expect(node.hasPrimaryFocus, isTrue, reason: 'fixture: it took focus');
    pixels['keyboard focus'] = await _pixels(tester);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await _settle(tester);
    pixels['focus under a pointer'] = await _pixels(tester);
    node.unfocus();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await _settle(tester);
  }

  // The BUTTON's node — the one its word is said in. The old button hung
  // its tooltip on a node above it; a face hangs it on its own, as every
  // light face does ([PressFace]).
  final data = tester.getSemantics(find.text(label)).getSemanticsData();
  final tooltip = [
    for (SemanticsNode? node = tester.getSemantics(find.text(label));
        node != null;
        node = node.parent)
      if (node.tooltip.isNotEmpty) node.tooltip,
  ].first;
  return (
    size: box.size,
    intrinsics: [
      box.getMinIntrinsicWidth(double.infinity),
      box.getMaxIntrinsicWidth(double.infinity),
      box.getMinIntrinsicHeight(double.infinity),
      box.getMaxIntrinsicHeight(double.infinity),
    ],
    pixels: pixels,
    cursor: _cursorAt(tester, center),
    node: (
      button: data.flagsCollection.isButton,
      enabled: data.flagsCollection.isEnabled,
      label: data.label,
      taps: data.hasAction(SemanticsAction.tap),
    ),
    tooltip: tooltip,
  );
}

void main() {
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  for (final (enabled, label, scale, theme) in [
    (true, '3', 1.0, null),
    (true, 'N', 1.0, null),
    (false, '3', 1.0, null),
    (true, '1', 1.5, null),
    (true, '3', 1.0, _askingTheme),
    (false, '3', 1.0, _askingTheme),
  ]) {
    testWidgets('a ${enabled ? 'live' : 'dead'} 「$label」 at ${scale}x'
        '${theme == null ? '' : ', under a theme that asks more,'} looks, '
        'measures, points and says as the TextButton did', (tester) async {
      final semantics = tester.ensureSemantics();
      final old = await _read(
        tester,
        _oldComma,
        enabled: enabled,
        label: label,
        scale: scale,
        theme: theme?.call(),
      );
      final now = await _read(
        tester,
        _newComma,
        enabled: enabled,
        label: label,
        scale: scale,
        theme: theme?.call(),
      );

      expect(now.size, old.size);
      expect(now.intrinsics, old.intrinsics);
      // 🔧The one part that changes, on purpose: the TextButton showed the
      // arrow on a desktop (M3's `adaptiveClickable`), and every other
      // button on the bar shows the hand ([CommaButton]).
      expect(old.cursor, SystemMouseCursors.basic);
      expect(
        now.cursor,
        enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        reason: 'the hand, as the icon buttons beside it',
      );
      // The node a screen reader meets says what the button's did — a
      // button, live or dead, its word, pressed by a tap. ⚠️It also says
      // what every face's node says ([PressFace]): the tooltip on itself
      // rather than on a node above, and its selected and focus states.
      expect(now.node, old.node);
      expect(now.node.label, label, reason: 'fixture: the word is said');
      expect(now.tooltip, old.tooltip);
      expect(now.pixels.keys, old.pixels.keys);
      for (final state in old.pixels.keys) {
        final (:most, :count) = _difference(
          now.pixels[state]!,
          old.pixels[state]!,
        );
        // ⚠️Where a state layer shows, its RIM may differ by a hair: the
        // face fills the app's control shape as the shape it is (the icon
        // buttons' since 2026-09-10), where the InkWell traced its outline
        // as a path — the edge is anti-aliased a little differently, at
        // most 5 of 255 in a channel (measured: 180 channels of ~22,000).
        // Wherever no layer shows, nothing differs at all.
        //
        // 🔧HELD DOWN, the face shows the press's layer alone, as every
        // icon button beside it does; the InkWell laid the press's over
        // the hover's, a little brighter (6 of 255, measured). The bar's
        // buttons press alike now.
        final (bound, rim) = switch (state) {
          'hovered' || 'keyboard focus' => (5, 400),
          'pressed' => (8, 1 << 20),
          _ => (0, 1),
        };
        expect(
          (state: state, most: most),
          (state: state, most: most.clamp(0, bound)),
        );
        expect(count, lessThan(rim), reason: '$state: the rim alone');
      }
      if (enabled) {
        expect(
          now.pixels['hovered'],
          isNot(now.pixels['rest']),
          reason: 'fixture: the hover shows',
        );
        expect(
          now.pixels['pressed'],
          isNot(now.pixels['hovered']),
          reason: 'fixture: the press shows over the hover',
        );
        expect(
          now.pixels['keyboard focus'],
          isNot(now.pixels['rest']),
          reason: 'fixture: the keyboard focus shows',
        );
      }
      semantics.dispose();
    });
  }

  testWidgets('a comma button presses once — on the release inside it, on '
      'Enter and on Space — and a drag off it presses nothing', (
    tester,
  ) async {
    for (final make in [_oldComma, _newComma]) {
      var presses = 0;
      await _pump(tester, make(label: '2', onPressed: () => presses += 1));
      final center = tester.getCenter(find.byKey(_button));

      final finger = await tester.startGesture(center);
      await tester.pump();
      expect(presses, 0, reason: 'not on the way down — the bar is 「그 외」');
      await finger.up();
      await tester.pump();
      expect(presses, 1, reason: 'the release inside it');

      final dragged = await tester.startGesture(center);
      await dragged.moveBy(const Offset(0, 60));
      await dragged.up();
      await tester.pump();
      expect(presses, 1, reason: 'a drag off it is not a press');

      Focus.of(tester.element(find.text('2'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 2, reason: 'Enter');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(presses, 3, reason: 'Space');
    }
  });

  testWidgets('a comma button is one face — no Material, no ink, no box of '
      'its own', (tester) async {
    await _pump(tester, _newComma(label: '4', onPressed: () {}));
    for (final kind in [Material, InkWell, ConstrainedBox, Semantics]) {
      expect(
        find.descendant(
          of: find.byType(CommaButton),
          matching: find.byType(kind),
        ),
        findsNothing,
        reason: '$kind',
      );
    }
  });
}

/// How far apart two images are: the largest difference of any channel,
/// and how many channels differ at all.
({int most, int count}) _difference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var most = 0;
  var count = 0;
  for (var i = 0; i < a.length; i += 1) {
    final d = (a[i] - b[i]).abs();
    if (d > 0) {
      count += 1;
      if (d > most) {
        most = d;
      }
    }
  }
  return (most: most, count: count);
}
