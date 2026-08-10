import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project_frame_rate.dart';
import '../../models/track_id.dart';
import '../../models/transition_geometry.dart';
import '../../ui/storyboard_timeline_layout.dart';

/// Wall-clock elapsed time → global frame index at [rate]. Elapsed-based
/// mapping is what makes playback drop frames instead of slowing down.
///
/// RT: the rate is the exact fraction, so a 23.976 project maps time to
/// frames without the 0.1% error a rounded 24 would accumulate — after an
/// hour that error is 3.6 seconds of drift.
int elapsedToGlobalFrame(Duration elapsed, ProjectFrameRate rate) {
  return rate.frameAtElapsed(elapsed);
}

/// Where a global playlist frame lands: which cut, and which local frame.
class PlaybackPosition {
  const PlaybackPosition({
    required this.cut,
    required this.localFrameIndex,
    required this.globalFrameIndex,
  });

  /// The cut snapshot from the playlist (frozen at play start).
  final Cut cut;
  final int localFrameIndex;
  final int globalFrameIndex;

  CutId get cutId => cut.id;

  @override
  String toString() =>
      'PlaybackPosition(cut: ${cut.id}, local: $localFrameIndex, '
      'global: $globalFrameIndex)';
}

/// Resolves [globalFrameIndex] against sequential playlist entries
/// (endFrame exclusive); `null` when out of range or on zero-length cuts.
PlaybackPosition? resolvePlaybackPosition({
  required List<StoryboardTimelineLayoutEntry> playlist,
  required int globalFrameIndex,
}) {
  for (final entry in playlist) {
    if (globalFrameIndex >= entry.startFrame &&
        globalFrameIndex < entry.endFrame) {
      return PlaybackPosition(
        cut: entry.cut,
        localFrameIndex: globalFrameIndex - entry.startFrame,
        globalFrameIndex: globalFrameIndex,
      );
    }
  }
  return null;
}

int playlistTotalFrames(List<StoryboardTimelineLayoutEntry> playlist) {
  return playlist.isEmpty ? 0 : playlist.last.endFrame;
}

/// One cut's contribution to a global frame while a transition is running.
class TransitionContribution {
  const TransitionContribution({
    required this.cut,
    required this.localFrameIndex,
    required this.opacity,
  });

  final Cut cut;

  /// The frame INSIDE the cut, counted from its first frame of MATERIAL —
  /// which is the cut's conte start only when it owes no head のりしろ.
  ///
  /// A cut on the incoming side of an O.L supplies pictures before its own
  /// block begins, so its frame 0 sits `head` frames earlier on the global
  /// axis. The block has not moved: the conte range still says which cut
  /// OWNS a frame, and every consumer asking that question keeps reading it.
  final int localFrameIndex;

  /// 1 outside a transition; the ramp while one crosses this cut's boundary.
  final double opacity;

  @override
  String toString() =>
      'TransitionContribution(cut: ${cut.id}, local: $localFrameIndex, '
      'opacity: $opacity)';
}

/// Everything visible at [globalFrameIndex] on ONE track, transitions
/// included — the resolution a compositor wants.
///
/// Ordinary frames answer with a single contribution at full opacity, so a
/// project without transitions behaves exactly as it did. Inside an O.L two
/// come back, OUTGOING FIRST: the cut being replaced, then the one arriving
/// over it. Painting them in that order is the cross-dissolve.
///
/// ★ This widens [resolvePlaybackPosition] in one specific way and no
/// other: it asks which cuts have MATERIAL here (the media range) rather
/// than which cut owns the frame (the conte range). The two differ only
/// where a transition reaches across a boundary — exactly where a second
/// picture is supposed to exist.
List<TransitionContribution> resolveTransitionContributions({
  required List<StoryboardTimelineLayoutEntry> playlist,
  required List<TransitionSpan> spans,
  required int globalFrameIndex,
}) {
  final contributions = <TransitionContribution>[];
  for (final entry in playlist) {
    final handles = cutTransitionHandles(
      cutStart: entry.startFrame,
      cutEnd: entry.endFrame,
      spans: spans,
    );
    final media = cutMediaRange(
      cutStart: entry.startFrame,
      cutEnd: entry.endFrame,
      handles: handles,
    );
    if (globalFrameIndex < media.start || globalFrameIndex >= media.end) {
      continue;
    }
    contributions.add(
      TransitionContribution(
        cut: entry.cut,
        localFrameIndex: globalFrameIndex - media.start,
        opacity: cutOpacityAt(
          cutStart: entry.startFrame,
          cutEnd: entry.endFrame,
          spans: spans,
          globalFrame: globalFrameIndex,
        ),
      ),
    );
  }
  return contributions;
}

