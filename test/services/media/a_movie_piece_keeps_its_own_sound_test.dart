import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/models/audio_pcm_scale.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_resampler.dart' show resampleAudio;
import 'package:anicel/src/services/audio/sound_span.dart'
    show decodeAudioOfFrames;
import 'package:anicel/src/services/audio/wav16_header.dart' show wav16Bytes;
import 'package:anicel/src/services/media/media_byte_source.dart'
    show MediaFileBytes;
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

  test('🎯fitted to the project, a piece is led by what the take plays just '
      'before its span ON THE CLOCK IT IS READ ON — its past read on the '
      'wall clock lies 20 ms back, out of step with it (F-588)', () async {
    final watch = await NativeCallWatch.start('a fitted piece is led');
    addTearDown(watch.stop);
    watch.step('asking for the encoder and writing the take');
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    String at(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    const rate = 48000;
    const inFrame = 480;
    // Read on the wall clock, the span would begin 960 samples (20 ms)
    // early: 15.4 turns of 770 Hz, so that past comes in 0.4 of a turn out
    // of step with the span's first sample.
    if (!writeEncodedMovie(
      at('source.mp4'),
      frames: inFrame + 8,
      fps: (numerator: 24000, denominator: 1001),
      sampleRate: rate,
      sound: (sample) =>
          (12000 * math.cos(2 * math.pi * 770 * sample / rate)).round(),
    )) {
      return;
    }
    const clock = (
      rate: ProjectFrameRate.fps24,
      speed: (numerator: 1, denominator: 1),
    );
    const pull = (numerator: 1001, denominator: 1000);

    watch.step('cutting the piece');
    final cut = writeMovieSpan(
      at('source.mp4'),
      at('piece.mp4'),
      trim: (inFrame: inFrame, outFrame: inFrame + 6),
      clock: clock,
      pull: pull,
    );
    expect(cut.failure, isNull);
    if (osVideoEncoderOrSkip()!.audioLead == 0) {
      return;
    }
    watch.step('reading what the piece was handed');
    final handed = decodeAudioOfFrames(
      MediaFileBytes(at('source.mp4')),
      (first: cut.kept!.first, count: cut.kept!.count),
      clock,
      pull: pull,
    )!;
    double handedAt(int sample) => handed.samples[sample * handed.channels];

    /// How far the first 128 samples of the movie at [path] came back from
    /// what the piece was handed.
    double headErrorOf(String path) {
      final sound = decodeAudioFile(path)!;
      var squares = 0.0;
      for (var index = 0; index < 128; index += 1) {
        final error = sound.samples[index * sound.channels] - handedAt(index);
        squares += error * error;
      }
      return math.sqrt(squares / 128);
    }

    watch.step('reading the sound of the piece');
    final led = headErrorOf(at('piece.mp4'));
    watch.step('writing the same samples with nothing before them');
    writeEncodedMovie(
      at('alone.mp4'),
      frames: 6,
      sampleRate: rate,
      sound: (sample) => int16FromUnitSample(handedAt(sample)),
    );
    watch.step('reading the sound written alone');
    final alone = headErrorOf(at('alone.mp4'));
    expect(
      led,
      lessThan(alone / 2),
      reason: 'led by its past, the piece\'s head came back $led from what '
          'it was handed; behind silence, $alone',
    );
  });

  test('🎯a pulled window is the whole sound converted, sample for sample — '
      'its edges read the sound around them, not silence (F-588)', () {
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}tone.wav';
    const rate = 48000;
    const pull = (numerator: 1001, denominator: 1000);
    const clock = (
      rate: ProjectFrameRate.fps24,
      speed: (numerator: 1, denominator: 1),
    );
    final pcm = Int16List(rate * 21 * 2);
    for (var sample = 0; sample < rate * 21; sample += 1) {
      pcm[sample * 2] = pcm[sample * 2 + 1] =
          (12000 * math.cos(2 * math.pi * 770 * sample / rate)).round();
    }
    File(path).writeAsBytesSync(
      wav16Bytes(pcm, sampleRate: rate, channels: 2),
    );
    final whole = resampleAudio(
      samples: decodeAudioFile(path)!.samples,
      channels: 2,
      inputRate: rate * pull.numerator,
      outputRate: rate * pull.denominator,
    );

    /// How far the pulled window over six frames from [first] lies from the
    /// whole conversion's output [at] on.
    double worstOf(int first, {required int at}) {
      final window = decodeAudioOfFrames(
        MediaFileBytes(path),
        (first: first, count: 6),
        clock,
        pull: pull,
      )!;
      expect(window.samples.length, 6 * 2000 * 2);
      var worst = 0.0;
      for (var index = 0; index < window.samples.length; index += 1) {
        worst = math.max(
          worst,
          (window.samples[index] - whole[at * 2 + index]).abs(),
        );
      }
      return worst;
    }

    // Frame 480 is the take's sample 960960 = 960 × 1001, which the whole
    // conversion's output 960000 stands on; frame 0 has only silence before
    // it.
    expect(worstOf(480, at: 960000), 0);
    expect(worstOf(0, at: 0), 0);
  });
}
