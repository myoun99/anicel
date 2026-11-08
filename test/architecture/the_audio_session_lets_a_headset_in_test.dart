import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️F-190 (유저 2026-09-27): 「블루투스로 연결한 헤드셋으로 소리가 안나.
/// 기본적으로 그 헤드셋으로 다른앱에선 나는데 이 앱만 소리가 스피커로나옴」.
///
/// iOS routes by the app's ONE audio session, which the engine's device
/// context sets up as it comes up (`mod session` in the device crate's
/// backend). Under PlayAndRecord — kept: the voice take needs the input — a
/// Bluetooth headset is an allowed output only when the session says
/// AllowBluetoothA2DP. ↩️The C's miniaudio context said DefaultToSpeaker
/// and nothing about Bluetooth by default, and that default was what it
/// got; cpal sets no category at all, so the context sets it.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on has an audio
/// session: the session is compiled into the iOS build only. It can say the
/// context asks for the options that let a headset in, and activates the
/// session it set; what the iPad does with them is the device's to show.
void main() {
  test('the device context asks for PlayAndRecord with the headset let in',
      () {
    final session = sourceBodyOf(
      File(
        'packages/gpu_engine/rust/native/audio_device/src/backend.rs',
      ).readAsStringSync(),
      'pub(super) fn begin() -> Option<()> {',
    );
    expect(session, contains('AVAudioSessionCategoryPlayAndRecord'));
    expect(session, contains('AVAudioSessionCategoryOptions::DefaultToSpeaker'));
    expect(
      session,
      contains('AVAudioSessionCategoryOptions::AllowBluetoothA2DP'),
    );
    expect(
      session,
      contains('setCategory_withOptions_error('
          'AVAudioSessionCategoryPlayAndRecord?, options)'),
      reason: 'and hands THOSE options to the session — options built and '
          'then dropped would read the same above',
    );
    expect(session, contains('setActive_error(true)'));
  });
}
