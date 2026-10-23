import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart';

/// F-450 ② (유저 2026-10-23): on the close prompt, the arrow keys moved
/// onto 「저장」 and Enter 「엔터한것처럼 반응해서 버튼 흰색되지만 아무런
/// 반응없었음」 — only 「닫기」 answered.
///
/// A claimed button fires from the raw pointer stream ([ControlPressClaim]),
/// and its inner button kept a callback that fired nothing — so the KEY,
/// which reaches the inner button and nothing else, pressed nothing. The
/// primary 「닫기」 is a bare `FilledButton`, which is why it alone worked.
///
/// The matrix: a key presses a claimed button ONCE; a click still presses
/// it once, whether it acts on the release or on the down; and an icon
/// button stays deaf to the keyboard, as 유저 decided for it (2026-09-10,
/// `screen-readers-cannot-press-app-buttons`).
void main() {
  Widget app(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  /// Whether the keyboard's focus sits in [target].
  bool focusIsIn(Finder target) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) {
      return false;
    }
    final element = target.evaluate().single;
    var inside = focused == element;
    focused.visitAncestorElements((ancestor) {
      inside = inside || ancestor == element;
      return !inside;
    });
    return inside;
  }

  Future<void> tabTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 12 && !focusIsIn(target); i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusIsIn(target), isTrue, reason: 'the keyboard never got there');
  }

  testWidgets('a window\'s quiet button is pressed by Enter and by Space, '
      'once each', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      app(
        AppWindowActionButton(
          AppWindowAction(
            label: 'Save',
            actionKey: const ValueKey<String>('save'),
            onPressed: () => presses += 1,
          ),
        ),
      ),
    );
    final save = find.byKey(const ValueKey<String>('save'));
    await tabTo(tester, save);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1, reason: 'Enter on a focused button presses it');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 2, reason: 'and so does Space');
  });

  testWidgets('a click still presses it ONCE — the claim fires it, and the '
      'inner button\'s own tap on the same lift does not — and a key after '
      'it is heard again', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      app(
        AppWindowActionButton(
          AppWindowAction(
            label: 'Save',
            actionKey: const ValueKey<String>('save'),
            onPressed: () => presses += 1,
          ),
        ),
      ),
    );
    final save = find.byKey(const ValueKey<String>('save'));
    await tester.tap(save);
    await tester.pump();
    expect(presses, 1);

    await tabTo(tester, save);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 2, reason: 'the click\'s silence ends with its own lift');
  });

  // 🚨The first cut heard the claim's lift alone, and a click on a brush
  // preset — an InstantTapRegion's press — applied it twice (2026-10-23).
  for (final kind in const [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('a click on a button an InstantTapRegion owns is ONE press '
        'too, and a key still presses it — ${kind.name}', (tester) async {
      var presses = 0;
      void press() => presses += 1;
      await tester.pumpWidget(
        app(
          InstantTapRegion(
            onTap: (_) => press(),
            child: TextButton(
              key: const ValueKey<String>('cell'),
              onPressed: silentPress(press),
              child: const Text('cell'),
            ),
          ),
        ),
      );
      final cell = find.byKey(const ValueKey<String>('cell'));
      await tester.tap(cell, kind: kind);
      await tester.pump();
      expect(presses, 1, reason: 'the region fires it, the button keeps quiet');

      await tabTo(tester, cell);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 2, reason: 'Enter on the focused button presses it');
    });
  }

  testWidgets('a button that acts on the DOWN is not pressed again by its '
      'lift', (tester) async {
    var presses = 0;
    void press() => presses += 1;
    await tester.pumpWidget(
      app(
        PressFireScope(
          fireOn: PressFire.down,
          child: ControlPressClaim(
            onPressed: press,
            child: TextButton(
              key: const ValueKey<String>('row-button'),
              onPressed: silentPress(press),
              child: const Text('row'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('row-button')));
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('an icon button stays deaf to the keyboard, as decided — and '
      'a click still presses it once', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      app(
        AppIconButton(
          keyValue: 'icon',
          tooltip: 'Add',
          icon: const Icon(Icons.add),
          onPressed: () => presses += 1,
        ),
      ),
    );
    final icon = find.byKey(const ValueKey<String>('icon'));
    await tabTo(tester, icon);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      presses,
      0,
      reason:
          '유저 2026-09-10: 「탭은 다른 숏컷 쓸수도있어서 굳이 필요없을거같고」',
    );

    await tester.tap(icon);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('🚨the close prompt: Enter on 「저장」 saves (F-450)', (
    tester,
  ) async {
    String? answer;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            key: const ValueKey<String>('open'),
            onPressed: () async {
              answer = await showDialog<String>(
                context: context,
                builder: (context) => AppConfirmDialog(
                  title: 'Close?',
                  message: 'Not saved.',
                  actions: [
                    for (final (key, emphasis) in const [
                      ('cancel', AppWindowActionEmphasis.quiet),
                      ('save-as', AppWindowActionEmphasis.quiet),
                      ('save', AppWindowActionEmphasis.quiet),
                      ('close', AppWindowActionEmphasis.primary),
                    ])
                      AppWindowAction(
                        label: key,
                        actionKey: ValueKey<String>('system-exit-$key'),
                        emphasis: emphasis,
                        onPressed: () => Navigator.of(context).pop(key),
                      ),
                  ],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open')));
    await tester.pumpAndSettle();

    await tabTo(tester, find.byKey(const ValueKey<String>('system-exit-save')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer, 'save');
  });
}
