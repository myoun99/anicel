/// The playback audio schedule, shared by BOTH output paths (audio program
/// wiring).
///
/// The mapping from track-global SE spans onto the playlist frame axis is
/// subtle — leading gaps, contiguous runs, spans spilling into a run start —
/// and it exists in exactly ONE place: here. The platform-player fallback
/// consumes [ScheduledAudioClip] in frames; the native device transport
/// converts the same schedule to samples with [audioMixScheduleFrom]. Two
/// consumers, one scheduler — the paths can disagree about output devices,
/// never about WHAT plays WHEN.
library;

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_mixer_reference.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../audio/audio_conform_store.dart';
import '../../models/storyboard_timeline_layout.dart';

/// A clip laid out on the playlist-global frame axis, end clamped at the
/// contiguous run's boundary.
class ScheduledAudioClip {
  const ScheduledAudioClip({
    required this.filePath,
    required this.startFrame,
    required this.endFrameExclusive,
    this.offsetFrames = 0,
    this.gain = 1.0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
    this.pan = 0.0,
    this.fadeCurve = AudioFadeCurve.linear,
    this.volumeKeys = const [],
  });

  /// ONE SPAN, LAID ON AN OUTPUT AXIS — the mapping the playback walk and
  /// the export walk both need, so neither can drift from the other (the
  /// export plan's own header says the mix must be "the SAME schedule
  /// shape playback consumes", which was a promise kept by hand twice).
  ///
  /// Envelope keys anchor to the SPAN start; a clipped lead shifts them
  /// (possibly negative — before the window).
  ///
  /// The layer fader multiplies in HERE (one gain per entry) so no
  /// consumer ever re-consults the layer.
  ///
  /// The fades are NUMBERS the caller computes: playback passes the
  /// clip's own, and the export bakes its anchoring into them. That
  /// difference is a value, not a mode.
  factory ScheduledAudioClip.ofSpan(
    SeAudioSpan span, {
    required int startFrame,
    required int endFrameExclusive,
    required int clippedLead,
    required double layerGain,
    required double layerPan,
    required int fadeInFrames,
    required int fadeOutFrames,
  }) => ScheduledAudioClip(
    filePath: span.clip.filePath,
    startFrame: startFrame,
    endFrameExclusive: endFrameExclusive,
    offsetFrames: clippedLead + span.clip.offsetFrames,
    gain: layerGain * span.clip.gain,
    fadeInFrames: fadeInFrames,
    fadeOutFrames: fadeOutFrames,
    pan: layerPan,
    fadeCurve: span.clip.fadeCurve,
    volumeKeys: clippedLead == 0
        ? span.clip.volumeKeys
        : [
            for (final key in span.clip.volumeKeys)
              AudioVolumeKey(frame: key.frame - clippedLead, gain: key.gain),
          ],
  );

  final String filePath;
  final int startFrame;
  final int endFrameExclusive;

  /// Frames skipped into the file where the block starts (the clip's trim).
  final int offsetFrames;

  /// The clip's volume envelope (see [AudioClip]); fades anchor to this
  /// schedule entry's own start/end. [gain] already carries the LAYER
  /// fader multiplied in (AUDIO-PRO R1) — consumers never re-consult the
  /// layer.
  final double gain;
  final int fadeInFrames;
  final int fadeOutFrames;

  /// The layer's pan, -1..1 equal-power (AUDIO-PRO R1); applied by the
  /// device mixer path only.
  final double pan;

  /// The shape both fades take.
  final AudioFadeCurve fadeCurve;

  /// The clip's volume envelope keys, frames RELATIVE TO THIS ENTRY's
  /// start (a trimmed entry shifts them, possibly negative — the ramp's
  /// early part simply sits before the audible window).
  final List<AudioVolumeKey> volumeKeys;

