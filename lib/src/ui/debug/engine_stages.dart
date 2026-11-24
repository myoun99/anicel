import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart' show GpuPlaceTook;

import '../../native/screen_texture.dart';
import 'measurement_mode.dart';
import 'screen_asked.dart';

/// One frame of a screen, as it went up while the engine was timed: what
/// it took on its way ([ScreenUp]), what its show asked of the engine
/// ([ScreenAsked.last] as it went up) and what each place of the engine
/// took since the frame before it went up (`GpuEngine.took`).
typedef StagedFrame = ({
  ScreenUp up,
  ScreenAsk? asked,
  List<GpuPlaceTook> took,
});

/// One place of the engine over some frames — the frames kept, or one of
/// them: whose time it is, where ([EngineStages.shortPlace]), its
/// microseconds, times and workgroups in all, the most microseconds it
/// took in one frame, and in one time ([GpuPlaceTook.longest]).
typedef StagedPlace = ({
  bool gpu,
  String place,
  int micros,
  int mostInAFrame,
  int longestOnce,
  int times,
  int groups,
});

/// What the frames kept say ([EngineStages.summarize]).
@immutable
class EngineStagesSummary {
  const EngineStagesSummary({
    required this.frames,
    required this.wholeMicros,
    required this.places,
    required this.slowest,
    required this.slowestPlaces,
  });

  /// How many frames it is of.
  final int frames;

  /// Their draw, finish and show in all.
  final int wholeMicros;

  /// Every place that took anything, the one that took most first.
  final List<StagedPlace> places;

  /// The frame that took longest from its draw to being up, and its places,
  /// the one that took most first.
  final StagedFrame slowest;
  final List<StagedPlace> slowestPlaces;

  /// What the GPU took of them, and what the engine's thread did.
  int get gpuMicros => microsOf(places, gpu: true);
  int get cpuMicros => microsOf(places, gpu: false);

  /// [places]' microseconds in all — the [gpu]'s, or the engine's
  /// thread's.
  static int microsOf(List<StagedPlace> places, {required bool gpu}) => places
      .where((place) => place.gpu == gpu)
      .fold(0, (sum, place) => sum + place.micros);
}

/// 🔬THE ENGINE'S WORK, PLACE BY PLACE, FRAME BY FRAME (Settings ▸ Debug ▸
/// Engine Stages): while the switch is on, each screen's engine is timed
/// ([ScreenTexture.tookAsItWentUp], rust/src/took.rs) and the newest
/// frames are kept with what each place of the engine took of them — the
/// bodies on its thread, and each submit on the GPU. The frame statistics
/// show them under their own lines ([lines]).
///
/// 🗣️유저 2026-11-22, a Galaxy Tab out of this machine's reach, build 1098
/// (card the-galaxy-tab-canvas-went-slow-on-build-1095): 「팬줌똑같이느리고
/// 획 빨라졋는데 스트로크 첫부분 항상멈칫하고 긋는도중에도 한번씩 멈춤해 …
/// 근본적으로 해결하고있는거맞아?」 — the readout's `finish` was one number
/// for the kernels, the copy onto the window's image and the wait for that
/// image, and a stall of one frame stood in a p95. The slowest frame kept
/// is told whole, by its own places ([EngineStagesSummary.slowest]).
///
/// 🚨A timed engine waits for nothing to be timed (rust/src/took.rs): a
/// submit's GPU time is the GPU's own clock's, read once written, where
/// the device has one ([GpuEngine.clocked]) — and none is shown where it
/// has not ([lines]). ↩️Till 2026-11-23 each submit was waited out where
/// it was made, and a timed engine's frames were the sum of their parts.
abstract final class EngineStages {
  /// How many frames are kept, the newest: seconds of them at a screen's
  /// rate, and a stroke's worth.
  @visibleForTesting
  static const int framesKept = 120;

  /// How many places the readout names of the frames kept, and of the
  /// slowest.
  @visibleForTesting
  static const int placesShown = 8;
  @visibleForTesting
  static const int slowestPlacesShown = 6;

  static final List<StagedFrame> _frames = <StagedFrame>[];
  static bool _installed = false;

