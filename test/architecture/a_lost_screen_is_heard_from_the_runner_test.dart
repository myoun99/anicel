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

  test('the runner says the device went on the channel, and hears the ask, '
      'the start again and the end there — the names spelled as Dart '
      'spells them',
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
    expect(source, contains('kEnd[] = "${LostScreen.endMethod}";'));
    expect(
      source,
      contains('kScreenStands[] = "${LostScreen.standsMethod}";'),
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
      'kEnd',
      'EndThisProcess();',
      'kScreenStands',
      'screen_watch_ != nullptr && screen_watch_->Stands()',
      'GetGraphicsAdapter(&adapter)',
      'kScreenWentMessage',
    ]) {
      expect(listens, contains(step));
    }
    final handles = sourceBodyOf(source, 'FlutterWindow::MessageHandler(');
    expect(
      handles,
      stringContainsInOrder([
        'if (message == kScreenWentMessage) {',
        'SayTheScreenWent(screen_channel_.get(), kScreenWent, wparam, '
            'lparam);',
      ]),
    );
    // H63 ③: [the reason as an int32, the moment it was seen as an int64]
    // — the shape `LostScreen.listen` reads, whoever said the screen went.
    expect(
      sourceBodyOf(source, 'void SayTheScreenWent('),
      stringContainsInOrder([
        'channel->InvokeMethod(',
        'method,',
        'std::make_unique<flutter::EncodableValue>(flutter::EncodableList{',
        'flutter::EncodableValue(static_cast<int32_t>(reason))',
        'flutter::EncodableValue(static_cast<int64_t>(seen_at))',
      ]),
    );
    expect(
      sourceBodyOf(source, 'void FlutterWindow::OnDestroy()'),
      contains('screen_watch_ = nullptr;'),
      reason: 'the watch posts to this window, which is going',
    );
  });

  // 🗣️유저 2026-11-22 (board a-real-gpu-reset-went-unheard-on-the-main-pc):
  // the engine is mended. Its first step: the engine Anicel builds says
  // that its screen's context is lost, by a window message registered by
  // a name — which only the patch and the runner spell, and no compiler
  // holds the two to one spelling.
  test('the runner hears the engine\'s own word by the name the engine\'s '
      'patch posts it by, and says it on the channel as the engine\'s, with '
      'the moment it heard it', () {
    expect(
      source,
      contains(
        'kScreenContextLost[] = "${LostScreen.contextLostMethod}";',
      ),
    );
    final name = RegExp(
      r'kEngineContextLostMessage\[\] =\s+L"(\w+)";',
    ).firstMatch(source)?[1];
    expect(name, isNotNull, reason: 'premise: the runner names the message');
    final patch = File(
      'tool/flutter_engine/3.47.4/'
      '0002-egl-context-lost-is-posted-to-the-process-windows.patch',
    ).readAsStringSync();
    expect(
      patch,
      contains('+constexpr wchar_t kContextLostMessageName[] = L"$name";'),
      reason: 'the engine registers the name the runner registers',
    );
    // Said where every failed EGL call of the embedder passes, and with
    // the EGL error as the WPARAM the runner hands on.
    expect(
      patch,
      stringContainsInOrder([
        'PostMessageW(window, static_cast<UINT>(message), EGL_CONTEXT_LOST',
        '::RegisterWindowMessageW(kContextLostMessageName)',
        ' void LogEGLError(std::string_view message) {',
        '+  if (error == EGL_CONTEXT_LOST) {',
        '+    TellContextLost();',
      ]),
    );
    expect(
      sourceBodyOf(source, 'UINT EngineContextLostMessage()'),
      contains('::RegisterWindowMessageW(kEngineContextLostMessage)'),
    );
    expect(
      sourceBodyOf(source, 'FlutterWindow::MessageHandler('),
      stringContainsInOrder([
        'if (const UINT lost = EngineContextLostMessage();',
        'lost != 0 && message == lost) {',
        'SayTheScreenWent(screen_channel_.get(), kScreenContextLost, wparam,',
        'UnixMillisecondsNow());',
      ]),
    );
  });

  test('the watch asks its own device on the screen\'s adapter, and a '
      'restart lets go of the handed files first and ends the process '
      'only once the next has started', () {
    final watch = sourceBodyOf(lost, 'void Watch(');
    expect(watch, contains('RegisterDeviceRemovedEvent'));
    expect(watch, contains('GetDeviceRemovedReason()'));
    expect(
      watch,
      stringContainsInOrder([
        'PostMessageW(window, message, static_cast<WPARAM>(reason),',
        'UnixMillisecondsNow());',
      ]),
      reason: 'H63 ③: the moment the watch saw it, beside the reason',
    );
    // 🗣️a-real-gpu-reset-went-unheard-on-the-main-pc-Q1: what the app
    // asks before it draws a pixel of its own is asked of the device then,
    // not read from what the thread last heard.
    expect(
      sourceBodyOf(lost, 'bool ScreenWatch::Stands() const'),
      contains('device_->GetDeviceRemovedReason() == S_OK'),
    );
    final again = sourceBodyOf(lost, 'bool StartAgainFor(');
    final letGo = again.indexOf('RemovePropW(window, kRunningWindowProp)');
    final started = again.indexOf('CreateProcessW(');
    final ended = again.indexOf('EndThisProcess();');
    expect(letGo, greaterThanOrEqualTo(0));
    expect(started, greaterThan(letGo), reason: 'or it is handed the files');
    expect(ended, greaterThan(started));
    expect(
      sourceBodyOf(lost, 'void EndThisProcess()'),
      contains('TerminateProcess(::GetCurrentProcess()'),
      reason: 'not the window closed: the teardown touches the gone device',
    );
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
