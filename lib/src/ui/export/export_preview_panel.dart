import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../native/qa_native_engine.dart';
import '../../services/media/viewer_document.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_pages_painter.dart';
import '../editor_session_manager.dart';
import '../effective_device_pixel_ratio.dart';
import '../media/media_run.dart';
import '../media/page_rasters.dart';
import '../media/viewer_raster_budget.dart';
import '../media/viewer_render_tier.dart';
import '../media/viewer_sound.dart';
import '../widgets/empty_state_text.dart';
import '../widgets/page_turn_strip.dart';
import '../widgets/static_raster.dart';
import '../widgets/transport_bar.dart';
import 'export_preview_document.dart';

/// THE EXPORT WINDOW'S PREVIEW — a canvas-base panel showing the file the
/// window would write.
///
/// 🗣️F-289 (유저 2026-10-06): the preview is the panel the viewer is — its
/// pill (fit, zoom, settings), both scrollbars always, 100% a pixel of the
/// file to a pixel of the screen — and it wears what its document is
/// ([ExportPreviewShape]): 「이 캔버스 베이스패널은 형식에 따라
/// 나누기로하자」. The file's name stands at the picture's lower left
/// whatever the tab (「그냥 제안한대로 동영상뷰어던 뭐던 해당 위치 고정으로
/// 두자」).
///
/// 🚨THE VIEWER'S PAGES AND RUN — the same code, not a second player. The
/// file under preview is a [ViewerDocument] ([ExportPreviewDocument]); its
/// pages are kept by the viewer's cache ([PageRasters]), drawn by the
/// viewer's painter ([ViewportPagesPainter]) and played by the viewer's run
/// ([MediaRun]) — whose wait for a frame that has not landed was written
/// once, there. No sound: a sequence plays silent here.
///
/// ↩️A picture fitted into a well, a scrub bar and two lines of text stood
/// here, each tab's picture rendered to fit one fixed box
/// (`ExportPreviewController`).
class ExportPreviewPanel extends StatefulWidget {
  const ExportPreviewPanel({
    super.key,
    required this.session,
    required this.document,
    required this.page,
    required this.onPage,
    required this.nothingToShow,
    this.range,
    this.fileName,
    this.fileAbsent = false,
    this.enabled = true,
  });

  /// The session the window exports from: the memory census this panel's
  /// pages are counted in, and the warnings they hear.
  final EditorSessionManager session;

  /// The file under preview, or null while the tab has nothing to write.
  final ExportPreviewDocument? document;

  /// The page of it the window stands on.
  final int page;

  /// A hand — or the run — moved to a page.
  final ValueChanged<int> onPage;

  /// What the panel says while there is no document.
  final String nothingToShow;

  /// The span IN/OUT keep, on the one tab that trims.
  final TransportRange? range;

  /// The name the page shown is written under.
  final String? fileName;

  /// Whether [fileName] names a picture the run does not write
  /// ([BrushCanvasPanel.documentAbsent]).
  final bool fileAbsent;

  /// False while an export runs: nothing here turns the picture, which
  /// shows what the run under way is writing.
  final bool enabled;

  @override
  State<ExportPreviewPanel> createState() => ExportPreviewPanelState();
}

