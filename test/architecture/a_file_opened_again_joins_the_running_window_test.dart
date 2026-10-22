import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/handed_files.dart';

import '../helpers/source_body.dart';

/// 🗣️open-door-windows-open-with-Q1 (유저 2026-10-22: 「떠 있는 창의 새
/// 탭으로」): a file opened with Anicel while one runs opens in that one.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// handover's type check: the second Anicel finds the window that takes
/// files, hands it the paths and ends before it makes a window, and the
/// running window says them on [HandedFiles.channel].
///
/// ⚠️A SOURCE PIN, because this suite runs no runner: it can say each half
/// does its part; a second Anicel ending is the desktop's to show.
void main() {
  final channel = '"${HandedFiles.channel.name}"';
  const open = '"${HandedFiles.openMethod}"';

  test('the running window takes the paths from its first frame on and says '
      'them on the channel, and lets go of the mark as it goes', () {
    final header = File('windows/runner/flutter_window.h').readAsStringSync();
    expect(header, contains('kRunningWindowProp[]'));
    expect(header, contains('kHandedFilesTag'));
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(source, contains('kHandedFilesChannel[] = $channel;'));
    expect(source, contains('kOpenHanded[] = $open;'));
    final created = sourceBodyOf(source, 'bool FlutterWindow::OnCreate()');
    expect(created, contains('kHandedFilesChannel'));
    final firstFrame = sourceBodyOf(created, 'SetNextFrameCallback([&]()');
    expect(
      firstFrame.indexOf('SetPropW(GetHandle(), kRunningWindowProp'),
      greaterThan(firstFrame.indexOf('app_can_answer_ = true;')),
      reason: 'marked once Dart hears, and not before',
    );
    expect(
      sourceBodyOf(source, 'void FlutterWindow::OnDestroy()'),
      contains('RemovePropW(GetHandle(), kRunningWindowProp)'),
    );
    final copied = sourceBodyOf(
      sourceBodyOf(source, 'FlutterWindow::MessageHandler('),
      'case WM_COPYDATA:',
    );
    expect(copied, contains('kHandedFilesTag'));
    expect(copied, contains('SayHandedFiles(*data);'));
    expect(
      sourceBodyOf(source, 'void FlutterWindow::SayHandedFiles('),
      contains('kOpenHanded'),
    );
  });

  test('a second Anicel hands its files to the running window before it '
      'makes one of its own, and runs when nothing takes them', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    expect(
      sourceBodyOf(source, 'BOOL CALLBACK FindTheRunningWindow('),
      contains('GetPropW(window, kRunningWindowProp)'),
    );
    final hand = sourceBodyOf(source, 'bool HandToTheRunningWindow(');
    for (final step in [
      'files.empty()',
      'EnumWindows(FindTheRunningWindow',
      'Absolute(file)',
      'kHandedFilesTag',
      'SendMessageTimeoutW(running, WM_COPYDATA',
      'SetForegroundWindow(running)',
    ]) {
      expect(hand, contains(step));
    }
    final start = sourceBodyOf(source, 'int APIENTRY wWinMain(');
    final handed = start.indexOf(
      'if (HandToTheRunningWindow(command_line_arguments)) {',
    );
    expect(handed, greaterThanOrEqualTo(0));
    expect(
      handed,
      lessThan(start.indexOf('window.Create(')),
      reason: 'it ends before a window of its own stands',
    );
  });
}
