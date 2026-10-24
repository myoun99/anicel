import 'dart:math' as math;

import '../../models/cut.dart';
import '../../models/cut_id.dart';

/// One picture a frame shows: [cut]'s, at its own [frameIndex] — on its
/// paper where the screen showing it paints the paper ([paintPaper]).
///
/// 🚨[paintPaper] IS PART OF WHICH PICTURE (one-picture-per-frame ②-2): the
/// paper is the root's bottom row, read by a blend over its backdrop and by
/// an adjustment as any row is, so it cannot be laid under a picture made
/// without it. A cut on the canvas, and the film's stage — its lowest track
/// covered at that frame — paint it; a track over the stage does not, and
/// the same frame of it is another picture there.
typedef DemandedPicture = ({Cut cut, int frameIndex, bool paintPaper});

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
  /// wherever nothing plays — and none (null) wherever the clock waits for
  /// its picture: the walk starts under the playhead, and what the run
  /// waits for is made whatever the room (`PlaybackPrerenderScheduler`).
  int? leadFor(Duration composeTime);
}

/// The frame a run that STANDS on [center] wants at step [step] of its
/// [count] frames, or null past the last: from [center] outwards, the frame
/// after before the frame before at each distance, and the longer side's
/// rest once the shorter has run out.
///
/// 🚨ONE ORDER for whatever stands — a cut's frames ([StandingDemand]) and
/// a document's pages (`MediaRun.wantedAt`) — read either way round by this
/// and [standingStepOf] (viewer-plays-by-the-one-playback-law, ②).
int? standingFrameAt(int step, {required int center, required int count}) {
  if (step < 0 || step >= count) {
    return null;
  }
  // Both sides reach this far: their frames alternate, after first.
  final both = math.min(center, count - 1 - center);
  if (step <= 2 * both) {
    final distance = (step + 1) ~/ 2;
    return step.isOdd ? center + distance : center - distance;
  }
  final distance = step - both;
  return center < count - 1 - center ? center + distance : center - distance;
}

/// [standingFrameAt] read back: the step [frame] is wanted at, or null for
/// a frame outside the [count].
int? standingStepOf(int frame, {required int center, required int count}) {
  if (frame < 0 || frame >= count) {
    return null;
  }
  final distance = (frame - center).abs();
  if (distance == 0) {
    return 0;
  }
  final both = math.min(center, count - 1 - center);
  if (distance > both) {
    // On the longer side, past where the shorter ran out.
    return both + distance;
  }
  return frame > center ? 2 * distance - 1 : 2 * distance;
}

/// How many steps on from [playhead] a run that PLAYS shows frame [frame]
/// of its [total], or null where it does not: round to the frame behind the
/// playhead when it [loops], and never again behind it when it plays once.
///
/// 🚨ONE ORDER for whatever plays — a canvas run's frames ([PlayingDemand])
/// and a document's pages (`MediaRun.wantedAt`).
int? playingStepOf(
  int frame, {
  required int playhead,
  required int total,
  required bool loops,
}) {
  if (frame < 0 || frame >= total) {
    return null;
  }
  final ahead = frame - playhead;
  if (loops) {
    return ahead % total;
  }
  // Played once, a frame behind the playhead is not shown again.
  return ahead >= 0 ? ahead : null;
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
  }) : _frameCount = frameCount,
       _center = around.clamp(0, frameCount - 1),
       _nextFrameCount = nextCutId == null || nextCutId == cutId
           ? 0
           : nextFrameCount;

  final CutId cutId;
  final CutId? nextCutId;

  /// The cut as it is NOW: an edit is a new cut, and a picture made of the
  /// one this was asked with would be a picture of what the cut was.
  final Cut? Function(CutId cutId) resolveCut;

  final int _frameCount;
  final int _center;
  final int _nextFrameCount;

  @override
  int get length => _frameCount + _nextFrameCount;

  @override
  List<DemandedPicture>? picturesAt(int step) {
    if (step < 0 || step >= length) {
      return null;
    }
    final own = step < _frameCount;
    final cut = resolveCut(own ? cutId : nextCutId!);
    if (cut == null) {
      return const [];
    }
    return [
      (
        cut: cut,
        frameIndex: own
            ? standingFrameAt(step, center: _center, count: _frameCount)!
            : step - _frameCount,
        // Both cuts are the canvas's: the one it stands on, and the one it
        // shows next.
        paintPaper: true,
      ),
    ];
  }

  @override
  int? stepOf(CutId cutId, int frameIndex) {
    if (cutId == this.cutId) {
      return standingStepOf(frameIndex, center: _center, count: _frameCount);
    }
    if (cutId == nextCutId && frameIndex >= 0 && frameIndex < _nextFrameCount) {
      return _frameCount + frameIndex;
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
  int? leadFor(Duration composeTime) => 0;
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

  /// [leadFor]'s answer — null where the clock waits for its picture, as
  /// where no [lead] is given.
  final int? Function(Duration composeTime)? lead;

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
    return frame == null
        ? null
        : playingStepOf(
            frame,
            playhead: playhead(),
            total: totalFrames,
            loops: loops(),
          );
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
  int? leadFor(Duration composeTime) => lead?.call(composeTime);
}
