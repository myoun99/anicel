import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../canvas/picture_up_view.dart' show PicturesUpTogether;
import 'engine_behind.dart';
import 'measurement_mode.dart';
import 'picture_writes.dart';
import 'screen_asked.dart';

/// What the frame that showed a step or a landing did ([StrokeSteps]): how
/// the pictures shown in it took their changes ([PictureWrites]), and the
/// ask of the newest screen shown in it — null where no screen drew
/// ([ScreenAsked]).
typedef FrameDid = ({PictureWritesCounted wrote, ScreenAsk? asked});

/// The newest stroke's first step ([StrokeSteps.firstStep]), in
/// microseconds from its press: when the press's own handling was done
/// (the stroke armed), when the step's first dab was queued, and when the
/// frame that showed the step was up — with how long that dab was held,
/// the submits behind as the step went out ([EngineBehind]), and what that
/// frame did. [up] and [did] are null till that frame is up.
typedef FirstStep = ({
  int armed,
  int dab,
  int held,
  int? up,
  int? behind,
  FrameDid? did,
});

/// The newest stroke's landing ([StrokeSteps.landing]), in microseconds
/// from the lift that landed it: when its commit was done — the lift's own
/// handling, the engine's word on what each tile became waited for in it —
/// and when the frame after it was up, null till then; with the submits
/// behind once it was committed ([EngineBehind]), and what that frame did.
typedef Landing = ({int commit, int? up, int? behind, FrameDid? did});

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
///
/// 🔬AND A STROKE'S FIRST STEP AND ITS LANDING, APART ([firstStep],
/// [landing]): 🗣️H67 on that tablet (card
/// the-start-of-every-stroke-stalls-on-the-galaxy-tab) — the start of every
/// stroke stalls, then draws, zoomed past 100% too. A percentile over the
/// steps kept asks one of a stroke's hundreds; a first step and a landing
/// are told whole — the press's handling, the opening's wait, the hold,
/// the GPU's backlog, and how the frame that showed it wrote its picture.
abstract final class StrokeSteps {
  /// How many steps the lists keep: a second or two of a stroke's.
  static const int stepsKept = 240;

  /// How many strokes' first steps [firstUpMicros] keeps.
  static const int strokesKept = 24;

  /// How many of the newest stroke's steps [newestStrokeUpMicros] keeps: a
  /// minute of them, at a step a frame of 60.
  static const int strokeStepsKept = 3600;

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

  /// [upMicros] of the newest stroke's steps alone, from its press, in the
  /// order they went out — its newest [strokeStepsKept] —: whether a
  /// stroke's steps come up later as it goes on.
  ///
  /// 🗣️관제 2026-11-24 (card the-start-of-every-stroke-stalls-on-the-galaxy-
  /// tab): a big brush's pen→up p95 rose 44 → 102 ms along one stroke on
  /// the emulator, and read again with the app opened afresh it was flat
  /// (39/62 → 36/56) — the rise was the steps of the strokes before it,
  /// in [upMicros]' window. Kept apart, one run answers it.
  static List<int> get newestStrokeUpMicros => List.unmodifiable(_strokeUps);
  static final List<int> _strokeUps = [];

  /// Which stroke is the newest ([pressed]): a step's frame up after the
  /// next press is not that one's.
  static int _stroke = 0;

  /// How long from each of the newest strokes' press to the frame that
  /// showed its first step being up, in microseconds, oldest first.
  static List<int> get firstUpMicros => List.unmodifiable(_firstUps);
  static final List<int> _firstUps = [];

  /// The newest stroke's first step; null till one went out.
  static FirstStep? get firstStep => _firstStep;
  static FirstStep? _firstStep;

  /// The newest stroke's landing; null till one landed.
  static Landing? get landing => _landing;
  static Landing? _landing;

  static final Stopwatch _clock = Stopwatch()..start();

  /// The clock the steps are timed by, in microseconds — a test's own
  /// where it says one.
  @visibleForTesting
  static int Function()? debugMicros;

  static int _micros() => debugMicros?.call() ?? _clock.elapsedMicroseconds;

  /// When the first dab of the step to come was queued ([_micros]) — none
  /// where none waits.
  static int? _firstQueuedAt;

  /// When the stroke whose first step is to come was pressed ([_micros]),
  /// and when, after that, its press was handled — none where no first
  /// step is to come.
  static int? _pressedAt;
  static int? _armedAt;

  /// When the pen lifted from the stroke whose landing is to come
  /// ([_micros]) — none where none is.
  static int? _liftedAt;

  /// A stroke was pressed: its first step is told from here ([firstStep]).
  static void pressed() {
    if (!MeasurementMode.debugWindow.value) {
      return;
    }
    _pressedAt = _micros();
    _armedAt = null;
    _stroke += 1;
    _strokeUps.clear();
  }