/// One entry of the stack a compositor paints: a cut's picture, its unit
/// alpha, and which track group it belongs to.
class TrackStackContribution {
  const TrackStackContribution({
    required this.cut,
    required this.localFrameIndex,
    required this.globalFrameIndex,
    required this.trackIndex,
    required this.opacity,
    required this.isBottomTrack,
  });

  final Cut cut;

  /// The frame inside the cut, counted from its first frame of MATERIAL —
  /// so a cut arriving over an O.L supplies pictures before its own block.
  final int localFrameIndex;
  final int globalFrameIndex;
  final int trackIndex;

  /// The share of the result this cut's picture should own — the transition
  /// ramp, before any track fade the caller multiplies in. 1 outside an O.L.
  final double opacity;

  /// Whether this contribution belongs to the bottom covered TRACK — the
  /// stage, which owns the paper, the letterbox and the pasteboard apron.
  ///
  /// ★Deliberately per TRACK and not "is this the bottom contribution".
  /// A Japanese O.L is a 場面転換: the whole screen changes, paper and BG
  /// included, so BOTH cuts of a same-track O.L paint the stage and the
  /// weights cross-fade it. Keying the stage to the bottom CONTRIBUTION is
  /// what made the arriving cut a superimpose of line art over the leaving
  /// cut's paper.
  final bool isBottomTrack;

  CutId get cutId => cut.id;

  @override
  String toString() =>
      'TrackStackContribution(cut: ${cut.id}, local: $localFrameIndex, '
      'global: $globalFrameIndex, track: $trackIndex, opacity: $opacity, '
      'bottom: $isBottomTrack)';
}

/// Source-over paint alphas that make a stack of contributions read as the
/// weighted MIX their [alphas] describe, with whatever sits below showing
/// exactly the share the mix leaves unclaimed.
///
/// 🚨★Painting an O.L's two halves at their own alphas is wrong and looks
/// like a bug: source-over leaves `t(1-t)` of the floor showing through the
/// middle of every dissolve — a dip to black at the exact moment the two
/// pictures should be all there is. The leaving picture has to go down
/// OPAQUE and the arriving one over it at `t`.
///
/// That is this formula's `i == 0` case, and it generalises: with
/// `S_i = below + Σ_{j≤i} a_j` and `w_i = a_i / S_i`, the result's
/// coefficient for each picture is exactly `a_i` and the floor keeps
/// `1 - Σa`. A lone F.O into a gap therefore still fades to the backdrop
/// (`w = a`), while an O.L's pair does not (`w = 1, t`).
///
/// [alphas] summing past 1 is not a mix but plain layering (independent
/// tracks), and the alphas are returned unchanged — the premise the
/// normalisation rests on is that the group PARTITIONS one screen, which is
/// true within a track and false across them.
List<double> sourceOverWeights(List<double> alphas) {
  final clamped = [for (final alpha in alphas) alpha.clamp(0.0, 1.0)];
  var total = 0.0;
  for (final alpha in clamped) {
    total += alpha;
  }
  if (total >= 1) {
    if (clamped.length <= 1) {
      return clamped;
    }
    // Only a partition can be normalised; anything else is layering.
    if (total > 1 + 1e-9) {
      return clamped;
    }
  }
  var cumulative = total >= 1 ? 0.0 : 1 - total;
  final weights = <double>[];
  for (final alpha in clamped) {
    cumulative += alpha;
    weights.add(cumulative <= 0 ? 0.0 : (alpha / cumulative).clamp(0.0, 1.0));
  }
  return weights;
}

