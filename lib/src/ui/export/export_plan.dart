import 'dart:math' as math;

import '../../models/audio_clip.dart' show AudioVolumeKey;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/export_cel_naming.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/se_audio_spans.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track.dart';
import '../playback/audio_playback_schedule.dart' show ScheduledAudioClip;

// The size/naming values moved to the model layer (EX1 — the export spec
// serializes them); re-exported here so plan consumers keep one import.
export '../../models/export_cel_naming.dart';
export '../../models/export_size_mode.dart';

/// Which frames the export window covers: the active cut, every cut of the
/// active cut's track in storyboard order, or a subrange of the active cut.
enum ExportRange { activeCut, allCuts, frameRange }

/// Export container: a PNG file per frame, one H.264 MP4 encoded through
/// an external ffmpeg (see VideoExportService), or XDTS digital timesheets
/// (one .xdts per cut — sheet data, no rendering).
enum ExportFormat { pngSequence, mp4Video, xdtsTimesheet }

/// One composited output frame: [cut]'s local [frameIndex]. A negative
/// [frameIndex] is a frame of [cut]'s LEADING GAP (empty space before the
/// cut, played and exported as black): -1 is the gap frame right before
/// local 0, -leadingGapFrames the gap's first.
class ExportFrameTask {
  const ExportFrameTask({required this.cut, required this.frameIndex});

  final Cut cut;
  final int frameIndex;

  /// Renders as a black frame instead of compositing [cut].
  bool get isGap => frameIndex < 0;
}

/// One instance (cel) output: a unique authored [frame] of [layer], exported
/// as drawn — no compositing.
class ExportCelTask {
  const ExportCelTask({
    required this.cut,
    required this.layer,
    required this.frame,
    required this.fileName,
  });

  final Cut cut;
  final Layer layer;
  final Frame frame;

  /// Relative to the export directory; may contain `/` subfolders.
  final String fileName;
}

/// Pads the first digit run in [name] to [digits] ('1' → '0001', 'a12b' →
/// 'a0012b' at 4). Runs already at least [digits] wide and names without
/// digits are unchanged.
String padFrameNumber(String name, int digits) {
  if (digits <= 0) {
    return name;
  }
  final match = RegExp(r'\d+').firstMatch(name);
  if (match == null) {
    return name;
  }
  final run = match.group(0)!;
  if (run.length >= digits) {
    return name;
  }
  return name.replaceRange(match.start, match.end, run.padLeft(digits, '0'));
}

/// The cuts the chosen range covers, in play order. [ExportRange.frameRange]
/// is a subrange of the active cut, so it resolves to the active cut alone;
/// [ExportRange.allCuts] follows the playback all-cuts scope (every cut of
/// the track containing the active cut, first track as fallback).
List<Cut> resolveExportCuts({
  required Project project,
  required CutId activeCutId,
  required ExportRange range,
}) {
  Track? activeTrack;
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      if (cut.id == activeCutId) {
        activeTrack = track;
        break;
      }
    }
  }
  activeTrack ??= project.tracks.isEmpty ? null : project.tracks.first;
  if (activeTrack == null) {
    return const [];
  }

  if (range == ExportRange.allCuts) {
    return activeTrack.cuts;
  }
  for (final cut in activeTrack.cuts) {
    if (cut.id == activeCutId) {
      return [cut];
    }
  }
  return const [];
}

/// Ordered composite frames for the chosen range. Every cut plays at least
/// one frame (same floor playback uses). For [ExportRange.frameRange] the
/// 0-based inclusive [rangeStartFrame]/[rangeEndFrame] are clamped to the
/// active cut; a reversed range is empty.
///
/// [includeGaps] adds each cut's leading gap as black-frame tasks
/// (negative frame indexes) so the output matches all-cuts playback
/// frame for frame — video wants this, a PNG sequence skips the gaps.
/// Single-cut ranges never include a gap (single-cut playback doesn't
/// play one either).
List<ExportFrameTask> buildExportFramePlan({
  required Project project,
  required CutId activeCutId,
  required ExportRange range,
  int? rangeStartFrame,
  int? rangeEndFrame,
  bool includeGaps = false,
}) {
  final cuts = resolveExportCuts(
    project: project,
    activeCutId: activeCutId,
    range: range,
  );

  final plan = <ExportFrameTask>[];
  for (final cut in cuts) {
    final duration = math.max(1, cut.duration);
    var start = 0;
    var end = duration - 1;
    if (range == ExportRange.frameRange) {
      start = (rangeStartFrame ?? 0).clamp(0, duration - 1);
      end = (rangeEndFrame ?? duration - 1).clamp(0, duration - 1);
    }
    if (includeGaps && range == ExportRange.allCuts) {
      for (var gap = -cut.leadingGapFrames; gap < 0; gap += 1) {
        plan.add(ExportFrameTask(cut: cut, frameIndex: gap));
      }
    }
    for (var frameIndex = start; frameIndex <= end; frameIndex += 1) {
      plan.add(ExportFrameTask(cut: cut, frameIndex: frameIndex));
    }
  }
  return plan;
}

