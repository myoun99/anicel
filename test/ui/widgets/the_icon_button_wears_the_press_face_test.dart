// The app's icon button wears the rail's light face (board
// `frame-panels-build-in-one-frame`, 2026-10-24): what a pointer and a screen
// reader meet is ONE render object around the glyph, where it was a
// semantics node, a tooltip, a mouse region, a listener and three boxes —
// rebuilt for every button whenever a tab was shown again. ⛔Nothing on the
// screen was to change: these pin the new face against the widgets it
// replaced, pixel for pixel and size for size.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// The face as master `25c942ee1` built it (`_AppIconButtonFaceState`),
/// less the widgets that paint nothing — its colours read for [states] in
/// the same order, from the same ink.
class _OldFace extends StatelessWidget {
  const _OldFace({
    required this.states,
    required this.size,
    required this.icon,
    this.isSelected = false,
    this.danger = false,
    this.outlined = false,
  });

  final ValueListenable<Set<WidgetState>> states;
  final AppIconButtonMetrics size;
  final Widget icon;
  final bool isSelected;
  final bool danger;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final box = appIconButtonBoxOnGrid(context, size);
    return ValueListenableBuilder<Set<WidgetState>>(
      valueListenable: states,
      builder: (context, states, _) {
        final ink = IconButtonInk.of(
          context,
          isSelected: isSelected,
          danger: danger,
        );
        final foreground = ink.foreground(states);
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: box.minWidth,
            maxWidth: box.maxWidth,
            minHeight: box.height,
            maxHeight: box.height,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: appIconButtonShape(
                size.height,
                outlined: outlined,
                danger: danger,
                isSelected: isSelected,
              ),
              color: ink.overlay(states),
            ),
            child: Align(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: size.iconSize),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: icon,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One button the pins compare: how it is made, and what it wears.
final class _Case {
  const _Case(
    this.name, {
    this.icon = const Icon(Icons.draw),
    this.size = AppIconButtonSize.bar,
    this.enabled = true,
    this.isSelected = false,
    this.danger = false,
    this.outlined = false,
  });

  final String name;
  final Widget icon;
  final AppIconButtonMetrics size;
  final bool enabled;
  final bool isSelected;
  final bool danger;
  final bool outlined;
}

const _cases = [
  _Case('plain'),
  _Case('selected', isSelected: true),
  _Case('dead', enabled: false),
  _Case('dead-selected', enabled: false, isSelected: true),
  _Case('danger', danger: true),
  _Case('outlined', outlined: true),
  _Case('outlined-on', outlined: true, isSelected: true),
  _Case('outlined-danger', outlined: true, danger: true),
  _Case('word', icon: Text('1:1')),
  _Case('strip', size: AppIconButtonSize.strip),
  _Case('tool', size: AppIconButtonSize.tool),
  _Case(
    'promised',
    size: AppIconButtonBox(width: 20, height: 22, iconSize: 14),
  ),
];

const _slot = Size(48, 48);

Widget _boxed(String key, Widget child) => RepaintBoundary(
  key: ValueKey<String>(key),
  child: SizedBox.fromSize(
    size: _slot,
    child: ColoredBox(
      color: AppColors.surface,
      child: Center(child: child),
    ),
  ),
);

/// Every case twice — the real button, and the old face beside it whose
/// state each test sets by hand.
Future<Map<String, ValueNotifier<Set<WidgetState>>>> _pumpPairs(
  WidgetTester tester,
) async {
  final states = {
    for (final c in _cases) c.name: ValueNotifier<Set<WidgetState>>({}),
  };
  for (final notifier in states.values) {
    addTearDown(notifier.dispose);
  }
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Material(
        child: Column(
          children: [
            for (final c in _cases)
              Row(
                children: [
                  _boxed(
                    'new-${c.name}',
                    AppIconButton(
                      keyValue: c.name,
                      tooltip: '',
                      icon: c.icon,
                      size: c.size,
                      onPressed: c.enabled ? () {} : null,
                      isSelected: c.isSelected,
                      danger: c.danger,
                      outlined: c.outlined,
                    ),
                  ),
                  _boxed(
                    'old-${c.name}',
                    _OldFace(
                      states: states[c.name]!,
                      size: c.size,
                      icon: c.icon,
                      isSelected: c.isSelected,
                      danger: c.danger,
                      outlined: c.outlined,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
  for (final c in _cases) {
    states[c.name]!.value = _restOf(c);
  }
  await tester.pump();
  return states;
}

Set<WidgetState> _restOf(_Case c) => {
  if (!c.enabled) WidgetState.disabled,
  if (c.isSelected) WidgetState.selected,
};

Future<Uint8List> _pixelsOf(WidgetTester tester, String key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey<String>(key)),
  );
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  return pixels;
}

/// The real button's pixels, once they are the old face's.
Future<Uint8List> _expectSamePixels(
  WidgetTester tester,
  _Case c,
  String state,
) async {
  final pixels = await _pixelsOf(tester, 'new-${c.name}');
  expect(
    pixels,
    await _pixelsOf(tester, 'old-${c.name}'),
    reason: '${c.name}, $state',
  );
  return pixels;
}

void main() {
  testWidgets('every kind of button paints what the old face painted — at '
      'rest, under the mouse and held down', (tester) async {
    final states = await _pumpPairs(tester);
    final rest = {
      for (final c in _cases)
        c.name: await _expectSamePixels(tester, c, 'at rest'),
    };

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 899));
    addTearDown(mouse.removePointer);
    for (final c in _cases) {
      final center = tester.getCenter(find.byKey(ValueKey<String>(c.name)));
      await mouse.moveTo(center);
      states[c.name]!.value = {..._restOf(c), WidgetState.hovered};
      await tester.pump();
      final hovered = await _expectSamePixels(tester, c, 'hovered');
      expect(
        hovered,
        c.enabled ? isNot(rest[c.name]) : rest[c.name],
        reason: '${c.name}: a live button shows its hover, a dead one none',
      );

      if (c.enabled) {
        await mouse.down(center);
        states[c.name]!.value = {
          ..._restOf(c),
          WidgetState.hovered,
          WidgetState.pressed,
        };
        await tester.pump();
        expect(
          await _expectSamePixels(tester, c, 'pressed'),
          isNot(hovered),
          reason: '${c.name}: the press shows over the hover',
        );
        await mouse.up();
        await tester.pump(const Duration(seconds: 1));
      }

      await mouse.moveTo(const Offset(399, 899));
      states[c.name]!.value = _restOf(c);
      await tester.pump(const Duration(seconds: 1));
      await _expectSamePixels(tester, c, 'left');
    }
  });

  testWidgets('a button the KEYBOARD focused wears the focus layer, and one '
      'focused under a pointer wears none — as the old face did', (
    tester,
  ) async {
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final states = await _pumpPairs(tester);
    for (final c in _cases.where((c) => c.enabled)) {
      final atRest = await _pixelsOf(tester, 'new-${c.name}');
      final node = Focus.of(
        tester.element(
          find.descendant(
            of: find.byKey(ValueKey<String>(c.name)),
            matching: find.byType(IconButtonPressFace),
          ),
        ),
      );

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      node.requestFocus();
      states[c.name]!.value = {..._restOf(c), WidgetState.focused};
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue, reason: c.name);
      expect(
        await _expectSamePixels(tester, c, 'keyboard focus'),
        isNot(atRest),
        reason: '${c.name}: the focus layer shows',
      );

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      states[c.name]!.value = _restOf(c);
      await tester.pump();
      await _expectSamePixels(tester, c, 'focus under a pointer');

      node.unfocus();
      await tester.pump();
    }
  });

  testWidgets('🚨the glyph\'s ink never answers the hover or the press — the '
      'face leaves them out of the colour it hands the glyph', (tester) async {
    for (final (theme, data) in [('app', buildAppTheme()), ('M3', null)]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey<String>(theme),
          theme: data,
          home: const SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      for (final (isSelected, danger) in const [
        (false, false),
        (true, false),
        (false, true),
      ]) {
        final ink = IconButtonInk.of(
          context,
          isSelected: isSelected,
          danger: danger,
        );
        for (final base in <Set<WidgetState>>[
          {},
          {WidgetState.disabled},
          {WidgetState.focused},
        ]) {
          for (final extra in const [
            WidgetState.hovered,
            WidgetState.pressed,
          ]) {
            expect(
              ink.foreground({...base, extra}),
              ink.foreground(base),
              reason:
                  '$theme theme, selected $isSelected, danger $danger, '
                  '$base + $extra',
            );
          }
        }
      }
    }
  });

  testWidgets('a button inside another tooltip shows only its own over '
      'itself — the innermost of a nest answers, as Flutter''s tooltips '
      'do — and a button with nothing to say leaves the hover to it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Center(
            child: AppTooltip(
              message: 'outer',
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconButton(
                      keyValue: 'says',
                      tooltip: 'inner',
                      icon: const Icon(Icons.close),
                      onPressed: () {},
                    ),
                    AppIconButton(
                      keyValue: 'silent',
                      tooltip: '',
                      icon: const Icon(Icons.close),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<void> hoverAt(Offset at) async {
      await mouse.moveTo(at);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> leave() async {
      await hoverAt(Offset.zero);
      await tester.pumpAndSettle();
    }

    await hoverAt(tester.getCenter(find.byKey(const ValueKey('says'))));
    expect(find.text('inner'), findsOneWidget);
    expect(find.text('outer'), findsNothing, reason: 'one tooltip at a time');
    await leave();

    await hoverAt(tester.getCenter(find.byKey(const ValueKey('silent'))));
    expect(find.text('outer'), findsOneWidget);
    await leave();

    await hoverAt(tester.getTopLeft(find.byType(Row)) - const Offset(10, 10));
    expect(find.text('outer'), findsOneWidget, reason: 'around the buttons');
    await leave();
  });

  testWidgets('a button that CHANGES tells a screen reader — lit, renamed, '
      'gone dead — in the node it already had', (tester) async {
    final handle = tester.ensureSemantics();
    final look = ValueNotifier<(bool, String, bool)>((false, 'Eye', true));
    addTearDown(look.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: ValueListenableBuilder<(bool, String, bool)>(
              valueListenable: look,
              builder: (context, value, _) {
                final (selected, tooltip, alive) = value;
                return AppIconButton(
                  keyValue: 'changes',
                  tooltip: tooltip,
                  icon: const Icon(Icons.visibility),
                  onPressed: alive ? () {} : null,
                  isSelected: selected,
                );
              },
            ),
          ),
        ),
      ),
    );
    final button = find.byKey(const ValueKey<String>('changes'));
    final node = tester.getSemantics(button);
    expect(
      node,
      isSemantics(tooltip: 'Eye', isSelected: false, isEnabled: true),
    );

    look.value = (true, 'Eye', true);
    await tester.pump();
    expect(tester.getSemantics(button), isSemantics(isSelected: true));

    look.value = (true, 'Hidden', true);
    await tester.pump();
    expect(tester.getSemantics(button), isSemantics(tooltip: 'Hidden'));

    look.value = (true, 'Hidden', false);
    await tester.pump();
    expect(tester.getSemantics(button), isSemantics(isEnabled: false));
    expect(
      tester.getSemantics(button).id,
      node.id,
      reason: 'the same node, told — not a new one',
    );
    handle.dispose();
  });

  testWidgets('a parent that asks the box\'s size any other way — dry, '
      'intrinsic or by its baseline — hears what the old face said', (
    tester,
  ) async {
    await _pumpPairs(tester);
    const asks = [
      BoxConstraints(),
      BoxConstraints(maxWidth: 10, maxHeight: 10),
      BoxConstraints.tightFor(width: 40, height: 30),
      BoxConstraints(minWidth: 29, maxWidth: 100, maxHeight: 100),
    ];
    for (final c in _cases) {
      final face = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byKey(ValueKey<String>(c.name)),
          matching: find.byType(IconButtonPressFace),
        ),
      );
      final old = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byKey(ValueKey<String>('old-${c.name}')),
          matching: find.byType(ConstrainedBox),
        ),
      );
      expect(face.size, old.size, reason: '${c.name}: laid out');
      // A baseline is a parent's question, asked during its layout — this
      // asks it from outside, as the intrinsics check of a debug build does.
      double? baselineOf(RenderBox box) {
        RenderObject.debugCheckingIntrinsics = true;
        try {
          return box.getDistanceToBaseline(
            TextBaseline.alphabetic,
            onlyReal: true,
          );
        } finally {
          RenderObject.debugCheckingIntrinsics = false;
        }
      }

      expect(
        baselineOf(face),
        baselineOf(old),
        reason: '${c.name}: baseline',
      );
      for (final extent in [0.0, 12.0, 30.0, double.infinity]) {
        for (final (name, ask) in [
          ('min width', (RenderBox box) => box.getMinIntrinsicWidth(extent)),
          ('max width', (RenderBox box) => box.getMaxIntrinsicWidth(extent)),
          ('min height', (RenderBox box) => box.getMinIntrinsicHeight(extent)),
          ('max height', (RenderBox box) => box.getMaxIntrinsicHeight(extent)),
        ]) {
          expect(ask(face), ask(old), reason: '${c.name}: $name at $extent');
        }
      }
      for (final constraints in asks) {
        expect(
          face.getDryLayout(constraints),
          old.getDryLayout(constraints),
          reason: '${c.name}: dry layout in $constraints',
        );
        expect(
          face.getDryBaseline(constraints, TextBaseline.alphabetic),
          old.getDryBaseline(constraints, TextBaseline.alphabetic),
          reason: '${c.name}: dry baseline in $constraints',
        );
      }
    }
  });
}
