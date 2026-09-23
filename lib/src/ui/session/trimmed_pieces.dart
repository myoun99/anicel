import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/kept_span.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_engine_abi.dart';
import '../../services/audio/sound_span.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/animated_png_writer.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/movie_span.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/media_staging_store.dart';
import 'session_roles.dart';

/// 🚨★★★**A TRIMMED FILE THAT IS CARRIED BRINGS ONLY ITS SPAN.**
///
/// 유저 2026-09-11: 「자를때 원본 전체만 안들어가고 자른것만 안으로
/// 들어가도록」, answered 2026-09-23 — Q1 「잘라낸 동영상으로 다시 인코딩」,
/// Q2 「조각을 가리킨다 — 원본 경로는 출처로만 남긴다」, and 「비디오든
/// 이미지든 오디오든 관계없이 법 하나로」.
///
/// So the span becomes a PIECE, a file of its own made from the kept frames
/// ([cut]), and the piece — not the original — is what the project carries
/// and what the pool names; the original is only where it came from. Every
/// kind, one law; only how a kind is cut differs:
///  * a movie → MP4 of the frames the project shows, at its pace
///    ([writeMovieSpan])
///  * a sound → WAV of the span in its own time ([soundSpanAsWav])
///  * a PDF → the kept pages as a PDF ([PdfRenderService.pageSpan])
///  * an animated image → APNG of the kept frames ([encodeAnimatedPng])
///
/// ⚠️The piece's ADDRESS is in the staging room, where nothing but this app
/// writes, and while it is being imported a real file stands there — the
/// doors read files, and a piece read through them is imported exactly
/// like any untrimmed carried file. [secure] then holds its bytes the way
/// every carried asset's are held and lets that file go: afterwards the
/// address is what a voice take's is — a name in the pool, bytes in the
/// store, and no second copy anywhere.
class TrimmedPieces {
  TrimmedPieces({
    required MediaStagingStore staging,
    required ProjectAccess project,
    required ProjectFrameRate Function() frameRate,
  }) : _staging = staging,
       _project = project,
       _frameRate = frameRate;

  final MediaStagingStore _staging;
  final ProjectAccess _project;
  final ProjectFrameRate Function() _frameRate;

  /// Test seam: cut on this isolate instead of a worker.
  ///
  /// 🚨A `testWidgets` clock never lets a real isolate finish — the same
  /// reason, and the same shape, as [MediaStagingStore.debugStageInline]:
  /// the same cut runs either way, and [cut] stays async either way.
  /// `flutter_test_config.dart` turns it on for the suite.
  @visibleForTesting
  static bool debugCutInline = false;

  /// Cuts [source]'s kept span — [inFrame] .. [outFrame], null running to
  /// its end — into its piece, and answers the piece's address, with a real
  /// file standing at it for the doors to read until [secure], and how many
  /// frames it keeps; null when this build cannot cut a file of that
  /// [kind].
  ///
  /// ⚠️[frames] is what places it. A sound's length is otherwise read off
  /// its waveform, a bucket at a time, which can come out a frame long — and
  /// the block is exactly the span that was kept.
  Future<({String path, int frames})?> cut(
    String source,
    MediaAssetKind kind, {
    int inFrame = 0,
    int? outFrame,
  }) async {
    // ⚠️Named with the piece's extension already: the OS encoder picks its
    // container from it, and refuses a name that has none.
    final work =
        '${_staging.directoryPath}/${_uniqueName('cutting')}.'
        '${_extensionOf(kind)}';
    Directory(_staging.directoryPath).createSync(recursive: true);
    try {
      final kept = switch (kind) {
        MediaAssetKind.video => await _movie(source, work, inFrame, outFrame),
        MediaAssetKind.audio => await _sound(source, work, inFrame, outFrame),
        MediaAssetKind.pdf => await _pages(source, work, inFrame, outFrame),
        MediaAssetKind.image => await _frames(source, work, inFrame, outFrame),
      };
      if (kept == null) {
        _deleteIfThere(work);
        return null;
      }
      final address = '${_staging.directoryPath}/'
          '${_pieceName(source, kind, kept)}';
      File(work).renameSync(address);
      return (path: address, frames: kept.count);
    } on Object {
      _deleteIfThere(work);
      return null;
    }
  }

  /// Holds [piece]'s bytes like every carried asset's, then lets go of the
  /// file the doors read — the staged copy is the only one left.
  Future<void> secure(String piece) async {
    await _staging.stageCarriedBytes([piece]);
    _deleteIfThere(piece);
  }

  /// Lets go of a piece whose import did not land.
  void discard(String piece) => _deleteIfThere(piece);

