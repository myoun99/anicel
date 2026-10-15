/// The making of a conform (audio program 2B): one pass over a sound at the
/// project's rate, a window at a time — decoded, resampled, measured, and
/// written to the scratch it is kept from as it comes. What
/// `AudioConformPipeline` asks for once it has decided a conform must be made.
///
/// 🚨★★★**SO A LONG SOUND IS NEVER HELD WHOLE ON ITS WAY IN** (user
/// 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전
/// 플랫폼」). The decoder used to hand the whole sound back and the resample
/// ran over all of it, the two side by side in the worker: 25 minutes of
/// 44.1 kHz stereo about 1.1 GB, an hour about 2.6 GB — the size that kills
/// an app on an old tablet. A window of the sound, the filter's reach and one
/// window of 16-bit PCM are what a pass holds now, however long the sound.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../models/audio_pcm_scale.dart' show int16PcmOf;
import '../media/media_byte_source.dart';
import '../persistence/media_blob_codec.dart';
import '../persistence/scratch_file.dart' show ScratchFile;
import 'audio_decode_stream.dart';
import 'audio_peaks_extractor.dart';
import 'audio_resampler_reference.dart' show AudioResampleStream;
import 'conform_pcm_codec.dart';
import 'conform_pcm_stream.dart' show conformStaysOnDisk;

/// Opens a container's sound to be read on, at the file's own rate — null
/// when no decoder recognized it. The native decoder supplies this; tests
/// supply a fake so the pipeline's logic is exercised without a binary.
///
/// 🚨★★★**IT TAKES THE SOURCE, NOT THE BYTES.** It used to take a
/// `Uint8List`, which meant the whole container was in memory before any
/// decoder was asked to look at it — and that, not the decoders, is why a
/// movie's soundtrack could not be conformed: a three-gigabyte reference
/// video is not a byte array. A source can name itself as a path plus a
/// span ([MediaByteSource.span]), and the native decoder takes exactly
/// that.
///
/// 🚨★★★**AND IT HANDS BACK A STREAM, NOT THE SOUND** — see
/// [AudioDecodeStream].
typedef AudioDecodeCallback =
    AudioDecodeStream? Function(MediaByteSource source);

/// Opens a conversion of [channels] from [inputRate] to [outputRate] — the
/// rates unequal — fed a piece at a time. The native polyphase resampler
/// supplies this.
typedef AudioResampleCallback =
    AudioResampleStream Function({
      required int channels,
      required int inputRate,
      required int outputRate,
    });

/// How much of a sound is held at once while its conform is made or
/// measured: a quarter of a million frames — 5.5 s of 48 kHz stereo, 2 MB
/// of floats.
const int conformWindowFrames = 1 << 18;

/// What one pass over a sound leaves: its peaks, and its PCM when it stays
/// in memory — null when it stays on disk ([conformStaysOnDisk]).
typedef ConformPass = ({
  AudioPeaks peaks,
  int channels,
  int frames,
  Float32List? samples,
});

/// The pass, at a pipeline's settings.
final class ConformMaking {
  const ConformMaking({
    required this.decode,
    required this.resample,
    required this.projectSampleRate,
    required this.bucketsPerSecond,
    required this.speedNumerator,
    required this.speedDenominator,
  });

  final AudioDecodeCallback decode;
  final AudioResampleCallback resample;
  final int projectSampleRate;
  final int bucketsPerSecond;
  final int speedNumerator;
  final int speedDenominator;

  /// One pass over [src]'s sound at the project's rate, a window at a time:
  /// its peaks folded, each window written to [scratch] as it comes, and its
  /// PCM kept in memory unless it stays on disk — null when no decoder
  /// recognized it. Throws [AudioDecodeFailure] where the decoder stops
  /// partway.
  ConformPass? passOver(MediaByteSource src, ConformScratch? scratch) {
    final sound = decode(src);
    if (sound == null) {
      return null;
    }
    try {
      if (sound.channels <= 0 || sound.sampleRate <= 0) {
        return null;
      }
      final resampler = _resamplerFor(sound);
      try {
        return _passThrough(_atProjectRate(sound, resampler), sound, scratch);
      } finally {
        resampler?.close();
      }
    } finally {
      sound.close();
    }
  }

  ConformPass _passThrough(
    Iterable<Float32List> windows,
    AudioDecodeStream sound,
    ConformScratch? scratch,
  ) {
    final channels = sound.channels;
    final peaks = AudioPeaksOfWindows(
      channels: channels,
      sampleRate: projectSampleRate,
      bucketsPerSecond: bucketsPerSecond,
    );
    List<Float32List>? kept = [];
    var frames = 0;
    for (final window in windows) {
      peaks.add(window);
      scratch?.write(window);
      kept?.add(window);
      frames += window.length ~/ channels;
      if (conformStaysOnDisk(
        frames: frames,
        sampleRate: projectSampleRate,
        onDisk: scratch != null && scratch.failure == null,
      )) {
        kept = null;
      }
    }
    return (
      peaks: peaks.finish(),
      channels: channels,
      frames: frames,
      samples: kept == null ? null : _joined(kept, frames * channels),
    );
  }

