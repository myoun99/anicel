import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/window_place.dart';

import '../helpers/source_body.dart';

/// 🗣️I-116 (유저 2026-10-21): 「닫고 열때 마지막크기/위치로 열고싶음」 — the
/// window opens where the last run left it, on the three desktops.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// place's type check: every desktop runner answers [WindowPlace.setMethod]
/// on [WindowPlace.channel] by placing its window, and says with
/// [WindowPlace.changedMethod] where it stands, the five keys
/// `windowFrameFromJson` reads.
///
/// ⚠️A SOURCE PIN, because this suite runs no runner, and on no Mac and no
/// Linux desktop: it can say each runner answers and reports; where the
/// window lands is the desktop's to show.
void main() {
  final channel = '"${WindowPlace.channel.name}"';
  const set = '"${WindowPlace.setMethod}"';
  const changed = '"${WindowPlace.changedMethod}"';
  const keys = ['"left"', '"top"', '"width"', '"height"', '"maximized"'];

  void saysEveryKey(String body, String where) {
    for (final key in keys) {
      expect(body, contains(key), reason: '$where says $key');
    }
  }

  test('Windows hears the channel from the start, places the window while '
      'it is hidden, and says where it stands after a drag and a snap', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(source, contains('kWindowPlaceChannel[] = $channel;'));
    expect(source, contains('kSetPlace[] = $set;'));
    expect(source, contains('kPlaceChanged[] = $changed;'));
    expect(
      sourceBodyOf(source, 'bool FlutterWindow::OnCreate()'),
      contains('ListenForPlace();'),
    );
    final listen = sourceBodyOf(source, 'void FlutterWindow::ListenForPlace()');
    expect(listen, contains('kSetPlace'));
    saysEveryKey(listen, 'ListenForPlace');
    expect(
      sourceBodyOf(source, 'void FlutterWindow::SetPlace('),
      contains('SetWindowPlacement('),
    );
    final say = sourceBodyOf(source, 'void FlutterWindow::SayPlace()');
    expect(say, contains('kPlaceChanged'));
    saysEveryKey(say, 'SayPlace');
    final handler = sourceBodyOf(source, 'FlutterWindow::MessageHandler(');
    final dragEnded = handler.substring(
      handler.indexOf('case WM_EXITSIZEMOVE:'),
      handler.indexOf('case WM_WINDOWPOSCHANGED:'),
    );
    expect(dragEnded, contains('SayPlace();'));
    expect(
      sourceBodyOf(handler, 'case WM_WINDOWPOSCHANGED: {'),
      contains('SayPlace();'),
    );
  });

  test('the Mac makes the channel with its window, places it, and says '
      'where it stands', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final keeper = sourceBodyOf(source, 'final class WindowPlaceKeeper');
    expect(keeper, contains('name: $channel'));
    expect(keeper, contains('call.method == $set'));
    expect(
      sourceBodyOf(keeper, 'private func set('),
      contains('setFrame('),
    );
    final moved = sourceBodyOf(keeper, '@objc private func moved()');
    expect(moved, contains(changed));
    saysEveryKey(moved, 'moved()');
    expect(keeper, contains('NSWindow.didMoveNotification'));
    expect(keeper, contains('NSWindow.didEndLiveResizeNotification'));
    expect(
      sourceBodyOf(source, 'override func awakeFromNib()'),
      contains('WindowPlaceKeeper('),
    );
  });

  test('Linux registers the channel with its window, builds it, places '
      'the window and says where it settled', () {
    final source = File('linux/runner/window_place.cc').readAsStringSync();
    final register = sourceBodyOf(source, 'void anicel_window_place_register(');
    expect(register, contains(channel));
    expect(register, contains('"configure-event"'));
    final call = sourceBodyOf(source, 'void on_method_call(');
    expect(call, contains(set));
    expect(call, contains('gtk_window_move('));
    saysEveryKey(call, 'on_method_call');
    final report = sourceBodyOf(source, 'void report()');
    expect(report, contains(changed));
    saysEveryKey(report, 'report()');
    expect(
      sourceBodyOf(
        File('linux/runner/my_application.cc').readAsStringSync(),
        'static void my_application_activate(',
      ),
      contains('anicel_window_place_register(window, view);'),
    );
    expect(
      File('linux/runner/CMakeLists.txt').readAsStringSync(),
      contains('"window_place.cc"'),
    );
  });
}