  @override
  bool operator ==(Object other) =>
      other is ScheduledAudioClip &&
      other.filePath == filePath &&
      other.startFrame == startFrame &&
      other.endFrameExclusive == endFrameExclusive &&
      other.offsetFrames == offsetFrames &&
      other.gain == gain &&
      other.fadeInFrames == fadeInFrames &&
      other.fadeOutFrames == fadeOutFrames &&
      other.pan == pan &&
      other.fadeCurve == fadeCurve &&
      listEquals(other.volumeKeys, volumeKeys);

  @override
  int get hashCode => Object.hash(
    filePath,
    startFrame,
    endFrameExclusive,
    offsetFrames,
    gain,
    fadeInFrames,
    fadeOutFrames,
    pan,
    fadeCurve,
    Object.hashAll(volumeKeys),
  );

  @override
  String toString() =>
      'ScheduledAudioClip(filePath: $filePath, startFrame: $startFrame, '
      'endFrameExclusive: $endFrameExclusive, offsetFrames: $offsetFrames, '
      'gain: $gain, fadeInFrames: $fadeInFrames, '
      'fadeOutFrames: $fadeOutFrames, pan: $pan, '
      'fadeCurve: ${fadeCurve.name}, volumeKeys: $volumeKeys)';
}

/// Clamps [endFrameExclusive] to the file's own audible length.
///
/// Rounding UP is deliberate — a file ending mid-frame still has audio
/// in that frame, and truncating would clip real sound. What must not
/// happen is rounding up on float noise alone: a 2.000s file at 24fps
/// computes as 48.000000000000004, and a bare `.ceil()` would hand it a
/// 49th frame of silence. [ProjectFrameRate.framesCoveringSeconds]
/// treats a value within a millionth of a frame of whole as whole.
int _clampToFileLength({
  required int startFrame,
  required int endFrameExclusive,
  required String filePath,
  required int offsetFrames,
  required ProjectFrameRate rate,
  required double? Function(String filePath) durationSecondsFor,
}) {
  final seconds = durationSecondsFor(filePath);
  if (seconds == null) {
    return endFrameExclusive;
  }
  return math.min(
    endFrameExclusive,
    startFrame + rate.framesCoveringSeconds(seconds) - offsetFrames,
  );
}

/// One entry's window onto its track: the track frames it shows, how far
/// back over a PLAYED leading gap that reaches, and whether it starts a
/// contiguous run.
typedef _EntryWindow = ({int start, int end, int coveredLead, bool isRunStart});

/// One call to [buildAudioPlaybackSchedule]: the timeline being played,
/// the monitoring state it is heard through, and the ruler its ends are
/// measured against. Every entry and every span consults all three
/// unchanged, so they are held once rather than threaded through.
class _ScheduleRun {
  _ScheduleRun({
    required this.playlist,
    required Project project,
    required this.muted,
    required this.soloed,
    required this.rate,
    required this.durationSecondsFor,
  }) : axis = trackAxisOf(project);

  final List<StoryboardTimelineLayoutEntry> playlist;
  final TrackAxis axis;
  final Set<LayerId> muted;
  final Set<LayerId> soloed;
  final ProjectFrameRate rate;
  final double? Function(String filePath) durationSecondsFor;

  /// Everything playlist entry [entryIndex] contributes: for each audible
  /// SE row of its track, every span this entry is the one to show.
  List<ScheduledAudioClip> entrySchedule(int entryIndex) {
    final entry = playlist[entryIndex];
    final track = axis.trackByCutId[entry.cutId];
    if (track == null || axis.startByCutId[entry.cutId] == null) {
      return const [];
    }
    final window = _windowAt(entryIndex);
    final runEnd = _contiguousEndFrom(entryIndex);
    final scheduled = <ScheduledAudioClip>[];
    for (final layer in track.seLayers) {
      if (!_rowIsAudible(layer)) {
        continue;
      }
      for (final span in seAudioSpans(layer)) {
        final clip = _spanClip(
          span,
          layer: layer,
          at: (
            window: window,
            entryStartFrame: entry.startFrame,
            runEnd: runEnd,
          ),
        );
        if (clip != null) {
          scheduled.add(clip);
        }
      }
    }
    return scheduled;
  }

