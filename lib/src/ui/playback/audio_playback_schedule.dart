/// The playback audio schedule, shared by BOTH output paths (audio program
/// wiring).
///
/// The mapping from track-global SE spans onto a run's frame axis exists in
/// exactly ONE place: here. The platform-player fallback consumes
/// [ScheduledAudioClip] in frames; the native device transport converts the
/// same schedule to samples with [audioMixScheduleFrom]. Two consumers, one
/// scheduler — the paths can disagree about output devices, never about
/// WHAT plays WHEN.
library;

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../../models/se_sound.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_mixer_reference.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../audio/audio_conform_store.dart';
import '../audio/sound_cannot_play.dart';

/// One point of a scheduled sound's volume line: at [frame] — counted from
/// the entry's own start — the line passes [gain].
/// Linear between points and held past the ends, as the mixer's envelope
/// is; an empty line is unity.
typedef ScheduledVolumePoint = ({int frame, double gain});

/// A clip laid out on a run's frame axis, end clamped at the run's end.
class ScheduledAudioClip {
  const ScheduledAudioClip({
    required this.filePath,
    required this.startFrame,
    required this.endFrameExclusive,
    this.offsetFrames = 0,
    this.gain = 1.0,
    this.pan = 0.0,
    this.volume = const [],
  });

  /// ONE SPAN, LAID ON AN OUTPUT AXIS — the mapping the playback walk and
  /// the export walk both need, so neither can drift from the other (the
  /// export plan's own header says the mix must be "the SAME schedule
  /// shape playback consumes", which was a promise kept by hand twice).
  ///
  /// The ROW's sound ([SeSound]) is laid in HERE, so no consumer ever
  /// re-consults the layer: a keyed volume becomes the entry's [volume]
  /// line, read off the row at the frames the entry sounds — [clippedLead]
  /// frames into the span — and its total multiplies into the [gain].
  factory ScheduledAudioClip.ofSpan(
    SeAudioSpan span, {
    required int startFrame,
    required int endFrameExclusive,
    required int clippedLead,
    required SeSound sound,
  }) {
    final first = span.startFrame + clippedLead;
    return ScheduledAudioClip(
      filePath: span.clip.filePath,
      startFrame: startFrame,
      endFrameExclusive: endFrameExclusive,
      offsetFrames: clippedLead + span.clip.offsetFrames,
      gain: span.clip.gain * sound.totalVolume,
      pan: sound.pan,
      volume: sound.isKeyed
          ? _volumeLine(
              sound,
              from: first,
              frames: endFrameExclusive - startFrame,
            )
          : const [],
    );
  }

  final String filePath;
  final int startFrame;
  final int endFrameExclusive;

  /// Frames skipped into the file where the block starts (the clip's trim).
  final int offsetFrames;

  /// The clip's own gain (`AudioClip.gain`) times the row's total; the
  /// row's keyed volume is [volume].
  final double gain;

  /// The row's pan, -1..1 equal-power; applied by the device mixer path
  /// only.
  final double pan;

  /// The row's keyed volume along this entry ([ScheduledVolumePoint]) —
  /// empty while the row's volume does not change.
  final List<ScheduledVolumePoint> volume;

  @override
  bool operator ==(Object other) =>
      other is ScheduledAudioClip &&
      other.filePath == filePath &&
      other.startFrame == startFrame &&
      other.endFrameExclusive == endFrameExclusive &&
      other.offsetFrames == offsetFrames &&
      other.gain == gain &&
      other.pan == pan &&
      listEquals(other.volume, volume);

  @override
  int get hashCode => Object.hash(
    filePath,
    startFrame,
    endFrameExclusive,
    offsetFrames,
    gain,
    pan,
    Object.hashAll(volume),
  );

  @override
  String toString() =>
      'ScheduledAudioClip(filePath: $filePath, startFrame: $startFrame, '
      'endFrameExclusive: $endFrameExclusive, offsetFrames: $offsetFrames, '
      'gain: $gain, pan: $pan, volume: $volume)';
}

