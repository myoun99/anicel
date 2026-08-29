import 'dart:ui' as ui;

/// One open document the viewer can show: how many pages it has, how big
/// one is, and a render of ONE page at exactly the pixels that will be
/// drawn.
///
/// 🚨★★★**ONE SHAPE FOR EVERY MEDIUM — 「보이는 것만, 보이는 해상도로」.**
/// 유저 2026-08-29: 「뷰어쪽 비디오,이미지 이런거 통합 … 최대한 통일하면서」.
///
/// A PDF page, a still image and a video frame are the same request asked
/// of different files, and the viewer used to answer it three ways: PDF
/// through a handle (right), image by reading the whole file and decoding
/// it at ORIGINAL resolution (17× the memory a screen-sized decode needs
/// on an 8000×6000 PNG — 183MB against 10.5MB), and video not at all.
/// Every one of those forks lived in the viewer as `if (pdf) … else if
/// (frames) …`, five times over.
///
/// ⛔The contract is deliberately NOT "give me the picture". It is "give
/// me this page at this size", because the size is the whole point: a
/// caller that could ask for the original would, and the memory the card
/// is about is the memory nobody meant to spend.
///
/// [pageSize] is the page's own size — PDF points, image pixels, video
/// frame pixels. The viewer uses it for layout and for capping the render,
/// never as the size to render at.
abstract class ViewerDocument {
  /// Number of pages (§6-k: 1 page = 1 frame when placed).
  int get pageCount;

  /// How fast this document's pages advance BY THEMSELVES, or null when
  /// they do not — a PDF and a still image are turned by a person, a movie
  /// and an animated GIF are not.
  ///
  /// 🚨It belongs here rather than on the video document because「재생」is
  /// not a video question: an animated GIF plays too, and asking the two
  /// separately is how one of them ends up with a play button and the
  /// other does not.
  double? get framesPerSecond;

  /// One page's natural size; pages of one document may differ.
  ui.Size pageSize(int pageIndex);

  /// Renders page [pageIndex] to exactly [width]×[height] pixels.
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  });

  /// Releases whatever the document holds — a native handle, an encoded
  /// buffer, a decoder.
  Future<void> dispose();
}

/// The open seam tests inject fakes through.
typedef ViewerDocumentOpener = Future<ViewerDocument> Function(String path);
