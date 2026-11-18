// THE TWO OS-NAMED ROWS OF THE RUNTIME PATH REPORT READ ONE HOST
// CLASSIFICATION — the audio codec stack and the video encoder are two
// columns of the same table, not two ladders that could drift apart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/runtime_path_report.dart';

// ↩️The audio row named a host only when the C engine's decoder loaded,
// so this ran only where a built C engine was found — until the
// connection round put the decoder in the Rust engine the app ships with
// (connection-round-checklist H, 2026-11-08).
void main() {
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

    expect(audio.isPrimary, isTrue, reason: 'the engine\'s decoder');
    expect(
      audio.active,
      'Native (symphonia WAV/FLAC/MP3/OGG/AAC-LC/ALAC, '
      '$audioName for the rest)',
    );
    expect(
      video.active,
      video.isPrimary ? '$videoName (H.264/AAC MP4)' : 'ffmpeg fallback',
    );
  });
}
