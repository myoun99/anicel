import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'os_video_codec.dart';

/// A colour of a picture in an [writeEncodedMovie] movie.
typedef MovieColour = ({int red, int green, int blue});

/// A real movie at [path], written by the engine's own encoder — false
/// where this run has no encoder, the test then marked skipped or failed
/// ([osVideoEncoderOrSkip]).
///
/// [frames] pictures, 64×48 (the OS encoder turns tiny frames away) at
/// [fps]: each pixel the colour [picture] gives it, or grey where none is
/// given. With [sound], a stereo track at [sampleRate] runs under them for
/// [soundFrames] frames — as long as the pictures unless said — each sample
/// [sound]'s value on both channels; without it, the track holds nothing.
/// Each frame's sound ends where its frame does, to the sample.
///
/// 🚨ONE WRITER (board test-movie-writers-with-sound-are-five-copies,
/// 2026-10-29): six tests each opened the encoder, wrote their pictures and
/// their sound frame by frame and finished it — one algorithm, spelled six
/// ways, one of them laying the same count of samples under every frame,
/// which drifts off where the frames end wherever a frame is no whole
/// count of them (44.1kHz at 24 fps). ⛔A test writes its movie here;
/// `a_movie_is_written_one_way_test` keeps it so.
bool writeEncodedMovie(
  String path, {
  required int frames,
  ({int numerator, int denominator}) fps = (numerator: 24, denominator: 1),
  MovieColour Function(int frame, int pixel)? picture,
  int Function(int sample)? sound,
  int sampleRate = 44100,
  int? soundFrames,
}) {
  final encoder = osVideoEncoderOrSkip();
  if (encoder == null) {
    return false;
  }
  expect(
    encoder.open(
      path: path,
      width: _width,
      height: _height,
      fpsNumerator: fps.numerator,
      fpsDenominator: fps.denominator,
      sampleRate: sampleRate,
      channels: 2,
    ),
    isTrue,
    reason: encoder.lastError,
  );
  final heard = sound == null ? 0 : soundFrames ?? frames;
  var written = 0;
  for (var frame = 0; frame < math.max(frames, heard); frame += 1) {
    if (frame < frames) {
      expect(
        encoder.writeFrame(_pictureOf(frame, picture)),
        isTrue,
        reason: encoder.lastError,
      );
    }
    if (frame < heard) {
      final upTo =
          (frame + 1) * sampleRate * fps.denominator ~/ fps.numerator;
      final pcm = Int16List((upTo - written) * 2);
      for (var at = written; at < upTo; at += 1) {
        final value = sound!(at);
        pcm[(at - written) * 2] = value;
        pcm[(at - written) * 2 + 1] = value;
      }
      expect(
        encoder.writeAudio(pcm, upTo - written),
        isTrue,
        reason: encoder.lastError,
      );
      written = upTo;
    }
  }
  expect(encoder.finish(), isTrue, reason: encoder.lastError);
  return true;
}

const int _width = 64;
const int _height = 48;

/// [frame]'s picture, as the encoder takes it: RGBA, [picture]'s colours
/// opaque — or every byte grey where there is no [picture].
Uint8List _pictureOf(
  int frame,
  MovieColour Function(int frame, int pixel)? picture,
) {
  final rgba = Uint8List(_width * _height * 4);
  if (picture == null) {
    return rgba..fillRange(0, rgba.length, 128);
  }
  for (var pixel = 0; pixel < _width * _height; pixel += 1) {
    final (:red, :green, :blue) = picture(frame, pixel);
    rgba
      ..[pixel * 4] = red
      ..[pixel * 4 + 1] = green
      ..[pixel * 4 + 2] = blue
      ..[pixel * 4 + 3] = 255;
  }
  return rgba;
}
