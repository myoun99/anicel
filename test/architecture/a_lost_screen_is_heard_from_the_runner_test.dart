import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/lost_screen.dart';

import '../helpers/source_body.dart';

/// 🗣️a-lost-gpu-leaves-the-window-unpainted-Q1 (유저 2026-11-16): 「윈도
/// 창으로 알리고 저장하고 다시 시작할지 묻는다」 — the Windows runner hears the
/// screen's device go, says so on [LostScreen.channel], asks with a window
/// Windows draws and starts Anicel again.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// handover's type check. ⚠️A SOURCE PIN, because this suite runs no
/// runner: a reset heard is the Surface's to show (dxcap -forcetdr,
/// 2026-11-18 15:08 — the watch's device removed with the screen's).
void main() {
  final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
  final lost = File('windows/runner/lost_screen.cpp').readAsStringSync();

  test('the runner says the device went on the channel, and hears the ask '
      'and the start again there — the names spelled as Dart spells them',
      () {
    expect(
      source,
      contains('kScreenChannel[] = "${LostScreen.channel.name}";'),
    );
    expect(source, contains('kScreenWent[] = "${LostScreen.wentMethod}";'));
    expect(
      source,
      contains('kAskWithWindows[] = "${LostScreen.askMethod}";'),
    );
    expect(
      source,
      contains('kStartAgain[] = "${LostScreen.startAgainMethod}";'),
    );
    expect(
      sourceBodyOf(source, 'bool FlutterWindow::OnCreate()'),
      contains('ListenForTheScreen();'),
    );
    final listens = sourceBodyOf(
      source,
      'void FlutterWindow::ListenForTheScreen()',
    );
    for (final step in [
      'kScreenChannel',
      'kAskWithWindows',
      'AskWithWindows(GetHandle()',
      'kStartAgain',
      'StartAgainFor(GetHandle(), words)',
      'GetGraphicsAdapter(&adapter)',
      'kScreenWentMessage',
    ]) {
      expect(listens, contains(step));
    }
    final handles = sourceBodyOf(source, 'FlutterWindow::MessageHandler(');
    expect(handles, contains('if (message == kScreenWentMessage) {'));
    expect(
      handles,
      contains('kScreenWent, std::make_unique<flutter::EncodableValue>('),
    );
    expect(
      sourceBodyOf(source, 'void FlutterWindow::OnDestroy()'),
      contains('screen_watch_ = nullptr;'),
      reason: 'the watch posts to this window, which is going',
    );
  });

  test('the watch asks its own device on the screen\'s adapter, and a '
      'restart lets go of the handed files first and ends the process '
      'only once the next has started', () {
    final watch = sourceBodyOf(lost, 'void Watch(');
    expect(watch, contains('RegisterDeviceRemovedEvent'));
    expect(watch, contains('GetDeviceRemovedReason()'));
    expect(watch, contains('PostMessageW(window, message'));
    final again = sourceBodyOf(lost, 'bool StartAgainFor(');
    final letGo = again.indexOf('RemovePropW(window, kRunningWindowProp)');
    final started = again.indexOf('CreateProcessW(');
    final ended = again.indexOf('TerminateProcess(');
    expect(letGo, greaterThanOrEqualTo(0));
    expect(started, greaterThan(letGo), reason: 'or it is handed the files');
    expect(ended, greaterThan(started));
    final manifest = File(
      'windows/runner/runner.exe.manifest',
    ).readAsStringSync();
    expect(
      manifest,
      contains('name="Microsoft.Windows.Common-Controls"'),
      reason: 'TaskDialogIndirect is only in Common Controls 6',
    );
  });
}
