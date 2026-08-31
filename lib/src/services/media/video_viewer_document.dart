import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/straight_rgba_image.dart';
import '../../native/qa_video_decoder.dart';
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
/// ⚠️**ONE document at a time**, still — `QaVideoDecoder` holds a single
/// native document by design (「스크럽하는 프리뷰가 주 용례고 그건 영화
/// 하나를 본다」). 🪦What this paragraph used to say next was that opening
/// here 「is also what closes the import preview's」, stated as a property to
/// live with. It was a bug: the other consumer's movie went blank with no
/// error, and so did this one when theirs opened. The decoder takes a
/// HANDLE now and puts your movie back when somebody else's is loaded —
/// see [QaVideoDecoder.frameOf].
final class VideoViewerDocument implements ViewerDocument {
  VideoViewerDocument._(this._document);

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
    final decoder = QaVideoDecoder.instance;
    final hasReader = decoder != null && decoder.isSupported;
    final document = hasReader ? decoder.openDocument(path, range: range) : null;
    switch (viewerOpenOutcome(hasReader: hasReader, opened: document != null)) {
      case ViewerOpenOutcome.noReaderInThisBuild:
        return null;
      case ViewerOpenOutcome.unreadable:
        // The decoders answer WITH A REASON — 「this file has no readable
        // video stream」, 「no decoder for this codec」 — and [lastError] has
        // been documented as saying why since it was written. Nobody read
        // it. The export path already surfaces the encoder's twin
        // (`video_export_service.dart`), so this is the same move.
        final reason = decoder!.lastError;
        decoder.close();
        throw ViewerDocumentException(
          reason.isEmpty ? 'that movie could not be read' : reason,
        );
      case ViewerOpenOutcome.opened:
        return VideoViewerDocument._(document!);
    }
  }

  final QaVideoDocument _document;

  QaVideoInfo get _info => _document.info;

  /// ONE buffer for the movie, not one per frame — see [QaVideoDecoder.frame].
  /// ⚠️Safe only because every consumer copies it synchronously; holding it
  /// across an await would read the next frame.
  Uint8List? _frameBytes;

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
    final decoder = QaVideoDecoder.instance;
    // ⚠️The native reader has no smaller ask: a frame comes out at the
    // movie's size, so the shrink happens in the DECODE — the picture the
    // cache keeps is the one on screen. The full-size buffer it arrives in
    // is allocated ONCE for the document, not once per frame.
    //
    // 🚨Through the DOCUMENT, so the import window scrubbing a different
    // movie does not turn this one into a still picture with no error.
    final rgba = decoder?.frameOf(
      _document,
      pageIndex,
      into: _frameBytes ??= Uint8List(_info.width * _info.height * 4),
    );
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
  Future<void> dispose() async =>
      QaVideoDecoder.instance?.closeDocument(_document);
}
