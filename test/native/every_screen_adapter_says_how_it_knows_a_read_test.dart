import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show SharedTexture;

import 'package:anicel/src/native/screen_turns.dart';

/// Card every-platform-knows-the-screen-was-read (관제 2026-11-24 ②③): the
/// law is one, the Dart side's ([ScreenTurns]); each platform's adapter has
/// only how it knows that Flutter's GPU has read a screen — or names why it
/// cannot. One that cannot draws by its frames alone through the same code
/// as a word cut off: its texture's unread count is always 0
/// (`a_screen_draws_on_no_surface_flutter_may_still_read_test`, 「where
/// Flutter tells nothing」 and ㉠).
void main() {
  test('🎯each adapter tells its reads, or names why it cannot', () {
    expect(
      SharedTexture.untoldOn('android'),
      isNull,
      reason: 'patch 0007 tells',
    );
    for (final os in ['windows', 'linux', 'macos', 'ios']) {
      expect(SharedTexture.untoldOn(os), isNotNull, reason: os);
    }
  });

  test('🎯an adapter named as telling nothing hands no read on, and '
      'Android\'s hands Flutter the engine\'s', () {
    expect(
      File('packages/gpu_engine/lib/gpu_engine.dart').readAsStringSync(),
      contains("'readSignal': Native.addressOf"),
    );
    const shims = {
      'windows': 'packages/gpu_engine/windows/gpu_engine_plugin_c_api.cpp',
      'linux': 'packages/gpu_engine/linux/gpu_engine_plugin.cc',
      'macos · ios': 'packages/gpu_engine/darwin/Classes/GpuEnginePlugin.m',
    };
    for (final MapEntry(key: os, value: path) in shims.entries) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('screen_read')),
        reason:
            '$os tells its reads now: its SharedTexture.untoldOn words '
            'are no longer true',
      );
    }
  });

  test('a read heard, or a word cut off, says more than why none can be', () {
    final waits = ScreenWaits()..untold = 'why';
    expect(waits.read.word, '못 냄 · why');
    waits.heard = true;
    expect(waits.read.word, '신호');
    waits.screensCut = 1;
    expect(waits.read.word, '끊김');
  });
}
