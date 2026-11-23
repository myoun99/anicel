import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../canvas/picture_up_view.dart' show PicturesUpTogether;
import 'measurement_mode.dart';

/// 🔬A STROKE'S STEPS, AS THE SCREEN SHOWS THEM: how many a second, how many
/// dabs each carried, how long the first of its dabs waited for it to go
/// out, and how long from that dab to the frame that showed it being up.
/// The frame statistics read these (`FrameStats`, Settings ▸ Debug), and
/// nothing is counted while they are off.
///
/// 🗣️유저 2026-11-23, build 1101 on a Galaxy Tab out of this machine's reach
/// (card the-galaxy-tab-canvas-went-slow-on-build-1095): 「그을수록
/// 같은선안에서 점점 느려지고 … 선떼고 5초뒤에 그은게 한번에 나오는정도」, then
/// 「몇번을 임시빌드로 테스트하게 만드는거냐고 … 모든가능성 철저하게 검사해서
/// 디버그화면 만들면되지」 — and 관제 23:24: 쌓인 걸음 · 걸음마다 합친 답 수 ·
/// 펜 표본에서 화면까지의 지연, with nothing waited for to read them.
abstract final class StrokeSteps {
  /// How many steps the lists keep: a second or two of a stroke's.
  static const int stepsKept = 240;

  /// The steps counted in all, and the dabs they carried.
  static int get stepsCounted => _stepsCounted;
  static int _stepsCounted = 0;

  static int get dabsCounted => _dabsCounted;
  static int _dabsCounted = 0;

  /// The dabs of each of the newest steps, oldest first.
  static List<int> get dabsKept => List.unmodifiable(_dabs);
  static final List<int> _dabs = [];

  /// How long each of the newest steps' first dab waited for the step to
  /// go out, in microseconds — a frame of the canvas's being drawn holds
  /// it (`_BrushEditOverlay.stepPendingOverlayDabs`).
  static List<int> get heldMicros => List.unmodifiable(_held);
  static final List<int> _held = [];

  /// How long from each of the newest steps' first dab to the frame that
  /// showed the step being up, in microseconds — the pen's line on the
  /// screen as late as it is.
  static List<int> get upMicros => List.unmodifiable(_up);
  static final List<int> _up = [];

  static final Stopwatch _clock = Stopwatch()..start();

  /// The clock the steps are timed by, in microseconds — a test's own
  /// where it says one.
  @visibleForTesting
  static int Function()? debugMicros;

  static int _micros() => debugMicros?.call() ?? _clock.elapsedMicroseconds;

  /// When the first dab of the step to come was queued ([_micros]) — none
  /// where none waits.
  static int? _firstQueuedAt;

  /// A dab was queued for the stroke's next step.
  static void queued() {
    if (!MeasurementMode.frameStats.value) {
      return;
    }
    _firstQueuedAt ??= _micros();
  }

  /// A step of [dabs] went out, shown by a frame of the pictures going up
  /// [together] — or of none where null, by the frame this one paints.
  static void stepped(int dabs, {required PicturesUpTogether? together}) {
    final first = _firstQueuedAt;
    _firstQueuedAt = null;
    if (!MeasurementMode.frameStats.value) {
      return;
    }
    _stepsCounted += 1;
    _dabsCounted += dabs;
    _keep(_dabs, dabs);
    if (first == null) {
      return;
    }
    _keep(_held, _micros() - first);
    void up() => _keep(_up, _micros() - first);
    // After the paint that draws the step: the frame begun there shows it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final drawn = together?.beingDrawn;
      if (drawn == null) {
        up();
      } else {
        unawaited(drawn.then((_) => up()));
      }
    });
  }

  static void _keep(List<int> kept, int value) {
    kept.add(value);
    if (kept.length > stepsKept) {
      kept.removeAt(0);
    }
  }

  /// No step counted yet: what was counted while the statistics were last
  /// up says nothing of now.
  static void forget() {
    _stepsCounted = 0;
    _dabsCounted = 0;
    _dabs.clear();
    _held.clear();
    _up.clear();
    _firstQueuedAt = null;
  }
}
