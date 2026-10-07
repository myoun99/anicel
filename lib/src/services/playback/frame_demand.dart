import '../../models/cut.dart';
import '../../models/cut_id.dart';

/// One picture a frame shows: [cut]'s, at its own [frameIndex].
typedef DemandedPicture = ({Cut cut, int frameIndex});

/// The order frames will be WANTED in, counted in steps on from where the
/// playhead stands — step 0 is the frame under it.
///
/// 🚨ONE ORDER, TWO READERS (유저 2026-10-08, the playback rework: 「통일할거
/// 통일하면서 권장대로가자」). The warmer makes pictures in this order and the
/// budget lets go of them in the reverse of it, so what is kept is what is
/// wanted soonest, whichever of the two is asked.
///
/// ↩️They answered apart. The warm walked a list of frames fixed when it was
/// asked for; the budget kept a RANGE whole — the active cut's frames, and
/// while playing every frame of every cut on the playlist — whatever the
/// allowance said. A range that large is no allowance at all: a film played
/// through kept every picture it made (유저: 「우리는 1500컷을 목표로 하니까
/// 그정도급에서의 재생인거지」), and a cut heavier than the allowance kept
/// baking the frames it had just let go.
abstract interface class FrameDemand {
  /// How many steps there are: a lap of a run that loops, the rest of one
  /// that plays once, every frame a warm reaches.
  int get length;

  /// The pictures the frame [step] steps on shows — none where it shows
  /// nothing — or null past the last step.
  List<DemandedPicture>? picturesAt(int step);

  /// How many steps on [cutId]'s frame [frameIndex] is next shown, or null
  /// when no step shows it.
  int? stepOf(CutId cutId, int frameIndex);

  /// How many steps the playhead has moved on since this was last asked —
  /// what a walker takes off the count it had reached.
  int advanced();

  /// Whether making these pictures stands aside for the editor: a warm
  /// under the hand that draws waits for it to rest; a run that plays has
  /// no hand drawing under it.
  bool get yieldsToEditing;

  /// How many steps ahead of the playhead a picture is STARTED, when making
  /// one takes [composeTime]: where the playhead will be when it lands. 0
  /// wherever the clock waits for its picture, and wherever nothing plays.
  int leadFor(Duration composeTime);
}

/// What is wanted while nothing plays: the cut being worked on, from the
/// playhead outwards ("navigate away from a frame and it gets pre-rendered"),
/// and then — when there is one — the cut after it, from its first frame.
///
/// #31 (유저 확정 2026-08-16: 스토리보드 프로 따라서) — the lookahead is
/// Storyboard Pro's shape: one direction, the cut you are about to enter,
/// entered at its first frame. It is wanted AFTER every frame of the cut
/// being worked on, which is the whole of its standing: it is made last, and
/// under a full allowance it is the first to be let go.
///
/// ⑯ / B1: [frameCount] is the caller's law for how far the cut's pictures
/// reach (`cutWarmFrameCount` — the runway past the end line takes drawings
/// like any other frame). The warm, the budget and the readiness bar read
/// that one count; here it is simply how many steps the cut has.
class StandingDemand implements FrameDemand {
  StandingDemand({
    required this.cutId,
    required int frameCount,
    required int around,
    this.nextCutId,
    int nextFrameCount = 0,
    required this.resolveCut,
  }) : _nextFrameCount = nextCutId == null || nextCutId == cutId
           ? 0
           : nextFrameCount {
    final center = around.clamp(0, frameCount - 1);
    _stepOfFrame = List<int>.filled(frameCount, 0);
    _frameAtStep.add(center);
    for (var distance = 1; distance < frameCount; distance += 1) {
      if (center + distance < frameCount) {
        _frameAtStep.add(center + distance);
      }
      if (center - distance >= 0) {
        _frameAtStep.add(center - distance);
      }
    }
    for (var step = 0; step < _frameAtStep.length; step += 1) {
      _stepOfFrame[_frameAtStep[step]] = step;
    }
  }

  final CutId cutId;
  final CutId? nextCutId;

