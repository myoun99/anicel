import 'dart:math' as math;

/// One reading of the device's clock, taken in the order that makes sense
/// of it (`QaAudioDevice.readClock`): the latest callback's word — what had
/// been handed, and when it was asked — or null when none has spoken since
/// the arm; the device's own count as it stands, the stair; the time now.
typedef DeviceClockReading = ({
  ({int positionSamples, int atMicros})? point,
  int stairSamples,
  int nowMicros,
});

/// The device's clock as a LINE through its stair.
///
/// 🗣️유저 2026-10-08: 「늦게바뀌는건 좀 많이 신경쓰이는데. 근본/구조적으로
/// 어떻게 안되나」 → 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되. 그게
/// 제일 최우선.」
///
/// What the device counts is the samples HANDED to it, and that count is a
/// stair: it climbs one audio callback at a time (🔬480 samples — 10ms — a
/// step, measured 2026-10-08). Read between two callbacks it says what had
/// been handed at the last one, while the device has gone on playing. A
/// picture that reads the stair changes its frame up to a step late, and by
/// a different amount each frame (at 24 frames a second over a 10ms step:
/// five frames of 40ms and one of 50).
///
/// Each callback also says WHEN it handed what it handed (the native
/// `qa_audio_device_clock`). A point is the stair's top corner: the count
/// as it stood then. The device plays on from there at its rate, so the
/// count that MEETS every corner is a line of that slope — and this is it.
///
/// 🚨THE LINE IS THE HIGHEST ONE ANY RECENT POINT LIES ON. A callback is
/// asked for late as often as on time (🔬7 to 14ms apart where 10 is due),
/// and the device has gone on playing while it was late: its point lies
/// UNDER the line, by its lateness. No point lies over it — a callback is
/// never asked for before the device wants it. So the points that came on
/// time are the ones on the line, and they are the highest. ⛔The line
/// through only the LATEST point would dip at every late callback and jump
/// back at the next: the picture's frames would wander by the callbacks'
/// lateness, which is the stair's fault in a smaller size.
///
/// Four things it holds to:
///
/// - 🚨NEVER BEHIND THE STAIR. What the stair says has been handed HAS
///   been handed: a frame changes no later than it did when the stair
///   alone was read.
/// - 🚨NEVER AHEAD OF THE SOUND. The count runs on from the latest point
///   only as far as the device has something to play ([arm]'s
///   `carriesFor` — what its buffer holds). A device whose callbacks have
///   stopped has run dry by then, and the clock stands where the sound did.
/// - 🚨NEVER A STEP BACK. The highest line is dropped for a lower one when
///   the point it rested on grows old ([_remembersFor]); read across that
///   seam the count would dip a hair, and a frame that steps back reads as
///   the lap wrapping. The count kept is the furthest one read.
/// - 🚨COUNTED ON THROUGH EVERY LAP. A device that loops wraps its own
///   count; this one does not. What is HEARD trails what is handed by the
///   device's latency, so the lap a listener is in is not the lap the
///   count is in: the latency comes off first, and only then is the count
///   folded into the loop ([foldedIntoTheLap]). ↩️Folded first — what
///   reading the device's wrapped count amounts to — the picture went
///   back to its first frame the moment the last sample was HANDED, a
///   latency before it was heard, and the lap's last frame was shown that
///   much short.
class DeviceClockLine {
  /// How long a point is remembered. Long enough to hold a callback that
  /// came on time (a few of them are asked for a second); short enough to
  /// follow a device whose own rate is a hair under the one it says — the
  /// line then sinks slowly, and a point kept for ever would hold it up.
  static const int _remembersFor = 500 * Duration.microsecondsPerMillisecond;

  /// The furthest count read under this arm, counted on through every lap.
  int _furthest = 0;

  /// The laps the device has wrapped through under this arm, and the point
  /// last read — a wrap is known by a point whose count stepped back.
  int _laps = 0;
  int? _lastPoint;

  /// The points heard of lately, each as WHERE ITS LINE STANDS — its count
  /// less what the device plays in the time to its stamp, in millionths of
  /// a sample: two points on one line have one height — by when it was
  /// stamped. A point read again is the one entry. Times are counted from
  /// the first point this line heard of, so the numbers stay small.
  final Map<int, int> _heights = {};
  int? _epochMicros;

  /// What the run under this arm is ([arm]).
  int _deviceRate = 0;
  int _carriesFor = 0;
  int _lapSamples = 0;

  /// A new arm: the transport was started afresh, on a device that plays
  /// [deviceRate] samples a second and carries [carriesFor] of them — what
  /// its buffer holds. [lapSamples] is the length of the span a looping
  /// device wraps through by itself, from the top; 0 for one that plays to
  /// its end. What was read before is of another run.
  void arm({
    required int deviceRate,
    required int carriesFor,
    int lapSamples = 0,
  }) {
    _furthest = 0;
    _deviceRate = deviceRate;
    _carriesFor = carriesFor;
    _lapSamples = lapSamples;
    _laps = 0;
    _lastPoint = null;
    _heights.clear();
  }

  /// The count at the time [clock] was read, counted on through every lap.
  int read(DeviceClockReading clock) {
    var read = clock.stairSamples;
    final point = clock.point;
    if (point != null) {
      final last = _lastPoint;
      if (last != null && point.positionSamples < last) {
        _laps += 1;
      }
      _lastPoint = point.positionSamples;
      final handed = point.positionSamples + _laps * _lapSamples;

      final epoch = _epochMicros ??= point.atMicros;
      final at = point.atMicros - epoch;
      final now = clock.nowMicros - epoch;
      const million = Duration.microsecondsPerSecond;
      _heights[at] = handed * million - _deviceRate * at;
      _heights.removeWhere((stamped, _) => at - stamped > _remembersFor);
      final highest = _heights.values.reduce(math.max);
      final onTheLine = (highest + _deviceRate * now) ~/ million;

      // How far past its point the stair stands. Read after the point it is
      // at it or past it — unless a callback under way has wrapped it
      // already, and then it is a lap further on than it reads. (A stair a
      // little UNDER its point was read before it: the point is the newer
      // word, and the greater of the two readings below leaves it out.)
      var stairAhead = clock.stairSamples - point.positionSamples;
      if (-stairAhead > _lapSamples ~/ 2) {
        stairAhead += _lapSamples;
      }
      read = math.max(
        handed + stairAhead,
        math.min(handed + _carriesFor, onTheLine),
      );
    }
    return _furthest = math.max(_furthest, read);
  }

  /// [samples] — a count kept on through every lap, the latency already off
  /// it — as a place in the lap. Under nothing it is not in the lap yet —
  /// the sound of the arm has not been heard — and stays where it is; so
  /// does every count of a device that does not loop.
  int foldedIntoTheLap(int samples) =>
      _lapSamples <= 0 || samples < 0 ? samples : samples % _lapSamples;
}
