import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/export_format_selection.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_encoder.dart';
import '../../services/audio/conform_pcm_stream.dart';
import 'png_sequence_export_service.dart' show ExportWriteSummary;
import '../../models/audio_pcm_scale.dart';

/// The ABI v21 integers the native encoder speaks (qa_video_encode.c).
extension ExportVideoContainerAbi on ExportVideoContainer {
  int get abiValue => switch (this) {
    ExportVideoContainer.mp4 => 0,
    ExportVideoContainer.mov => 1,
  };
}

extension ExportVideoCodecAbi on ExportVideoCodec {
  int get abiValue => switch (this) {
    ExportVideoCodec.h264 => 0,
    ExportVideoCodec.h265 => 1,
    ExportVideoCodec.proresProxy => 2,
    ExportVideoCodec.proresLt => 3,
    ExportVideoCodec.prores422 => 4,
    ExportVideoCodec.proresHq => 5,
    ExportVideoCodec.prores4444 => 6,
  };

  /// The ffmpeg prores_ks profile index (proxy..4444).
  int get proresKsProfile => switch (this) {
    ExportVideoCodec.proresProxy => 0,
    ExportVideoCodec.proresLt => 1,
    ExportVideoCodec.prores422 => 2,
    ExportVideoCodec.proresHq => 3,
    ExportVideoCodec.prores4444 => 4,
    _ => 2,
  };
}

/// Injectable process launcher so tests can stand in for the real ffmpeg.
typedef VideoProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

Future<Process> _startProcess(String executable, List<String> arguments) =>
    Process.start(executable, arguments);

/// Resolves the OS encoder for this run; null keeps the ffmpeg path.
/// Widget tests must never bind a real encoder — same gate the audio
/// device uses.
typedef VideoEncoderResolver = QaVideoEncoder? Function();

QaVideoEncoder? _defaultEncoderResolver() =>
    Platform.environment['FLUTTER_TEST'] == 'true'
    ? null
    : QaVideoEncoder.instance;

/// Internal: the OS encoder refused the JOB (no encoder MFT, bad open) —
/// distinct from failing midway, because refusing up front means the
/// ffmpeg fallback can still carry the run.
class _OsEncoderRefused implements Exception {
  const _OsEncoderRefused();
}

/// A video export failure with a user-presentable [message] (missing ffmpeg,
/// non-zero exit); the dialog shows it verbatim.
class VideoExportException implements Exception {
  const VideoExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Encodes rendered frames into an H.264/AAC MP4.
///
/// The OS encoder carries the run when it can (AUDIO-PRO R7): Media
/// Foundation on Windows, AVAssetWriter on Apple, NDK MediaCodec on
/// Android — hardware-backed, nothing to install, and the only path a
/// tablet has. RGBA goes straight in; no PNG encode, no pipe.
///
/// The ffmpeg pipe remains as the FALLBACK — Linux, an old binary, or an
/// OS whose encoder refuses the job. It must be installed and on PATH (or
/// injected via [executable]). Either path finalizes a playable partial
/// on cancel instead of leaving a corrupt file.
class VideoExportService {
  const VideoExportService({
    this.executable = 'ffmpeg',
    this.processStarter = _startProcess,
    this.encoderResolver = _defaultEncoderResolver,
  });

  final String executable;
  final VideoProcessStarter processStarter;
  final VideoEncoderResolver encoderResolver;

  /// Builds the full ffmpeg argument list for the codec matrix (EX4):
  /// MP4 = libx264/libx265 (the confirmed software H.265), MOV = libx264
  /// or prores_ks with the profile per flavor — 4444 in 10-bit 4:4:4,
  /// with alpha when asked. ProRes carries PCM (the delivery convention);
  /// the H.26x containers carry AAC.
  ///
  /// Audio, when present, arrives as ONE finished WAV ([audioMixPath]) —
  /// already mixed by the same mixer that carries playback (EXPORT-AUDIO
  /// round); ffmpeg only transcodes it.
  ///
  /// The even-dimension pad H.264/H.265 require gains white pixels —
  /// TRANSPARENT ones under alpha, where a paper hairline would read as
  /// content. The rate goes out as ffmpeg's own fraction (`24000/1001`).
  @visibleForTesting
  static List<String> buildFfmpegArguments({
    required ProjectFrameRate frameRate,
    required String outputFilePath,
    String? audioMixPath,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
  }) {
    final keepAlpha = codec.supportsAlpha && alpha;
    final padFilter =
        'pad=ceil(iw/2)*2:ceil(ih/2)*2:color=${keepAlpha ? 'black@0.0' : 'white'}';
    final video = <String>[
      if (codec.isProRes) ...[
        '-c:v',
        'prores_ks',
        '-profile:v',
        '${codec.proresKsProfile}',
        '-vendor',
        'apl0',
        '-pix_fmt',
        if (codec == ExportVideoCodec.prores4444)
          keepAlpha ? 'yuva444p10le' : 'yuv444p10le'
        else
          'yuv422p10le',
      ] else ...[
        '-c:v',
        if (codec == ExportVideoCodec.h265) 'libx265' else 'libx264',
        '-pix_fmt',
        'yuv420p',
        if (bitrateBps > 0) ...[
          '-b:v',
          '$bitrateBps',
        ] else ...[
          '-crf',
          if (codec == ExportVideoCodec.h265) '20' else '18',
        ],
      ],
      '-vf',
      padFilter,
    ];
    final audioCodec = codec.isProRes ? 'pcm_s16le' : 'aac';
    final args = <String>[
      '-y',
      '-f',
      'image2pipe',
      '-framerate',
      frameRate.ffmpegRateArgument,
      '-i',
      '-',
    ];
    if (audioMixPath == null) {
      return args..addAll([...video, outputFilePath]);
    }
    return args..addAll([
      '-i',
      audioMixPath,
      '-map',
      '0:v',
      '-map',
      '1:a',
      ...video,
      '-c:a',
      audioCodec,
      '-shortest',
      outputFilePath,
    ]);
  }

