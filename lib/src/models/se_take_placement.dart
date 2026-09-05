import 'dart:collection';

import 'audio_clip.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'timeline_exposure.dart';

/// A landed take (REC1-B): the SE row's next state and the id of the new
/// instance carrying the recording.
class SeTakePlacement {
  const SeTakePlacement({required this.layer, required this.takeFrameId});

  final Layer layer;
  final FrameId takeFrameId;
}

/// Plans landing a recorded take on an SE row, tape-style: the take wins
/// every frame it covers, existing blocks lose exactly the overlap.
///
/// The row's axis is whatever [layer] itself uses — track-global for
/// track SE lanes, cut-local for cut-owned rows; the planner never maps.
///
/// Overlap policy (user decision, 07-22):
///  - a block fully inside the take span is REMOVED (its instance and
///    audio links garbage-collect when nothing else references them —
///    the sound file itself stays in the media pool);
///  - a block the take runs into loses its head, and its sound keeps
///    playing from the matching point INSIDE the file
///    ([AudioClip.offsetFrames] grows by the trimmed frames);
///  - a block the take starts inside keeps its head part; a remainder
///    past the take's end survives as a NEW instance (the head keeps the
///    original frame, so the tail needs its own to carry its own offset);
///  - a head-trimmed block whose instance is SHARED by other blocks
///    (footsteps reuse) also gets a new instance — bumping the shared
///    clip would shift every sibling's sound.
///
/// Ghost exposures are derived material and pass through untouched.
/// Breakdown offsets are a drawing-row concept and no SE row carries
/// them; trims go through [TimelineExposure.copyWith]'s normalization.
///
/// [newFrameId] mints ids for split/shared remainders. Returns null when
/// [lengthFrames] < 1.
SeTakePlacement? planSeTakePlacement({
  required Layer layer,
  required int startFrame,
  required int lengthFrames,
  required String filePath,
  required FrameId takeFrameId,
  required FrameId Function() newFrameId,
  bool takeClipped = false,
}) {
  if (lengthFrames < 1 || startFrame < 0) {
    return null;
  }
  final splice = _TakeSplice(
    layer: layer,
    takeStart: startFrame,
    takeEnd: startFrame + lengthFrames,
    newFrameId: newFrameId,
  );
  for (final entry in layer.timeline.entries) {
    splice.place(entry.key, entry.value);
  }
  final nextTimeline = splice.timeline;

  nextTimeline[startFrame] = TimelineExposure.drawing(
    takeFrameId,
    length: lengthFrames,
  );

  final referenced = <FrameId>{
    for (final exposure in nextTimeline.values)
      if (exposure.isDrawing && !exposure.ghost && exposure.frameId != null)
        exposure.frameId!,
  };
  final nextFrames = <Frame>[
    for (final frame in layer.frames)
      if (referenced.contains(frame.id)) frame,
    ...splice.clonedFrames,
    Frame(id: takeFrameId, duration: 1, strokes: const [], name: null),
  ];
  final nextClips = <AudioClip>[
    for (final clip in layer.audioClips)
      if (referenced.contains(clip.frameId))
        splice.offsetBumps.containsKey(clip.frameId)
            ? clip.copyWith(
                offsetFrames:
                    clip.offsetFrames + splice.offsetBumps[clip.frameId]!,
              )
            : clip,
    ...splice.clonedClips,
    AudioClip(filePath: filePath, frameId: takeFrameId, clipped: takeClipped),
  ];

  return SeTakePlacement(
    layer: layer.copyWith(
      frames: nextFrames,
      timeline: nextTimeline,
      audioClips: nextClips,
    ),
    takeFrameId: takeFrameId,
  );
}

/// Splicing a take into an SE row, block by block, the way tape is cut.
///
/// A block either misses the take entirely, is wholly covered by it, has
/// the take land INSIDE it (head plus a remainder), or is trimmed at one
/// end. Only three of those need a new instance, and which three is the
/// whole of this class.
class _TakeSplice {
  _TakeSplice({
    required this.layer,
    required this.takeStart,
    required this.takeEnd,
    required this.newFrameId,
  }) {
    // Sharing detection uses the row BEFORE the edit: an instance is
    // shared when more than one real block exposes it.
    for (final exposure in layer.timeline.values) {
      final frameId = exposure.frameId;
      if (exposure.isDrawing && !exposure.ghost && frameId != null) {
        _referenceCounts[frameId] = (_referenceCounts[frameId] ?? 0) + 1;
      }
    }
  }

  final Layer layer;
  final int takeStart;
  final int takeEnd;
  final FrameId Function() newFrameId;

  final _referenceCounts = <FrameId, int>{};
  final timeline = SplayTreeMap<int, TimelineExposure>();
  final clonedFrames = <Frame>[];
  final clonedClips = <AudioClip>[];

  /// Unshared head-trims: the instance's own clips slide into the file.
  final offsetBumps = <FrameId, int>{};

  void place(int blockStart, TimelineExposure exposure) {
    final length = exposure.length;
    if (!exposure.isDrawing || exposure.ghost || length == null) {
      timeline[blockStart] = exposure;
      return;
    }
    final blockEnd = blockStart + length;
    if (blockEnd <= takeStart || blockStart >= takeEnd) {
      timeline[blockStart] = exposure;
      return;
    }
    if (blockStart >= takeStart && blockEnd <= takeEnd) {
      return; // Fully covered: the take erased it.
    }
    final frameId = exposure.frameId;
    if (blockStart < takeStart) {
      // The head part keeps its instance and offset as-is; when the take
      // lands strictly INSIDE, what is left past it becomes a remainder.
      timeline[blockStart] = exposure.copyWith(length: takeStart - blockStart);
      if (blockEnd > takeEnd && frameId != null) {
        _addRemainder(
          sourceFrameId: frameId,
          source: exposure,
          remainderLength: blockEnd - takeEnd,
          trimmedFrames: takeEnd - blockStart,
        );
      }
      return;
    }
    // Head-trim: the block starts inside the take and survives past it.
    final trimmed = takeEnd - blockStart;
    if (frameId != null && (_referenceCounts[frameId] ?? 0) > 1) {
      // SHARED, so the surviving tail cannot move the instance everyone
      // else is reading — it gets one of its own.
      _addRemainder(
        sourceFrameId: frameId,
        source: exposure,
        remainderLength: blockEnd - takeEnd,
        trimmedFrames: trimmed,
      );
      return;
    }
    timeline[takeEnd] = exposure.copyWith(length: blockEnd - takeEnd);
    if (frameId != null) {
      offsetBumps[frameId] = trimmed;
    }
  }

  /// The remainder of a block past the take's end, carried by a fresh
  /// instance whose clips start [trimmedFrames] further into their files.
  void _addRemainder({
    required FrameId sourceFrameId,
    required TimelineExposure source,
    required int remainderLength,
    required int trimmedFrames,
  }) {
    final remainderId = newFrameId();
    clonedFrames.add(
      layer.frames
          .firstWhere((frame) => frame.id == sourceFrameId)
          .copyWith(id: remainderId),
    );
    for (final clip in layer.audioClips) {
      if (clip.frameId == sourceFrameId) {
        clonedClips.add(
          clip.copyWith(
            frameId: remainderId,
            offsetFrames: clip.offsetFrames + trimmedFrames,
          ),
        );
      }
    }
    timeline[takeEnd] = source.copyWith(
      frameId: remainderId,
      length: remainderLength,
    );
  }
}
