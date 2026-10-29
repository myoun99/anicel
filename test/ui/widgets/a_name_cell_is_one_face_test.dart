// A pill's name cell wears the plate face (card frame-panels-build-in-one-
// frame, 2026-10-25), where it was a claim, a Material, an InkWell and a
// tooltip. ⛔Nothing on the screen was to change: these hold the face
// against the cell it replaced, driven by real input, pixel for pixel.
import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// The name cell as master `ae6592342` built it (`PillNameCell.build`).
class _OldNameCell extends StatelessWidget {
  const _OldNameCell({
    required this.keyValue,
    required this.entriesBuilder,
    this.label,
    this.icon,
    this.tooltip,
  });

  final String keyValue;
  final List<PanelFlyoutEntry> Function() entriesBuilder;
  final String? label;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final Widget content = label == null
        ? Icon(icon, size: 16, color: AppColors.textDim)
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: 11.5, color: AppColors.text),
          );
    final cell = ControlPressClaim(
      onPressed: () {
        final entries = entriesBuilder();
        if (entries.isEmpty) {
          return;
        }
        unawaited(showPanelFlyout(context, entries: entries));
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(keyValue),
          customBorder: AppShapes.control(CommandPill.heightIn(context) - 4),
          onTap: () {},
          child: Container(
            height: CommandPill.heightIn(context) - 4,
            constraints: const BoxConstraints(minWidth: 24),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal:
                  (label == null
                      ? PillNameCell.iconBreath
                      : PillNameCell.textBreath) -
                  1,
            ),
            child: content,
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: tooltip == null ? cell : AppTooltip(message: tooltip, child: cell),
    );
  }
}

typedef _Make =
    Widget Function({
      String? label,
      IconData? icon,
      String? tooltip,
      List<PanelFlyoutEntry> Function()? entries,
    });

List<PanelFlyoutEntry> _someEntries() => [
  PanelFlyoutRow(
    keyValue: 'the-entry',
    label: 'Entry',
    builder: (_) => const SizedBox(width: 40, height: 20),
  ),
];

Widget _old({
  String? label,
  IconData? icon,
  String? tooltip,
  List<PanelFlyoutEntry> Function()? entries,
}) => _OldNameCell(
  keyValue: 'cell',
  label: label,
  icon: icon,
  tooltip: tooltip,
  entriesBuilder: entries ?? _someEntries,
);

Widget _new({
  String? label,
  IconData? icon,
  String? tooltip,
  List<PanelFlyoutEntry> Function()? entries,
}) => PillNameCell(
  keyValue: 'cell',
  label: label,
  icon: icon,
  tooltip: tooltip,
  entriesBuilder: entries ?? _someEntries,
);

const _boundary = ValueKey<String>('boundary');
const _cell = ValueKey<String>('cell-slot');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// One cell as a pill holds it — at the head of a row of the pill's
/// height, on the panel's surface — under [scale] of the OS text size.
Future<void> _pump(WidgetTester tester, Widget cell, {double scale = 1}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
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
                        children: [KeyedSubtree(key: _cell, child: cell)],
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

/// The cursor a mouse at [position] is shown, as the mouse tracker picks
/// it: the first answer on the hit path that does not defer.
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

typedef _Reading = ({
  Size size,
  List<double> intrinsics,
  Map<String, Uint8List> pixels,
  MouseCursor cursor,
});

Future<_Reading> _read(
  WidgetTester tester,
  _Make make, {
  String? label,
  IconData? icon,
  double scale = 1,
}) async {
  await _pump(
    tester,
    make(label: label, icon: icon, entries: () => const []),
    scale: scale,
  );
  final box = tester.renderObject<RenderBox>(find.byKey(_cell));
  final center = tester.getCenter(find.byKey(_cell));
  final pixels = <String, Uint8List>{'rest': await _pixels(tester)};

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await tester.pump();
  await mouse.moveTo(center);
  await _settle(tester);
  pixels['hovered'] = await _pixels(tester);
  await mouse.down(center);
  await _settle(tester);
  pixels['pressed'] = await _pixels(tester);
  await mouse.up();
  await _settle(tester);
  await mouse.moveTo(Offset.zero);
  await _settle(tester);
  pixels['left'] = await _pixels(tester);
  await mouse.removePointer();

  final word = label == null ? find.byIcon(icon!) : find.text(label);
  final node = Focus.of(tester.element(word));
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  node.requestFocus();
  await _settle(tester);
  expect(node.hasPrimaryFocus, isTrue, reason: 'fixture: it took focus');
  pixels['keyboard focus'] = await _pixels(tester);
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  await _settle(tester);
  pixels['focus under a pointer'] = await _pixels(tester);
  node.unfocus();
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  await _settle(tester);

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
  );
}

void main() {
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  for (final (label, icon, scale) in [
    ('프레임', null, 1.0),
    (null, Icons.auto_awesome, 1.0),
    ('레이어', null, 1.5),
  ]) {
    testWidgets('a cell named ${label ?? 'by a glyph'} at ${scale}x looks, '
        'measures and points as the InkWell did', (tester) async {
      final old = await _read(
        tester,
        _old,
        label: label,
        icon: icon,
        scale: scale,
      );
      final now = await _read(
        tester,
        _new,
        label: label,
        icon: icon,
        scale: scale,
      );

      expect(now.size, old.size);
      expect(now.intrinsics, old.intrinsics);
      // 🔧The one thing that changes, on purpose: the InkWell showed the
      // arrow on a desktop (M3's `adaptiveClickable`), and the icon verbs
      // in the same pill show the hand ([PillNameCell]).
      expect(old.cursor, SystemMouseCursors.basic);
      expect(now.cursor, SystemMouseCursors.click);
      expect(now.pixels.keys, old.pixels.keys);
      for (final state in old.pixels.keys) {
        expect(now.pixels[state], old.pixels[state], reason: state);
      }
      expect(
        now.pixels['hovered'],
        isNot(now.pixels['rest']),
        reason: 'fixture: the hover shows',
      );
      expect(
        now.pixels['keyboard focus'],
        isNot(now.pixels['rest']),
        reason: 'fixture: the keyboard focus shows',
      );
    });
  }

  testWidgets('the cell opens its menu on the release inside it — and now on '
      'Enter and Space too, as the icon buttons beside it do', (tester) async {
    for (final (make, keys) in [(_old, false), (_new, true)]) {
      var built = 0;
      List<PanelFlyoutEntry> entries() {
        built += 1;
        return const [];
      }

      await _pump(tester, make(label: '컷', entries: entries));
      final center = tester.getCenter(find.byKey(_cell));
      final finger = await tester.startGesture(center);
      await tester.pump();
      expect(built, 0, reason: 'not on the way down — the bar is 「그 외」');
      await finger.up();
      await tester.pump();
      expect(built, 1, reason: 'the release inside it asks for the menu');

      Focus.of(tester.element(find.text('컷'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        built,
        keys ? 3 : 1,
        reason: keys
            ? '🔧Enter and Space open it (board F-450-Q1)'
            : 'the InkWell took the focus and answered with nothing',
      );
    }
  });

  testWidgets('a name cell is one face — no Material, no ink, no tooltip '
      'box of its own', (tester) async {
    await _pump(tester, _new(label: '컷', tooltip: 'Cut'));
    for (final kind in [Material, InkWell, AppTooltip, ControlPressClaim]) {
      expect(
        find.descendant(
          of: find.byType(PillNameCell),
          matching: find.byType(kind),
        ),
        findsNothing,
        reason: '$kind',
      );
    }
  });
}
