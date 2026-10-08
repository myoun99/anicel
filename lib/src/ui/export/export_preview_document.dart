import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../services/media/viewer_document.dart';
import 'offscreen_raster.dart';

/// What the file under preview IS — which is what the panel showing it
/// wears (F-289, 유저 2026-10-06: 「이 캔버스 베이스패널은 형식에 따라
/// 나누기로하자」; of this window: the Sequence and Image tabs stand on the
/// transport, the Conte tab turns its pages on the left, and a cel is one
/// picture).
enum ExportPreviewShape {
  /// It runs in time: the transport's rows stand under it.
  runs,

  /// It turns pages: the page cluster stands on its left.
  book,

  /// One picture, with neither.
  single,
}

/// THE FILE THE WINDOW WOULD WRITE, AS A DOCUMENT — its pages asked for one
/// at a time at the pixels the view draws them, as the viewer asks a file's
/// ([ViewerDocument]: 「보이는 것만, 보이는 해상도로」).
///
/// The export window's preview is a canvas-base panel (F-289), so what it
/// shows is a document like any the viewer opens: the same page cache
/// (`PageRasters`), the same run (`MediaRun`), the same painter. What is the
/// window's own is where a page comes from — [renderAt], the very render
/// the run writes its file through, at a size the view chose.
///
/// A page's own size ([pageSize]) is the size its FILE is written at, so
/// the panel's 100% is a pixel of the file to a pixel of the screen.
class ExportPreviewDocument implements ViewerDocument {
  const ExportPreviewDocument({
    required this.subject,
    required this.look,
    required this.shape,
    required this.pageCount,
    required this.sizeOf,
    required this.renderAt,
    this.framesPerSecond,
    this.opensAlpha = false,
  });

  /// WHAT is under preview — a tab's file, and where it has one, the scope
  /// or the cut it is of. A document of another subject is another thing to
  /// look at, and the panel shows nothing of the last: a picture from
  /// another tab is not to linger under this one's.
  final Object subject;

  /// Everything that decides what a page of this subject looks like — the
  /// pages it holds and each setting their pictures are drawn by. Two
  /// documents of one subject with equal looks draw the same pictures, and
  /// the panel keeps what it has rendered for as long as the look stands.
  final Object look;

  final ExportPreviewShape shape;

  @override
  final int pageCount;

  /// The project's rate for a document that [ExportPreviewShape.runs], and
  /// null for one a hand turns.
  @override
  final double? framesPerSecond;

  /// Whether the file is written with open alpha — its preview stands on
  /// the transparency checker (유저 2026-09-09: 「투명이라는 의미의 체크무늬」).
  final bool opensAlpha;

  /// The pixels page [page]'s file is written at.
  final CanvasSize Function(int page) sizeOf;

  /// Page [page] as its file is written, at [size] — or null for a page
  /// with nothing on it.
  final Future<ui.Image?> Function(int page, CanvasSize size) renderAt;

  @override
  ui.Size pageSize(int pageIndex) {
    final size = sizeOf(pageIndex);
    return ui.Size(size.width.toDouble(), size.height.toDouble());
  }

  /// A page with nothing on it lands as a clear picture: it is a page that
  /// was drawn, and what stands under it shows.
  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async =>
      await renderAt(pageIndex, CanvasSize(width: width, height: height)) ??
      await rasterizeOffscreen(width: 1, height: 1, paint: (_) {});

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => readRegionByRenderingPage(this, pageIndex, box);

  /// Nothing is held: every render's pictures are freed by the render.
  @override
  Future<void> dispose() async {}
}
