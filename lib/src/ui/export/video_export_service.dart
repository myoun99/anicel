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
import '../../services/media/media_byte_source.dart' show MediaFileBytes;
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
///
/// ONE loop walks the frames whichever of the two takes them
/// ([exportVideo]): the first frame that renders says how large the movie
/// is, the first sink that takes a job that size is opened with it
/// ([_openSink]), and every frame after goes into that sink.
class VideoExportService {
  const VideoExportService({
    this.executable = 'ffmpeg',
    this.processStarter = _startProcess,
    this.encoderResolver = _defaultEncoderResolver,
  });

  final String executable;
  final VideoProcessStarter processStarter;
  final VideoEncoderResolver encoderResolver;

  /// How many frames have been read back off the GPU (test hook) — a frame
  /// that is the picture before it is not ([_FramePixels]).
  @visibleForTesting
  static int debugReadbacks = 0;

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
  ///
  /// The container is [outputFilePath]'s: ffmpeg muxes by the extension,
  /// which the export dialog names from the container it was given.
  ///
  /// The frames arrive RAW — [width]×[height] of RGBA, a frame after a
  /// frame with nothing between them, so the size is said here because the
  /// stream cannot say it. ↩️They arrived as PNGs (`image2pipe`): every
  /// frame was deflated here and inflated there for a picture that lives
  /// only as long as the pipe — a cost the OS encoder's road never paid
  /// (F-289, 유저 2026-10-05: 「비디오 출력하는데 너무 느린데? mp4도 느리고
  /// mov의 첫번째 코덱도 느렸음」).
  @visibleForTesting
  static List<String> buildFfmpegArguments({
    required ProjectFrameRate frameRate,
    required String outputFilePath,
    required int width,
    required int height,
    String? audioMixPath,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
  }) {
    final keepAlpha = codec.supportsAlpha && alpha;
    final padFilter =
        'pad=ceil(iw/2)*2:ceil(ih/2)*2:color=${keepAlpha ? 'black@0.0' : 'white'}';
    final video = <String>[
      ..._videoCodecArguments(
        codec: codec,
        keepAlpha: keepAlpha,
        bitrateBps: bitrateBps,
      ),
      '-vf',
      padFilter,
    ];
    final audioCodec = codec.isProRes ? 'pcm_s16le' : 'aac';
    final args = <String>[
      '-y',
      '-f',
      'rawvideo',
      '-pixel_format',
      'rgba',
      '-video_size',
      '${width}x$height',
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

  /// The codec's own half of the argument list: which encoder, which pixel
  /// format, and how the rate is asked for. ProRes carries its profile and
  /// the 10-bit 4:4:4 flavors (alpha only in 4444); the H.26x pair take a
  /// bitrate when one was asked for and a per-codec CRF otherwise.
  static List<String> _videoCodecArguments({
    required ExportVideoCodec codec,
    required bool keepAlpha,
    required int bitrateBps,
  }) => [
    if (codec.isProRes) ...[
      '-c:v',
      'prores_ks',
      '-profile:v',
      '${codec.proresKsProfile}',
      '-vendor',
      'apl0',
      '-pix_fmt',
      if (codec == ExportVideoCodec.prores4444)
        if (keepAlpha) 'yuva444p10le' else 'yuv444p10le'
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
  ];

  /// Walks the [count] frames into the movie at [outputFilePath].
  ///
  /// The movie is the size of the first frame that renders
  /// ([_firstRenderedFrame]), and every frame after it is held to that: a
  /// raw frame of another size would be read at this one by whichever sink
  /// has the run — its pixels sliding across every frame behind it, or
  /// bytes read past its end.
  ///
  /// ↩️Each sink walked the frames for itself, and the OS encoder's walk
  /// rendered the first frame to learn whether the OS would take the job —
  /// so a job it refused (every MOV on Windows) rendered that frame again
  /// for ffmpeg.
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
    if (count <= 0) {
      return (written: 0, processed: 0);
    }
    final probe = await _firstRenderedFrame(
      count: count,
      renderImage: renderImage,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    var processed = probe.processed;
    var index = probe.nextIndex;
    if (probe.cancelled) {
      return (written: 0, processed: processed);
    }
    final first = probe.image;
    if (first == null) {
      // Nothing rendered at all: no frame says how large the movie is, so
      // there is no encoder to open.
      throw const VideoExportException('video export: nothing rendered');
    }
    final width = first.width;
    final height = first.height;
    final _FrameSink sink;
    try {
      sink = await _openSink(
        width: width,
        height: height,
        outputFilePath: outputFilePath,
        frameRate: frameRate,
        audioMixPath: audioMixPath,
        container: container,
        codec: codec,
        alpha: alpha,
        bitrateBps: bitrateBps,
      );
    } on Object {
      first.dispose();
      rethrow;
    }

    /// Ends a run that cannot go on: [why], or what the sink says of it.
    Future<Never> giveUp([String? why]) async {
      final said = await sink.abandon();
      throw VideoExportException(why ?? said);
    }

    if (!await sink.take(first)) {
      await giveUp();
    }
    var cancelled = false;
    while (index < count) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final image = await renderImage(index);
      index += 1;
      if (image != null) {
        if (image.width != width || image.height != height) {
          final size = '${image.width}x${image.height}';
          image.dispose();
          await giveUp(
            'video export: frame $index is $size in a movie of '
            '${width}x$height',
          );
        }
        if (!await sink.take(image)) {
          await giveUp();
        }
      }
      processed += 1;
      onProgress?.call(processed, count);
    }
    await sink.finish(cancelled: cancelled);
    return (written: sink.written, processed: processed);
  }

  /// The FIRST frame that renders, and how far the run got finding it.
  ///
  /// ⚠️Its size is the geometry the encoder opens with, so the search
  /// cannot be skipped: a leading gap renders null and would open the
  /// encoder at nothing. A null [image] with [cancelled] false means the
  /// whole range rendered nothing.
  Future<({ui.Image? image, int nextIndex, int processed, bool cancelled})>
  _firstRenderedFrame({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required void Function(int completed, int total)? onProgress,
    required bool Function()? isCancelled,
  }) async {
    var processed = 0;
    var index = 0;
    while (index < count) {
      if (isCancelled?.call() ?? false) {
        return (
          image: null,
          nextIndex: index,
          processed: processed,
          cancelled: true,
        );
      }
      final image = await renderImage(index);
      index += 1;
      processed += 1;
      onProgress?.call(processed, count);
      if (image != null) {
        return (
          image: image,
          nextIndex: index,
          processed: processed,
          cancelled: false,
        );
      }
    }
    return (
      image: null,
      nextIndex: index,
      processed: processed,
      cancelled: false,
    );
  }

  /// The first sink that takes a movie of [width]×[height]: the OS encoder
  /// when this machine has one and it accepts the job, the ffmpeg pipe
  /// otherwise.
  Future<_FrameSink> _openSink({
    required int width,
    required int height,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    required String? audioMixPath,
    required ExportVideoContainer container,
    required ExportVideoCodec codec,
    required bool alpha,
    required int bitrateBps,
  }) async {
    final encoder = encoderResolver();
    if (encoder != null && encoder.isSupported) {
      // The mix is the WAV the dialog wrote
      // ([ConformPcmStreamReader.overWav16]).
      final audio = audioMixPath == null
          ? null
          : ConformPcmStreamReader.overWav16(MediaFileBytes(audioMixPath));
      if (encoder.open(
        path: outputFilePath,
        width: width,
        height: height,
        fpsNumerator: frameRate.numerator,
        fpsDenominator: frameRate.denominator,
        sampleRate: audio?.sampleRate ?? 0,
        channels: audio?.channels ?? 0,
        container: container.abiValue,
        codec: codec.abiValue,
        alpha: alpha,
        bitrateBps: bitrateBps,
      )) {
        return _OsEncoderFeed(
          encoder: encoder,
          audio: audio,
          frameRate: frameRate,
        );
      }
      // The OS could not take the job (an N-edition Windows with no codec
      // pack, MOV/ProRes on Windows, a refused format) — the ffmpeg pipe
      // below still can.
    }
    final Process process;
    try {
      process = await processStarter(
        executable,
        buildFfmpegArguments(
          frameRate: frameRate,
          outputFilePath: outputFilePath,
          width: width,
          height: height,
          audioMixPath: audioMixPath,
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
    return _FfmpegPipe(process);
  }

  /// Reads the process's stderr into [into], keeping only the TAIL: ffmpeg
  /// logs a lot and only the last lines explain a failure. Never throws —
  /// a stream that dies with the process must not replace the real error.
  static Future<void> _drainStderrTail(
    Process process, {
    required StringBuffer into,
  }) => process.stderr
      .transform(utf8.decoder)
      .forEach((chunk) {
        into.write(chunk);
        const cap = 4000;
        if (into.length > cap * 2) {
          final kept = into.toString();
          into
            ..clear()
            ..write(kept.substring(kept.length - cap));
        }
      })
      .catchError((Object _) {});

  /// The last three non-empty lines of [tail] — what a failed ffmpeg run
  /// says, without the hundred lines of banner in front of it.
  static String _lastLinesOf(StringBuffer tail) {
    final text = tail.toString().trim();
    if (text.isEmpty) {
      return 'no ffmpeg output';
    }
    return (text.split('\n')..removeWhere((line) => line.trim().isEmpty))
        .reversed
        .take(3)
        .toList()
        .reversed
        .join('\n');
  }
}

/// The pixels of the frame a sink took last, read off the GPU in [format].
///
/// 🚨A FRAME THAT IS THE PICTURE BEFORE IT IS NOT READ BACK. The renderer
/// hands such a frame as the SAME image (`ExportFrameRenderer`'s held
/// frames; `ui.Image.isCloneOf`), and one image is one set of bytes — so
/// they go in again as they were read. Nothing here decides that two
/// pictures look alike.
///
/// ↩️Every frame was read back (F-289, measured 2026-10-07: 27 ms a frame
/// of 960×540 beside 5.5 ms for the OS encoder to take it — on a film
/// where four frames in five are the frame before them).
class _FramePixels {
  _FramePixels(this.format);

  final ui.ImageByteFormat format;

  ui.Image? _image;
  Uint8List? _bytes;

  /// [image]'s pixels — and [image] is this's from here on: kept to know
  /// the next frame by, or let go at once when it is the one already kept.
  /// Null when the engine handed nothing back.
  Future<Uint8List?> of(ui.Image image) async {
    final kept = _image;
    if (kept != null && image.isCloneOf(kept)) {
      image.dispose();
      return _bytes;
    }
    kept?.dispose();
    _image = image;
    _bytes = null;
    VideoExportService.debugReadbacks += 1;
    final data = await image.toByteData(format: format);
    return _bytes = data?.buffer.asUint8List();
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _bytes = null;
  }
}

/// Where one run's frames go, once it is known how large they are: the OS
/// encoder ([_OsEncoderFeed]) or the ffmpeg pipe ([_FfmpegPipe]).
///
/// A run ends ONE of two ways — [finish] or [abandon] — so nothing can ask
/// a sink to end a run that both failed and was cancelled.
abstract interface class _FrameSink {
  /// How many frames have gone in.
  int get written;

  /// Takes [image]'s pixels and lets go of it. False means the sink can
  /// take no more; the run is [abandon]ed.
  Future<bool> take(ui.Image image);

  /// Ends a run that reached its end or was [cancelled]: the file is
  /// finalized, and a cancelled run keeps the playable partial it got to.
  /// Throws when the file did not come out and nobody cancelled.
  Future<void> finish({required bool cancelled});

  /// Ends a run that cannot go on, and answers what the sink has to say
  /// about it.
  Future<String> abandon();
}

/// The A/V feed of one OS-encoder run: how many video frames have gone
/// in, and how much audio the timeline owes for them.
///
/// 🚨THE TWO CURSORS MOVE TOGETHER. The audio target is read from the
/// written frame count through the SAME `frameToSample` pairing the clock
/// uses, so A and V cannot come to disagree about where a frame sits.
class _OsEncoderFeed implements _FrameSink {
  _OsEncoderFeed({
    required this.encoder,
    required this.audio,
    required this.frameRate,
  });

  final QaVideoEncoder encoder;
  final ConformPcmStreamReader? audio;
  final ProjectFrameRate frameRate;

  @override
  int written = 0;
  int _audioCursor = 0;

  /// Exactly what the encoder takes: the renderer's own premultiplied
  /// rows.
  final _FramePixels _pixels = _FramePixels(ui.ImageByteFormat.rawRgba);

  /// Writes [image] and the audio that now owes for it. False means the
  /// encoder refused something and the run is over.
  @override
  Future<bool> take(ui.Image image) async {
    final rgba = await _pixels.of(image);
    if (rgba == null) {
      return false;
    }
    if (!encoder.writeFrame(rgba)) {
      return false;
    }
    written += 1;
    return _feedAudioUpTo(written);
  }

  /// A CANCELLED run finalizes a playable partial — the pipe path's
  /// behavior, kept. ⚠️Untested (2026-09-05): nothing cancels the OS path
  /// mid-run yet, so `&& !cancelled` mutates away green.
  @override
  Future<void> finish({required bool cancelled}) async {
    _pixels.dispose();
    if (!encoder.finish() && !cancelled) {
      final detail = encoder.lastError;
      throw VideoExportException(
        detail.isEmpty ? 'video export: the MP4 failed to finalize' : detail,
      );
    }
  }

  /// A failed feed aborts the file.
  @override
  Future<String> abandon() async {
    _pixels.dispose();
    final detail = encoder.lastError;
    encoder.abort();
    return detail.isEmpty ? 'video export: the OS encoder failed' : detail;
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
      // The exact inverse of the WAV decode — see int16FromUnitSample.
      final pcm = int16PcmOf(window.samples);
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

/// One ffmpeg run fed through its stdin: raw frames in, the movie out when
/// the pipe closes.
class _FfmpegPipe implements _FrameSink {
  _FfmpegPipe(this._process) {
    _stderrDone = VideoExportService._drainStderrTail(
      _process,
      into: _stderrTail,
    );
    _stdoutDone = _process.stdout.drain<void>().catchError((Object _) {});
  }

  final Process _process;
  final StringBuffer _stderrTail = StringBuffer();
  late final Future<void> _stderrDone;
  late final Future<void> _stdoutDone;

  @override
  int written = 0;

  /// STRAIGHT alpha, as `rgba` means to ffmpeg — and as the PNGs this pipe
  /// used to carry held it, so a pixel the picture leaves part clear goes
  /// in with the colour it went in with before.
  final _FramePixels _pixels = _FramePixels(
    ui.ImageByteFormat.rawStraightRgba,
  );

  @override
  Future<bool> take(ui.Image image) async {
    try {
      _process.stdin.add((await _pixels.of(image))!);
      await _process.stdin.flush();
      written += 1;
      return true;
    } on Object {
      // ffmpeg died mid-stream (broken pipe); its stderr explains why.
      return false;
    }
  }

  @override
  Future<void> finish({required bool cancelled}) async {
    final ended = await _waitOut();
    // A cancelled run keeps whatever partial video ffmpeg finalized; only a
    // completed run that failed to encode is an error.
    if (!cancelled && (ended.exitCode != 0 || ended.pipeBroken)) {
      throw VideoExportException(_complaintAt(ended.exitCode));
    }
  }

  @override
  Future<String> abandon() async => _complaintAt((await _waitOut()).exitCode);

  /// Closes the pipe and waits ffmpeg out: how it exited, and whether the
  /// pipe was already gone when it was closed.
  Future<({int exitCode, bool pipeBroken})> _waitOut() async {
    _pixels.dispose();
    var pipeBroken = false;
    try {
      await _process.stdin.close();
    } on Object {
      pipeBroken = true;
    }
    final exitCode = await _process.exitCode;
    await _stderrDone;
    await _stdoutDone;
    return (exitCode: exitCode, pipeBroken: pipeBroken);
  }

  String _complaintAt(int exitCode) =>
      'ffmpeg failed (exit $exitCode): '
      '${VideoExportService._lastLinesOf(_stderrTail)}';
}