/// [sound]'s volume over the [frames] an entry sounds from the row's frame
/// [from], as the entry's line: the value at every frame from its first to
/// its end — a line between frames, as the mixer draws it — less every
/// point that stands on the line its neighbours draw, so a keyed ramp is
/// its two ends.
///
/// ⚠️Every frame, not every key: a key may ease, and the mixer's line is
/// straight, so a curve between two keys is met at each frame it passes.
List<ScheduledVolumePoint> _volumeLine(
  SeSound sound, {
  required int from,
  required int frames,
}) {
  final points = [
    for (var at = 0; at <= frames; at += 1)
      (frame: at, gain: sound.volumeAt((from + at) * 1.0)),
  ];
  final line = <ScheduledVolumePoint>[];
  for (var index = 0; index < points.length; index += 1) {
    final point = points[index];
    if (line.isNotEmpty && index + 1 < points.length) {
      final before = line.last;
      final after = points[index + 1];
      final share =
          (point.frame - before.frame) / (after.frame - before.frame);
      final onTheLine = before.gain + (after.gain - before.gain) * share;
      if ((point.gain - onTheLine).abs() < 1e-9) {
        continue;
      }
    }
    line.add(point);
  }
  return line;
}

/// The frames a file covers at [rate], read off [durationSecondsFor] —
/// null while its length is not known yet.
///
/// Rounding UP is deliberate — a file ending mid-frame still has audio
/// in that frame, and truncating would clip real sound. What must not
/// happen is rounding up on float noise alone: a 2.000s file at 24fps
/// computes as 48.000000000000004, and a bare `.ceil()` would hand it a
/// 49th frame of silence. [ProjectFrameRate.framesCoveringSeconds]
/// treats a value within a millionth of a frame of whole as whole.
int? Function(String filePath) _fileFramesAt(
  ProjectFrameRate rate,
  double? Function(String filePath) durationSecondsFor,
) => (filePath) {
  final seconds = durationSecondsFor(filePath);
  return seconds == null ? null : rate.framesCoveringSeconds(seconds);
};

/// Clamps [endFrameExclusive] to the file's own audible length: its
/// [fileFrames], the first [offsetFrames] of them skipped. A file whose
/// length is not known yet is not clamped.
int _clampToFileLength({
  required int startFrame,
  required int endFrameExclusive,
  required int offsetFrames,
  required int? fileFrames,
}) => fileFrames == null
    ? endFrameExclusive
    : math.min(endFrameExclusive, startFrame + fileFrames - offsetFrames);

/// Lays the project's track-owned SE spans onto a run's frame axis: the
/// rows of [window]'s track, as much of each span as falls inside it.
///
/// ONE window, read straight off the track ([PlaybackWindow]) — the sound
/// does not ask the run's cuts where it is. A span that began before the
/// window plays from where it has got to (the file offset bumped by the
/// clipped lead); every span runs to its true end or the window's,
/// whichever comes first.
///
/// Clip lengths come from the waveform peaks ([durationSecondsFor]); clips
/// whose peaks are not extracted yet fall back to the window's end (a
/// shorter file simply completes early — stopping a completed player is a
/// no-op, and the mixer plays silence past a source's last sample).
List<ScheduledAudioClip> buildAudioPlaybackSchedule({
  required PlaybackWindow? window,
  required Project? project,
  required ProjectFrameRate rate,
  required double? Function(String filePath) durationSecondsFor,
  Set<LayerId>? soloedLayerIds,
  Set<LayerId>? mutedLayerIds,
  List<ScheduledAudioClip>? extraClips,
}) {
  // Solo is a MONITORING state (AUDIO-PRO R1): a non-empty set narrows
  // the audible layers to it. Export never passes one — soloing while
  // rendering would bake a monitoring choice into the file.
  final soloed = soloedLayerIds ?? const <LayerId>{};
  // A transient monitoring mute on top of the layers' own flags (REC1-B:
  // the armed lane yields to the microphone while a take rolls). Export
  // never passes one either — same reasoning as solo.
  final muted = mutedLayerIds ?? const <LayerId>{};
  final schedule = <ScheduledAudioClip>[];

  // SE rows are TRACK-owned and live on each track's GLOBAL frame axis;
  // a cut merely shows a window onto them. Cut-owned SE is what the .tvpp
  // and .clip doors build before they lift it onto the track, and the shape
  // of files refused by their format number, so no loaded project can
  // carry one — and scheduling from cut layers would
  // clamp sounds at cut boundaries, which is exactly the restart-per-cut
  // behaviour the global model exists to remove.
  final track = window == null
      ? null
      : project?.tracks
            .where((track) => track.id == window.trackId)
            .firstOrNull;
  if (window != null && track != null) {
    final fileFramesOf = _fileFramesAt(rate, durationSecondsFor);
    for (final layer in track.seLayers) {
      final audible =
          !layer.muted &&
          !muted.contains(layer.id) &&
          (soloed.isEmpty || soloed.contains(layer.id));
      if (!audible) {
        continue;
      }
      for (final span in seAudioSpans(layer)) {
        final clip = _spanInWindow(
          span,
          layer: layer,
          window: window,
          fileFramesOf: fileFramesOf,
        );
        if (clip != null) {
          schedule.add(clip);
        }
      }
    }
  }
  // Injected cues (REC1-E): already on the run's axis, appended verbatim —
  // the ADR beeps ride the same mixer as every other sound, which is what
  // routes them to the CHOSEN output device.
  if (extraClips != null) {
    schedule.addAll(extraClips);
  }
  return schedule;
}

