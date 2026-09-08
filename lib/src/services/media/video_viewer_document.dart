import 'dart:async';
import 'dart:ui' as ui;

import '../straight_rgba_image.dart';
import '../../native/qa_video_decoder.dart';
import 'video_decode_worker.dart';
import 'viewer_document.dart';

/// A movie, as a [ViewerDocument]: one page per FRAME.
///
/// 유저 2026-08-29: 「비디오 지금 불러오는거 못하니까 불러와서 재생가능하게
/// 하는거나 그런거 통합적으로」. The viewer used to answer a movie with
/// 「표시할 수 없음」 — not because a frame could not be produced (the
/// import preview has drawn them since #1211) but because the viewer had
/// no shape that a movie could be.
///
/// 🚨**A frame IS a page.** Paging, the zoom tier, the render cache and
/// its eviction all work on this without knowing what a movie is, which is
/// the whole reason [ViewerDocument] was worth extracting. Playing is then
/// just turning pages on a timer — the viewer owns that, not this.
///
/// ⚠️**ONE document at a time**, still — the native side holds a single
/// document by design (「스크럽하는 프리뷰가 주 용례고 그건 영화 하나를
/// 본다」). 🪦What this paragraph used to say next was that opening here
/// 「is also what closes the import preview's」, stated as a property to live
/// with. It was a bug: the other consumer's movie went blank with no error.
/// A handle says which movie is whose (#1458), and the DECODE now happens on
/// a worker isolate ([videoDecodeBackend]) rather than on the thread that
/// draws.
final class VideoViewerDocument implements ViewerDocument {
  /// Opens [path]. Returns null when this build has **no reader at all**,
  /// and THROWS when there is a reader that could not read this file.
  ///
  /// 🚨★★★**ONE `null` USED TO ANSWER TWO QUESTIONS.**
  ///
  /// Both arms returned null, and the viewer turns null into 「No video
  /// decoder in this build — movies cannot be shown.」 So opening an `.mkv`
  /// on an iPad — where the decoder is right there and AVFoundation simply
  /// does not read Matroska — told the user to go find a different BUILD.
  /// They would hunt for a codec they already have.
  ///
  /// ⚠️The two states already existed in the caller: [MediaViewerTabHost]
  /// prints the honest-absence message for null and its could-not-read
  /// message for a throw. Nothing there needed inventing; this function was
  /// simply answering the wrong one of the two.
  ///
  /// 🧪The decision is [viewerOpenOutcome] rather than an `if` here, because
  /// a widget test cannot conjure a native decoder — and the truth table is
  /// exactly what went wrong.
  ///
  /// [range] opens a movie that lives INSIDE [path] — a carried video, whose
  /// bytes are a stretch of the `.anicel` and which therefore has no path of
  /// its own. ⛔Never a temp copy: 유저 2026-08-27 「사본 남으면 진짜
  /// 용서안할게」.
  ///
  /// ⚠️A range that this platform cannot open is 「unreadable」, not 「no
  /// reader」 — Windows and Apple refuse a range by name while decoding
  /// paths perfectly well, and telling the user their build has no decoder
  /// would be the exact lie this function was just fixed for.
  static Future<VideoViewerDocument?> open(
    String path, {
    ({int offset, int length})? range,
  }) async {
    // 🚨Through the decode BACKEND, never `QaVideoDecoder` directly: the
    // frames arrive off the UI isolate, which is the difference between a
    // reference movie playing beside a drawing and one that eats a third of
    // every frame's budget. See [videoDecodeBackend].
    final backend = videoDecodeBackend;
    // 🪦This asked `QaVideoDecoder.instance?.isSupported` until 2026-09-08,
    // which is a second object answering for the one that does the work —
    // and it is what made the whole video arm untestable: a fake backend
    // could be injected and then never consulted, because the gate in front
    // of it said no on any machine without the native library.
    final hasReader = backend.supported;
    final opened = hasReader ? await backend.open(path, range: range) : null;
    switch (viewerOpenOutcome(hasReader: hasReader, opened: opened != null)) {
      case ViewerOpenOutcome.noReaderInThisBuild:
        return null;
      case ViewerOpenOutcome.unreadable:
        // The decoders answer WITH A REASON — 「this file has no readable
        // video stream」, 「no decoder for this codec」 — and [lastError] has
        // been documented as saying why since it was written. Nobody read
        // it. The export path already surfaces the encoder's twin
        // (`video_export_service.dart`), so this is the same move.
        final reason = await backend.lastError();
        throw ViewerDocumentException(
          reason.isEmpty ? 'that movie could not be read' : reason,
        );
      case ViewerOpenOutcome.opened:
        return VideoViewerDocument._(backend, opened!.token, opened.info);
    }
  }

  VideoViewerDocument._(this._backend, this._token, this._info);

  final VideoDecodeBackend _backend;
  final int _token;
  final QaVideoInfo _info;

  /// The movie's own frame rate. Null when the file does not state one —
  /// then it is a stack of frames a person turns, which is still useful
  /// and is what the paging strip already does.
  @override
  double? get framesPerSecond =>
      _info.fpsDenominator == 0 || _info.fpsNumerator == 0
      ? null
      : _info.fpsNumerator / _info.fpsDenominator;

  @override
  int get pageCount => _info.frameCount <= 0 ? 0 : _info.frameCount;

  @override
  ui.Size pageSize(int pageIndex) =>
      ui.Size(_info.width.toDouble(), _info.height.toDouble());

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    // ⚠️The native reader has no smaller ask: a frame comes out at the
    // movie's size, so the shrink happens on the way to the picture the
    // cache keeps, which is the one on screen.
    //
    // 🚨The await is the point of the round: the decode happens on the
    // worker, and this isolate is free while it does. A frame measured
    // 14.97 ms at 1080p — more than a third of a 24fps budget — and it used
    // to be spent right here, beside the brush.
    final rgba = await _backend.frame(_token, pageIndex);
    if (rgba == null) {
      throw StateError('frame $pageIndex could not be read');
    }
    final completer = Completer<ui.Image>();
    decodeStraightRgbaImage(
      rgba: rgba,
      width: _info.width,
      height: _info.height,
      targetWidth: width,
      targetHeight: height,
      onDecoded: completer.complete,
    );
    return completer.future;
  }

  /// ⛔Closes only if THIS document is the one loaded. A bare close would
  /// take the import preview's movie with it — the same bug as the silent
  /// replace, wearing the other hat.
  @override
  Future<void> dispose() => _backend.close(_token);
}
