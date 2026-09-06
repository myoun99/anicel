// THE TWO OS-NAMED ROWS OF THE RUNTIME PATH REPORT READ ONE HOST
// CLASSIFICATION — the audio codec stack and the video encoder are two
// columns of the same table, not two ladders that could drift apart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/runtime_path_report.dart';

import '../helpers/native_engine_path.dart';

void main() {
  // The rows only NAME a host on their primary path, and the primary path
  // needs the built engine — the same resolver every parity suite uses.
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    debugQaEngineLibraryPathOverride = libraryPath;
    QaAudioDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
  });

  tearDown(() {
    QaAudioDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  test('the audio codec and the video encoder are named for THIS host', () {
    final entries = collectRuntimePathReport();
    final audio = entries.singleWhere(
      (entry) => entry.subsystem == 'Audio import decoder',
    );
    final video = entries.singleWhere(
      (entry) => entry.subsystem == 'Video export encoder',
    );
    // The expected names, spelled here by hand so the table in the product
    // cannot quietly rename a host.
    final (audioName, videoName) = Platform.isWindows
        ? ('Media Foundation', 'Media Foundation')
        : Platform.isMacOS || Platform.isIOS
        ? ('AudioToolbox', 'AVAssetWriter')
        : Platform.isAndroid
        ? ('MediaCodec', 'MediaCodec (NDK)')
        : ('OS codecs', 'OS encoder');

    expect(audio.isPrimary, isTrue, reason: 'the native decoder must load');
    expect(
      audio.active,
      'Native (dr_libs WAV/FLAC/MP3, stb_vorbis OGG, '
      '$audioName for AAC/M4A)',
    );
    expect(
      video.active,
      video.isPrimary ? '$videoName (H.264/AAC MP4)' : 'ffmpeg fallback',
    );
  }, skip: skip);
}
