import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_byte_source.dart';

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
/// 🆕I-14 (2026-09-11) adds the ONE read at the page's own size — a box a
/// person dragged out to cut, billed to the viewer's budget before it is
/// asked for ([ViewerDocument.readRegionRgba]).
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

  /// The STRAIGHT RGBA of a box of page [pageIndex] at the page's OWN size —
  /// one pixel per document unit, which is what the viewer calls 100%. The
  /// box is in those pixels ([viewerPagePixels]) and inside the page.
  ///
  /// 🗣️I-14 (유저 2026-09-11): 「뷰어패널의 잘라내기툴 … 원본크기로
  /// 잘라냄」, and to be sure of it: 「34%의 크기가 스탬프 크기값이 100%이
  /// 되는게 아니라, 제대로 100% 해상도만큼」. So this is the one read that is
  /// NOT at the size on screen — see the ⛔ above for why it may exist.
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  );

  /// Releases whatever the document holds — a native handle, an encoded
  /// buffer, a decoder.
  ///
  /// 🚨Completes only once nothing reads the document's bytes any more: a
  /// reader holding them for it (`ProjectFile.holdMediaBytes`) gives them
  /// back on this, and a save may move them the moment it does.
  Future<void> dispose();
}

/// The open seam tests inject fakes through — handed where the bytes are,
/// exactly as the engine it stands in for would be.
typedef ViewerDocumentOpener =
    Future<ViewerDocument> Function(MediaByteSource source);

/// A page's own size in whole PIXELS — the size
/// [ViewerDocument.readRegionRgba] reads at. PDF points round to the
/// nearest pixel; never below one.
({int width, int height}) viewerPagePixels(ui.Size pageSize) => (
  width: math.max(1, pageSize.width.round()),
  height: math.max(1, pageSize.height.round()),
);

/// [ViewerDocument.readRegionRgba] for a document that can only render a
/// WHOLE page: the page at its own size, then the box out of it.
///
/// ⚠️The whole page is decoded to read any part of it — the price of a codec
/// with no region read (an image's), and why the viewer bills a cut at the
/// page's full size.
Future<Uint8List> readRegionByRenderingPage(
  ViewerDocument document,
  int pageIndex,
  ({int left, int top, int width, int height}) box,
) async {
  final pixels = viewerPagePixels(document.pageSize(pageIndex));
  final page = await document.renderPage(
    pageIndex,
    width: pixels.width,
    height: pixels.height,
  );
  try {
    return await cropImageRgba(page, box);
  } finally {
    page.dispose();
  }
}

/// The straight RGBA of a box of [image], byte for byte: drawn unfiltered
/// onto a picture the box's size, so nothing is resampled.
Future<Uint8List> cropImageRgba(
  ui.Image image,
  ({int left, int top, int width, int height}) box,
) async {
  final (:left, :top, :width, :height) = box;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    ),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()
      ..blendMode = ui.BlendMode.src
      ..filterQuality = ui.FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final ui.Image cropped;
  try {
    cropped = await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
  try {
    final data = await cropped.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      throw StateError('the box could not be read back');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    cropped.dispose();
  }
}

/// The box out of a straight RGBA buffer [sourceWidth] pixels wide, row by
/// row — for a document whose pages already arrive as bytes (a movie's).
Uint8List cropStraightRgba(
  Uint8List rgba, {
  required int sourceWidth,
  required ({int left, int top, int width, int height}) box,
}) {
  final (:left, :top, :width, :height) = box;
  final out = Uint8List(width * height * 4);
  final rowBytes = width * 4;
  for (var row = 0; row < height; row += 1) {
    out.setRange(
      row * rowBytes,
      (row + 1) * rowBytes,
      rgba,
      ((top + row) * sourceWidth + left) * 4,
    );
  }
  return out;
}
