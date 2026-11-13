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

import 'dart:ffi' show Float, FloatPointer, Pointer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../models/audio_pcm_scale.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart'
    show QaAudioDevice, audioDeviceUnlessTesting;
import '../../services/audio/audio_mixer_reference.dart';
import '../../services/audio/wav16_header.dart';
import '../../services/audio/conform_pcm_stream.dart';
import '../../services/media/media_byte_source.dart' show MediaFileBytes;
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
  QaAudioDevice? Function() device = audioDeviceUnlessTesting,
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
  await writer.writeOnAWorker(
    outputPath,
    totalSamples: rate.frameToSample(totalFrames, sampleRate),
    device: device(),
  );
  return true;
}

/// The last [samples] frames of the mix at [path], interleaved as it was
/// written — behind silence where the mix is shorter than that, for nothing
/// sounded before it began. Null where the file cannot be read as a mix.
///
/// What a writer that puts a frame of sound before a movie's mix is handed
/// (`SoundBefore`, video_export_service.dart): the mix of the frames before
/// the movie's first ends where the movie's own begins, so its END is the
/// movie's past.
Int16List? exportAudioMixTail(String path, int samples) {
  final reader = ConformPcmStreamReader.overWav16(MediaFileBytes(path));
  if (reader == null || samples <= 0) {
    return null;
  }
  final held = math.min(samples, reader.length);
  final tail = reader.readInt16Window(reader.length - held, held).samples;
  // A window that came back short is a file that could not be read.
  if (tail.length != held * reader.channels) {
    return null;
  }
  return Int16List(samples * reader.channels)
    ..setAll(samples * reader.channels - tail.length, tail);
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

  /// Writes the header and then [totalSamples] of mixed audio, on a worker
  /// ([_mixOnAWorker]) — each resident source read where it lies, lent by
  /// [device] for as long as the mix takes ([QaAudioDevice.lendToAWorker]).
  ///
  /// ↩️It mixed here, on the UI isolate, the whole timeline in one stretch
  /// (card `the-export-sound-blocks-the-ui-isolate`, the CPU census — 관제
  /// 2026-11-13). The Dart reference still mixes it (this library's head
  /// says why) — on a worker, which changes nothing it writes.
  Future<void> writeOnAWorker(
    String outputPath, {
    required int totalSamples,
    required QaAudioDevice? device,
  }) => _lendingEach(
    device,
    [for (final source in _sources) source.samples],
    (lent) => _mixOnAWorker(
      (
        path: outputPath,
        totalSamples: totalSamples,
        channels: channels,
        sampleRate: sampleRate,
      ),
      _clips,
      [
        for (final (index, source) in _sources.indexed)
          (
            samples: lent[index] == null ? source.samples : Float32List(0),
            lent: lent[index],
            channels: source.channels,
            sourceStart: source.sourceStart,
          ),
      ],
      _streamed,
    ),
  );
}

/// Where a mix is written: the file, its length, its channels and rate.
typedef _MixInto = ({
  String path,
  int totalSamples,
  int channels,
  int sampleRate,
});

/// A resident source on its way to the mix's worker: where it lies when
/// the device lent it, its samples when not.
typedef _SourceCrossing = ({
  Float32List samples,
  ({int address, int floats})? lent,
  int channels,
  int sourceStart,
});

/// [work] given where each of [each] lies — each held until [work] is done
/// ([QaAudioDevice.lendToAWorker]), null for one the device did not make,
/// which [work] sends itself.
Future<T> _lendingEach<T>(
  QaAudioDevice? device,
  List<Float32List> each,
  Future<T> Function(List<({int address, int floats})?> lent) work, [
  List<({int address, int floats})?> lent = const [],
]) {
  if (lent.length == each.length) {
    return work(lent);
  }
  if (device == null) {
    return work(List.filled(each.length, null));
  }
  return device.lendToAWorker(
    each[lent.length],
    (one) => _lendingEach(device, each, work, [...lent, one]),
  );
}

/// The mix [onAWorker] writes, in a function of its own: the closure
/// carries what it is handed — the clips, the sources, the streaming
/// readers, which hold no OS handle — and nothing of the writer's, whose
/// resolvers hold the session.
Future<void> _mixOnAWorker(
  _MixInto into,
  List<AudioMixClip> clips,
  List<_SourceCrossing> sources,
  List<_StreamedClip> streamed,
) => onAWorker(
  () => _writeMix(into, clips, [
    for (final source in sources) _sourceHere(source),
  ], streamed),
);

AudioMixSource _sourceHere(_SourceCrossing source) {
  final lent = source.lent;
  return AudioMixSource(
    samples: lent == null
        ? source.samples
        : Pointer<Float>.fromAddress(lent.address).asTypedList(lent.floats),
    channels: source.channels,
    sourceStart: source.sourceStart,
  );
}

/// Writes the header and then [into]'s samples of [clips] mixed over
/// [sources].
///
/// Block-mixed so a long timeline never holds its whole bus in memory;
/// the buffers are reused across blocks, and streaming sources read
/// exactly one block's worth of disk at a time.
void _writeMix(
  _MixInto into,
  List<AudioMixClip> clips,
  List<AudioMixSource> sources,
  List<_StreamedClip> streamed,
) {
  final (:path, :totalSamples, :channels, :sampleRate) = into;
  final sink = File(path).openSync(mode: FileMode.write);
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
      _refillStreamedSources(sources, streamed, position, count);
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
void _refillStreamedSources(
  List<AudioMixSource> sources,
  List<_StreamedClip> streamed,
  int position,
  int count,
) {
  for (final each in streamed) {
    final clip = each.clip;
    if (position + count <= clip.startSample || position >= clip.endSample) {
      continue; // this block never reads the clip; keep whatever is there
    }
    final clipLength = clip.endSample - clip.startSample;
    final from =
        clip.sourceOffset + (position - clip.startSample).clamp(0, clipLength);
    final to =
        clip.sourceOffset +
        (position + count - clip.startSample).clamp(0, clipLength);
    final window = each.reader.readWindow(from, to - from);
    sources[each.slot] = AudioMixSource(
      samples: window.samples,
      channels: each.reader.channels,
      sourceStart: window.startSample,
    );
  }
}