class ExportPreviewPanelState extends State<ExportPreviewPanel>
    implements MediaRunSurface {
  /// Where this panel's pages are counted in the memory census
  /// (`RenderCaches.viewerRasterBytesByViewer`).
  static const String _censusKey = 'export-preview';

  /// Commit sink required by the panel API; nothing here is ever edited.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  /// The renders out with the document, for [debugSettle].
  final List<Future<void>> _asks = [];

  late final PageRasters _rasters = PageRasters(
    budget: ViewerRasterBudget(
      physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    ),
    document: () => document,
    distance: (page) => _run.distanceTo(page),
    rebuild: setState,
    mounted: () => mounted,
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[_censusKey] =
            bytes,
  );

  late final MediaRun _run = MediaRun(
    surface: this,
    rasters: _rasters,
    sound: ViewerSound.ofSession(widget.session),
  );

  late int _page = widget.page;

  /// The page whose picture is up — the page stood on once its own has
  /// landed, and until then the one that was up before it.
  ///
  /// A hand running along the track passes frames faster than they render;
  /// the picture stays on the last one drawn rather than going blank
  /// between them, and the transport says which frame is stood on. (A RUN
  /// never shows it: the playhead does not reach a frame that is not
  /// there — [MediaRun].)
  int? _drawn;

  @override
  void initState() {
    super.initState();
    widget.session.memoryPressureTicks.addListener(_onMemoryPressure);
  }

  @override
  void didUpdateWidget(ExportPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.document;
    final now = widget.document;
    final sizeBefore = was?.pageSize(_pageIn(was, _page));
    _page = _pageIn(now, widget.page);
    if (was?.subject != now?.subject || was?.look != now?.look) {
      _heardAnother(
        sameSheet:
            was?.subject == now?.subject &&
            sizeBefore == now?.pageSize(_page),
      );
    }
    if (!widget.enabled && _run.playing) {
      _run.stop();
    }
  }

  /// The document is another one. The SAME SHEET drawn another way — one
  /// subject, a setting changed or another row's drawing stood on, at the
  /// size it was — keeps the picture that is up until the new one lands
  /// ([PageRasters.changedLook]). Another subject, or a sheet of another
  /// size, is another thing to look at, and nothing of the last is kept.
  void _heardAnother({required bool sameSheet}) {
    _run.stop();
    if (sameSheet) {
      _rasters.changedLook(showing: _drawn);
    } else {
      _rasters.clear();
    }
    _drawn = null;
  }

  @override
  void dispose() {
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
    _run.dispose();
    _rasters.clear();
    widget.session.renderCaches.viewerRasterBytesByViewer.remove(_censusKey);
    super.dispose();
  }

  void _onMemoryPressure() => _rasters.heardMemoryPressure(keeping: _page);

  static int _pageIn(ExportPreviewDocument? document, int page) =>
      document == null || document.pageCount <= 0
      ? 0
      : page.clamp(0, document.pageCount - 1);

  // --- The run's surface ([MediaRunSurface]) -------------------------------

  /// The document as the page cache and the run ask it — each render asked
  /// of it remembered until it answers ([debugSettle]).
  @override
  ViewerDocument? get document {
    final shown = widget.document;
    return shown == null ? null : _AskedDocument(shown, _asks);
  }

  @override
  int get page => _page;

  @override
  void turnToPage(int page) {
    final next = _pageIn(widget.document, page);
    if (next == _page) {
      return;
    }
    _page = next;
    widget.onPage(next);
  }

  /// A sequence plays silent here, for now: the design as it was closed on
  /// the card (F-289, 2026-10-06) leaves the preview's sound for later.
  @override
  String? get soundPath => null;

  @override
  ViewerLoudness get loudness => const ViewerLoudness();

  /// Test seam: asks for the page stood on and completes once it has
  /// landed — called inside `tester.runAsync`, where time is real. (A render
  /// asked for under a test's faked clock never answers, so what is out is
  /// turned away and asked again from here.)
  @visibleForTesting
  Future<void> debugSettle() async {
    final scale = _rasters.scale;
    if (widget.document == null || scale == null) {
      return;
    }
    _rasters.turnAway();
    _asks.clear();
    _rasters.ensureRendered(_page, scale);
    while (_asks.isNotEmpty) {
      final out = [..._asks];
      _asks.clear();
      await Future.wait(out);
      // The landing is a turn behind the answer it waits on.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Test seam: the picture drawn, and what stands under it.
  @visibleForTesting
  ({ui.Image? image, bool checkered}) get debugPicture => (
    image: _pictureUp(),
    checkered: widget.document?.opensAlpha ?? false,
  );

  /// The picture that is up: the page's own; until it lands, the last one
  /// drawn ([_drawn]); and across a change of look, the one held over.
  ui.Image? _pictureUp() {
    final own = _rasters.imageOf(_page);
    if (own != null) {
      _drawn = _page;
      return own;
    }
    final drawn = _drawn;
    return (drawn == null ? null : _rasters.imageOf(drawn)) ??
        _rasters.heldOver;
  }

  // --- What the panel wears ------------------------------------------------

  /// The page cluster on the left — a book's.
  List<Widget> _pageStrip(ExportPreviewDocument? document) =>
      document == null || document.shape != ExportPreviewShape.book
      ? const []
      : pageTurnStrip(
          keyPrefix: 'export-preview',
          page: viewerPage(_page, document.pageCount),
          onTurnTo: widget.enabled ? turnToPage : null,
        );

  /// The transport under a document that runs — there whatever its length
  /// (a cut of one frame keeps the rows, with nowhere to go).
  CanvasTransportBand? _transport(
    BuildContext context,
    ExportPreviewDocument? document,
  ) {
    if (document == null || document.shape != ExportPreviewShape.runs) {
      return null;
    }
    final rate = widget.session.projectSettings.projectFrameRate;
    final range = widget.range;
    return CanvasTransportBand(
      height: TransportBar.heightIn(context, range: range != null),
      child: AbsorbPointer(
        absorbing: !widget.enabled,
        child: TransportBar(
          keyPrefix: 'export-transport',
          frameCount: document.pageCount,
          currentFrame: _page,
          playing: _run.playing,
          onSeek: (frame) => _run.seekToFrame(frame, rate),
          onPlayPause: widget.enabled && _run.canPlay ? _run.toggle : null,
          range: range,
        ),
      ),
    );
  }

  /// The page stood on, asked for at the pixels the view shows it at —
  /// never more than the file has (100% is a pixel of the file) — and the
  /// picture that is up meanwhile ([_drawn]).
  List<({Rect rect, ui.Image? image})> _pictures(
    BuildContext context,
    CanvasViewport viewport,
    ExportPreviewDocument document,
  ) {
    final size = document.pageSize(_page);
    final scale = math.min(
      1.0,
      viewerRenderScaleFor(
        CanvasZoomScale.of(context).display(viewport.zoom),
        size,
      ),
    );
    _rasters.scale = scale;
    final up = _pictureUp();
    _rasters.shown = {_page, ?_drawn};
    // ONE ask out at a time, and it is the latest: a hand running along
    // the track passes frames nobody will look at, and every one of them
    // rendered keeps the frame it stops on waiting.
    if (!_rasters.rendering) {
      _rasters.ensureRendered(_page, scale);
    }
    _run.fillBuffer();
    return [(rect: Offset.zero & size, image: up)];
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final paper = document == null
        ? null
        : Offset.zero & document.pageSize(_page);
    final canvas = paper?.size ?? const Size(640, 360);
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
      hasContentToView: document != null,
      pageStrip: _pageStrip(document),
      transport: _transport(context, document),
      documentName: document == null ? null : widget.fileName,
      documentAbsent: widget.fileAbsent,
      contentOverride: (context, viewport) => Stack(
        children: [
          Positioned.fill(
            child: document == null
                ? _nothing()
                : _picture(context, viewport, document),
          ),
        ],
      ),
    );
  }

  /// What the panel says in the picture's place while there is no document.
  Widget _nothing() => Padding(
    padding: const EdgeInsets.all(24),
    child: EmptyStateText(
      widget.nothingToShow,
      key: const ValueKey<String>('export-preview-empty'),
      place: EmptyStatePlace.stage,
    ),
  );

  /// The page, drawn through the view — the viewer's shape: a picture that
  /// changes when it is paged or panned and not otherwise.
  Widget _picture(
    BuildContext context,
    CanvasViewport viewport,
    ExportPreviewDocument document,
  ) => StaticRaster(
    debugLabel: 'export-preview-page',
    child: CustomPaint(
      key: const ValueKey<String>('export-preview-page'),
      painter: ViewportPagesPainter(
        pages: _pictures(context, viewport, document),
        ground: document.opensAlpha
            ? ViewportPageGround.checker
            : ViewportPageGround.none,
        viewport: viewport,
        effectiveRatio: EffectiveDevicePixelRatio.of(context),
      ),
      child: const SizedBox.expand(),
    ),
  );
}

/// A document as it is ASKED: every render asked of it is remembered until
/// it answers, so a test can wait for the pictures
/// ([ExportPreviewPanelState.debugSettle]).
class _AskedDocument implements ViewerDocument {
  const _AskedDocument(this._document, this._asks);

  final ExportPreviewDocument _document;
  final List<Future<void>> _asks;

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
  }) {
    final render = _document.renderPage(
      pageIndex,
      width: width,
      height: height,
    );
    final asked = render.then<void>((_) {}, onError: (Object _) {});
    _asks.add(asked);
    unawaited(asked.whenComplete(() => _asks.remove(asked)));
    return render;
  }

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => _document.readRegionRgba(pageIndex, box);

  @override
  Future<void> dispose() => _document.dispose();
}