  /// Whether [layer] is heard at all: its own mute, the transient
  /// monitoring mute, and solo, which narrows to itself when anything is
  /// soloed.
  bool _rowIsAudible(Layer layer) =>
      !layer.muted &&
      !muted.contains(layer.id) &&
      (soloed.isEmpty || soloed.contains(layer.id));

  /// The playlist frame where the contiguous run starting at [entryIndex]
  /// ends. Contiguous = the playlist and track axes advance by the SAME
  /// amount between entries — back-to-back cuts, or a leading gap the
  /// playlist plays through as black. Sounds keep running through played
  /// gaps (audio lives on the global axis).
  int _contiguousEndFrom(int entryIndex) {
    var end = playlist[entryIndex].endFrame;
    var trackEnd =
        (axis.startByCutId[playlist[entryIndex].cutId] ?? 0) +
        playlist[entryIndex].duration;
    final track = axis.trackByCutId[playlist[entryIndex].cutId];
    for (var i = entryIndex + 1; i < playlist.length; i += 1) {
      final next = playlist[i];
      final nextTrackStart = axis.startByCutId[next.cutId];
      if (nextTrackStart == null ||
          next.startFrame < end ||
          next.startFrame - end != nextTrackStart - trackEnd ||
          !identical(axis.trackByCutId[next.cutId], track)) {
        break;
      }
      end = next.endFrame;
      trackEnd = nextTrackStart + next.duration;
    }
    return end;
  }

  /// Where playlist entry [entryIndex]'s window sits on its TRACK's axis,
  /// and whether it starts a contiguous run.
  ///
  /// A run-start entry also carries sounds spilling in from before the
  /// playlist window (offset-bumped); interior entries only emit spans
  /// STARTING in their window, so nothing is scheduled twice. The window
  /// extends back over the entry's PLAYED leading gap — playlist frames
  /// before the cut that map 1:1 onto the track frames before it — so a
  /// sound starting inside a gap is scheduled too.
  _EntryWindow _windowAt(int entryIndex) {
    final entry = playlist[entryIndex];
    final track = axis.trackByCutId[entry.cutId];
    final cutTrackStart = axis.startByCutId[entry.cutId]!;
    final previous = entryIndex == 0 ? null : playlist[entryIndex - 1];
    final previousTrackStart = previous == null
        ? null
        : axis.startByCutId[previous.cutId];
    final playlistLead = entry.startFrame - (previous?.endFrame ?? 0);
    final axesAligned = previous == null
        // The playlist head maps straight onto the track axis (all-cuts
        // playlists ARE the track axis; a rebased single-cut playlist has
        // no lead at all).
        ? playlistLead >= 0
        : previousTrackStart != null &&
              identical(axis.trackByCutId[previous.cutId], track) &&
              playlistLead >= 0 &&
              cutTrackStart - (previousTrackStart + previous.duration) ==
                  playlistLead;
    final coveredLead = axesAligned ? playlistLead : 0;
    return (
      start: cutTrackStart - coveredLead,
      end: cutTrackStart + entry.duration,
      coveredLead: coveredLead,
      isRunStart: previous == null || !axesAligned,
    );
  }