/// Lays every SE layer's audio clips onto the exported video's timeline,
/// in FRAMES on the export plan's own axis (frame 0 = the first exported
/// frame).
///
/// [plan] lists the exported frames in output order (contiguous per cut),
/// exactly what [VideoExportService] encodes — so a clip's offset is just
/// its position within its cut's block. Clips starting before the exported
/// range seek into the source instead of delaying; clips starting at or
/// past their cut's exported end are silent and dropped. Durations cap at
/// the cut's exported block, matching canvas playback (SE audio never
/// bleeds into the next cut); shorter sources simply end early (the mixer
/// plays silence past a source's last sample).
///
/// The result is the SAME schedule shape playback consumes — the export
/// mix renders through the same mixer, which is the whole point: what the
/// preview played is what the file holds.
/// One span, trimmed into the exported window [audibleStart, audibleEnd)
/// — or null when the window closed before it opened.
///
/// ⛔THE SAME anchors playback ramps at: the fade-in anchors to the span
/// (block) start, so a range starting mid-fade keeps only the remainder,
/// and the fade-out anchors to the audible end. Both cap at the audible
/// length, and the envelope keys shift by the trimmed lead (possibly
/// negative — before the exported window).
ScheduledAudioClip? _trimmedExportClip(
  SeAudioSpan span, {
  required _ExportWindow at,
  required double layerGain,
  required double layerPan,
}) {
  if (at.audibleEnd <= at.audibleStart) {
    return null;
  }
  final audibleFrames = at.audibleEnd - at.audibleStart;
  final trimmedLead = at.audibleStart - at.spanExportStart;
  return ScheduledAudioClip(
    filePath: span.clip.filePath,
    startFrame: at.audibleStart,
    endFrameExclusive: at.audibleEnd,
    // The clip's offset trim seeks past the skipped file head on top of
    // any range clipping.
    offsetFrames: trimmedLead + span.clip.offsetFrames,
    gain: layerGain * span.clip.gain,
    fadeInFrames:
        (at.spanExportStart + span.clip.fadeInFrames - at.audibleStart).clamp(
          0,
          audibleFrames,
        ),
    fadeOutFrames: span.clip.fadeOutFrames.clamp(0, audibleFrames),
    pan: layerPan,
    fadeCurve: span.clip.fadeCurve,
    volumeKeys: trimmedLead == 0
        ? span.clip.volumeKeys
        : [
            for (final key in span.clip.volumeKeys)
              AudioVolumeKey(frame: key.frame - trimmedLead, gain: key.gain),
          ],
  );
}

/// Where one span lands in the exported timeline: where the span begins
/// and the window it is trimmed into.
typedef _ExportWindow = ({
  int spanExportStart,
  int audibleStart,
  int audibleEnd,
});

/// One exported block: the frames of one cut, in plan order.
typedef _ExportBlock = ({int start, int end, int firstFrameIndex, Cut cut});

/// The block starting at [blockStart]: every following task that is still
/// the same cut belongs to it.
_ExportBlock _blockAt(int blockStart, List<ExportFrameTask> plan) {
  final cut = plan[blockStart].cut;
  var blockEnd = blockStart;
  while (blockEnd < plan.length && plan[blockEnd].cut.id == cut.id) {
    blockEnd += 1;
  }
  return (
    start: blockStart,
    end: blockEnd,
    firstFrameIndex: plan[blockStart].frameIndex,
    cut: cut,
  );
}

