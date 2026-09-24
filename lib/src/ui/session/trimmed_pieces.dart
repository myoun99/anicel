import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/kept_span.dart';
import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show ProjectClock;
import '../../models/project_frame_rate.dart';
import '../../native/qa_engine_abi.dart';
import '../../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
import '../../services/audio/sound_span.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/animated_png_writer.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/movie_span.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/media_staging_store.dart';
import '../../services/project_lookup.dart' show projectMediaCarryOf;
import 'session_roles.dart';

/// The IN/OUT the window chose for a file — what a [KeptSpan] is made of
/// once the file's own length is known (OUT null for its last frame).
typedef _Trim = ({int inFrame, int? outFrame});

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
/// 🚨The span is measured the way the kind's DOOR measures the file — a
/// movie on the sound's clock, a sound off its conform's peaks, a PDF by its
/// pages, an animation by its frames — so the piece keeps exactly what the
/// untrimmed file would have kept under the same IN/OUT, and what the
/// window showed.
///
/// ⚠️The piece's ADDRESS is in the staging room, where nothing but this app
/// writes, and while it is being imported a real file stands there — the
/// doors read files, and a piece read through them is imported exactly
/// like any untrimmed carried file — the door holds its bytes as it holds
/// every carried file's, and [secure] lets that file go: afterwards the
/// address is what a voice take's is — a name in the pool, bytes in the
/// store, and no second copy anywhere.
class TrimmedPieces {
  TrimmedPieces({
    required MediaStagingStore staging,
    required ProjectAccess project,
    required ProjectFrameRate Function() frameRate,
    required Future<AudioPeaks?> Function(String path) soundPeaks,
  }) : _staging = staging,
       _project = project,
       _frameRate = frameRate,
       _soundPeaks = soundPeaks;

  final MediaStagingStore _staging;
  final ProjectAccess _project;
  final ProjectFrameRate Function() _frameRate;

  /// A sound's length and picture as the project measures it — the
  /// conform's, the one wait the window and the sound's door both take.
  final Future<AudioPeaks?> Function(String path) _soundPeaks;

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
    final trim = (inFrame: inFrame, outFrame: outFrame);
    try {
      final kept = switch (kind) {
        MediaAssetKind.video => await _movie(source, work, trim),
        MediaAssetKind.audio => await _sound(source, work, trim),
        MediaAssetKind.pdf => await _pages(source, work, trim),
        MediaAssetKind.image => await _frames(source, work, trim),
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

  /// Lets go of the file the doors read, once its bytes are held: the door
  /// that placed the piece held them before it landed, as it holds every
  /// carried file's (`ProjectImportDoors._holdCarried`), and the staged
  /// copy is then the only one left.
  ///
  /// ⚠️Only once they ARE held. Staging SKIPS a file it cannot open rather
  /// than throw — one unreadable file must not cost a folder import the
  /// rest — and a piece let go of after a skip would take the only copy of
  /// its bytes with it. Left standing, it is carried the way any carried
  /// file nothing staged is: the save reads it where it is.
  ///
  /// 🪦It staged the bytes itself until the doors did (2026-09-23): a
  /// second answer to 「who holds a placed file's bytes」, and the later
  /// one — it ran after the landing had recorded the piece.
  void secure(String piece) {
    // The carry the landing recorded — a piece's path is fresh, so the pool
    // names exactly one ([projectMediaCarryOf]).
    final carry = projectMediaCarryOf(
      _project.repository.requireProject(),
      piece,
    );
    if (carry != null && _staging.find(carry) != null) {
      _deleteIfThere(piece);
    }
  }

  /// Lets go of a piece whose import did not land.
  void discard(String piece) => _deleteIfThere(piece);

  Future<KeptSpan?> _movie(String source, String work, _Trim trim) async {
    final clock = _clock();
    final library = debugQaEngineLibraryPathOverride;
    final written = await _run(() {
      debugQaEngineLibraryPathOverride ??= library;
      return writeMovieSpan(source, work, trim: trim, clock: clock);
    });
    return written.kept;
  }

  Future<KeptSpan?> _sound(String source, String work, _Trim trim) async {
    final peaks = await _soundPeaks(normalizedMediaPath(source));
    if (peaks == null) {
      return null;
    }
    final clock = _clock();
    final kept = KeptSpan(
      length: peaks.durationFrames(clock.rate),
      inFrame: trim.inFrame,
      outFrame: trim.outFrame,
    );
    final library = debugQaEngineLibraryPathOverride;
    final wav = await _run(() {
      debugQaEngineLibraryPathOverride ??= library;
      return soundSpanAsWav(MediaFileBytes(source), kept, clock);
    });
    if (wav == null) {
      return null;
    }
    File(work).writeAsBytesSync(wav, flush: true);
    return kept;
  }

  Future<KeptSpan?> _pages(String source, String work, _Trim trim) async {
    final document = await PdfRenderService.open(MediaFileBytes(source));
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
    final kept = KeptSpan(
      length: pages,
      inFrame: trim.inFrame,
      outFrame: trim.outFrame,
    );
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

  Future<KeptSpan?> _frames(String source, String work, _Trim trim) async {
    final decoded = await decodeImageFrames(await MediaFileBytes(source).read());
    try {
      if (decoded.isEmpty) {
        return null;
      }
      final kept = KeptSpan(
        length: decoded.length,
        inFrame: trim.inFrame,
        outFrame: trim.outFrame,
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

  /// The project's rate and the speed its sounds play at — how a timed
  /// source's frames fall on the project's.
  ProjectClock _clock() => (
    rate: _frameRate(),
    speed: _project.repository.requireProject().audioSpeed,
  );

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
          !_staging.holdsAnyCopyOf(address) &&
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