  /// The one span, mapped onto the playlist axis — or null when this
  /// entry is not the one that shows it.
  ///
  /// A span is emitted at the entry containing its START; a run START
  /// also takes a span spilling in from before its window, bumping the
  /// file offset by the clipped lead so the sound is heard from where it
  /// has got to rather than from the top.
  ScheduledAudioClip? _spanClip(
    SeAudioSpan span, {
    required Layer layer,
    required ({_EntryWindow window, int entryStartFrame, int runEnd}) at,
  }) {
    final window = at.window;
    final spanEnd = span.startFrame + span.lengthFrames;
    final startsHere =
        span.startFrame >= window.start && span.startFrame < window.end;
    final spillsIntoRunStart =
        window.isRunStart &&
        span.startFrame < window.start &&
        spanEnd > window.start;
    if (!startsHere && !spillsIntoRunStart) {
      return null;
    }
    final clippedLead = spillsIntoRunStart ? window.start - span.startFrame : 0;
    // at.entryStartFrame - coveredLead = the playlist frame the
    // (gap-extended) window begins at.
    final startFrame =
        at.entryStartFrame -
        window.coveredLead +
        (spillsIntoRunStart ? 0 : span.startFrame - window.start);
    final offsetFrames = span.clip.offsetFrames + clippedLead;
    final endFrameExclusive = _clampToFileLength(
      startFrame: startFrame,
      endFrameExclusive: math.min(
        at.runEnd,
        startFrame + span.lengthFrames - clippedLead,
      ),
      filePath: span.clip.filePath,
      offsetFrames: offsetFrames,
      rate: rate,
      durationSecondsFor: durationSecondsFor,
    );
    if (endFrameExclusive <= startFrame) {
      return null;
    }
    return ScheduledAudioClip.ofSpan(
      span,
      startFrame: startFrame,
      endFrameExclusive: endFrameExclusive,
      clippedLead: clippedLead,
      layerGain: layer.audioGain,
      layerPan: layer.audioPan,
      // Playback plays the clip's own ramps: nothing is trimmed off the
      // front here, so there is nothing to re-anchor.
      fadeInFrames: span.clip.fadeInFrames,
      fadeOutFrames: span.clip.fadeOutFrames,
    );
  }
}

