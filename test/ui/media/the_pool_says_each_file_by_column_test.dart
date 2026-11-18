import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_clock.dart' show MovieClock;
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/media_facts.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart'
    show importFitLabel;
import 'package:anicel/src/ui/media/media_pool_words.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️asset-placement-presets Q4 (유저 2026-11-17): the pool's list says each
/// file column by column — as it is (품기 · 크기 · 길이 · 비디오 정보 · 오디오
/// 정보 · 날짜) and as its preset places it (종류 · 맞춤 · 시작 · 끝 · 길이).
void main() {
  const sound = 'C:/snd/door.wav';
  const movie = 'C:/mov/rain.mp4';
  const gif = 'C:/pic/blink.gif';
  const still = 'C:/pic/cloud.png';
  const pdf = 'C:/doc/layout.pdf';

  MediaPoolWords words({
    Map<String, MediaPoolFacts> facts = const {},
    Map<String, int> soundFrames = const {},
  }) => MediaPoolWords(
    clock: (rate: ProjectFrameRate.fps24, speed: noPull),
    factsOf: (path) => facts[path],
    soundFramesOf: (path) => soundFrames[path],
  );

  MediaAsset asset(
    String path, {
    MediaAssetKind? kind,
    int? frameCount,
    int? pageCount,
    double? sourceFps,
    MediaPreset preset = const MediaPreset(),
  }) => MediaAsset(
    path: path,
    name: path,
    kind: kind ?? mediaAssetKindForPath(path)!,
    frameCount: frameCount,
    pageCount: pageCount,
    sourceFps: sourceFps,
    preset: preset,
  );

  /// [frames] of a movie at [rate], as the pool reads it.
  MediaPoolFacts movieRead(
    int frames, {
    ({int numerator, int denominator}) rate = (numerator: 24, denominator: 1),
  }) => (
    picture: (
      size: const CanvasSize(width: 1920, height: 1080),
      pictures: frames,
      rate: rate,
    ),
    sound: null,
  );

  test('a length is a running time, a PDF\'s its pages — and a still has '
      'none, nor a sound whose conform is not held, nor a movie whose rate '
      'is not read', () {
    final known = words(
      soundFrames: {sound: 30},
      facts: {movie: movieRead(120)},
    );
    expect(known.lengthWord(asset(sound)), '0:01+6');
    expect(words().lengthWord(asset(sound)), MediaPoolWords.none);
    expect(known.lengthWord(asset(movie, frameCount: 120)), '0:05+0');
    expect(
      words().lengthWord(asset(movie, frameCount: 120)),
      MediaPoolWords.none,
    );
    expect(known.lengthWord(asset(gif, frameCount: 6)), '0:00+6');
    expect(
      known.lengthWord(asset(pdf, pageCount: 12)),
      AppText.strings.mediaPages(12),
    );
    expect(known.lengthWord(asset(still)), MediaPoolWords.none);
  });

  test('🐛a movie at another rate is counted as a placement counts it — in '
      'the PROJECT\'s frames on the sound\'s clock, never its own', () {
    final thirty = words(
      facts: {movie: movieRead(150, rate: (numerator: 30, denominator: 1))},
    );
    expect(
      thirty.lengthWord(asset(movie, frameCount: 150)),
      '0:05+0',
      reason: 'five seconds of a 30 fps take are 120 frames of 24, not 150',
    );
    String span(MediaPoolWords pool, MediaAsset of) => pool
        .presetColumns()
        .singleWhere((column) => column.id == 'span')
        .wordOf(of);
    expect(span(thirty, asset(movie, frameCount: 150)), '0:05+0');
    expect(
      placedPicturesOf(
        asset(movie, frameCount: 150),
        movieRead(150, rate: (numerator: 30, denominator: 1)).picture,
        (rate: ProjectFrameRate.fps24, speed: noPull),
      ),
      const MovieClock(
        projectRate: ProjectFrameRate.fps24,
        audioSpeed: noPull,
        movieRate: (numerator: 30, denominator: 1),
      ).projectFramesCovering(150),
      reason: 'the door that places a movie keeps it by this count',
    );
  });

  test('the video column says the picture\'s size and a movie\'s rate, once '
      'read; the audio column the rate and the channels', () {
    final read = words(
      facts: {
        movie: (
          picture: (
            size: const CanvasSize(width: 1920, height: 1080),
            pictures: 120,
            rate: (numerator: 24000, denominator: 1001),
          ),
          sound: (sampleRate: 48000, channels: 2),
        ),
        still: (
          picture: (
            size: const CanvasSize(width: 2048, height: 1152),
            pictures: 1,
            rate: null,
          ),
          sound: null,
        ),
        sound: (picture: null, sound: (sampleRate: 44100, channels: 1)),
      },
    );
    expect(
      read.videoWord(asset(movie, sourceFps: 24000 / 1001)),
      '1920×1080 · 23.976 fps',
    );
    expect(read.videoWord(asset(still)), '2048×1152');
    expect(read.videoWord(asset(sound)), MediaPoolWords.none);
    expect(
      read.audioWord(asset(movie)),
      '48kHz · ${AppText.strings.mediaStereo}',
    );
    expect(
      read.audioWord(asset(sound)),
      '44.1kHz · ${AppText.strings.mediaMono}',
    );
    expect(read.audioWord(asset(still)), MediaPoolWords.none);
    expect(
      words().videoWord(asset(movie)),
      MediaPoolWords.none,
      reason: 'not read yet',
    );
  });

  test('a sound places an SE block; one picture places what its preset '
      'asks, and more than one an animation (F-429)', () {
    expect(placedKindOf(asset(sound)), LayerKind.se);
    expect(placedKindOf(asset(still)), LayerKind.bornOfOnePicture);
    expect(
      placedKindOf(
        asset(
          still,
          preset: const MediaPreset(pictureKind: LayerKind.animation),
        ),
      ),
      LayerKind.animation,
    );
    expect(placedKindOf(asset(gif, frameCount: 3)), LayerKind.animation);
    expect(
      placedKindOf(
        asset(gif, frameCount: 3, preset: const MediaPreset(outFrame: 0)),
      ),
      LayerKind.image,
      reason: 'a preset that keeps one of its pictures places one',
    );
    expect(placedKindOf(asset(pdf, pageCount: 1)), LayerKind.image);
    expect(placedKindOf(asset(movie, frameCount: 120)), LayerKind.animation);
  });

  test('a preset\'s start and end count from 1, never past the file, and '
      'its length is what they keep', () {
    final pool = words(
      soundFrames: {sound: 48},
      facts: {movie: movieRead(10)},
    );
    final trimmed = asset(
      sound,
      preset: const MediaPreset(inFrame: 1, outFrame: 30),
    );
    expect(pool.presetColumns().map((column) => column.id), [
      'kind',
      'fit',
      'start',
      'end',
      'span',
    ]);
    String say(String id, MediaAsset of) => pool
        .presetColumns()
        .singleWhere((column) => column.id == id)
        .wordOf(of);
    expect(say('start', trimmed), '2');
    expect(say('end', trimmed), '31');
    expect(say('span', trimmed), '0:01+6');
    final past = asset(
      movie,
      frameCount: 10,
      preset: const MediaPreset(outFrame: 99),
    );
    expect(say('end', past), '10', reason: 'end ≤ the file (KeptSpan)');
    expect(say('start', asset(still)), MediaPoolWords.none);
    expect(say('fit', asset(sound)), MediaPoolWords.none);
    expect(
      say('fit', asset(still)),
      importFitLabel(MediaFitMode.born),
    );
  });

  test('the file\'s columns are the old second line spread out, and the '
      'length and the two kinds of facts', () {
    expect(words().fileColumns().map((column) => column.id), [
      'kept',
      'size',
      'length',
      'video',
      'audio',
      'date',
    ]);
  });
}