/// [span] on [window]'s axis, or null when none of it falls inside.
ScheduledAudioClip? _spanInWindow(
  SeAudioSpan span, {
  required Layer layer,
  required PlaybackWindow window,
  required int? Function(String filePath) fileFramesOf,
}) {
  final windowEnd = window.trackStart + window.frames;
  if (span.startFrame >= windowEnd ||
      span.startFrame + span.lengthFrames <= window.trackStart) {
    return null;
  }
  final clippedLead = math.max(0, window.trackStart - span.startFrame);
  final startFrame = span.startFrame + clippedLead - window.trackStart;
  final offsetFrames = span.clip.offsetFrames + clippedLead;
  final endFrameExclusive = _clampToFileLength(
    startFrame: startFrame,
    endFrameExclusive: math.min(
      window.frames,
      startFrame + span.lengthFrames - clippedLead,
    ),
    offsetFrames: offsetFrames,
    fileFrames: fileFramesOf(span.clip.filePath),
  );
  if (endFrameExclusive <= startFrame) {
    return null;
  }
  return ScheduledAudioClip.ofSpan(
    span,
    startFrame: startFrame,
    endFrameExclusive: endFrameExclusive,
    clippedLead: clippedLead,
    sound: layer.seSound,
  );
}

/// The frame schedule converted to mixer samples: [clips] index into
/// [sourcePaths] via `sourceIndex` (one entry per DISTINCT file, in first-
/// appearance order — the caller loads each path's PCM once and uploads it
/// once, however many clips share it).
class AudioMixSchedule {
  const AudioMixSchedule({required this.clips, required this.sourcePaths});

  final List<AudioMixClip> clips;
  final List<String> sourcePaths;
}

/// Converts [schedule] to sample positions at [sampleRate].
///
/// Every conversion uses [ProjectFrameRate.frameToSample] — the rounding-UP
/// half of the round-trip pair — so a clip scheduled at frame N starts on
/// the first sample BELONGING to frame N, and the clock's `sampleToFrame`
/// reads back the frame that was scheduled. All 64-bit integer arithmetic;
/// nothing here drifts at any timeline length.
AudioMixSchedule audioMixScheduleFrom({
  required List<ScheduledAudioClip> schedule,
  required ProjectFrameRate rate,
  required int sampleRate,
}) {
  final sourceIndexByPath = <String, int>{};
  final sourcePaths = <String>[];
  final clips = <AudioMixClip>[];
  for (final clip in schedule) {
    final sourceIndex = sourceIndexByPath.putIfAbsent(clip.filePath, () {
      sourcePaths.add(clip.filePath);
      return sourcePaths.length - 1;
    });
    final pan = equalPowerPanGains(clip.pan);
    clips.add(
      AudioMixClip(
        sourceIndex: sourceIndex,
        startSample: rate.frameToSample(clip.startFrame, sampleRate),
        endSample: rate.frameToSample(clip.endFrameExclusive, sampleRate),
        sourceOffset: rate.frameToSample(clip.offsetFrames, sampleRate),
        gain: clip.gain,
        panLeft: pan.left,
        panRight: pan.right,
        envelope: [
          for (final point in clip.volume)
            AudioEnvelopePoint(
              sample: rate.frameToSample(point.frame, sampleRate),
              gain: point.gain,
            ),
        ],
      ),
    );
  }
  return AudioMixSchedule(clips: clips, sourcePaths: sourcePaths);
}