  /// The press of the stroke [pressed] told was handled: the stroke is
  /// armed, its first dabs out or waited for.
  static void armed() {
    if (_pressedAt == null) {
      return;
    }
    _armedAt = _micros();
  }

  /// A dab was queued for the stroke's next step.
  static void queued() {
    if (!MeasurementMode.debugWindow.value) {
      return;
    }
    _firstQueuedAt ??= _micros();
  }

  /// A step of [dabs] went out, shown by a frame of the pictures going up
  /// [together] — or of none where null, by the frame this one paints.
  static void stepped(int dabs, {required PicturesUpTogether? together}) {
    final first = _firstQueuedAt;
    _firstQueuedAt = null;
    if (!MeasurementMode.debugWindow.value) {
      return;
    }
    _stepsCounted += 1;
    _dabsCounted += dabs;
    _keep(_dabs, dabs, stepsKept);
    if (first == null) {
      return;
    }
    final out = _micros();
    final stroke = _stroke;
    _keep(_held, out - first, stepsKept);
    final pressedAt = _pressedAt;
    _pressedAt = null;
    if (pressedAt == null) {
      _afterItsFrame(together, (_) => _keepUp(stroke, _micros() - first));
      return;
    }
    final step = (
      armed: (_armedAt ?? out) - pressedAt,
      dab: first - pressedAt,
      held: out - first,
      behind: EngineBehind.now,
    );
    _firstStep = (
      armed: step.armed,
      dab: step.dab,
      held: step.held,
      up: null,
      behind: step.behind,
      did: null,
    );
    _afterItsFrame(together, (did) {
      final up = _micros();
      _keepUp(stroke, up - first);
      _keep(_firstUps, up - pressedAt, strokesKept);
      // The newest stroke's: a frame is up after the frames before it.
      _firstStep = (
        armed: step.armed,
        dab: step.dab,
        held: step.held,
        up: up - pressedAt,
        behind: step.behind,
        did: did,
      );
    });
  }

  /// The pen lifted from a stroke: its landing is told from here
  /// ([landing]).
  static void lifted() {
    if (!MeasurementMode.debugWindow.value) {
      return;
    }
    _liftedAt = _micros();
  }

  /// The stroke the pen lifted from landed: committed, told from its lift
  /// to the frame after it being up, of the pictures going up [together]
  /// ([landing]) — or from here, where no lift was told.
  static void landed({required PicturesUpTogether? together}) {
    if (!MeasurementMode.debugWindow.value) {
      return;
    }
    final now = _micros();
    final at = _liftedAt ?? now;
    _liftedAt = null;
    final behind = EngineBehind.now;
    _landing = (commit: now - at, up: null, behind: behind, did: null);
    // The newest landing's: a frame is up after the frames before it.
    _afterItsFrame(
      together,
      (did) => _landing = (
        commit: now - at,
        up: _micros() - at,
        behind: behind,
        did: did,
      ),
    );
  }

  /// [up] once the frame begun here — the one whose paint draws what went
  /// out now — is up: of the pictures going up [together], or of none where
  /// null, the frame itself. Told what that frame did ([FrameDid]).
  static void _afterItsFrame(
    PicturesUpTogether? together,
    void Function(FrameDid did) up,
  ) {
    final wrote = PictureWrites.counted;
    final shows = ScreenAsked.shows;
    // After the paint that draws it: the frame begun there shows it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final now = PictureWrites.counted;
      final did = (
        wrote: (
          inPlace: now.inPlace - wrote.inPlace,
          copied: now.copied - wrote.copied,
          whole: now.whole - wrote.whole,
        ),
        asked: ScreenAsked.shows == shows ? null : ScreenAsked.last,
      );
      final drawn = together?.beingDrawn;
      if (drawn == null) {
        up(did);
      } else {
        unawaited(drawn.then((_) => up(did)));
      }
    });
  }

  /// A step of [stroke]'s up [up] after its first dab: in [upMicros], and
  /// in [newestStrokeUpMicros] while [stroke] is the newest.
  static void _keepUp(int stroke, int up) {
    _keep(_up, up, stepsKept);
    if (stroke == _stroke) {
      _keep(_strokeUps, up, strokeStepsKept);
    }
  }

  static void _keep(List<int> kept, int value, int room) {
    kept.add(value);
    if (kept.length > room) {
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
    _strokeUps.clear();
    _firstUps.clear();
    _firstStep = null;
    _landing = null;
    _firstQueuedAt = null;
    _pressedAt = null;
    _armedAt = null;
    _liftedAt = null;
  }
}
