import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/ui_scale_binding.dart';

/// 🚨★★★H30 — the stroke after a shortcut paid for every button on the
/// screen (유저 실기 2026-09-10: 「그리다가 언두하고 빠르게 다음 스트로크
/// 그리면 렉이 심하거든?」).
///
/// The framework's automatic highlight strategy flips the focus highlight
/// mode on a key press and flips it back on the next stylus or touch
/// pointer, and every `InkResponse` rebuilds on each flip. What is pinned
/// here is the flip itself: the highlight-mode listeners ARE those
/// rebuilds, so zero notifications is zero rebuilds. What it cost is
/// measured in `undo_then_next_stroke_benchmark_test.dart`.
void main() {
  testWidgets('a shortcut and the pen after it leave the highlight mode '
      'alone', (tester) async {
    AnicelBinding.applyFocusHighlightPolicy(FocusManager.instance);
    await tester.pumpWidget(const SizedBox.expand());
    var flips = 0;
    void countFlip(FocusHighlightMode _) => flips += 1;
    FocusManager.instance.addHighlightModeListener(countFlip);
    addTearDown(
      () => FocusManager.instance.removeHighlightModeListener(countFlip),
    );

    // Every kind the framework counts as touch, each after a shortcut.
    for (final kind in const [
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.touch,
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      final pen = await tester.startGesture(const Offset(40, 40), kind: kind);
      await pen.moveBy(const Offset(12, 7));
      await pen.up();
      await tester.pump();
    }

    expect(
      flips,
      0,
      reason: '🚨each flip rebuilds every InkResponse on the screen — the '
          'editor held 156 (62 after the icon buttons lost their ink), and '
          'the pen-down after Ctrl+Z paid for all of them in the first frame '
          'of the stroke',
    );
    expect(
      FocusManager.instance.highlightMode,
      FocusHighlightMode.traditional,
      reason: 'a highlight follows FOCUS, not the last device: a keyboard '
          'user who tabs through the chrome keeps it, which touch would '
          'hide for good',
    );
  });

  testWidgets('drawing with a key held down leaves the highlight mode '
      'alone', (tester) async {
    AnicelBinding.applyFocusHighlightPolicy(FocusManager.instance);
    await tester.pumpWidget(const SizedBox.expand());
    var flips = 0;
    void countFlip(FocusHighlightMode _) => flips += 1;
    FocusManager.instance.addHighlightModeListener(countFlip);
    addTearDown(
      () => FocusManager.instance.removeHighlightModeListener(countFlip),
    );

    // Shift for a straight line, Space to pan: the key stays down and
    // repeats, and the pen keeps moving between the repeats.
    final pen = await tester.startGesture(
      const Offset(40, 40),
      kind: PointerDeviceKind.stylus,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var step = 0; step < 4; step += 1) {
      await pen.moveBy(const Offset(9, 5));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await pen.moveBy(const Offset(9, 5));
    await pen.up();
    await tester.pump();

    expect(
      flips,
      0,
      reason: '🚨a held key repeats while the pen moves — without the policy '
          'every repeat and the move after it flip the mode, and each flip '
          'rebuilds every InkResponse on the screen in the middle of the '
          'stroke',
    );
  });

  test('the app binding applies the policy to the manager it creates', () {
    // A source check, because nothing else can see it: `AnicelBinding`
    // cannot be the binding under `flutter_test`, so no widget test runs
    // its `initInstances` and every one would stay green with the call gone.
    final source = File(
      'lib/src/ui/ui_scale_binding.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final binding = source.indexOf('class AnicelBinding');
    expect(binding, greaterThanOrEqualTo(0), reason: 'fixture: the binding');
    final init = source.indexOf('void initInstances()', binding);
    expect(init, greaterThan(binding), reason: 'fixture: its initInstances');
    final body = source.substring(init, source.indexOf('\n  }\n', init));
    expect(
      body,
      contains('applyFocusHighlightPolicy(focusManager);'),
      reason: 'the app binding must apply the policy to its own focus '
          'manager — without it the shipped app flips the highlight mode on '
          'every shortcut again',
    );
  });
}