/// Where the disk window sits and how far it reaches, in device samples.
typedef _StreamWindow = ({int centerSample, int backSamples, int aheadSamples});

/// The sources that are already conformed and resident, in upload order,
/// with the mix's source index mapped onto that order — and every source,
/// resident or streamed, that cannot be played and why, which the upload
/// leaves out ([WindowedUploadPlan.cannotPlay]). ⛔Asked here once per
/// source: the clip loop that windows the streams reads this answer, it
/// does not ask again.
///
/// Null when one of them is still landing — the caller uploads nothing
/// and any old schedule keeps playing. ⛔Every lookup runs even after a
/// miss: each one KICKS its conform or rate conversion, and the next
/// attempt wants them all landed.
({
  List<AudioMixSource> sources,
  Map<int, int> byMixIndex,
  Map<String, SoundCannotPlay> cannotPlay,
})?
_residentSources({
  required AudioMixSchedule mix,
  required AudioConformStore conformStore,
  required int deviceRate,
}) {
  final sources = <AudioMixSource>[];
  final byMixIndex = <int, int>{};
  final cannotPlay = <String, SoundCannotPlay>{};
  var landing = false;
  for (var index = 0; index < mix.sourcePaths.length; index += 1) {
    final path = mix.sourcePaths[index];
    final why = conformStore.cannotPlayAt(path, deviceRate);
    if (why != null) {
      cannotPlay[path] = why;
      continue;
    }
    if (conformStore.isStreaming(path)) {
      continue; // windowed per clip by the caller
    }
    final samples = conformStore.samplesAtRate(path, deviceRate);
    final entry = conformStore.resultFor(path);
    if (samples != null && entry != null && entry.isUsable) {
      byMixIndex[index] = sources.length;
      sources.add(AudioMixSource(samples: samples, channels: entry.channels));
    } else {
      landing = true;
    }
  }
  // ⛔Do NOT delete this as redundant because the caller refuses again on
  // a missing map entry: this returns BEFORE the clip loop, so a tick
  // that cannot upload anyway does not pay for a streamed clip's disk
  // read — and while a conform is landing, every tick takes this path.
  if (landing) {
    return null;
  }
  return (sources: sources, byMixIndex: byMixIndex, cannotPlay: cannotPlay);
}

/// One streamed clip's window: [count] samples per channel from [start] of
/// [reader]'s conform — what an upload reads for that clip, here or on a
/// worker.
typedef StreamWindowRead = ({
  ConformPcmStreamReader reader,
  int start,
  int count,
});

/// The window a streamed source [clip] needs right now: trailing behind
/// the playhead and leading in front of it, clamped into the clip's own
/// span (and, by the reader, into the file).
StreamWindowRead _streamWindowRead(
  AudioMixClip clip, {
  required ConformPcmStreamReader reader,
  required _StreamWindow at,
}) {
  final clipLength = clip.endSample - clip.startSample;
  final positionInClip = (at.centerSample - clip.startSample).clamp(
    0,
    clipLength,
  );
  final sourceAt = clip.sourceOffset + positionInClip;
  final windowStart = math.max(clip.sourceOffset, sourceAt - at.backSamples);
  final windowEnd = math.min(
    clip.sourceOffset + clipLength,
    sourceAt + at.aheadSamples,
  );
  return (reader: reader, start: windowStart, count: windowEnd - windowStart);
}

/// [read]'s window, read here — into the list [place] makes for it when it
/// makes one ([ConformPcmStreamReader.readWindow]).
AudioMixSource streamWindowReadHere(
  StreamWindowRead read, {
  Float32List? Function(int floats)? place,
}) {
  final window = read.reader.readWindow(read.start, read.count, place: place);
  return AudioMixSource(
    samples: window.samples,
    channels: read.reader.channels,
    sourceStart: window.startSample,
  );
}

/// A device upload: the clips, pointed at their sources, and whether any of
/// those streams ([AudioStreamingWindow.hasStreaming]).
typedef WindowedUpload = ({
  List<AudioMixClip> clips,
  List<AudioMixSource> sources,
  bool hasStreaming,
});

/// The device upload for a mix before its streamed clips' windows are read
/// ([planWindowedMixUpload]): the clips, pointed at their sources — the
/// [resident] ones first, then one window for each of [reads], in order.
///
/// 🚨PLANNED APART FROM THE READING, so an advance can read on a worker
/// (streaming-advance-reads-on-the-ui-thread, 10-15): what to read is
/// decided on the thread that holds the store, and only the reading goes
/// elsewhere.
final class WindowedUploadPlan {
  const WindowedUploadPlan._({
    required this.clips,
    required this.resident,
    required this.reads,
    required this.cannotPlay,
  });