  Future<KeptSpan?> _movie(
    String source,
    String work,
    int inFrame,
    int? outFrame,
  ) async {
    final rate = _frameRate();
    final speed = _speed();
    final library = debugQaEngineLibraryPathOverride;
    final written = await _run(() {
      debugQaEngineLibraryPathOverride ??= library;
      return writeMovieSpan(
        sourcePath: source,
        piecePath: work,
        inFrame: inFrame,
        outFrame: outFrame,
        rate: rate,
        speed: speed,
      );
    });
    return written.kept;
  }

  Future<KeptSpan?> _sound(
    String source,
    String work,
    int inFrame,
    int? outFrame,
  ) async {
    final rate = _frameRate();
    final speed = _speed();
    final library = debugQaEngineLibraryPathOverride;
    final cut = await _run(() {
      debugQaEngineLibraryPathOverride ??= library;
      return soundSpanAsWav(
        MediaFileBytes(source),
        inFrame: inFrame,
        outFrame: outFrame,
        rate: rate,
        speed: speed,
      );
    });
    if (cut == null) {
      return null;
    }
    File(work).writeAsBytesSync(cut.wav, flush: true);
    return cut.kept;
  }

  Future<KeptSpan?> _pages(
    String source,
    String work,
    int inFrame,
    int? outFrame,
  ) async {
    final document = await PdfRenderService.open(source);
    if (document == null) {
      return null;
    }
    final int pages;
    try {
      pages = document.pageCount;
    } finally {
      await document.dispose();
    }
    if (pages < 1) {
      return null;
    }
    final kept = KeptSpan(length: pages, inFrame: inFrame, outFrame: outFrame);
    final bytes = await PdfRenderService.pageSpan(
      source,
      first: kept.first,
      count: kept.count,
    );
    if (bytes == null) {
      return null;
    }
    File(work).writeAsBytesSync(bytes, flush: true);
    return kept;
  }

  Future<KeptSpan?> _frames(
    String source,
    String work,
    int inFrame,
    int? outFrame,
  ) async {
    final decoded = await decodeImageFrames(await MediaFileBytes(source).read());
    try {
      if (decoded.isEmpty) {
        return null;
      }
      final kept = KeptSpan(
        length: decoded.length,
        inFrame: inFrame,
        outFrame: outFrame,
      );
      final first = decoded[kept.first].image;
      final frames = <AnimatedPngFrame>[];
      for (var index = kept.first; index <= kept.last; index += 1) {
        final data = await decoded[index].image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) {
          return null;
        }
        frames.add((
          rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          duration: decoded[index].duration,
        ));
      }
      final width = first.width;
      final height = first.height;
      final png = await _run(
        () => encodeAnimatedPng(width: width, height: height, frames: frames),
      );
      File(work).writeAsBytesSync(png, flush: true);
      return kept;
    } finally {
      for (final frame in decoded) {
        frame.image.dispose();
      }
    }
  }

  ({int numerator, int denominator}) _speed() =>
      _project.repository.requireProject().audioSpeed;

  /// `<name>_<in>-<out>.<ext>`, 1-based like the window's own IN/OUT, and
  /// free — of the pool, of the store, and of the room.
  String _pieceName(String source, MediaAssetKind kind, KeptSpan kept) {
    final file = mediaFileName(source);
    final dot = file.lastIndexOf('.');
    final stem = dot <= 0 ? file : file.substring(0, dot);
    final base = '${stem}_${kept.first + 1}-${kept.last + 1}';
    final extension = _extensionOf(kind);
    final taken = {
      for (final asset in _project.repository.requireProject().mediaAssets)
        mediaFileName(asset.path),
    };
    for (var copy = 1; ; copy += 1) {
      final name = copy == 1 ? '$base.$extension' : '${base}_$copy.$extension';
      final address = '${_staging.directoryPath}/$name';
      if (!taken.contains(name) &&
          _staging.find(address) == null &&
          !File(address).existsSync()) {
        return name;
      }
    }
  }

  /// What a piece of [kind] is written as.
  static String _extensionOf(MediaAssetKind kind) => switch (kind) {
    MediaAssetKind.video => 'mp4',
    MediaAssetKind.audio => 'wav',
    MediaAssetKind.pdf => 'pdf',
    MediaAssetKind.image => 'png',
  };

  /// A name nothing else in the room could be using.
  String _uniqueName(String what) =>
      '.$what-${DateTime.now().microsecondsSinceEpoch}';

  static Future<T> _run<T>(T Function() job) =>
      debugCutInline ? Future<T>.sync(job) : Isolate.run(job);

  static void _deleteIfThere(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // Never written, or already gone.
    }
  }
}
