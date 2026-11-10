import 'dart:io';
import 'dart:math' as math;

import 'package:anicel/src/models/audio_pcm_scale.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/movie_span.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/encoded_movie.dart';
import '../../helpers/native_call_watch.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// A trimmed movie's piece carries the span's own sound. Since 10-09 it is
/// cut from a decode that holds only the span (board
/// sound-lands-on-its-exact-sample-Q5), so each project frame's samples are
/// counted from the span's first frame, not the sound's — and a click in the
/// span has to come back where it sat in it.
void main() {
  test('a click inside the span comes back where it sat in it', () async {
    // A movie read and written through the engine can stop inside a native
    // call under load (board the-trimmed-movie-test-can-hang-on-windows-ci —
    // this test, unwatched, held a whole run once): the watch names the
    // step and ends the file instead.
    final watch = await NativeCallWatch.start('a movie piece keeps its sound');
    addTearDown(watch.stop);
    watch.step('asking for the encoder and writing the take');
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    String at(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    const rate = 48000;
    const perFrame = rate ~/ 24;
    const clickFrame = 6;
    if (!writeEncodedMovie(
      at('source.mp4'),
      frames: 12,
      sampleRate: rate,
      sound: (sample) {
        final index = sample - clickFrame * perFrame;
        // A decaying click, so the codec keeps it.
        return index < 0 || index >= 48
            ? 0
            : ((index.isEven ? 1 : -1) * 30000 * (1 - index / 48)).round();
      },
    )) {
      return;
    }

    watch.step('cutting the piece');
    final cut = writeMovieSpan(
      at('source.mp4'),
      at('piece.mp4'),
      trim: (inFrame: 3, outFrame: 8),
      clock: (
        rate: ProjectFrameRate.fps24,
        speed: (numerator: 1, denominator: 1),
      ),
    );
    expect(cut.failure, isNull);
    expect(cut.kept!.first, 3);

    watch.step('reading the sound of the piece');
    final sound = decodeAudioFile(at('piece.mp4'));
    expect(sound, isNotNull, reason: 'the piece carries a sound');
    var peakAt = -1;
    var peak = 0.0;
    for (var frame = 0; frame < sound!.length; frame += 1) {
      final value = sound.samples[frame * sound.channels].abs();
      if (value > peak) {
        peak = value;
        peakAt = frame;
      }
    }
    const want = (clickFrame - 3) * perFrame;
    expect(
      peakAt,
      inInclusiveRange(want - 4, want + 4),
      reason: 'the click sat 3 frames into the span; it came back at '
          '$peakAt, ${peakAt / perFrame} frames in',
    );
  });

  test('🚨a piece cut from inside a sound comes out behind that sound — its '
      'first samples closer than the same samples written with nothing '
      'before them', () async {
    // 🗣️유저 2026-11-10 (board an-mp4-reopened-loses-its-first-9-ms-of-
    // sound-Q2): 「무음, 범위 앞에 소리가 있으면 그 소리」.
    final watch = await NativeCallWatch.start('a movie piece is led');
    addTearDown(watch.stop);
    watch.step('asking for the encoder and writing the take');
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    String at(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    const rate = 48000;
    const perFrame = rate ~/ 24;
    const inFrame = 6;
    // A tone on its peak where frame 6 begins (750 Hz turns 187.5 times in
    // six frames): behind silence, the hardest first sample there is.
    if (!writeEncodedMovie(
      at('source.mp4'),
      frames: 18,
      sampleRate: rate,
      sound: (sample) =>
          (12000 * math.cos(2 * math.pi * 750 * sample / rate)).round(),
    )) {
      return;
    }
    watch.step('reading the sound of the take');
    final source = decodeAudioFile(at('source.mp4'))!;

    /// What the take plays [sample] samples into frame 6.
    double heardAt(int sample) =>
        source.samples[(inFrame * perFrame + sample) * source.channels];

    /// How far the first 128 samples of the movie at [path] came back from
    /// what the take plays from frame 6 on.
    double headErrorOf(String path) {
      final sound = decodeAudioFile(path)!;
      var squares = 0.0;
      for (var index = 0; index < 128; index += 1) {
        final error = sound.samples[index * sound.channels] - heardAt(index);
        squares += error * error;
      }
      return math.sqrt(squares / 128);
    }

    watch.step('cutting the piece');
    final cut = writeMovieSpan(
      at('source.mp4'),
      at('piece.mp4'),
      trim: (inFrame: inFrame, outFrame: inFrame + 6),
      clock: (
        rate: ProjectFrameRate.fps24,
        speed: (numerator: 1, denominator: 1),
      ),
    );
    expect(cut.failure, isNull);
    watch.step('reading the sound of the piece');
    final led = headErrorOf(at('piece.mp4'));
    // The take was written, so there is an encoder.
    if (osVideoEncoderOrSkip()!.audioLead == 0) {
      // A writer that leads a movie's sound itself is handed nothing, so
      // there are no two movies to tell apart.
      return;
    }

    // The span's own samples as a movie of their own: nothing sounds
    // before its first.
    watch.step('writing the same samples with nothing before them');
    writeEncodedMovie(
      at('alone.mp4'),
      frames: 6,
      sampleRate: rate,
      sound: (sample) => int16FromUnitSample(heardAt(sample)),
    );
    watch.step('reading the sound written alone');
    final alone = headErrorOf(at('alone.mp4'));
    expect(
      led,
      lessThan(alone / 2),
      reason: '🔬2026-11-10, through Media Foundation\'s AAC: 0.0007 behind '
          'its own past, 0.0045 behind silence',
    );
  });
}