  /// The cut as it is NOW: an edit is a new cut, and a picture made of the
  /// one this was asked with would be a picture of what the cut was.
  final Cut? Function(CutId cutId) resolveCut;

  final int _nextFrameCount;
  final List<int> _frameAtStep = <int>[];
  late final List<int> _stepOfFrame;

  @override
  int get length => _frameAtStep.length + _nextFrameCount;

  @override
  List<DemandedPicture>? picturesAt(int step) {
    if (step < 0 || step >= length) {
      return null;
    }
    final own = step < _frameAtStep.length;
    final cut = resolveCut(own ? cutId : nextCutId!);
    if (cut == null) {
      return const [];
    }
    return [
      (
        cut: cut,
        frameIndex: own ? _frameAtStep[step] : step - _frameAtStep.length,
      ),
    ];
  }

  @override
  int? stepOf(CutId cutId, int frameIndex) {
    if (frameIndex < 0) {
      return null;
    }
    if (cutId == this.cutId) {
      return frameIndex < _stepOfFrame.length ? _stepOfFrame[frameIndex] : null;
    }
    if (cutId == nextCutId && frameIndex < _nextFrameCount) {
      return _frameAtStep.length + frameIndex;
    }
    return null;
  }

  /// A playhead that moves is a new demand ([resolveCut]'s caller asks
  /// again), so this one never moves.
  @override
  int advanced() => 0;

  @override
  bool get yieldsToEditing => true;

  @override
  int leadFor(Duration composeTime) => 0;
}

/// What a run that is PLAYING wants: its frames in the order it plays them,
/// from the playhead on — round to the frame behind it when it loops, to its
/// last frame when it plays once.
///
/// The playlist is frozen when the run begins, so [totalFrames] is the
/// run's; everything else is read as it stands, because the playhead moves
/// and the loop button can be pressed under a run.
class PlayingDemand implements FrameDemand {
  PlayingDemand({
    required this.totalFrames,
    required this.loops,
    required this.playhead,
    required this.picturesOf,
    required this.playlistFrameOf,
    this.lead,
  }) : _askedAt = playhead();

  /// The run's frames, its trailing gap included.
  final int totalFrames;
  final bool Function() loops;

  /// The playlist frame the run stands on.
  final int Function() playhead;

  /// The pictures playlist frame [playlistFrame] shows: the one cut's while
  /// a cut plays alone, every covered track's — and both halves of an O.L —
  /// while the film does.
  final List<DemandedPicture> Function(int playlistFrame) picturesOf;

  /// The playlist frame [cutId]'s own frame [frameIndex] is shown at, or
  /// null when the run does not show that cut.
  final int? Function(CutId cutId, int frameIndex) playlistFrameOf;

  /// [leadFor]'s answer; null where the clock waits for its picture.
  final int Function(Duration composeTime)? lead;

  int _askedAt;

  @override
  int get length =>
      loops() ? totalFrames : (totalFrames - playhead()).clamp(0, totalFrames);

  @override
  List<DemandedPicture>? picturesAt(int step) {
    if (step < 0 || step >= length) {
      return null;
    }
    return picturesOf((playhead() + step) % totalFrames);
  }

  @override
  int? stepOf(CutId cutId, int frameIndex) {
    final frame = playlistFrameOf(cutId, frameIndex);
    if (frame == null || frame < 0 || frame >= totalFrames) {
      return null;
    }
    final ahead = frame - playhead();
    if (loops()) {
      return ahead % totalFrames;
    }
    // Played once, a frame behind the playhead is not shown again.
    return ahead >= 0 ? ahead : null;
  }

  @override
  int advanced() {
    final now = playhead();
    final moved = now - _askedAt;
    _askedAt = now;
    if (loops()) {
      return moved % totalFrames;
    }
    // A step back in a run that plays once is a seek: start over.
    return moved >= 0 ? moved : totalFrames;
  }

  @override
  bool get yieldsToEditing => false;

  @override
  int leadFor(Duration composeTime) => lead?.call(composeTime) ?? 0;
}