  /// The conversion [sound] needs to land at the project's rate, or null when
  /// it is there already.
  ///
  /// Equal rates skip the filter entirely and stay bit-exact — most SE
  /// libraries and dialogue are already at the project rate, so this is the
  /// common path. A non-unity speed (the NTSC pull) REINTERPRETS the source
  /// rate: both sides of the resample scale by the exact rational, so 48k
  /// pulled by 1001/1000 is a 48048000→48000000 conversion — integer ratios
  /// end to end, and the output lands at the project rate holding 0.1% less
  /// time.
  AudioResampleStream? _resamplerFor(AudioDecodeStream sound) {
    final inputRate = sound.sampleRate * speedNumerator;
    final outputRate = projectSampleRate * speedDenominator;
    return inputRate == outputRate
        ? null
        : resample(
            channels: sound.channels,
            inputRate: inputRate,
            outputRate: outputRate,
          );
  }

  /// [sound] a window at a time, through [resampler] when it needs one.
  static Iterable<Float32List> _atProjectRate(
    AudioDecodeStream sound,
    AudioResampleStream? resampler,
  ) sync* {
    for (
      var window = sound.read(conformWindowFrames);
      window.isNotEmpty;
      window = sound.read(conformWindowFrames)
    ) {
      final out = resampler == null ? window : resampler.push(window);
      if (out.isNotEmpty) {
        yield out;
      }
    }
    final rest = resampler?.finish();
    if (rest != null && rest.isNotEmpty) {
      yield rest;
    }
  }

  /// [windows] end to end, [length] samples.
  static Float32List _joined(List<Float32List> windows, int length) {
    if (windows.length == 1) {
      return windows.single;
    }
    final out = Float32List(length);
    var at = 0;
    for (final window in windows) {
      out.setAll(at, window);
      at += window.length;
    }
    return out;
  }
}

/// Where a conform lies while it is made: its 16-bit PCM written as it
/// comes, behind room for the header the end fills in — the conform's own
/// layout, so [writeMediaBlob] reads it straight off.
///
/// A `.part` ([mediaPartPathFor]), so nothing that lists the room it sits in
/// counts it, and it goes when the build does.
final class ConformScratch {
  ConformScratch._(this.conformPath, this._path, this._file, this.failure);

  /// The scratch of a conform to be kept at [conformPath] — one that says
  /// why in [failure] when it cannot be written at all.
  factory ConformScratch.open(String conformPath) {
    final path = mediaPartPathFor(conformPath);
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final open = file.openSync(mode: FileMode.write)
        ..writeFromSync(Uint8List(ConformHeader.length));
      return ConformScratch._(conformPath, path, open, null);
    } on FileSystemException catch (error) {
      return ConformScratch._(conformPath, path, null, error);
    }
  }

  /// Where the conform is kept once it is made.
  final String conformPath;
  final String _path;
  RandomAccessFile? _file;

  /// Why it could not be written, once it could not.
  FileSystemException? failure;

  /// One window's samples as the conform's PCM, kept for the next.
  Int16List _pcm = Int16List(0);

  void write(Float32List window) {
    final file = _file;
    if (file == null || failure != null) {
      return;
    }
    if (_pcm.length < window.length) {
      _pcm = Int16List(window.length);
    }
    int16PcmOf(window, into: _pcm);
    try {
      file.writeFromSync(_pcm.buffer.asUint8List(0, window.length * 2));
    } on FileSystemException catch (error) {
      failure = error;
    }
  }

  /// The conform made, kept at [conformPath] with [header] — where it landed,
  /// or a throw where it could not be written.
  ///
  /// 🚨★★★**AND IT IS WRITTEN COMPRESSED.** A conform is ~12× its source
  /// and zstd takes 38–51% of it back, measured on the user's own audio
  /// (see [writeMediaBlob]). 유저 2026-08-30 chose this against the
  /// alternative — 「다른 앱으로 들을 필요성을 못느끼겟고 그럴거면
  /// 압축해제시켜서 내보내기 기능 만들면 되는거아닌가?」 — which is why
  /// `conform_pcm_codec.dart`'s「any audio tool can open it」is now a
  /// property of the EXPORT, not of the cache file.
  ///
  /// ⛔Block-framed, never one frame: a long conform is read as a sliding
  /// WINDOW by `ConformPcmStreamReader`, and a whole frame has no random
  /// access. This is the same codec media uses, so「how do I read this」
  /// has one answer for both.
  String keep(ConformHeader header) {
    final refused = failure;
    if (refused != null) {
      throw refused;
    }
    final file = _file!
      ..setPositionSync(0)
      ..writeFromSync(header.toBytes());
    // Streamed out rather than compressed whole: an hour of dialogue is
    // hundreds of megabytes, and holding every compressed block beside the
    // PCM to find out whether they were worth keeping is the allocation this
    // build exists not to make. 🆕And read off this scratch: the PCM is on
    // disk already, in the conform's own layout.
    final keptAt = writeMediaBlob(
      basePath: conformPath,
      length: header.totalBytes,
      readInto: (buffer, position, size) {
        file.setPositionSync(position);
        return file.readIntoSync(buffer, 0, size);
      },
    ).path;
    // ⛔The OTHER spelling goes. A rebuild that flips framedness — a build
    // without an engine, or audio that stopped shrinking — would otherwise
    // leave both, and [mediaFramedOrPlainPaths] asks framed first, so the
    // stale one is the one the next open would find.
    for (final other in mediaFramedOrPlainPaths(conformPath)) {
      if (other != keptAt && File(other).existsSync()) {
        File(other).deleteSync();
      }
    }
    return keptAt;
  }

  void delete() {
    try {
      _file?.closeSync();
    } on FileSystemException {
      // Closed by a failure already; the removal below is what matters.
    }
    _file = null;
    ScratchFile.remove(_path);
  }
}
