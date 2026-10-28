import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../services/media/viewer_document.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_pages_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../widgets/static_raster.dart';
import 'viewer_page_loading.dart';
import 'viewer_pages_and_run.dart';
import 'viewer_render_tier.dart';

/// A WINDOW'S PREVIEW OF A DOCUMENT — the page stood on, in a canvas-base
/// panel: its pill (fit, zoom, 1:1), both scrollbars always, 100% a pixel
/// of the file to a pixel of the screen; under it a transport where the
/// document runs, a page turner where it is a book.
///
/// 🗣️The export window's preview first (F-289, 유저 2026-10-06), and the
/// import window's on it (F-282 ④, 유저 2026-10-09: 「임포트창 미리보기도
/// 출력창 미리보기 개편한것처럼 공용화된거 쓰는거 잊지말고 재료는 다
/// 있을거야」). ↩️The import window fitted the file into a 16:9 well with no
/// zoom.
///
/// The pages and the run are the surface's ([ViewerPagesAndRun]): it knows
/// the document, the page stood on and the sound. This draws them.
class DocumentPreviewPanel extends StatefulWidget {
  const DocumentPreviewPanel({
    super.key,
    required this.keyPrefix,
    required this.pagesAndRun,
    required this.document,
    required this.page,
    required this.nothing,
    this.ground = ViewportPageGround.none,
    this.transport,
    this.documentName,
    this.documentAbsent = false,
    this.marks,
    this.bottomBarLeading = const <Widget>[],
  });

  /// What this panel's keys are named under — `<prefix>-page`,
  /// `<prefix>-loading`.
  final String keyPrefix;

  /// The surface's pages and run.
  final ViewerPagesAndRun pagesAndRun;

  /// The document shown, or null while there is none.
  final ViewerDocument? document;

  /// The page of it stood on.
  final int page;

  /// What stands in the picture's place while there is no document.
  final Widget nothing;

  /// What stands under the page where it is open — the app's one checker,
  /// or nothing.
  final ViewportPageGround ground;

  /// The band under it — the transport of a document that runs, a book's
  /// page turner ([BrushCanvasPanel.transport]).
  final CanvasTransportBand? transport;

  /// The name the page shown is written under.
  final String? documentName;

  /// Whether [documentName] names a picture nothing writes
  /// ([BrushCanvasPanel.documentAbsent]).
  final bool documentAbsent;

  /// A layer over the page, in the page's own transform — what moves while
  /// the page does not (a sound's playhead), on its own layer so the page's
  /// [StaticRaster] is not baked again on every tick.
  final Widget Function(CanvasViewport viewport, ui.Size page)? marks;

  /// The head of the pill ([BrushCanvasPanel.bottomBarLeading]) — what a
  /// host keeps in its place beside the pictures it shows among papers.
  final List<Widget> bottomBarLeading;

  @override
  State<DocumentPreviewPanel> createState() => _DocumentPreviewPanelState();
}

class _DocumentPreviewPanelState extends State<DocumentPreviewPanel> {
  /// Commit sink required by the panel API; nothing here is ever edited.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  String _key(String suffix) => '${widget.keyPrefix}-$suffix';

  /// The page stood on, asked for at the pixels the view shows it at —
  /// never more than the file has (100% is a pixel of the file) unless it
  /// is drawn at any size ([ViewerDocument.drawnAtAnySize]).
  List<({Rect rect, ui.Image? image})> _pictures(
    BuildContext context,
    CanvasViewport viewport,
    ViewerDocument document,
  ) {
    final rasters = widget.pagesAndRun.rasters;
    final page = widget.page;
    final size = document.pageSize(page);
    final scale = viewerRenderScaleFor(
      CanvasZoomScale.of(context).display(viewport.zoom),
      size,
      drawnAtAnySize: document.drawnAtAnySize,
    );
    rasters.scale = scale;
    final up = rasters.imageOf(page);
    rasters.shown = {page};
    // ONE ask out at a time, and it is the latest: a hand running along
    // the track passes frames nobody will look at, and every one of them
    // rendered keeps the frame it stops on waiting.
    if (!rasters.rendering) {
      rasters.ensureRendered(page, scale);
    }
    widget.pagesAndRun.run.fillBuffer();
    return [(rect: Offset.zero & size, image: up)];
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final paper = document == null
        ? null
        : Offset.zero & document.pageSize(widget.page);
    final canvas = paper?.size ?? const Size(640, 360);
    final marks = widget.marks;
    return BrushCanvasPanel(
      // The panel keeps the view, and a view nobody has framed is a fit of
      // the page ([BrushCanvasPanel.unframedFit]): a page of another size
      // is a panel that has not been framed yet.
      key: ValueKey<Size?>(paper?.size),
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: CanvasSize(
        width: canvas.width.ceil().clamp(1, 1 << 14).toInt(),
        height: canvas.height.ceil().clamp(1, 1 << 14).toInt(),
      ),
      unframedFit: paper,
      fitFocusRect: paper,
      viewLimit: paper,
      // The paper rule: a document is not turned.
      allowViewRotation: false,
      // Nothing here is drawn on: a press moves the page.
      toolCursorsEnabled: false,
      runsTheSelectedTool: false,
      oneFingerAction: CanvasTouchDragAction.navigate,
      canvasBase: true,
      // F-315: the viewer's 1:1, where the viewer keeps it.
      oneToOneOnPill: true,
      hasContentToView: document != null,
      bottomBarLeading: widget.bottomBarLeading,
      transport: widget.transport,
      documentName: document == null ? null : widget.documentName,
      documentAbsent: widget.documentAbsent,
      contentOverride: (context, viewport) => Stack(
        children: [
          Positioned.fill(
            child: document == null
                ? widget.nothing
                : _picture(context, viewport, document),
          ),
          if (document != null && marks != null)
            Positioned.fill(
              child: IgnorePointer(child: marks(viewport, paper!.size)),
            ),
          if (document != null &&
              widget.pagesAndRun.rasters.imageOf(widget.page) == null)
            Positioned.fill(
              child: ViewerPageLoading(key: ValueKey<String>(_key('loading'))),
            ),
        ],
      ),
    );
  }

  /// The page, drawn through the view — the viewer's shape: a picture that
  /// changes when it is paged or panned and not otherwise.
  Widget _picture(
    BuildContext context,
    CanvasViewport viewport,
    ViewerDocument document,
  ) => StaticRaster(
    debugLabel: _key('page'),
    child: CustomPaint(
      key: ValueKey<String>(_key('page')),
      painter: ViewportPagesPainter(
        pages: _pictures(context, viewport, document),
        ground: widget.ground,
        viewport: viewport,
        effectiveRatio: EffectiveDevicePixelRatio.of(context),
      ),
      child: const SizedBox.expand(),
    ),
  );
}