/// [sourceOverWeights] applied PER TRACK GROUP over a whole stack.
///
/// The normalisation only holds inside a track, where an O.L's two halves
/// partition one screen. Across tracks the contributions layer, so each
/// track's run is weighted on its own and the runs stack unchanged.
List<double> trackGroupSourceOverWeights(
  List<TrackStackContribution> stack,
  List<double> unitAlphas,
) {
  final weights = List<double>.filled(stack.length, 1);
  var runStart = 0;
  while (runStart < stack.length) {
    var runEnd = runStart;
    while (runEnd < stack.length &&
        stack[runEnd].trackIndex == stack[runStart].trackIndex) {
      runEnd += 1;
    }
    final run = sourceOverWeights(unitAlphas.sublist(runStart, runEnd));
    for (var i = 0; i < run.length; i += 1) {
      weights[runStart + i] = run[i];
    }
    runStart = runEnd;
  }
  return weights;
}

/// Everything a compositor must paint at [globalFrameIndex], across every
/// track, transitions included — bottom to top.
///
/// Per track this is [resolveTransitionContributions] (so an O.L answers
/// with both cuts, outgoing first); across tracks it keeps project track
/// order, exactly as [resolveTrackStackPositions] did. With no transition
/// anywhere the two agree contribution for contribution.
List<TrackStackContribution> resolveTrackStackContributions({
  required List<StoryboardTimelineLayoutEntry> layout,
  required List<TransitionSpan> Function(TrackId trackId) spansOf,
  required int globalFrameIndex,
}) {
  final byTrack = <int, List<StoryboardTimelineLayoutEntry>>{};
  for (final entry in layout) {
    (byTrack[entry.trackIndex] ??= []).add(entry);
  }
  final trackIndexes = byTrack.keys.toList()..sort();
  final stack = <TrackStackContribution>[];
  var bottomTrackIndex = -1;
  for (final trackIndex in trackIndexes) {
    final entries = byTrack[trackIndex]!;
    final contributions = resolveTransitionContributions(
      playlist: entries,
      spans: spansOf(entries.first.trackId),
      globalFrameIndex: globalFrameIndex,
    );
    if (contributions.isEmpty) {
      continue;
    }
    if (bottomTrackIndex < 0) {
      bottomTrackIndex = trackIndex;
    }
    for (final contribution in contributions) {
      stack.add(
        TrackStackContribution(
          cut: contribution.cut,
          localFrameIndex: contribution.localFrameIndex,
          globalFrameIndex: globalFrameIndex,
          trackIndex: trackIndex,
          opacity: contribution.opacity,
          isBottomTrack: trackIndex == bottomTrackIndex,
        ),
      );
    }
  }
  return stack;
}

/// The multitrack display resolution: [globalFrameIndex] answered by EVERY
/// track of a multi-track [layout] — at most one position per track, the
/// entry that STRICTLY contains the frame. Gap frames and frames past a
/// track's last cut contribute nothing (never the owner-rule runway the
/// editing axis uses), so a track without picture at this frame is simply
/// absent from the result.
///
/// Track axes each start at global frame 0 (buildStoryboardTimelineLayout
/// resets per track), so one shared index addresses all tracks in parallel;
/// entries within one track never overlap, and cross-track startFrame
/// overlap is fine because containment is tested per entry. The result
/// keeps layout order (= project track order): painting it in order stacks
/// later tracks on top.
List<PlaybackPosition> resolveTrackStackPositions({
  required List<StoryboardTimelineLayoutEntry> layout,
  required int globalFrameIndex,
}) {
  return [
    for (final entry in layout)
      if (globalFrameIndex >= entry.startFrame &&
          globalFrameIndex < entry.endFrame)
        PlaybackPosition(
          cut: entry.cut,
          localFrameIndex: globalFrameIndex - entry.startFrame,
          globalFrameIndex: globalFrameIndex,
        ),
  ];
}
