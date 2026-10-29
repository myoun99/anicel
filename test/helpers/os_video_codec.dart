import 'dart:io';

import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_engine_path.dart';

/// Whether this host's engine writes movies with the OS: Media Foundation
/// on Windows, AVAssetWriter on macOS. Linux exports through FFmpeg, and
/// Android's encoder is a device's, never a test host's.
bool get osHasVideoEncoder => Platform.isWindows || Platform.isMacOS;

/// Whether this host's engine reads movies with the OS: Media Foundation's
/// source reader on Windows, AVFoundation on macOS. The Linux engine has no
/// reader at all.
bool get osHasVideoDecoder => Platform.isWindows || Platform.isMacOS;

/// The engine's OS video encoder — or null, the test marked skipped, or
/// FAILED where this run must have one ([videoCodecAbsence]).
QaVideoEncoder? osVideoEncoderOrSkip() {
  final encoder = QaVideoEncoder.instance;
  if (encoder != null && encoder.isSupported) {
    return encoder;
  }
  _answer(
    videoCodecAbsence(
      what: 'video encoder',
      engineBound: encoder != null,
      hostHasOne: osHasVideoEncoder,
      engineRequired: nativeEngineRequired,
    ),
  );
  return null;
}

/// The engine's OS video decoder — or null, the test marked skipped, or
/// FAILED where this run must have one ([videoCodecAbsence]).
QaVideoDecoder? osVideoDecoderOrSkip() {
  final decoder = QaVideoDecoder.instance;
  if (decoder != null && decoder.isSupported) {
    return decoder;
  }
  _answer(
    videoCodecAbsence(
      what: 'video decoder',
      engineBound: decoder != null,
      hostHasOne: osHasVideoDecoder,
      engineRequired: nativeEngineRequired,
    ),
  );
  return null;
}

/// 🚨A TEST THAT NEEDS THE OS VIDEO CODEC ASKS FOR IT HERE — and where there
/// is none it is SKIPPED, with why, never passed in silence.
///
/// 🗣️Board F-494 (관제 2026-10-29): the movies written through
/// `writeEncodedMovie` returned when there was no encoder, and so did every
/// test that read one back without a decoder — on a machine that should
/// have them and lost them, the whole family went green having tested
/// nothing. `qa_video_encoder_v21_test` already answered it this way; the
/// others returned in silence, or failed anywhere but Linux.
/// `a_missing_video_codec_is_a_named_skip_test` keeps them here.
///
/// What a test does where this run has no OS [what]: it FAILS when the run
/// builds its engine ([nativeEngineRequired]) on a host that has one, and is
/// skipped otherwise — with the reason either way.
({bool fails, String reason}) videoCodecAbsence({
  required String what,
  required bool engineBound,
  required bool hostHasOne,
  required bool engineRequired,
}) {
  final fails = engineRequired && hostHasOne;
  final why = engineBound
      ? 'the engine has no OS $what on this platform'
      : nativeEngineMissingSkipReason;
  return (
    fails: fails,
    reason: fails ? 'QA_REQUIRE_NATIVE=1 but no OS $what: $why' : why,
  );
}

void _answer(({bool fails, String reason}) absence) {
  if (absence.fails) {
    fail(absence.reason);
  }
  markTestSkipped(absence.reason);
}
