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

import 'dart:math' as math;

import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../models/track.dart';
import '../../services/audio/audio_mixer_reference.dart';
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
      _keysEqual(other.volumeKeys, volumeKeys);

  static bool _keysEqual(List<AudioVolumeKey> a, List<AudioVolumeKey> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

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
    final trackStartByCutId = <CutId, int>{};
    final trackByCutId = <CutId, Track>{};
    for (final track in project.tracks) {
      var start = 0;
      for (final cut in track.cuts) {
        start += cut.leadingGapFrames;
        trackStartByCutId[cut.id] = start;
        trackByCutId[cut.id] = track;
        start += cut.duration;
      }
    }

    /// The playlist frame where the contiguous run starting at
    /// [entryIndex] ends. Contiguous = the playlist and track axes
    /// advance by the SAME amount between entries — back-to-back cuts,
    /// or a leading gap the playlist plays through as black. Sounds keep
    /// running through played gaps (audio lives on the global axis).
    int contiguousPlaylistEndFrom(int entryIndex) {
      var end = playlist[entryIndex].endFrame;
      var trackEnd =
          (trackStartByCutId[playlist[entryIndex].cutId] ?? 0) +
          playlist[entryIndex].duration;
      final track = trackByCutId[playlist[entryIndex].cutId];
      for (var i = entryIndex + 1; i < playlist.length; i += 1) {
        final next = playlist[i];
        final nextTrackStart = trackStartByCutId[next.cutId];
        if (nextTrackStart == null ||
            next.startFrame < end ||
            next.startFrame - end != nextTrackStart - trackEnd ||
            !identical(trackByCutId[next.cutId], track)) {
          break;
        }
        end = next.endFrame;
        trackEnd = nextTrackStart + next.duration;
      }
      return end;
    }

    for (var i = 0; i < playlist.length; i += 1) {
      final entry = playlist[i];
      final track = trackByCutId[entry.cutId];
      final cutTrackStart = trackStartByCutId[entry.cutId];
      if (track == null || cutTrackStart == null) {
        continue;
      }
      // A run-start entry also carries sounds spilling in from before
      // the playlist window (offset-bumped); interior entries only emit
      // spans STARTING in their window (no duplicates). The window
      // extends back over the entry's PLAYED leading gap — playlist
      // frames before the cut that map 1:1 onto the track frames before
      // it — so sounds starting inside a gap are scheduled too.
      final previous = i == 0 ? null : playlist[i - 1];
      final previousTrackStart = previous == null
          ? null
          : trackStartByCutId[previous.cutId];
      final playlistLead = entry.startFrame - (previous?.endFrame ?? 0);
      final axesAligned = previous == null
          // The playlist head maps straight onto the track axis
          // (all-cuts playlists ARE the track axis; a rebased
          // single-cut playlist has no lead at all).
          ? playlistLead >= 0
          : previousTrackStart != null &&
                identical(trackByCutId[previous.cutId], track) &&
                playlistLead >= 0 &&
                cutTrackStart - (previousTrackStart + previous.duration) ==
                    playlistLead;
      final coveredLead = axesAligned ? playlistLead : 0;
      final isRunStart = previous == null || !axesAligned;
      final windowStart = cutTrackStart - coveredLead;
      final windowEnd = cutTrackStart + entry.duration;
      final runEnd = contiguousPlaylistEndFrom(i);

      for (final layer in track.seLayers) {
        if (layer.muted ||
            muted.contains(layer.id) ||
            (soloed.isNotEmpty && !soloed.contains(layer.id))) {
          continue;
        }
        for (final span in seAudioSpans(layer)) {
          final spanEnd = span.startFrame + span.lengthFrames;
          final startsHere =
              span.startFrame >= windowStart && span.startFrame < windowEnd;
          final spillsIntoRunStart =
              isRunStart &&
              span.startFrame < windowStart &&
              spanEnd > windowStart;
          if (!startsHere && !spillsIntoRunStart) {
            continue;
          }
          final clippedLead = spillsIntoRunStart
              ? windowStart - span.startFrame
              : 0;
          // entry.startFrame - coveredLead = the playlist frame the
          // (gap-extended) window begins at.
          final startFrame =
              entry.startFrame -
              coveredLead +
              (spillsIntoRunStart ? 0 : span.startFrame - windowStart);
          var endFrameExclusive = math.min(
            runEnd,
            startFrame + span.lengthFrames - clippedLead,
          );
          final offsetFrames = span.clip.offsetFrames + clippedLead;
          endFrameExclusive = _clampToFileLength(
            startFrame: startFrame,
            endFrameExclusive: endFrameExclusive,
            filePath: span.clip.filePath,
            offsetFrames: offsetFrames,
            rate: rate,
            durationSecondsFor: durationSecondsFor,
          );
          if (endFrameExclusive <= startFrame) {
            continue;
          }
          schedule.add(
            ScheduledAudioClip(
              filePath: span.clip.filePath,
              startFrame: startFrame,
              endFrameExclusive: endFrameExclusive,
              offsetFrames: offsetFrames,
              // The layer fader multiplies in HERE (one gain per entry) so
              // no consumer ever re-consults the layer.
              gain: layer.audioGain * span.clip.gain,
              fadeInFrames: span.clip.fadeInFrames,
              fadeOutFrames: span.clip.fadeOutFrames,
              pan: layer.audioPan,
              fadeCurve: span.clip.fadeCurve,
              // Envelope keys anchor to the SPAN start; a clipped lead
              // shifts them (possibly negative — before the window).
              volumeKeys: clippedLead == 0
                  ? span.clip.volumeKeys
                  : [
                      for (final key in span.clip.volumeKeys)
                        AudioVolumeKey(
                          frame: key.frame - clippedLead,
                          gain: key.gain,
                        ),
                    ],
            ),
          );
        }
      }
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
  int backSeconds = 2,
  int aheadSeconds = 30,
}) {
  final sources = <AudioMixSource>[];
  final residentIndex = <int, int>{};
  var complete = true;
  var hasStreaming = false;
  for (var index = 0; index < mix.sourcePaths.length; index += 1) {
    final path = mix.sourcePaths[index];
    if (conformStore.isStreaming(path)) {
      hasStreaming = true;
      continue; // windowed per clip below
    }
    // Every lookup runs even after a miss: each one KICKS its conform or
    // rate conversion, and the next attempt wants them all landed.
    final samples = conformStore.samplesAtRate(path, deviceRate);
    final entry = conformStore.resultFor(path);
    if (samples == null || entry == null || !entry.isUsable) {
      complete = false;
      continue;
    }
    residentIndex[index] = sources.length;
    sources.add(AudioMixSource(samples: samples, channels: entry.channels));
  }
  if (!complete) {
    return null;
  }
  if (hasStreaming && deviceRate != conformStore.projectSampleRate) {
    return null;
  }

  AudioMixClip clipWithSource(AudioMixClip clip, int sourceIndex) =>
      AudioMixClip(
        sourceIndex: sourceIndex,
        startSample: clip.startSample,
        endSample: clip.endSample,
        sourceOffset: clip.sourceOffset,
        gain: clip.gain,
        fadeInSamples: clip.fadeInSamples,
        fadeOutSamples: clip.fadeOutSamples,
        panLeft: clip.panLeft,
        panRight: clip.panRight,
        fadeCurve: clip.fadeCurve,
        envelope: clip.envelope,
      );

  final clips = <AudioMixClip>[];
  final backSamples = backSeconds * deviceRate;
  final aheadSamples = aheadSeconds * deviceRate;
  for (final clip in mix.clips) {
    final path = mix.sourcePaths[clip.sourceIndex];
    if (!conformStore.isStreaming(path)) {
      final mapped = residentIndex[clip.sourceIndex];
      if (mapped == null) {
        return null;
      }
      clips.add(clipWithSource(clip, mapped));
      continue;
    }
    final reader = conformStore.streamReaderFor(path);
    if (reader == null) {
      return null;
    }
    final clipLength = clip.endSample - clip.startSample;
    final positionInClip = (centerSample - clip.startSample).clamp(
      0,
      clipLength,
    );
    final sourceAt = clip.sourceOffset + positionInClip;
    final windowStart = math.max(clip.sourceOffset, sourceAt - backSamples);
    final windowEnd = math.min(
      clip.sourceOffset + clipLength,
      sourceAt + aheadSamples,
    );
    final window = reader.readWindow(windowStart, windowEnd - windowStart);
    clips.add(clipWithSource(clip, sources.length));
    sources.add(
      AudioMixSource(
        samples: window.samples,
        channels: reader.channels,
        sourceStart: window.startSample,
      ),
    );
  }
  return (clips: clips, sources: sources, hasStreaming: hasStreaming);
}
