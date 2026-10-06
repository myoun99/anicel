import 'package:anicel/src/models/app_input_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppInput.toolAcceptsPress` — the press a tool's own canvas layer ACTS
/// on: from a device that may drive a tool at all, and its primary contact.
///
/// The selection layer spelled the pair out and the text tool's layer would
/// have again (R9-rest); it is one question now, asked here.
void main() {
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  PointerDownEvent press(
    PointerDeviceKind kind, {
    int buttons = kPrimaryButton,
  }) => PointerDownEvent(kind: kind, buttons: buttons);

  test('a mouse or a pen: its primary contact, and nothing held with it', () {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
      expect(AppInput.toolAcceptsPress(press(kind)), isTrue, reason: '$kind');
      for (final buttons in [
        kSecondaryButton,
        kMiddleMouseButton,
        // The tip down WITH a barrel button is the mapping's, not the tool's.
        kPrimaryButton | kSecondaryButton,
      ]) {
        expect(
          AppInput.toolAcceptsPress(press(kind, buttons: buttons)),
          isFalse,
          reason: '$kind with buttons $buttons',
        );
      }
    }
  });

  test('a finger: while one finger DRAWS — whatever buttons it reports', () {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );

    expect(AppInput.toolAcceptsPress(press(PointerDeviceKind.touch)), isTrue);
    expect(
      AppInput.toolAcceptsPress(press(PointerDeviceKind.touch, buttons: 0)),
      isTrue,
    );
  });

  test('⛔a finger that NAVIGATES is no tool\'s — the host\'s own answer for '
      'one finger, as for every tool door', () {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );

    expect(
      AppInput.toolAcceptsPress(
        press(PointerDeviceKind.touch),
        oneFinger: CanvasTouchDragAction.navigate,
      ),
      isFalse,
    );
    expect(
      AppInput.toolAcceptsPress(
        press(PointerDeviceKind.stylus),
        oneFinger: CanvasTouchDragAction.navigate,
      ),
      isTrue,
      reason: 'a pen still drives the tool',
    );
  });
}