/// Legacy path: cut-owned SE layers (test fixtures; production cuts no
/// longer carry SE rows). Ends clamp at the cut's exported block.
Iterable<ScheduledAudioClip> _cutOwnedSpans(_ExportBlock block) sync* {
  for (final layer in block.cut.layers) {
    if (layer.kind != LayerKind.se || layer.muted) {
      continue;
    }
    for (final span in seAudioSpans(layer)) {
      final offsetFrames =
          block.start + (span.startFrame - block.firstFrameIndex);
      if (offsetFrames >= block.end) {
        continue;
      }
      final clip = _trimmedExportClip(
        span,
        at: (
          spanExportStart: offsetFrames,
          audibleStart: math.max(block.start, offsetFrames),
          audibleEnd: math.min(block.end, offsetFrames + span.lengthFrames),
        ),
        layerGain: 1,
        layerPan: 0,
      );
      if (clip != null) {
        yield clip;
      }
    }
  }
}

/// Whether the block ENDING at [endIndex] runs straight on into the one
/// starting there, on the TRACK axis.
///
/// Contiguous = the next block's first exported frame sits exactly where
/// the previous cut ended on the track: back-to-back cuts, or a leading
/// gap the plan exports as black frames (the next task's frameIndex is
/// then the negative gap index, offsetting its cut's track start back to
/// the gap's first frame). A gap the plan SKIPS breaks the run — the
/// exported timeline collapsed it.
///
/// 🚨SYMMETRIC on purpose: BOTH blocks must be on [track] and both must
/// have a place on it. That is what lets the same question answer "does
/// this run continue?" looking forward and "did a run already reach me?"
/// looking back — one predicate, asked at two indices, rather than two
/// spellings of contiguity that could disagree.
bool _blocksContiguous(
  int endIndex, {
  required List<ExportFrameTask> plan,
  required Track track,
  required TrackAxis axis,
}) {
  if (endIndex <= 0 || endIndex >= plan.length) {
    return false;
  }
  final prevTask = plan[endIndex - 1];
  final nextTask = plan[endIndex];
  final prevTrackStart = axis.startByCutId[prevTask.cut.id];
  final nextTrackStart = axis.startByCutId[nextTask.cut.id];
  return prevTrackStart != null &&
      nextTrackStart != null &&
      identical(axis.trackByCutId[prevTask.cut.id], track) &&
      identical(axis.trackByCutId[nextTask.cut.id], track) &&
      prevTask.frameIndex == prevTask.cut.duration - 1 &&
      nextTrackStart + nextTask.frameIndex ==
          prevTrackStart + prevTask.cut.duration;
}

/// Where the contiguous run starting at [block] ends in the plan: block
/// after block, for as long as each runs straight on into the next.
int _runEndFrom(
  _ExportBlock block, {
  required List<ExportFrameTask> plan,
  required Track track,
  required TrackAxis axis,
}) {
  var runEnd = block.end;
  while (_blocksContiguous(runEnd, plan: plan, track: track, axis: axis)) {
    final nextCutId = plan[runEnd].cut.id;
    while (runEnd < plan.length && plan[runEnd].cut.id == nextCutId) {
      runEnd += 1;
    }
  }
  return runEnd;
}

/// Track-owned SE rows: spans sit on the track's global axis and may
/// cross cut boundaries. Each span is laid ONCE — at the block where it
/// starts, or a run-start block it spills into — and runs to its true
/// end, clamped where the exported sequence stops being contiguous with
/// the track (a frame-subrange boundary, a skipped cut).
Iterable<ScheduledAudioClip> _trackOwnedSpans(
  _ExportBlock block, {
  required List<ExportFrameTask> plan,
  required TrackAxis axis,
}) sync* {
  final track = axis.trackByCutId[block.cut.id];
  final cutTrackStart = axis.startByCutId[block.cut.id];
  if (track == null || cutTrackStart == null) {
    return;
  }
  final windowTrackStart = cutTrackStart + block.firstFrameIndex;
  final runEnd = _runEndFrom(block, plan: plan, track: track, axis: axis);
  // A run STARTS here unless the block before it ran straight into this
  // one — the same contiguity, asked backwards. ⛔No `block.start == 0`
  // case: index zero has no block before it, which _blocksContiguous
  // already answers.
  final isRunStart = !_blocksContiguous(
    block.start,
    plan: plan,
    track: track,
    axis: axis,
  );

  for (final layer in track.seLayers) {
    if (layer.muted) {
      continue;
    }
    for (final span in seAudioSpans(layer)) {
      final exportPos = block.start + (span.startFrame - windowTrackStart);
      final startsHere = exportPos >= block.start && exportPos < block.end;
      final spillsIn =
          isRunStart &&
          exportPos < block.start &&
          exportPos + span.lengthFrames > block.start;
      if (!startsHere && !spillsIn) {
        continue;
      }
      final clip = _trimmedExportClip(
        span,
        at: (
          spanExportStart: exportPos,
          audibleStart: math.max(block.start, exportPos),
          audibleEnd: math.min(runEnd, exportPos + span.lengthFrames),
        ),
        layerGain: layer.audioGain,
        layerPan: layer.audioPan,
      );
      if (clip != null) {
        yield clip;
      }
    }
  }
}

