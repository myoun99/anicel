import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_byte_source.dart' show HeldMediaBytes;
import 'viewer_document.dart';

/// A document, and the bytes it reads given back once it has closed.
///
/// 🚨The hold belongs to the READER, not to the document: a document knows
/// only how its medium decodes (유저 2026-09-11: 「파일 뭐든 관계없이 법
/// 하나로」), so the hold rides on the outside of every kind alike.
/// 🪦A movie used to take an `onClosed` of its own for this; a PDF read a
/// window at a time would have been the second to be taught it, and an
/// image the third.
final class HeldViewerDocument implements ViewerDocument {
  HeldViewerDocument(this._document, HeldMediaBytes held)
    : _release = held.release,
      moved = held.moved;

  final ViewerDocument _document;
  final void Function() _release;

  /// When the bytes this document reads have an answer somewhere else now
  /// ([HeldMediaBytes.moved]) — the viewer opens the same request again and
  /// lets this one go.
  final Future<void> moved;

  @override
  int get pageCount => _document.pageCount;

  @override
  double? get framesPerSecond => _document.framesPerSecond;

  @override
  ui.Size pageSize(int pageIndex) => _document.pageSize(pageIndex);

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) => _document.renderPage(pageIndex, width: width, height: height);

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => _document.readRegionRgba(pageIndex, box);

  /// ⛔Given back AFTER the document has closed, never before: a save may
  /// move or remove the bytes the moment they are.
  @override
  Future<void> dispose() async {
    try {
      await _document.dispose();
    } finally {
      _release();
    }
  }
}
