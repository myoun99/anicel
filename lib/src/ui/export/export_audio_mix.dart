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

import '../../models/audio_pcm_scale.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_mixer_reference.dart';
import '../../services/audio/wav16_header.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../playback/audio_playback_schedule.dart'
    show AudioMixSchedule, ScheduledAudioClip, audioMixScheduleFrom;

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

/// One clip whose PCM is read from disk a block at a time, with the source
/// slot it refreshes (AUDIO-PRO R6).
typedef _StreamedClip = ({
  AudioMixClip clip,
  ConformPcmStreamReader reader,
  int slot,
});

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
  final writer = _ExportMixWriter(
    mix: audioMixScheduleFrom(
      schedule: schedule,
      rate: rate,
      sampleRate: sampleRate,
    ),
    sampleRate: sampleRate,
    channels: channels,
    resolveSource: resolveSource,
    resolveStreamReader: resolveStreamReader,
    log: log,
  );
  if (!await writer.bindSources()) {
    return false;
  }
  writer.writeTo(
    outputPath,
    totalSamples: rate.frameToSample(totalFrames, sampleRate),
  );
  return true;
}

/// ONE export mix on its way to disk, in the three phases it always had:
/// resolve every source (streaming where the conform allows it), bind each
/// clip to the slot it will read from, then write the WAV block by block.
///
/// 🚨A COLLABORATOR, NOT A NEW POLICY (audit round 2, 2026-09-10): every
/// decision below moved here verbatim from `writeExportAudioMixWav`, which
/// held all three phases, five collections and the file handle in one body.
/// The phases share state on purpose — a slot index means nothing without
/// the source list it points into — and that is exactly what an object is
/// for.
class _ExportMixWriter {
  _ExportMixWriter({
    required this.mix,
    required this.sampleRate,
    required this.channels,
    required this.resolveSource,
    required this.resolveStreamReader,
    required this.log,
  });

  final AudioMixSchedule mix;
  final int sampleRate;
  final int channels;
  final ExportAudioSourceResolver resolveSource;
  final ExportAudioStreamResolver? resolveStreamReader;
  final void Function(String message)? log;

  final List<AudioMixSource> _sources = [];
  final List<AudioMixClip> _clips = [];

  /// Streaming clips own a PRIVATE source slot each, refreshed per block.
  final List<_StreamedClip> _streamed = [];

  /// Resolves every source and binds every clip to the slot it reads.
  /// False = nothing audible came back, and the caller writes no file.
  Future<bool> bindSources() async {
    final residentByOriginal = <int, int>{};
    final readerByOriginal = <int, ConformPcmStreamReader>{};
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
        readerByOriginal[index] = reader;
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
      residentByOriginal[index] = _sources.length;
      _sources.add(source);
    }
    // ⚠️THE ONLY EMPTY OUTCOME. Every path in `mix.sourcePaths` was put
    // there BY a clip (`audioMixScheduleFrom` walks the schedule), so once
    // one path resolves, the loop below binds at least one clip. The
    // `clips.isEmpty` check that used to follow it could not fire — no
    // test could kill it, which is how it was found.
    if (_sources.isEmpty && readerByOriginal.isEmpty) {
      return false;
    }
    for (final clip in mix.clips) {
      final resident = residentByOriginal[clip.sourceIndex];
      if (resident != null) {
        _clips.add(clip.pointedAt(resident));
        continue;
      }
      final reader = readerByOriginal[clip.sourceIndex];
      if (reader == null) {
        continue; // unresolvable: renders silent, already logged
      }
      final slot = _sources.length;
      _sources.add(
        AudioMixSource(samples: Float32List(0), channels: reader.channels),
      );
      final rebuilt = clip.pointedAt(slot);
      _clips.add(rebuilt);
      _streamed.add((clip: rebuilt, reader: reader, slot: slot));
    }
    return true;
  }

  /// Writes the header and then [totalSamples] of mixed audio.
  ///
  /// Block-mixed so a long timeline never holds its whole bus in memory;
  /// the buffers are reused across blocks, and streaming sources read
  /// exactly one block's worth of disk at a time.
  void writeTo(String outputPath, {required int totalSamples}) {
    final sink = File(outputPath).openSync(mode: FileMode.write);
    try {
      sink.writeFromSync(
        wav16HeaderBytes(
          dataBytes: totalSamples * channels * 2,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );
      const blockSamples = 65536;
      final bus = Float64List(blockSamples * channels);
      final out = Int16List(blockSamples * channels);
      var position = 0;
      while (position < totalSamples) {
        final count = (totalSamples - position).clamp(0, blockSamples);
        _refillStreamedSources(position, count);
        final busView = count == blockSamples
            ? bus
            : Float64List.sublistView(bus, 0, count * channels);
        mixAudioReference(
          clips: _clips,
          sources: _sources,
          startSample: position,
          sampleCount: count,
          outChannels: channels,
          into: busView,
        );
        final outView = count == blockSamples
            ? out
            : Int16List.sublistView(out, 0, count * channels);
        int16PcmOf(busView, into: outView);
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
  }

  /// Reads this block's window for every streaming clip that sounds in it.
  void _refillStreamedSources(int position, int count) {
    for (final streamed in _streamed) {
      final clip = streamed.clip;
      if (position + count <= clip.startSample || position >= clip.endSample) {
        continue; // this block never reads the clip; keep whatever is there
      }
      final clipLength = clip.endSample - clip.startSample;
      final from =
          clip.sourceOffset + (position - clip.startSample).clamp(0, clipLength);
      final to =
          clip.sourceOffset +
          (position + count - clip.startSample).clamp(0, clipLength);
      final window = streamed.reader.readWindow(from, to - from);
      _sources[streamed.slot] = AudioMixSource(
        samples: window.samples,
        channels: streamed.reader.channels,
        sourceStart: window.startSample,
      );
    }
  }
}
