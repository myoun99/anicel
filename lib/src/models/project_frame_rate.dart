/// A project's frame rate as an EXACT rational. 23.976 is not a number —
/// it is 24000/1001, and every professional tool stores it that way. A
/// double drifts: 3600s of playback at `1/23.976` accumulates error that
/// no amount of careful rounding downstream can undo.
///
/// [countingBase] is the separate, integer question of "how many frames
/// do we COUNT to a second" — 24 for both 24 and 23.976, exactly as a
/// broadcast timecode counts 24 frames per second in a 23.976 timeline.
/// Every integer-frame surface (the sheet rows, the grid, the 6f lines,
/// the second labels) keeps using it and never sees the fraction. That is
/// why this migration is small: only the four places that convert frames
/// to REAL TIME care about the numerator and denominator.
class ProjectFrameRate {
  const ProjectFrameRate({
    required this.numerator,
    required this.denominator,
    required this.countingBase,
  });

  /// A whole-number rate, where counting and timing agree.
  const ProjectFrameRate.integer(int fps)
    : numerator = fps,
      denominator = 1,
      countingBase = fps;

  /// An NTSC pulldown rate: [base] slowed by exactly 1000/1001.
  const ProjectFrameRate.ntsc(int base)
    : numerator = base * 1000,
      denominator = 1001,
      countingBase = base;

  /// Frames per [denominator] seconds. 24000/1001 = 23.976…
  final int numerator;
  final int denominator;

  /// The integer frames-per-second the sheet and the grid count with.
  final int countingBase;

  static const ProjectFrameRate fps24 = ProjectFrameRate.integer(24);

  /// The picker's menu, in the order it shows them.
  static const List<ProjectFrameRate> presets = [
    ProjectFrameRate.integer(8),
    ProjectFrameRate.integer(12),
    ProjectFrameRate.integer(15),
    ProjectFrameRate.ntsc(24), // 23.976
    ProjectFrameRate.integer(24),
    ProjectFrameRate.integer(25),
    ProjectFrameRate.ntsc(30), // 29.97
    ProjectFrameRate.integer(30),
    ProjectFrameRate.integer(48),
    ProjectFrameRate.integer(50),
    ProjectFrameRate.ntsc(60), // 59.94
    ProjectFrameRate.integer(60),
  ];

  bool get isInteger => denominator == 1;

  /// For display and for the rare consumer that genuinely wants a double
  /// (a pixels-per-second layout, say). Never use this for timing.
  double get approximateFps => numerator / denominator;

  /// `24 fps`, `23.976 fps` — trailing zeros trimmed.
  String get label {
    if (isInteger) {
      return '$numerator fps';
    }
    final text = approximateFps.toStringAsFixed(3);
    final trimmed = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '$trimmed fps';
  }

  /// What ffmpeg wants for `-framerate` / `-r`: it takes the fraction
  /// directly, so an NTSC export is exact rather than 23.976-rounded.
  String get ffmpegRateArgument =>
      isInteger ? '$numerator' : '$numerator/$denominator';

  // --- Exact conversions. Integers only: a 64-bit int holds a 3-hour
  // timeline in samples with 5 orders of magnitude to spare, and unlike a
  // double it cannot lose the low bits as the timeline grows. ---

  /// The frame showing at [elapsed] of wall clock. Truncating (not
  /// rounding) is what makes playback DROP frames under load instead of
  /// slowing down — the frame you are late for is already gone.
  int frameAtElapsed(Duration elapsed) {
    final micros = elapsed.inMicroseconds;
    if (micros <= 0) {
      return 0;
    }
    return micros * numerator ~/ (denominator * Duration.microsecondsPerSecond);
  }

  /// When [frame] begins, exactly.
  Duration frameStart(int frame) =>
      Duration(microseconds: frameStartMicroseconds(frame));

  int frameStartMicroseconds(int frame) =>
      frame * denominator * Duration.microsecondsPerSecond ~/ numerator;

  /// When [frame] begins, in seconds — for the consumers that must hand a
  /// decimal to something outside our control (ffmpeg's `adelay`/`atrim`).
  /// The frame count is reduced exactly first, so the only rounding is the
  /// final divide.
  double frameStartSeconds(int frame) =>
      frameStartMicroseconds(frame) / Duration.microsecondsPerSecond;

  /// The first device sample belonging to [frame] — the mixer's whole
  /// reason for existing. Sample-exact at any distance from zero, so clip
  /// starts land within ±1 sample no matter how long the movie runs.
  ///
  /// Rounds UP deliberately. At 29.97 frame 1 begins at sample 1601.6, and
  /// sample 1601 is still inside frame 0 — truncating would start a clip a
  /// sample BEFORE the frame that owns it, and [sampleToFrame] would then
  /// report the previous frame for the position we just scheduled. Rounding
  /// up is the only choice that makes the pair round trip.
  int frameToSample(int frame, int sampleRate) {
    if (frame <= 0) {
      return 0;
    }
    return _ceilDiv(frame * sampleRate * denominator, numerator);
  }

