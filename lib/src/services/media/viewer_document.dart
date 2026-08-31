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
/// What an open attempt meant. ⛔`null` used to mean two of these, and the
/// viewer printed the wrong one.
enum ViewerOpenOutcome {
  /// A document is in hand.
  opened,

  /// This build carries no engine for the medium at all. The viewer says so
  /// by name, because a different build is the thing that fixes it.
  noReaderInThisBuild,

  /// The engine is present and refused THIS file — an unsupported container
  /// on this platform, a corrupt header, a stream that is not there.
  unreadable,
}

/// The truth table, apart from any engine, so a test can reach it.
///
/// 🚨A reader that is present and failed is NOT 「no reader」. Collapsing the
/// two is what told an iPad user hunting a codec that their build had no
/// video decoder, while the decoder sat right there refusing an `.mkv`
/// AVFoundation has never read.
ViewerOpenOutcome viewerOpenOutcome({
  required bool hasReader,
  required bool opened,
}) {
  if (!hasReader) {
    return ViewerOpenOutcome.noReaderInThisBuild;
  }
  return opened ? ViewerOpenOutcome.opened : ViewerOpenOutcome.unreadable;
}

/// A document that could not be read, carrying the reason the engine gave.
///
/// ⚠️The reason is the NATIVE decoder's own sentence and is not translated —
/// the same choice `VideoExportException` already makes with the encoder's.
/// It rides UNDER a localized line rather than replacing it, so the reader
/// gets a sentence they know plus a detail they can quote.
class ViewerDocumentException implements Exception {
  const ViewerDocumentException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

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
