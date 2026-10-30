import '../../models/canvas_size.dart';
import '../../models/rgba_image_bytes.dart' show estimatedImageBytes;
import '../../services/media/viewer_document.dart';
import 'shown_rasters.dart';

/// THE PAGES A SURFACE DRAWS, AS RASTERS — asked of the document one at a
/// time at the scale the view draws them, kept under the device's budget,
/// and a page the document refused asked for again only when a clock says
/// so ([forgetRefusals]).
///
/// 🚨One of these per surface that shows a [ViewerDocument] — the media
/// viewer's, and the import window's preview (import-preview-plays-silent,
/// 2026-09-29: 「뷰어패널이랑 통일할거하면서」). It lived inside the viewer,
/// and a second surface that plays would have been a second copy of it.
///
/// How it holds them is every shown picture's ([ShownRasters]); what is its
/// own is the document it asks, the scale a page is drawn at, and the order
/// a page goes in.
class PageRasters extends ShownRasters<int, double> {
  PageRasters({
    required super.budget,
    required ViewerDocument? Function() document,
    required super.wantedAt,
    required super.rebuild,
    required super.mounted,
    required super.report,
  }) : _document = document,
       super(lastUsed: _byPage);

  /// The document shown — the surface's, asked when a page goes out.
  final ViewerDocument? Function() _document;

  /// The render scale the last build chose. The buffer measures readiness
  /// in the unit the cache is keyed by, and only build knows the zoom —
  /// the timer that asks cannot work it out.
  double? scale;

  /// Pages are wanted alike only behind a run that plays — none is shown
  /// again — and among those the lowest goes first: the farthest behind, as
  /// a run that plays forward left them. ⛔Not who landed first: a page read
  /// by hand before the run would go before the frames the run had just
  /// played (tried 10-10).
  static int _byPage(int page) => page;

  /// Asks the document for [pageIndex] at [at], unless it is cached at
  /// that scale or already asked.
  void ensureRendered(int pageIndex, double at) {
    final document = _document();
    if (document == null) {
      return;
    }
    ask(pageIndex, at, () {
      final CanvasSize(:width, :height) = pagePixelSize(
        document,
        pageIndex,
        at: at,
      );
      return document.renderPage(pageIndex, width: width, height: height);
    });
  }

  /// Makes room for [page] at [at] by letting go of the pages wanted LATER
  /// than [step] ([makeRoom]) — and answers whether it fits.
  bool makeRoomFor(int page, double at, {required int step}) {
    final document = _document();
    if (document == null) {
      return false;
    }
    final CanvasSize(:width, :height) = pagePixelSize(document, page, at: at);
    return makeRoom(estimatedImageBytes(width, height), step: step);
  }

  /// Nothing kept — the document is gone, or draws its pages another way.
  ///
  /// ↩️A change of look kept the picture that was up, HELD OVER until a
  /// page of the new look landed (the export window's preview) — F-315
  /// (유저 2026-10-08) asked for the loading widget in its place.
  @override
  void clear() {
    super.clear();
    scale = null;
  }
}