  final List<AudioMixClip> clips;
  final List<AudioMixSource> resident;
  final List<StreamWindowRead> reads;

  /// The mix's sources whose clips this upload leaves out, and why
  /// ([AudioConformStore.cannotPlayAt]): nothing is making them ready to
  /// play, so the rest plays without them.
  ///
  /// 🗣️유저 2026-10-16 (se-fallback-opens-the-original-path-Q2): 「대체
  /// 재생을 안 쓰고」 · 「재생못하거나 하는 상황에선 제대로 메시지라던가 뭔가
  /// 표시」 (playback-waits-for-its-sound ③). ↩️One such source held the
  /// whole upload back, and the platform players carried the run.
  final Map<String, SoundCannotPlay> cannotPlay;

  bool get hasStreaming => reads.isNotEmpty;

  /// The upload, its streamed clips playing [windows] — [reads], read.
  WindowedUpload withWindows(List<AudioMixSource> windows) {
    assert(windows.length == reads.length, 'one window for each read');
    return (
      clips: clips,
      sources: [...resident, ...windows],
      hasStreaming: hasStreaming,
    );
  }

  /// The upload with every window read here ([streamWindowReadHere]) —
  /// into what [place] makes for each, when it makes one.
  WindowedUpload readHere({Float32List? Function(int floats)? place}) =>
      withWindows([
        for (final read in reads) streamWindowReadHere(read, place: place),
      ]);
}

/// Plans the device upload for [mix] — resident PCM for ordinary clips, a
/// disk WINDOW around [centerSample] for streaming ones (AUDIO-PRO R6).
/// One plan for the transport AND the scrubber, so streamed playback and
/// streamed scrubbing can never disagree.
///
/// Each streaming clip gets a PRIVATE source: two placements of one long
/// file read different parts of it, and a shared window would have to
/// span the gap between them. The window trails [backSeconds] (loop wraps
/// and small seeks land just behind the playhead) and leads
/// [aheadSeconds] (the advance must upload long before the mix reads past
/// the edge), clamped into the clip's own span and, by the reader, into
/// the file.
///
/// Null — so the caller uploads NOTHING and any old schedule keeps
/// playing — while a resident source is landing (each lookup kicks its
/// conform or rate conversion). A source that cannot be played is left out
/// instead ([WindowedUploadPlan.cannotPlay]), by the one answer the screen
/// reads too ([AudioConformStore.cannotPlayAt]) — a stream on a device off
/// the project rate among them.
WindowedUploadPlan? planWindowedMixUpload({
  required AudioMixSchedule mix,
  required AudioConformStore conformStore,
  required int deviceRate,
  required int centerSample,
  // ⛔No defaults: the geometry has ONE home ([AudioStreamingWindow]) and
  // a default here was a second spelling of it.
  required int backSeconds,
  required int aheadSeconds,
}) {
  final resident = _residentSources(
    mix: mix,
    conformStore: conformStore,
    deviceRate: deviceRate,
  );
  if (resident == null) {
    return null;
  }

  final cannotPlay = resident.cannotPlay;
  final clips = <AudioMixClip>[];
  final reads = <StreamWindowRead>[];
  final at = (
    centerSample: centerSample,
    backSamples: backSeconds * deviceRate,
    aheadSamples: aheadSeconds * deviceRate,
  );
  for (final clip in mix.clips) {
    final path = mix.sourcePaths[clip.sourceIndex];
    if (!conformStore.isStreaming(path)) {
      final mapped = resident.byMixIndex[clip.sourceIndex];
      if (mapped != null) {
        clips.add(clip.pointedAt(mapped));
      }
      continue;
    }
    if (cannotPlay.containsKey(path)) {
      continue;
    }
    final reader = conformStore.streamReaderFor(path)!;
    clips.add(clip.pointedAt(resident.sources.length + reads.length));
    reads.add(_streamWindowRead(clip, reader: reader, at: at));
  }
  return WindowedUploadPlan._(
    clips: clips,
    resident: resident.sources,
    reads: reads,
    cannotPlay: cannotPlay,
  );
}
