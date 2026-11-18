import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/native/app_gpu_engine.dart' show appGpuExport;
import 'package:anicel/src/native/qa_video_decoder.dart' show MovieColours;
import 'package:anicel/src/native/qa_video_encoder.dart' show QaVideoEncoder;
import 'package:anicel/src/ui/frame_shots.dart' show frameOfRows;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuExport;

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
/// The writer takes NV12, as every H.264 writer does: the pictures go in
/// as an export's frames do — on the engine, made NV12 by its pass
/// ([engineNv12Of]). With [colours] the movie names its pictures as
/// those, as a movie made elsewhere does, and goes in as such a movie's
/// piece does (`QaVideoEncoder.open`): each frame flat at
/// [encodedMovieLumaOf] its index, its chroma neutral, and [picture] not
/// asked. ↩️Till 2026-11-15 the pictures went in as RGBA, which the writer
/// made NV12 on the CPU (board trimmed-movie-decodes-to-nv12-Q2).
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
  MovieColours? colours,
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
      colours: colours,
    ),
    isTrue,
    reason: encoder.lastError,
  );
  // 🚨A step refused lets the job go: the engine writes one movie at a
  // time, and a job left open answers every later open 「bad open
  // parameters」 — on the Mac runner one refused frame failed three more
  // tests that way (round-1091-builds-all-stop-at-their-checks, 11-16).
  try {
    _writeOpened(
      encoder,
      frames: frames,
      fps: fps,
      picture: picture,
      sound: sound,
      sampleRate: sampleRate,
      soundFrames: soundFrames,
      colours: colours,
    );
  } on Object {
    encoder.abort();
    rethrow;
  }
  return true;
}

/// [writeEncodedMovie]'s frames and sound into the job [encoder] has open,
/// and the job finished.
void _writeOpened(
  QaVideoEncoder encoder, {
  required int frames,
  required ({int numerator, int denominator}) fps,
  required MovieColour Function(int frame, int pixel)? picture,
  required int Function(int sample)? sound,
  required int sampleRate,
  required int? soundFrames,
  required MovieColours? colours,
}) {
  final nv12 = encoder.nv12Frame;
  expect(nv12, isNotNull, reason: 'an H.264 writer takes NV12');
  final stride = GpuExport.nv12RowBytes(nv12!.width);
  final heard = sound == null ? 0 : soundFrames ?? frames;
  final running = Stopwatch()..start();
  var written = 0;
  for (var frame = 0; frame < math.max(frames, heard); frame += 1) {
    if (frame < frames) {
      final bytes = colours == null
          ? engineNv12Of(_pictureOf(frame, picture), _width, _height, nv12)
          : _flatNv12Of(frame, nv12, stride);
      expect(
        encoder.writeNv12(bytes, stride: stride),
        isTrue,
        reason: _why(encoder, 'frame $frame of $frames', running),
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
        reason: _why(encoder, 'the sound of frame $frame', running),
      );
      written = upTo;
    }
  }
  expect(
    encoder.finish(),
    isTrue,
    reason: _why(encoder, 'the finish', running),
  );
}

/// Why [step] of a job was refused: how long the job had run, and what
/// the writer said — on the Mac runner a frame of a long movie was refused
/// some 70 s in with nothing said (round-1091-builds-all-stop-at-their-
/// checks, 11-16).
String _why(QaVideoEncoder encoder, String step, Stopwatch running) {
  final said = encoder.lastError;
  return '$step, ${running.elapsedMilliseconds} ms into the job: '
      '${said.isEmpty ? 'the writer said nothing' : said}';
}

const int _width = 64;
const int _height = 48;

/// [rgba] — [width] × [height] premultiplied pixels, red first — as an
/// export hands an H.26x writer its frame: on the engine ([frameOfRows])
/// and made NV12 there by its pass, the writer's [frame] (its
/// `nv12Frame`), rows [GpuExport.nv12RowBytes] apart.
Uint8List engineNv12Of(
  Uint8List rgba,
  int width,
  int height,
  ({int width, int height}) frame,
) {
  final export = appGpuExport;
  final laid = frameOfRows(export, rgba, width, height);
  try {
    return export
        .nv12(
          laid,
          width,
          height,
          frameWidth: frame.width,
          frameHeight: frame.height,
          stride: GpuExport.nv12RowBytes(frame.width),
        )
        .take();
  } finally {
    laid.free();
  }
}

/// The luma every pixel of [frame] holds in a movie written with its own
/// colours ([writeEncodedMovie]): 40 on, 12 a frame, inside studio range.
int encodedMovieLumaOf(int frame) => 40 + 12 * (frame % 15);

/// [frame] as NV12 in the writer's [shape], rows [stride] apart: its Y
/// rows flat at [encodedMovieLumaOf], then half as many CbCr rows,
/// neutral.
Uint8List _flatNv12Of(int frame, ({int width, int height}) shape, int stride) {
  final luma = stride * shape.height;
  return Uint8List(luma * 3 ~/ 2)
    ..fillRange(0, luma, encodedMovieLumaOf(frame))
    ..fillRange(luma, luma * 3 ~/ 2, 128);
}

/// [frame]'s picture as the app hands the engine one: RGBA, [picture]'s
/// colours opaque — grey where there is no [picture].
Uint8List _pictureOf(
  int frame,
  MovieColour Function(int frame, int pixel)? picture,
) {
  final colourOf = picture ?? (_, _) => (red: 128, green: 128, blue: 128);
  final rgba = Uint8List(_width * _height * 4);
  for (var pixel = 0; pixel < _width * _height; pixel += 1) {
    final (:red, :green, :blue) = colourOf(frame, pixel);
    rgba
      ..[pixel * 4] = red
      ..[pixel * 4 + 1] = green
      ..[pixel * 4 + 2] = blue
      ..[pixel * 4 + 3] = 255;
  }
  return rgba;
}
