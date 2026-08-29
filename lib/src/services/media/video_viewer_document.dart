import 'dart:async';
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
/// ⚠️**ONE document at a time.** `QaVideoDecoder` holds a single native
/// document by design (「스크럽하는 프리뷰가 주 용례고 그건 영화 하나를
///본다」), so opening here is also what closes the import preview's. That
/// is a property of the decoder, not a rule invented here — [dispose]
/// closes, and a second open replaces.
final class VideoViewerDocument implements ViewerDocument {
  VideoViewerDocument._(this._info);

  /// Opens [path], or null when this build has no reader for movies — the
  /// viewer turns that into its honest-absence message rather than an
  /// empty frame.
  static Future<VideoViewerDocument?> open(String path) async {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return null;
    }
    final info = decoder.open(path);
    if (info == null) {
      decoder.close();
      return null;
    }
    return VideoViewerDocument._(info);
  }

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
    final decoder = QaVideoDecoder.instance;
    // ⚠️The native reader has no smaller ask: a frame comes out at the
    // movie's size. So the big buffer is TRANSIENT and the decode is what
    // shrinks it — the picture the cache keeps is the one on screen.
    final rgba = decoder?.frame(
      pageIndex,
      width: _info.width,
      height: _info.height,
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

  @override
  Future<void> dispose() async => QaVideoDecoder.instance?.close();
}