List<ScheduledAudioClip> buildExportAudioPlan({
  required List<ExportFrameTask> plan,
  Project? project,
}) {
  // THE walk, so the export axis and the playback axis cannot drift.
  final axis = trackAxisOf(project);
  final clips = <ScheduledAudioClip>[];
  var blockStart = 0;
  while (blockStart < plan.length) {
    final block = _blockAt(blockStart, plan);
    clips.addAll(_cutOwnedSpans(block));
    clips.addAll(_trackOwnedSpans(block, plan: plan, axis: axis));
    blockStart = block.end;
  }
  return clips;
}

/// Instance-only plan: each unique authored frame (cel) of every visible
/// drawing layer, once, in authored order — regardless of how often (or
/// whether) the timeline exposes it. Camera and hidden layers are skipped.
/// A frame-subrange does not apply to cels, so [ExportRange.frameRange]
/// covers the active cut whole.
List<ExportCelTask> buildExportCelPlan({
  required Project project,
  required CutId activeCutId,
  required ExportRange range,
  ExportCelNaming naming = const ExportCelNaming(),
  bool onTimesheetOnly = false,
  String fileExtension = 'png',
}) {
  final cuts = resolveExportCuts(
    project: project,
    activeCutId: activeCutId,
    range: range,
  );

  final plan = <ExportCelTask>[];
  final usedNames = <String>{};
  for (final cut in cuts) {
    for (final layer in cut.layers) {
      if (!layer.kind.paintsArtwork || !layer.isVisible) {
        continue;
      }
      // Cel-export scope: the timesheet toggle on layer labels marks which
      // layers belong to the sheet output.
      if (onTimesheetOnly && !layer.onTimesheet) {
        continue;
      }
      for (var index = 0; index < layer.frames.length; index += 1) {
        final frame = layer.frames[index];
        final base = _celFileBase(
          projectName: project.name,
          cut: cut,
          layer: layer,
          frame: frame,
          celPosition: index + 1,
          naming: naming,
        );
        final folder = [
          if (naming.cutFolder) sanitizeExportFileComponent(cut.name),
          if (naming.layerFolder) sanitizeExportFileComponent(layer.name),
        ].join('/');
        final prefix = folder.isEmpty ? '' : '$folder/';
        var fileName = '$prefix$base.$fileExtension';
        var bump = 2;
        while (!usedNames.add(fileName)) {
          fileName = '$prefix${base}_$bump.$fileExtension';
          bump += 1;
        }
        plan.add(
          ExportCelTask(
            cut: cut,
            layer: layer,
            frame: frame,
            fileName: fileName,
          ),
        );
      }
    }
  }
  return plan;
}

String _celFileBase({
  required String projectName,
  required Cut cut,
  required Layer layer,
  required Frame frame,
  required int celPosition,
  required ExportCelNaming naming,
}) {
  final rawFrameName = (frame.name ?? '').trim();
  final frameName = padFrameNumber(
    rawFrameName.isEmpty ? '$celPosition' : rawFrameName,
    naming.frameDigits,
  );

  final prefixes = [
    if (naming.includeProjectName) sanitizeExportFileComponent(projectName),
    if (naming.includeCutName) sanitizeExportFileComponent(cut.name),
  ];
  final buffer = StringBuffer();
  if (prefixes.isNotEmpty) {
    buffer
      ..writeAll(prefixes, '_')
      ..write('_');
  }
  if (naming.includeLayerName) {
    buffer.write(sanitizeExportFileComponent(layer.name));
  }
  buffer.write(sanitizeExportFileComponent(frameName));
  final suffix = naming.suffix.trim();
  if (suffix.isNotEmpty) {
    buffer.write(sanitizeExportFileComponent(suffix));
  }
  return buffer.toString();
}

/// Makes a cut/layer name safe as a file-name component: characters Windows
/// forbids become '_', trailing dots/spaces are trimmed, and an empty result
/// falls back to 'untitled'.
String sanitizeExportFileComponent(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  return sanitized.isEmpty ? 'untitled' : sanitized;
}
