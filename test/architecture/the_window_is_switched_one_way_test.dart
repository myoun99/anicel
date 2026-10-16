import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/window_full_screen.dart';

import '../helpers/source_body.dart';

/// 🗣️I-103-Q2 (유저 2026-10-16): 「데스크톱만 켜고 끄기」 — the window's
/// full screen, a switch on the three desktops.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// switch's type check: every desktop runner answers
/// [WindowFullScreen.setMethod] on [WindowFullScreen.channel] by throwing
/// its OS's switch, and says with [WindowFullScreen.changedMethod] what the
/// window did — the report the app's mark follows ([WindowFullScreen.on]),
/// its own switch's and the OS's alike.
///
/// ⚠️A SOURCE PIN, because this suite runs no runner, and on no Mac and no
/// Linux desktop: it can say each runner answers and reports; what the
/// window does is the desktop's to show.
void main() {
  final channel = '"${WindowFullScreen.channel.name}"';
  const set = '"${WindowFullScreen.setMethod}"';
  const changed = '"${WindowFullScreen.changedMethod}"';

  test('Windows hears the channel from the start, and says where the window '
      'stands after every switch — moved or already so', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(source, contains('kWindowChannel[] = $channel;'));
    expect(source, contains('kSetFullScreen[] = $set;'));
    expect(source, contains('kFullScreenChanged[] = $changed;'));
    expect(
      sourceBodyOf(source, 'bool FlutterWindow::OnCreate()'),
      contains('ListenForFullScreen();'),
    );
    final listen = sourceBodyOf(
      source,
      'void FlutterWindow::ListenForFullScreen()',
    );
    expect(listen, contains('kWindowChannel'));
    expect(listen, contains('SetFullScreen(*on);'));
    final switched = sourceBodyOf(
      source,
      'void FlutterWindow::SetFullScreen(bool on)',
    );
    final back = sourceBodyOf(switched, '} else if (!on && full_screen_)');
    final afterBoth = switched.substring(
      switched.indexOf(back) + back.length,
    );
    expect(afterBoth, contains('InvokeMethod('));
    expect(afterBoth, contains('kFullScreenChanged'));
  });

  test('the Mac makes the channel with its window, and says the window\'s '
      'every going in and out — the green button\'s too', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final switcher = sourceBodyOf(source, 'final class FullScreenSwitch');
    expect(switcher, contains('name: $channel'));
    expect(switcher, contains('call.method == $set'));
    expect(
      sourceBodyOf(switcher, 'private func report('),
      contains('invokeMethod($changed'),
    );
    expect(switcher, contains('NSWindow.didEnterFullScreenNotification'));
    expect(switcher, contains('NSWindow.didExitFullScreenNotification'));
    expect(
      sourceBodyOf(switcher, 'private func entered()'),
      contains('report(true)'),
    );
    expect(
      sourceBodyOf(switcher, 'private func exited()'),
      contains('report(false)'),
    );
    expect(
      sourceBodyOf(switcher, 'private func set('),
      contains('report(on)'),
      reason: 'a window already so is said at once — no notice will come',
    );
    expect(
      sourceBodyOf(source, 'override func awakeFromNib()'),
      contains('FullScreenSwitch('),
    );
  });

  test('Linux registers the channel with its window, builds it, and says '
      'the window manager\'s own switch', () {
    final source = File(
      'linux/runner/window_full_screen.cc',
    ).readAsStringSync();
    final register = sourceBodyOf(
      source,
      'void anicel_window_full_screen_register(',
    );
    expect(register, contains(channel));
    expect(register, contains('"window-state-event"'));
    expect(sourceBodyOf(source, 'void on_method_call('), contains(set));
    expect(sourceBodyOf(source, 'void report('), contains(changed));
    expect(
      sourceBodyOf(source, 'gboolean on_window_state('),
      contains('report('),
    );
    expect(
      sourceBodyOf(
        File('linux/runner/my_application.cc').readAsStringSync(),
        'static void my_application_activate(',
      ),
      contains('anicel_window_full_screen_register(window, view);'),
    );
    expect(
      File('linux/runner/CMakeLists.txt').readAsStringSync(),
      contains('"window_full_screen.cc"'),
    );
  });

  // `main()` runs once, at startup, and a test that pumps a widget has
  // already missed it — the colour key program's reason for its own source
  // check (`the_shader_is_loaded_before_the_first_frame_test`).
  test('main() puts the window back before the first frame', () {
    final source = File('lib/main.dart').readAsStringSync();
    final restoredAt = source.indexOf(
      'await WindowFullScreen.restore(AppWindowStore())',
    );
    expect(restoredAt, greaterThanOrEqualTo(0));
    expect(
      restoredAt,
      lessThan(source.indexOf('runApp(')),
      reason: 'a window that opened and then jumped',
    );
  });
}