  Future<ExportWriteSummary> exportVideo({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final encoder = encoderResolver();
    if (encoder != null && encoder.isSupported) {
      try {
        return await _exportViaOsEncoder(
          encoder: encoder,
          count: count,
          renderImage: renderImage,
          outputFilePath: outputFilePath,
          frameRate: frameRate,
          audioMixPath: audioMixPath,
          container: container,
          codec: codec,
          alpha: alpha,
          bitrateBps: bitrateBps,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } on _OsEncoderRefused {
        // The OS could not take the job (an N-edition Windows with no
        // codec pack, MOV/ProRes on Windows, a refused format) — the
        // ffmpeg path below still can.
      }
    }
    return _exportViaFfmpeg(
      count: count,
      renderImage: renderImage,
      outputFilePath: outputFilePath,
      frameRate: frameRate,
      audioMixPath: audioMixPath,
      container: container,
      codec: codec,
      alpha: alpha,
      bitrateBps: bitrateBps,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// The OS-encoder run: raw RGBA frames straight into the system H.264
  /// encoder, the mixed WAV read back in per-frame chunks and fed to the
  /// system AAC encoder — interleaved, so neither side buffers the track.
  Future<ExportWriteSummary> _exportViaOsEncoder({
    required QaVideoEncoder encoder,
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    required ExportVideoContainer container,
    required ExportVideoCodec codec,
    required bool alpha,
    required int bitrateBps,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (count <= 0) {
      return (written: 0, processed: 0);
    }
    var processed = 0;

    // The first renderable frame decides the geometry.
    ui.Image? first;
    var index = 0;
    while (index < count) {
      if (isCancelled?.call() ?? false) {
        return (written: 0, processed: processed);
      }
      first = await renderImage(index);
      index += 1;
      processed += 1;
      onProgress?.call(processed, count);
      if (first != null) {
        break;
      }
    }
    if (first == null) {
      // Nothing rendered at all — same outcome the pipe path reports.
      throw const VideoExportException('video export: nothing rendered');
    }

    final audio = audioMixPath == null
        ? null
        : ConformPcmStreamReader.open(audioMixPath);
    if (!encoder.open(
      path: outputFilePath,
      width: first.width,
      height: first.height,
      fpsNumerator: frameRate.numerator,
      fpsDenominator: frameRate.denominator,
      sampleRate: audio?.sampleRate ?? 0,
      channels: audio?.channels ?? 0,
      container: container.abiValue,
      codec: codec.abiValue,
      alpha: alpha,
      bitrateBps: bitrateBps,
    )) {
      first.dispose();

      throw const _OsEncoderRefused();
    }

    final feed = _OsEncoderFeed(
      encoder: encoder,
      audio: audio,
      frameRate: frameRate,
    );
    var failed = false;
    var cancelled = false;

    if (!await feed.feed(first)) {
      failed = true;
    }
    while (!failed && index < count) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final image = await renderImage(index);
      index += 1;
      if (image != null && !await feed.feed(image)) {
        failed = true;
        break;
      }
      processed += 1;
      onProgress?.call(processed, count);
    }

    if (failed) {
      final detail = encoder.lastError;
      encoder.abort();
      throw VideoExportException(
        detail.isEmpty ? 'video export: the OS encoder failed' : detail,
      );
    }
    // A cancelled run finalizes a playable partial — the pipe path's
    // behavior, kept. ⚠️Untested (2026-09-05): nothing cancels the OS
    // path mid-run yet, so `&& !cancelled` mutates away green.
    if (!encoder.finish() && !cancelled) {
      final detail = encoder.lastError;
      throw VideoExportException(
        detail.isEmpty ? 'video export: the MP4 failed to finalize' : detail,
      );
    }
    return (written: feed.written, processed: processed);
  }

  Future<ExportWriteSummary> _exportViaFfmpeg({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final Process process;
    try {
      process = await processStarter(
        executable,
        buildFfmpegArguments(
          frameRate: frameRate,
          outputFilePath: outputFilePath,
          audioMixPath: audioMixPath,
          container: container,
          codec: codec,
          alpha: alpha,
          bitrateBps: bitrateBps,
        ),
      );
    } on ProcessException {
      throw const VideoExportException(
        'ffmpeg not found — install FFmpeg and make sure it is on PATH.',
      );
    }

    final stderrTail = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach((chunk) {
          stderrTail.write(chunk);
          // Keep only the tail: ffmpeg logs a lot and only the last lines
          // explain a failure.
          const cap = 4000;
          if (stderrTail.length > cap * 2) {
            final kept = stderrTail.toString();
            stderrTail
              ..clear()
              ..write(kept.substring(kept.length - cap));
          }
        })
        .catchError((Object _) {});
    final stdoutDone = process.stdout.drain<void>().catchError((Object _) {});

    var written = 0;
    var processed = 0;
    var pipeBroken = false;
    var cancelled = false;
    for (var index = 0; index < count; index += 1) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final image = await renderImage(index);
      if (image != null) {
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          process.stdin.add(bytes!.buffer.asUint8List());
          await process.stdin.flush();
          written += 1;
        } on Object {
          // ffmpeg died mid-stream (broken pipe); its stderr explains why.
          pipeBroken = true;
          break;
        } finally {
          image.dispose();
        }
      }
      processed += 1;
      onProgress?.call(processed, count);
    }

    if (cancelled && written == 0) {
      // Nothing was fed; an empty pipe makes ffmpeg exit with an error and
      // there is no partial video to finalize.
      process.kill();
      await process.exitCode;
      await stderrDone;
      await stdoutDone;
      return (written: written, processed: processed);
    }

    try {
      await process.stdin.close();
    } on Object {
      pipeBroken = true;
    }
    final exitCode = await process.exitCode;
    await stderrDone;
    await stdoutDone;

    // A cancelled run keeps whatever partial video ffmpeg finalized; only a
    // completed run that failed to encode is an error.
    if (!cancelled && (exitCode != 0 || pipeBroken)) {
      final tail = stderrTail.toString().trim();
      final lines = tail.isEmpty
          ? 'no ffmpeg output'
          : (tail.split('\n')..removeWhere((line) => line.trim().isEmpty))
                .reversed
                .take(3)
                .toList()
                .reversed
                .join('\n');
      throw VideoExportException('ffmpeg failed (exit $exitCode): $lines');
    }
    return (written: written, processed: processed);
  }
}

/// The A/V feed of one OS-encoder run: how many video frames have gone
/// in, and how much audio the timeline owes for them.
///
/// 🚨THE TWO CURSORS MOVE TOGETHER. The audio target is read from the
/// written frame count through the SAME `frameToSample` pairing the clock
/// uses, so A and V cannot come to disagree about where a frame sits.
class _OsEncoderFeed {
  _OsEncoderFeed({
    required this.encoder,
    required this.audio,
    required this.frameRate,
  });

  final QaVideoEncoder encoder;
  final ConformPcmStreamReader? audio;
  final ProjectFrameRate frameRate;

  int written = 0;
  int _audioCursor = 0;

  /// Writes [image] and the audio that now owes for it. False means the
  /// encoder refused something and the run is over.
  Future<bool> feed(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) {
      return false;
    }
    if (!encoder.writeFrame(data.buffer.asUint8List())) {
      return false;
    }
    written += 1;
    return _feedAudioUpTo(written);
  }

  bool _feedAudioUpTo(int frames) {
    final reader = audio;
    if (reader == null) {
      return true;
    }
    final target = frameRate.frameToSample(frames, reader.sampleRate);
    while (_audioCursor < target) {
      final window = reader.readWindow(
        _audioCursor,
        math.min(target - _audioCursor, 65536),
      );
      // ⚠️Untested (2026-09-05): the end-to-end encoder test's mix always
      // outlasts its frames, so the pad never fires and mutating it away
      // stays green. It needs a WAV shorter than the video.
      if (window.samples.isEmpty) {
        return _padSilenceTo(target, reader.channels);
      }
      final frameCount = window.samples.length ~/ reader.channels;
      final pcm = Int16List(window.samples.length);
      for (var i = 0; i < window.samples.length; i += 1) {
        // The exact inverse of the WAV decode — see int16FromUnitSample.
        pcm[i] = int16FromUnitSample(window.samples[i]);
      }
      if (!encoder.writeAudio(pcm, frameCount)) {
        return false;
      }
      _audioCursor += frameCount;
    }
    return true;
  }

  /// Past the WAV's end (a cancelled mix, a rounding tail): pad with
  /// silence rather than starving the encoder.
  bool _padSilenceTo(int target, int channels) {
    final missing = target - _audioCursor;
    if (!encoder.writeAudio(Int16List(missing * channels), missing)) {
      return false;
    }
    _audioCursor = target;
    return true;
  }
}
