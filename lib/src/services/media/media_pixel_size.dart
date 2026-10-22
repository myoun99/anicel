import '../../models/canvas_size.dart';
import '../../models/media_asset.dart';
import '../pdf/pdf_render_service.dart';
import 'held_viewer_document.dart';
import 'image_viewer_document.dart';
import 'media_byte_source.dart';
import 'movie_bytes.dart';
import 'video_decode_worker.dart' show videoDecodeBackend;
import 'viewer_document.dart' show pagePixelSize;

/// The size [path] lands at 1:1 — a picture's own pixels, a movie's frame,
/// a PDF's first page as the renderer draws it 1:1 ([pagePixelSize]) — read
/// from the bytes [hold] answers for it, the project's own copy first. Null
/// for a sound, which has none, and for a file that cannot be read.
///
/// 🚨CHEAP ENOUGH TO ASK OF EVERY ROW of a list (the import window's
/// resolution column, F-375): a picture is read from its header and never
/// decoded ([ImageViewerDocument.sizeOf]), a movie's decoder is opened and
/// shut ([readHeldMovieInfo]), a PDF's document opened and closed.
Future<CanvasSize?> readMediaPixelSize(
  MediaAssetKind kind,
  String path,
  HoldMediaBytes hold,
) async {
  try {
    switch (kind) {
      case MediaAssetKind.image:
        return await readOnHeldBytes(hold, path, ImageViewerDocument.sizeOf);
      case MediaAssetKind.video:
        final info = await readHeldMovieInfo(videoDecodeBackend, hold, path);
        return info == null
            ? null
            : CanvasSize(width: info.width, height: info.height);
      case MediaAssetKind.pdf:
        final document = await openHeldViewerDocument(
          hold,
          path,
          PdfRenderService.open,
        );
        if (document == null) {
          return null;
        }
        try {
          return pagePixelSize(document, 0);
        } finally {
          await document.dispose();
        }
      case MediaAssetKind.audio:
        return null;
    }
  } on Object {
    return null;
  }
}