  /// Follows the switch from here on. Once, from `main()`.
  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    MeasurementMode.debugWindow.addListener(_onSwitch);
    _onSwitch();
  }

  /// The switch thrown either way begins again: what a timed engine took
  /// before is another window's.
  static void _onSwitch() {
    _frames.clear();
    ScreenTexture.tookAsItWentUp = MeasurementMode.debugWindow.value
        ? wentUp
        : null;
  }

  /// A frame went up as [up] says, the engine's places having taken [took]
  /// since the one before it.
  @visibleForTesting
  static void wentUp(ScreenUp up, List<GpuPlaceTook> took) {
    _frames.add((up: up, asked: ScreenAsked.last, took: took));
    if (_frames.length > framesKept) {
      _frames.removeAt(0);
    }
  }

  /// No frame kept — the debug window's reset, and test hygiene.
  static void forget() => _frames.clear();

  /// What the frames kept say; null with none.
  static EngineStagesSummary? get summary =>
      _frames.isEmpty ? null : summarize(_frames);

  static int _whole(ScreenUp up) => up.draw + up.finish + up.show;

  /// A place as the readout names it: the engine's file without what every
  /// one of them shares — the path down to `src`, `kernels/` and `.rs` —
  /// and its line: `composite/screen:412`, `platform/android:237`.
  @visibleForTesting
  static String shortPlace(String place) {
    final slashed = place.replaceAll(r'\', '/');
    final from = slashed.lastIndexOf('src/');
    final inSrc = from < 0 ? slashed : slashed.substring(from + 4);
    final area = inSrc.startsWith('kernels/') ? inSrc.substring(8) : inSrc;
    return area.replaceFirst('.rs:', ':');
  }

  /// [frames]' places in all, the one that took most first.
  static List<StagedPlace> _placesOf(Iterable<StagedFrame> frames) {
    final places = <(bool, String), StagedPlace>{};
    for (final frame in frames) {
      // A place's share of this frame — told once a frame, but nothing of
      // the engine's says it could not be told twice.
      final inFrame = <(bool, String), int>{};
      for (final took in frame.took) {
        final key = (took.gpu, took.place);
        inFrame[key] = (inFrame[key] ?? 0) + took.micros;
        final before = places[key];
        places[key] = (
          gpu: took.gpu,
          place: shortPlace(took.place),
          micros: (before?.micros ?? 0) + took.micros,
          mostInAFrame: before?.mostInAFrame ?? 0,
          longestOnce: math.max(before?.longestOnce ?? 0, took.longest),
          times: (before?.times ?? 0) + took.times,
          groups: (before?.groups ?? 0) + took.groups,
        );
      }
      for (final MapEntry(:key, value: micros) in inFrame.entries) {
        final place = places[key]!;
        if (micros > place.mostInAFrame) {
          places[key] = (
            gpu: place.gpu,
            place: place.place,
            micros: place.micros,
            mostInAFrame: micros,
            longestOnce: place.longestOnce,
            times: place.times,
            groups: place.groups,
          );
        }
      }
    }
    return places.values.toList()
      ..sort((a, b) => b.micros.compareTo(a.micros));
  }

  /// What [frames] say — one at the least.
  @visibleForTesting
  static EngineStagesSummary summarize(List<StagedFrame> frames) {
    var slowest = frames.first;
    var whole = 0;
    for (final frame in frames) {
      whole += _whole(frame.up);
      if (_whole(frame.up) > _whole(slowest.up)) {
        slowest = frame;
      }
    }
    return EngineStagesSummary(
      frames: frames.length,
      wholeMicros: whole,
      places: _placesOf(frames),
      slowest: slowest,
      slowestPlaces: _placesOf([slowest]),
    );
  }

  static String _ms(num micros, {int width = 7}) =>
      (micros / 1000).toStringAsFixed(2).padLeft(width);

  /// A GPU column where the GPU has no clock: none, as wide as a figure.
  static final String _noClock = '—'.padLeft(7);

  /// The workgroups a frame, in thousands — a kernel's are of 64 texels
  /// or so each, so how many it ran says how many texels it wrote.
  static String _groups(num groups) =>
      groups == 0 ? '' : '  ${(groups / 1000).toStringAsFixed(1)}k';

  static String _placeLine(StagedPlace place, int frames, {String most = ''}) =>
      ' ${place.gpu ? 'gpu' : 'cpu'} ${place.place.padRight(28)}'
      '${_ms(place.micros / frames)}$most  '
      '${(place.times / frames).toStringAsFixed(1)}x'
      '${_groups(place.groups / frames)}';

  /// The readout's lines of [summary]: the frames kept — a frame's
  /// milliseconds on the average, whole, the GPU's and the engine
  /// thread's, then place by place, each with the most it took in one
  /// frame, its times a frame and its workgroups —, and the slowest frame,
  /// with what it was drawn as. `timed, no frame yet` with none.
  ///
  /// 🗣️관제 2026-11-23 23:51, of a device whose GPU has no clock
  /// ([clocked] false): 「단계 GPU 시간 칸만 「이 기기는 시각 쿼리 없음」으로
  /// 비우고, 나머지 숫자는 기다림 없이 그대로」 — its GPU columns say none
  /// rather than a zero, which reads as measured and free.
  static List<String> lines(
    EngineStagesSummary? summary, {
    required bool clocked,
  }) {
    if (summary == null) {
      return const <String>['STAGES  timed, no frame yet'];
    }
    final frames = summary.frames;
    final slowest = summary.slowest;
    const of = EngineStagesSummary.microsOf;
    String gpu(num micros) => clocked ? _ms(micros) : _noClock;
    return <String>[
      'STAGES  ${frames}f  a frame${_ms(summary.wholeMicros / frames)}  '
          'gpu${gpu(summary.gpuMicros / frames)}  '
          'cpu${_ms(summary.cpuMicros / frames)}',
      if (!clocked) ' gpu: no timestamp queries on this device',
      for (final place in summary.places.take(placesShown))
        _placeLine(
          place,
          frames,
          most:
              '  max${_ms(place.mostInAFrame, width: 7)}'
              '  once${_ms(place.longestOnce, width: 7)}',
        ),
      'SLOWEST${_ms(_whole(slowest.up))}  '
          'draw${_ms(slowest.up.draw, width: 6)}  '
          'finish${_ms(slowest.up.finish)}  '
          'show${_ms(slowest.up.show, width: 6)}'
          '${switch (slowest.asked) {
            null => '',
            final asked => '  ${screenAskWords(asked)}',
          }}',
      '        gpu${gpu(of(summary.slowestPlaces, gpu: true))}  '
          'cpu${_ms(of(summary.slowestPlaces, gpu: false))}',
      for (final place in summary.slowestPlaces.take(slowestPlacesShown))
        _placeLine(place, 1),
    ];
  }
}
