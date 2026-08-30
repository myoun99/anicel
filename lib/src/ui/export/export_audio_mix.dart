/// The export audio mix (EXPORT-AUDIO round): the SAME mixer that carries
/// playback renders the file.
///
/// Until this round, export audio went through an ffmpeg filter graph —
/// a SECOND mixer, with its own fade curves and its own rounding. Two
/// mixers is how a preview ends up telling a small lie about the render.
/// Now the schedule is mixed by our own reference (block by block, 64-bit
/// bus, output-stage clipping — everything the parity tests pin) into one
/// plain WAV, and ffmpeg's only audio job left is encoding that PCM.
///
/// The Dart reference mixes here on purpose, not the FFI path: this is an
/// offline render where determinism and simplicity beat throughput, and
/// the byte-parity contract makes the choice inaudible by construction.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_mixer_reference.dart';
import '../../services/audio/wav16_header.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../playback/audio_playback_schedule.dart'
    show ScheduledAudioClip, audioMixScheduleFrom;

/// Resolves one source's conformed PCM (at the mix's own sample rate), or
/// null when it cannot be had — that clip renders silent, the export goes
/// on (a missing sound must not kill a deadline render; the log says so).
typedef ExportAudioSourceResolver =
    Future<AudioMixSource?> Function(String filePath);

/// Resolves a DISK-BACKED source (AUDIO-PRO R6): a long conform whose PCM
/// was never resident. The render then reads it block by block instead of
/// asking [ExportAudioSourceResolver] to produce the whole file — which
/// for a thirty-minute track would mean holding the memory streaming
/// exists to avoid.
typedef ExportAudioStreamResolver =
    ConformPcmStreamReader? Function(String filePath);

/// Renders [schedule] to an int16 stereo WAV at [outputPath].
///
/// Returns false when there is nothing audible (empty schedule or no
/// resolvable source) — the caller then runs a video-only encode instead
/// of muxing a silent track.
///
/// The length is EXACTLY [totalFrames] of video time, sample-converted
/// with the same `frameToSample` pairing the clock uses; ffmpeg's
/// `-shortest` then has nothing to trim.
Future<bool> writeExportAudioMixWav({
  required List<ScheduledAudioClip> schedule,
  required ProjectFrameRate rate,
  required int totalFrames,
  required int sampleRate,
  required ExportAudioSourceResolver resolveSource,
  required String outputPath,
  ExportAudioStreamResolver? resolveStreamReader,
  int channels = 2,
  void Function(String message)? log,
}) async {
  if (schedule.isEmpty || totalFrames <= 0) {
    return false;
  }
  final mix = audioMixScheduleFrom(
    schedule: schedule,
    rate: rate,
    sampleRate: sampleRate,
  );
  final sources = <AudioMixSource>[];
  final resolvedIndexByOriginal = <int, int>{};
  final streamReaderByOriginal = <int, ConformPcmStreamReader>{};
  for (var index = 0; index < mix.sourcePaths.length; index += 1) {
    final path = mix.sourcePaths[index];
    // Disk-backed first (AUDIO-PRO R6): a streaming conform is read block
    // by block below — asking the resolver for the whole file would hold
    // exactly the memory streaming exists to avoid. Its conform is
    // project-rate PCM, so a mix at any other rate falls through to the
    // resolver (which resamples, at full residency — the honest cost of
    // that rare setup).
    final reader = resolveStreamReader?.call(path);
    if (reader != null && reader.sampleRate == sampleRate) {
      streamReaderByOriginal[index] = reader;
      continue;
    }
    final source = await resolveSource(path);
    if (source == null) {
      log?.call(
        '[export audio] no decodable source for $path — that clip renders '
        'silent',
      );
      continue;
    }
    resolvedIndexByOriginal[index] = sources.length;
    sources.add(source);
  }
  if (sources.isEmpty && streamReaderByOriginal.isEmpty) {
    return false;
  }
  // EVERY clip field carries over — the render must hear exactly what the
  // preview heard. (Pan, the fade curve and the volume envelope arrived
  // with AUDIO-PRO R1; dropping any of them here is how a preview starts
  // lying about the export again.)
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
  // Streaming clips own a PRIVATE source slot each, refreshed per block.
  final streamedClips =
      <({AudioMixClip clip, ConformPcmStreamReader reader, int slot})>[];
  for (final clip in mix.clips) {
    final resident = resolvedIndexByOriginal[clip.sourceIndex];
    if (resident != null) {
      clips.add(clipWithSource(clip, resident));
      continue;
    }
    final reader = streamReaderByOriginal[clip.sourceIndex];
    if (reader == null) {
      continue; // unresolvable: renders silent, already logged
    }
    final slot = sources.length;
    sources.add(
      AudioMixSource(samples: Float32List(0), channels: reader.channels),
    );
    final rebuilt = clipWithSource(clip, slot);
    clips.add(rebuilt);
    streamedClips.add((clip: rebuilt, reader: reader, slot: slot));
  }
  if (clips.isEmpty) {
    return false;
  }

  final totalSamples = rate.frameToSample(totalFrames, sampleRate);
  final dataBytes = totalSamples * channels * 2;
  final sink = File(outputPath).openSync(mode: FileMode.write);
  try {
    sink.writeFromSync(
      wav16HeaderBytes(
        dataBytes: dataBytes,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
    // Block-mixed so a long timeline never holds its whole bus in memory;
    // the buffers are reused across blocks, and streaming sources read
    // exactly one block's worth of disk at a time.
    const blockSamples = 65536;
    final bus = Float64List(blockSamples * channels);
    final out = Int16List(blockSamples * channels);
    var position = 0;
    while (position < totalSamples) {
      final count = (totalSamples - position).clamp(0, blockSamples);
      for (final streamed in streamedClips) {
        final clip = streamed.clip;
        if (position + count <= clip.startSample ||
            position >= clip.endSample) {
          continue; // this block never reads the clip; keep whatever is there
        }
        final clipLength = clip.endSample - clip.startSample;
        final from =
            clip.sourceOffset +
            (position - clip.startSample).clamp(0, clipLength);
        final to =
            clip.sourceOffset +
            (position + count - clip.startSample).clamp(0, clipLength);
        final window = streamed.reader.readWindow(from, to - from);
        sources[streamed.slot] = AudioMixSource(
          samples: window.samples,
          channels: streamed.reader.channels,
          sourceStart: window.startSample,
        );
      }
      final busView = count == blockSamples
          ? bus
          : Float64List.sublistView(bus, 0, count * channels);
      mixAudioReference(
        clips: clips,
        sources: sources,
        startSample: position,
        sampleCount: count,
        outChannels: channels,
        into: busView,
      );
      final outView = count == blockSamples
          ? out
          : Int16List.sublistView(out, 0, count * channels);
      audioBusToInt16(busView, into: outView);
      sink.writeFromSync(
        outView.buffer.asUint8List(
          outView.offsetInBytes,
          outView.lengthInBytes,
        ),
      );
      position += count;
    }
  } finally {
    sink.closeSync();
  }
  return true;
}
