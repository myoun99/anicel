import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️F-190 (유저 2026-09-27): 「블루투스로 연결한 헤드셋으로 소리가 안나.
/// 기본적으로 그 헤드셋으로 다른앱에선 나는데 이 앱만 소리가 스피커로나옴」.
///
/// iOS routes by the app's ONE audio session, which the engine's device
/// context sets up as it comes up (`qa_audio_ensure_context`). Under
/// PlayAndRecord — kept: the voice take needs the input — a Bluetooth
/// headset is an allowed output only when the session says
/// AllowBluetoothA2DP, and miniaudio's default config says DefaultToSpeaker
/// and nothing about Bluetooth. That default was what the context got.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on has an audio
/// session: Apple's mobile backend is compiled into the iOS build only. It
/// can say the context is opened with the options that let a headset in;
/// what the iPad does with them is the device's to show.
void main() {
  test('the device context asks for PlayAndRecord with the headset let in',
      () {
    final context = sourceBodyOf(
      File('packages/qa_native/src/qa_audio_device.c').readAsStringSync(),
      'static int qa_audio_ensure_context(',
    );
    expect(context, contains('ma_ios_session_category_play_and_record'));
    expect(
      context,
      contains('ma_ios_session_category_option_allow_bluetooth_a2dp'),
    );
    expect(
      context,
      contains('ma_context_init(NULL, 0, &config, &g_context)'),
      reason: 'and hands THAT config to the context — one built and then '
          'dropped would read the same above',
    );
  });
}