/// Lays the project's track-owned SE spans onto [playlist]'s frame axis.
///
/// Clip lengths come from the waveform peaks ([durationSecondsFor]); clips
/// whose peaks are not extracted yet fall back to the run end (a shorter
/// file simply completes early — stopping a completed player is a no-op,
/// and the mixer plays silence past a source's last sample).
List<ScheduledAudioClip> buildAudioPlaybackSchedule({
  required List<StoryboardTimelineLayoutEntry> playlist,
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
  // a cut merely shows a window onto them. Cut-owned SE is a legacy file
  // shape that `Track.fromJson` lifts onto the track at load, so no
  // loaded project can carry one — and scheduling from cut layers would
  // clamp sounds at cut boundaries, which is exactly the restart-per-cut
  // behaviour the global model exists to remove.
  //
  // Spans map into the playlist axis once — at the entry containing the
  // start (or the first overlapping entry when the playlist begins
  // mid-sound, bumping the file offset by the clipped lead) — and run to
  // the span's true end, clamped only where the playlist run stops being
  // contiguous with the track.
  if (project != null && playlist.isNotEmpty) {
    final run = _ScheduleRun(
      playlist: playlist,
      project: project,
      muted: muted,
      soloed: soloed,
      rate: rate,
      durationSecondsFor: durationSecondsFor,
    );
    for (var i = 0; i < playlist.length; i += 1) {
      schedule.addAll(run.entrySchedule(i));
    }
  }
  // Injected cues (REC1-E): already on the playlist axis, appended
  // verbatim — the ADR beeps ride the same mixer as every other sound,
  // which is what routes them to the CHOSEN output device.
  if (extraClips != null) {
    schedule.addAll(extraClips);
  }
  return schedule;
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
  // Envelope keys may sit BEFORE the entry (a trimmed lead shifted them
  // negative); frameToSample clamps at zero, so negatives convert through
  // their magnitude.
  int signedFrameToSample(int frame) => frame >= 0
      ? rate.frameToSample(frame, sampleRate)
      : -rate.frameToSample(-frame, sampleRate);

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
        fadeInSamples: rate.frameToSample(clip.fadeInFrames, sampleRate),
        fadeOutSamples: rate.frameToSample(clip.fadeOutFrames, sampleRate),
        panLeft: pan.left,
        panRight: pan.right,
        fadeCurve: clip.fadeCurve.index,
        envelope: [
          for (final key in clip.volumeKeys)
            AudioEnvelopePoint(
              sample: signedFrameToSample(key.frame),
              gain: key.gain,
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
/// with the mix's source index mapped onto that order.
///
/// Null when one of them is still landing — the caller uploads nothing
/// and any old schedule keeps playing. ⛔Every lookup runs even after a
/// miss: each one KICKS its conform or rate conversion, and the next
/// attempt wants them all landed.
({List<AudioMixSource> sources, Map<int, int> byMixIndex, bool hasStreaming})?
_residentSources({
  required AudioMixSchedule mix,
  required AudioConformStore conformStore,
  required int deviceRate,
}) {
  final sources = <AudioMixSource>[];
  final byMixIndex = <int, int>{};
  var complete = true;
  var hasStreaming = false;
  for (var index = 0; index < mix.sourcePaths.length; index += 1) {
    final path = mix.sourcePaths[index];
    if (conformStore.isStreaming(path)) {
      hasStreaming = true;
      continue; // windowed per clip by the caller
    }
    final samples = conformStore.samplesAtRate(path, deviceRate);
    final entry = conformStore.resultFor(path);
    if (samples == null || entry == null || !entry.isUsable) {
      complete = false;
      continue;
    }
    byMixIndex[index] = sources.length;
    sources.add(AudioMixSource(samples: samples, channels: entry.channels));
  }
  // ⛔Do NOT delete this as redundant because the caller refuses again on
  // a missing map entry: this returns BEFORE the clip loop, so a tick
  // that cannot upload anyway does not pay for a streamed clip's disk
  // read — and while a conform is landing, every tick takes this path.
  if (!complete) {
    return null;
  }
  return (sources: sources, byMixIndex: byMixIndex, hasStreaming: hasStreaming);
}

/// The slice of a streamed source [clip] needs right now: trailing behind
/// the playhead and leading in front of it, clamped into the clip's own
/// span (and, by the reader, into the file).
AudioMixSource _streamWindowSource(
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
  final window = reader.readWindow(windowStart, windowEnd - windowStart);
  return AudioMixSource(
    samples: window.samples,
    channels: reader.channels,
    sourceStart: window.startSample,
  );
}

/// Builds the device upload for [mix] — resident PCM for ordinary clips,
/// a disk WINDOW around [centerSample] for streaming ones (AUDIO-PRO R6).
/// One implementation for the transport AND the scrubber, so streamed
/// playback and streamed scrubbing can never disagree.
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
/// playing — when a resident source is missing (each lookup kicks its
/// conform or rate conversion), a stream will not open, or streaming
/// meets a device off the project rate (the conform on disk IS
/// project-rate PCM; resampling windows on the fly would buy that rare
/// case with a permanent cost).
({List<AudioMixClip> clips, List<AudioMixSource> sources, bool hasStreaming})?
windowedMixUpload({
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
  if (resident.hasStreaming && deviceRate != conformStore.projectSampleRate) {
    return null;
  }

  final sources = [...resident.sources];
  final clips = <AudioMixClip>[];
  final at = (
    centerSample: centerSample,
    backSamples: backSeconds * deviceRate,
    aheadSamples: aheadSeconds * deviceRate,
  );
  for (final clip in mix.clips) {
    final path = mix.sourcePaths[clip.sourceIndex];
    if (!conformStore.isStreaming(path)) {
      final mapped = resident.byMixIndex[clip.sourceIndex];
      if (mapped == null) {
        return null;
      }
      clips.add(clip.pointedAt(mapped));
      continue;
    }
    final reader = conformStore.streamReaderFor(path);
    if (reader == null) {
      return null;
    }
    clips.add(clip.pointedAt(sources.length));
    sources.add(_streamWindowSource(clip, reader: reader, at: at));
  }
  return (clips: clips, sources: sources, hasStreaming: resident.hasStreaming);
}
