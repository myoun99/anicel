import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../../helpers/native_engine_path.dart';

/// A test file is a process of its own: in this one the audio device has
/// never been opened, and nothing has ever armed its transport.
///
/// ⚠️It stays the ONLY test here. In any other file a test that ran before
/// has opened the device, and the native side remembers that it did — the
/// state this asks about cannot be got back to.
///
/// 🧪A mutant that took the reader's own guard away lived: with no arm and
/// no stamp, the arm the stamp was written under and the arm the transport
/// is in are both nothing, and the same.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  test('🚨a device that was never opened has no point: there is no run for '
      'one to be of', () {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    addTearDown(() {
      QaAudioDevice.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
    });

    final device = QaAudioDevice.instance;
    expect(device, isNotNull, reason: 'the binary did not bind');
    expect(device!.clockPoint, isNull);
  }, skip: skip);
}