  /// The frame containing device sample [sample]. The inverse the audio
  /// clock reads back once the device, not a timer, drives playback.
  int sampleToFrame(int sample, int sampleRate) =>
      sample * numerator ~/ (sampleRate * denominator);

  /// Whole frames covering an EXACT duration of [seconds]/[per] seconds,
  /// rounded up. Callers with a rational source (a bucket count over a
  /// bucket rate) should use this and never touch a double: at 24fps a
  /// 2-second file computed as `2.0 * 24` yields 48.000000000000004, and
  /// a naive `.ceil()` invents a 49th frame of silence.
  int framesCoveringExactSeconds(int seconds, int per) {
    final denominatorProduct = per * denominator;
    if (denominatorProduct <= 0) {
      return 0;
    }
    return _ceilDiv(seconds * numerator, denominatorProduct);
  }

  /// Whole frames covering [seconds], rounded up — for the one source
  /// that is genuinely a double (ffprobe's reported file duration). A
  /// value within a millionth of a frame of a whole one IS whole; float
  /// noise must not buy a frame the file does not have.
  int framesCoveringSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      return 0;
    }
    final exact = seconds * numerator / denominator;
    final nearest = exact.roundToDouble();
    if ((exact - nearest).abs() < 1e-6) {
      return nearest.toInt();
    }
    return exact.ceil();
  }

  ProjectFrameRate copyWith({
    int? numerator,
    int? denominator,
    int? countingBase,
  }) {
    return ProjectFrameRate(
      numerator: numerator ?? this.numerator,
      denominator: denominator ?? this.denominator,
      countingBase: countingBase ?? this.countingBase,
    );
  }

  Map<String, dynamic> toJson() => {
    'numerator': numerator,
    'denominator': denominator,
    'countingBase': countingBase,
  };

  factory ProjectFrameRate.fromJson(Map<String, dynamic> json) {
    final numerator = json['numerator'] as int;
    final denominator = json['denominator'] as int;
    return ProjectFrameRate(
      numerator: numerator,
      denominator: denominator,
      // A hand-edited or older file may carry the fraction alone; the
      // counting base of every real-world rate is the fraction rounded.
      countingBase:
          (json['countingBase'] as int?) ??
          (denominator <= 0 ? 24 : (numerator / denominator).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectFrameRate &&
          other.numerator == numerator &&
          other.denominator == denominator &&
          other.countingBase == countingBase;

  @override
  int get hashCode => Object.hash(numerator, denominator, countingBase);

  @override
  String toString() =>
      'ProjectFrameRate($numerator/$denominator, base: $countingBase)';
}

/// Integer division rounding up, for non-negative operands.
int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// THE seconds+frames notation (秒+コマ): `2+3`, `2+12`, `0+0`.
///
/// One function for every surface that prints a duration this way — the
/// timeline's block labels and counter, the storyboard's cut blocks, and
/// the conte sheet's TIME column. They used to be two that differed only
/// in zero padding, which meant the same 51 frames read `2+03` on screen
/// and `2+3` on paper (user: "타임라인도 0패딩 없애자. 통일하게").
///
/// [framesPerSecond] is the COUNTING base, never the exact fraction: this
/// is the integer-frame surface ProjectFrameRate.countingBase exists for.
String secondsPlusFramesLabel(int frames, int framesPerSecond) {
  final fps = framesPerSecond < 1 ? 1 : framesPerSecond;
  return '${frames ~/ fps}+${frames % fps}';
}

/// The audio pull that keeps every sound's exact FRAME span across a
/// [from]→[to] rate change, or null when the question does not arise
/// (EXPORT-AUDIO ④, the RT conform semantics).
///
/// Meaningful only for a pulldown pair — same counting base, different
/// fraction (23.976↔24, 29.97↔30): the real speed shifts by 0.1% and
/// pulling the audio by the exact rational keeps frame alignment with an
/// inaudible pitch change. Across DIFFERENT counting bases (24→30) a
/// "pull" would be a 25% speed change nobody wants — sounds keep real
/// time and their frame spans simply recompute, so no choice is offered.
({int numerator, int denominator})? audioPullBetween(
  ProjectFrameRate from,
  ProjectFrameRate to,
) {
  if (from.countingBase != to.countingBase) {
    return null;
  }
  // Frame durations are den/num seconds: the pull is their exact ratio.
  final numerator = from.denominator * to.numerator;
  final denominator = from.numerator * to.denominator;
  if (numerator == denominator) {
    return null;
  }
  final divisor = numerator.gcd(denominator);
  return (
    numerator: numerator ~/ divisor,
    denominator: denominator ~/ divisor,
  );
}
