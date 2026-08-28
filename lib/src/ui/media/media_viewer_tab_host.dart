import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../services/media/image_viewer_document.dart';
import '../../services/media/viewer_document.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'media_asset_drag_data.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';

/// What the media viewer is looking at. Owned by the workspace (the
/// dockable-panel view-state rule) so the choice survives tab switches
/// and re-docking.
class MediaViewerRequest {
  const MediaViewerRequest({required this.path, required this.kind, this.name});

  final String path;
  final MediaAssetKind kind;

  /// Display name (the asset's); null falls back to the file name.
  final String? name;

  String get displayName => name ?? mediaAssetDefaultName(path);
}

/// ONE viewer's whole state, owned by the workspace: what it looks at,
/// how far into that document, and where the view sits.
///
/// Two of these exist — the floor's viewer and the sub viewer beside the
/// drawing — and they share NOTHING. Opening a reference in one must
/// never change what the other is showing, which is the entire reason
/// there are two.
class MediaViewerSlot {
  final ValueNotifier<MediaViewerRequest?> request = ValueNotifier(null);

  /// See [MediaViewerTabHost.position] — one slot, whatever the kind.
  final ValueNotifier<int> position = ValueNotifier(0);

  final ValueNotifier<CanvasViewport?> viewport = ValueNotifier(null);

  /// WHICH DOCUMENT the [viewport] above was framed for.
  ///
  /// 🚨★★★It lives up here for the same reason the viewport does. The
  /// reframe used to be keyed on the host State's own load counter, so
  ///「문서 하나당 한 번」 was really 「로드 하나당 한 번」 — and closing the
  /// panel destroys the State, so REOPENING was a new load and the fit ran
  /// again over a view the user had set (유저 2026-08-27: 「확대해두고 패널
  /// 닫고 다시열면 초기화되있음 … 다시 열었을때 이전 배율 그대로 있었다가,
  /// fit으로 초기화되」).
  ///
  /// ⛔A panel-local memory cannot answer 「have I already framed this
  /// document?」, because the panel is exactly what goes away. The slot is
  /// what survives, so the slot is what remembers.
  final ValueNotifier<Object?> framedFor = ValueNotifier(null);

  /// Points this viewer at a document. The position goes back to the
  /// start, because "page 37" of the file you just left means nothing in
  /// the one you just opened.
  ///
  /// A SWAP deliberately does not come through here — it carries each
  /// file's own page across with it (see [swapWith]).
  void open(MediaViewerRequest? next) {
    request.value = next;
    position.value = 0;
  }

  /// Puts back a document the project remembered, at the page it
  /// remembered — the one path that sets a request WITHOUT going back to
  /// the start. Null empties the viewer, which is what a reference the
  /// app can no longer reach comes back as (유저 확정 ⑭: quietly).
  void restore(MediaViewerRequest? request, {int position = 0}) {
    this.request.value = request;
    this.position.value = request == null || position < 0 ? 0 : position;
  }

  /// Trades documents with the other viewer: 유저 확정 ⑪⑯⑰ — the verb is
  /// SWAP and it has no special cases, so trading with an empty viewer
  /// leaves this one empty. A button whose result depends on what the
  /// other side happens to hold is a button nobody can predict.
  ///
  /// The page travels WITH its file (page 37 of the conte is still page
  /// 37 when it lands on the floor). The viewport does not: the two
  /// panels are different widths, so each re-frames what arrives.
  void swapWith(MediaViewerSlot other) {
    final request = this.request.value;
    final position = this.position.value;
    this.request.value = other.request.value;
    this.position.value = other.position.value;
    other.request.value = request;
    other.position.value = position;
  }

  void dispose() {
    request.dispose();
    position.dispose();
    viewport.dispose();
    framedFor.dispose();
  }
}

/// The media viewer PANEL (§6-h, absorbing backlog 11's image viewer):
/// any browsable file — registered asset or one picked on the spot —
/// inside the canvas panel shell, so navigation is the drawing canvas's
/// (wheel zoom, middle-drag pan, panbars, Fit). Images decode once
/// through the import codec; PDFs render LAZILY, the visible page at the
/// current zoom tier (§6-m — a 100-page conte must never pre-render for
/// viewing). No PDF renderer is a stated condition on screen, never a
/// blank page — and images never route through the PDF engine.
class MediaViewerTabHost extends StatefulWidget {
  const MediaViewerTabHost({
    super.key,
    required this.viewerId,
    required this.session,
    required this.request,
    this.position = 0,
    this.onPositionChanged,
    this.onRequestPicked,
    this.onSwapViewers,
    this.onRegisterAsset,
    this.isPathRegistered,
    this.onAssetDropped,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.framedFor,
    this.filePicker,
  });

  /// WHICH viewer this is — the panel's tab id, and the prefix every
  /// widget key in here is built from.
  ///
  /// 🚨 Required, and never spell a key literally below. The app mounts
  /// more than one of these at once (the floor's viewer and the sub
  /// viewer beside the drawing), and a hardcoded key would have both
  /// instances answering the same `find.byKey` — one test finding two
  /// widgets, and no way to say which viewer a test means.
  final String viewerId;

  final EditorSessionManager session;

  /// The workspace-owned "what to view" signal. EVERY open lands here —
  /// a browser double-click, a dropped row, a swap, and the panel's own
  /// file button through [onRequestPicked]. The panel used to keep a
  /// loose file in its own State and prefer it over this one; that made
  /// the panel's own choice the one thing the workspace could neither
  /// remember across a rebuild nor hand to the other viewer.
  final ValueListenable<MediaViewerRequest?> request;

  /// How far into the document — the page of a PDF, the frame of an
  /// animated image. ONE slot, deliberately: a video's paused position
  /// belongs in this same field when video arrives, with only its unit
  /// (a tick rather than a page) decided then. The KIND already says how
  /// to read it.
  ///
  /// Owned above the panel, like the viewport, because a rail group the
  /// user folds away unmounts the panel inside it — and coming back to
  /// page 1 of a hundred-page conte is not "where I was".
  final int position;
  final ValueChanged<int>? onPositionChanged;

  /// Where the panel's own file button puts its answer. Null hides that
  /// button: a viewer with nowhere to put the reply should not ask.
  final ValueChanged<MediaViewerRequest>? onRequestPicked;

  /// Trades documents with the OTHER viewer (유저 확정 ⑪): same button on
  /// both sides, because swapping is symmetric.
  final VoidCallback? onSwapViewers;

  /// Adds the file being viewed to the media pool (유저 확정 ⑱), through
  /// whatever the app's one import does. Offered only for a file that is
  /// not in the pool yet — [isPathRegistered] answers that.
  ///
  /// The point of the button: a loose path is remembered as an absolute
  /// path and breaks on another machine, while a pooled one travels with
  /// the project. This is how a person promotes the first into the
  /// second without going back to the browser to find the file again.
  final ValueChanged<String>? onRegisterAsset;
  final bool Function(String path)? isPathRegistered;

  /// A media-browser row dropped on this panel (유저 확정 ⑬).
  final ValueChanged<MediaAssetDragData>? onAssetDropped;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;

  /// [MediaViewerSlot.framedFor] — the document this viewer's stored view was
  /// framed for. Null in hosts that own no slot; then every load frames, which
  /// is the old behaviour and correct when there is nothing to preserve.
  final ValueNotifier<Object?>? framedFor;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Injectable loose-file picker (tests).
  final Future<String?> Function()? filePicker;

  @override
  State<MediaViewerTabHost> createState() => _MediaViewerTabHostState();
}

/// One lazily rendered page: the raster and the scale it was rendered at
/// (stale-while-revalidate — a wrong-scale image still draws while the
/// right one renders).
class _RenderedPage {
  const _RenderedPage({required this.scale, required this.image});

  final double scale;
  final ui.Image image;
}

class _MediaViewerTabHostState extends State<MediaViewerTabHost> {
  /// Commit sink required by the panel API; the viewer never invalidates
  /// playback caches.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  MediaViewerRequest? get _currentRequest => widget.request.value;

  /// The open document, whatever medium it came from — 🪦there used to be
  /// a `_frames` list AND a `_pdf` handle here, and five places downstream
  /// had to ask which was live. See [ViewerDocument].
  ViewerDocument? _document;
  final Map<int, _RenderedPage> _pageCache = {};
  String? _message;

  /// Read-only here — the workspace holds it (see
  /// [MediaViewerTabHost.position]) and [_turnToPage] asks it to move.
  int get _page => widget.position;

  /// Guards every async landing against a newer load.
  int _generation = 0;

  /// Renders in flight, one marker per (page, scale) — landings remove
  /// their own marker, so a stale landing can never wipe a newer one.
  final Set<(int, double)> _rendersInFlight = {};

  /// Token that changes once per successfully LOADED document — drives
  /// the panel's auto-reframe so a preserved deep zoom/pan from the
  /// previous asset can never leave the new one entirely off-screen.
  Object? _loadedToken;

  /// What identifies the DOCUMENT this viewer is showing — the file it came
  /// from, since that is what「이 문서를 이미 맞춰 놓았나」 has to be asked
  /// about. ⛔Not the page: turning a page inside one document must not
  /// throw away the zoom the user set to read it.
  String? get _documentIdentity => widget.request.value?.path;

  /// Whether the stored view still belongs to some OTHER document — the one
  /// case a fit is right, and the case the original comment was written for
  /// (a deep zoom from a large scan leaving a small next document entirely
  /// off-screen).
  bool get _needsFraming {
    final remembered = widget.framedFor;
    if (remembered == null) {
      return true;
    }
    return remembered.value != _documentIdentity;
  }

  /// Records that this document has been framed, so the next open of the
  /// SAME one leaves the user's view alone. Runs after the frame the
  /// request went out on, because the request is read during build.
  void _rememberFramed() {
    final remembered = widget.framedFor;
    final identity = _documentIdentity;
    if (remembered == null || remembered.value == identity) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        remembered.value = identity;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.request.addListener(_onRequestChanged);
    _load(_currentRequest);
  }

  @override
  void didUpdateWidget(covariant MediaViewerTabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) {
      oldWidget.request.removeListener(_onRequestChanged);
      widget.request.addListener(_onRequestChanged);
      _onRequestChanged();
    }
  }

  @override
  void dispose() {
    widget.request.removeListener(_onRequestChanged);
    _generation += 1;
    _disposeContent();
    super.dispose();
  }

  void _onRequestChanged() => _load(widget.request.value);

  void _disposeContent() {
    for (final page in _pageCache.values) {
      page.image.dispose();
    }
    _pageCache.clear();
    _rendersInFlight.clear();
    final document = _document;
    _document = null;
    document?.dispose();
    _message = null;
  }

  Future<void> _load(MediaViewerRequest? request) async {
    _generation += 1;
    final generation = _generation;
    // The position is NOT reset here. Whoever changes the request decides
    // whether this is a new document (page 1) or the same one arriving
    // again — a swap hands the other viewer's page over with the file,
    // and a remount after a folded-away rail must land where it left.
    // A position past the end of a shorter document reads clamped
    // ([_turnToPage] and the build both clamp), never out of range.
    setState(_disposeContent);
    if (request == null) {
      return; // The empty state reads from _currentRequest == null.
    }
    final strings = AppText.strings;
    // ONE landing for every medium: open a document, or say why not. The
    // three arms this replaces differed only in HOW they opened and in
    // which field they parked the result — the guards against a stale
    // generation, the failure message and the reframe were written three
    // times and had already drifted (the image arm disposed its frames on a
    // stale landing, the PDF arm its handle, and audio had neither).
    final ViewerDocument? document;
    try {
      document = await _openDocument(request);
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _message = strings.mediaViewerLoadFailed);
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await document?.dispose();
      return;
    }
    setState(() {
      if (document == null) {
        // The honest-absence states: audio has no picture to show, and
        // there is no Dart fallback for a PDF rasterizer, so the panel
        // SAYS so rather than showing an empty frame.
        _message = request.kind == MediaAssetKind.pdf
            ? strings.mediaViewerNoPdfRenderer
            : strings.mediaViewerCannotDisplay;
      } else {
        _document = document;
        _loadedToken = generation;
      }
    });
    // The page request goes out on the build this setState causes; the
    // record lands after it, so the NEXT open of this document sees it.
    _rememberFramed();
  }

  /// Opens whatever [request] names, or null when this medium has nothing
  /// to show — the one place that knows which document a kind makes.
  Future<ViewerDocument?> _openDocument(MediaViewerRequest request) async {
    switch (request.kind) {
      case MediaAssetKind.image:
        return ImageViewerDocument.open(request.path);
      case MediaAssetKind.pdf:
        return PdfRenderService.open(request.path);
      case MediaAssetKind.audio:
      case MediaAssetKind.video:
        return null;
    }
  }

  // --- Lazy rendering (§6-m: the visible page at the current zoom) ------

  /// The render scale for [zoom]: powers of two so a settled zoom reuses
  /// its raster, capped so one page never exceeds ~16M pixels.
  double _renderScaleFor(double zoom, ui.Size pageSize) {
    var scale = 1.0;
    while (scale < zoom && scale < 8) {
      scale *= 2;
    }
    const maxPixels = 16 * 1024 * 1024;
    while (scale > 1 &&
        pageSize.width * scale * pageSize.height * scale > maxPixels) {
      scale /= 2;
    }
    return scale;
  }

  void _ensurePageRendered(int pageIndex, double scale) {
    final document = _document;
    if (document == null) {
      return;
    }
    final cached = _pageCache[pageIndex];
    if (cached != null && cached.scale == scale) {
      return;
    }
    // One marker PER (page, scale): a shared single slot got wiped by
    // whichever render landed first, and the wipe re-issued duplicates
    // of work already queued on PDFium's serial worker.
    if (!_rendersInFlight.add((pageIndex, scale))) {
      return;
    }
    final generation = _generation;
    final pageSize = document.pageSize(pageIndex);
    () async {
      final ui.Image image;
      try {
        image = await document.renderPage(
          pageIndex,
          width: (pageSize.width * scale).round().clamp(1, 1 << 13).toInt(),
          height: (pageSize.height * scale).round().clamp(1, 1 << 13).toInt(),
        );
      } on Object {
        if (mounted && generation == _generation) {
          setState(() => _rendersInFlight.remove((pageIndex, scale)));
        }
        return;
      }
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _rendersInFlight.remove((pageIndex, scale));
        _pageCache[pageIndex]?.image.dispose();
        _pageCache[pageIndex] = _RenderedPage(scale: scale, image: image);
        // Keep the pages nearest the one on screen, drop the rest (a
        // 100-page conte must not accumulate). Drain in a LOOP excluding
        // the just-landed page: a landing for a page already paged away
        // from is itself the farthest entry, and a single-shot eviction
        // that skipped it ratcheted the cache up scrub after scrub.
        while (_pageCache.length > 4) {
          final farthest = _pageCache.keys
              .where((page) => page != pageIndex)
              .reduce((a, b) => (a - _page).abs() >= (b - _page).abs() ? a : b);
          _pageCache.remove(farthest)?.image.dispose();
        }
      });
    }();
  }

  // --- Paging ------------------------------------------------------------

  int get _pageCount => _document?.pageCount ?? 0;

  void _turnToPage(int page) {
    final count = _pageCount;
    final next = count <= 0 ? 0 : page.clamp(0, count - 1);
    if (next != _page) {
      widget.onPositionChanged?.call(next);
    }
  }

  Future<void> _pickLooseFile() async {
    final picker =
        widget.filePicker ??
        () async {
          final file = await openFile(
            acceptedTypeGroups: const [FileTypeGroups.viewableMedia],
          );
          return file?.path;
        };
    final path = await picker();
    if (path == null || !mounted) {
      return;
    }
    final kind = mediaAssetKindForPath(path) ?? MediaAssetKind.image;
    widget.onRequestPicked?.call(MediaViewerRequest(path: path, kind: kind));
  }

  /// Whether the file on screen can still be added to the media pool —
  /// false for one already in it, and for nothing at all.
  bool get _canRegister {
    final path = _currentRequest?.path;
    return path != null &&
        widget.onRegisterAsset != null &&
        !(widget.isPathRegistered?.call(path) ?? true);
  }

  void _registerCurrent() {
    final path = _currentRequest?.path;
    if (path == null) {
      return;
    }
    widget.onRegisterAsset?.call(path);
    // The import lands synchronously and this panel does not listen to
    // the session (a viewer that rebuilt on every session notify would
    // be the expensive kind of panel). Ask again ourselves, so the
    // button goes quiet the moment its work is done.
    setState(() {});
  }

  /// Every widget key in this panel, built from [MediaViewerTabHost.viewerId]
  /// — the ONE place the prefix is applied, so a second viewer cannot end
  /// up sharing a key with the first.
  String _key(String suffix) => '${widget.viewerId}-$suffix';

  /// The page cluster, STACKED for the left strip (유저 확정 ⑥) — and empty
  /// unless there is more than one page, because a still image has no pages
  /// to turn and a strip standing there for it would be a permanent
  /// disabled promise.
  ///
  /// ⚠️Up/down rather than left/right: the strip reads vertically, so a
  /// chevron pointing sideways would point at nothing.
  List<Widget> _pageStrip(int pageIndex, int pageCount) {
    if (pageCount <= 1) {
      return const <Widget>[];
    }
    final strings = AppText.strings;
    return [
      AppIconButton(
        keyValue: _key('previous-page-button'),
        tooltip: strings.cnPreviousPage,
        icon: const Icon(Icons.keyboard_arrow_up),
        size: AppIconButtonSize.strip,
        onPressed: pageIndex > 0 ? () => _turnToPage(pageIndex - 1) : null,
      ),
      DragValueLabel(
        keyValue: _key('page-readout'),
        inputKeyValue: _key('page-input'),
        text: '${pageIndex + 1} / $pageCount',
        tooltip: strings.sheetPageDrag,
        width: 30,
        textStyle: const TextStyle(fontSize: 9),
        unitsPerPixel: 1 / 8,
        onDragDelta: (units) => _turnToPage(pageIndex + units.round()),
        onEditSubmit: (text) {
          final parsed = int.tryParse(text.split('/').first.trim());
          if (parsed != null) {
            _turnToPage(parsed - 1);
          }
        },
      ),
      AppIconButton(
        keyValue: _key('next-page-button'),
        tooltip: strings.cnNextPage,
        icon: const Icon(Icons.keyboard_arrow_down),
        size: AppIconButtonSize.strip,
        onPressed: pageIndex < pageCount - 1
            ? () => _turnToPage(pageIndex + 1)
            : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final request = _currentRequest;
    final pageCount = _pageCount;
    final pageIndex = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);

    // Document space: the page/frame being shown. ONE answer now — the
    // document knows its own page size, whether that is PDF points, image
    // pixels or a video frame.
    final document = _document;
    final docSize = document != null && pageCount > 0
        ? document.pageSize(pageIndex)
        : const ui.Size(640, 480);

    // The lazy render for the visible page, at the current zoom's tier.
    //
    // 🚨★★★**IMAGES COME THROUGH HERE NOW.** They used to skip the tier
    // entirely and draw a decode of the ORIGINAL file, which is the 17×
    // the card measured. Nothing about the tier was image-specific — it
    // was only ever written inside an `if (pdf)`.
    ui.Image? pageImage;
    if (document != null && pageCount > 0) {
      // 🚨The tier is chosen from DEVICE coverage, not from the render
      // zoom. The viewer is a document view, so R11 excludes it from the
      // UI scale by DIVIDING its render zoom when the scale goes up — so
      // reading the raw zoom made raising the interface LOWER the tier
      // while the page deliberately stayed the same size on screen: same
      // dimensions, visibly softer, and the only thing the user changed was
      // how big the chrome is.
      final zoom = widget.viewport?.zoom ?? 1.0;
      final scale = _renderScaleFor(
        CanvasZoomScale.of(context).display(zoom),
        docSize,
      );
      _ensurePageRendered(pageIndex, scale);
      pageImage = _pageCache[pageIndex]?.image;
    }

    final message = request == null ? strings.mediaViewerEmpty : _message;

    final panel = BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: CanvasSize(
        width: docSize.width.ceil().clamp(1, 1 << 14).toInt(),
        height: docSize.height.ceil().clamp(1, 1 << 14).toInt(),
      ),
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      // Paper rule: the viewer never rotates the view.
      allowViewRotation: false,
      // Read-only host: a brush-tip cursor over undrawable content is a
      // false affordance.
      toolCursorsEnabled: false,
      // Reframe ONCE per loaded document: the workspace-owned viewport
      // survives asset switches, and a deep zoom/pan from a large scan
      // would otherwise leave a small next document entirely off-screen
      // — a blank panel this viewer promises never to show.
      // 🚨THE TOKEN IS THE DOCUMENT, NOT THE LOAD. It used to be this
      // State's own load counter, and a State dies with the panel — so
      // reopening minted a fresh one and the fit ran again over a view the
      // user had set. What the slot remembers is what makes 「once per
      // document」 true across a close.
      autoFrame: message == null && _loadedToken != null && _needsFraming
          ? CanvasAutoFrameRequest(
              token: _loadedToken!,
              rect: Rect.fromLTWH(0, 0, docSize.width, docSize.height),
            )
          : null,
      // 유저 확정 2026-08-13 (⑤): opening a file is the one verb that stays
      // on the pill. Register and swap are a session's worth of taps
      // between them, and every control that stays costs the pill 44px of
      // budget it then takes from the page navigation on a narrow rail.
      bottomBarLeading: [
        if (widget.onRequestPicked != null)
          AppIconButton(
            keyValue: _key('open-file-button'),
            tooltip: strings.mediaViewerOpenFile,
            icon: const Icon(Icons.file_open_outlined),
            size: AppIconButtonSize.strip,
            onPressed: _pickLooseFile,
          ),
      ],
      pageStrip: _pageStrip(pageIndex, pageCount),
      bottomBarSettings: [
        // Both keep their retired button's key string — the flyout's own
        // convention, so every test that pressed them gains a menu-open
        // tap and nothing else.
        if (widget.onRegisterAsset != null)
          PanelFlyoutItem(
            keyValue: _key('register-asset-button'),
            label: strings.mediaViewerRegisterAsset,
            icon: Icons.playlist_add_outlined,
            enabled: _canRegister,
            onSelected: _registerCurrent,
          ),
        if (widget.onSwapViewers != null)
          PanelFlyoutItem(
            keyValue: _key('swap-button'),
            label: strings.mediaViewerSwap,
            icon: Icons.swap_horiz,
            onSelected: widget.onSwapViewers,
          ),
      ],
      // The register command's enabled state rides this token too — it
      // changes with the file, which is exactly when the answer to "is
      // this one in the pool" can change. ⚠️It has to: the list captures
      // the entries when the BAR is built, not when the list opens.
      bottomBarHostToken: (pageIndex, pageCount, _canRegister),
      fitFocusRect: message == null
          ? Rect.fromLTWH(0, 0, docSize.width, docSize.height)
          : null,
      contentOverride: (context, viewport) => Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          if (message != null)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    message,
                    key: ValueKey<String>(_key('message')),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              // Same shape and same reason as the conte and envelope
              // pages: a light table that changes when you page or pan
              // and not otherwise, which was being re-rastered on every
              // frame the app produced for any reason at all.
              child: StaticRaster(
                debugLabel: _key('page'),
                child: CustomPaint(
                  key: ValueKey<String>(_key('page')),
                  painter: _MediaPagePainter(
                    image: pageImage,
                    docSize: docSize,
                    // PDF paper is opaque white; a transparent image
                    // shows the checker-free paper too — the viewer is a
                    // light table, not a compositor.
                    paperFill: document != null,
                    viewport: viewport,
                    effectiveRatio: EffectiveDevicePixelRatio.of(context),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );

    final surface = ColoredBox(
      key: ValueKey<String>(_key('panel')),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: panel,
    );
    final onAssetDropped = widget.onAssetDropped;
    if (onAssetDropped == null) {
      return surface;
    }
    // 유저 확정 ⑬: a browser row dropped here opens HERE. The rows are
    // already `Draggable<MediaAssetDragData>` for the SE blocks, so this
    // is a second destination for a drag people already do — and it says
    // which viewer with the hand instead of with a menu entry.
    return DragTarget<MediaAssetDragData>(
      onAcceptWithDetails: (details) => onAssetDropped(details.data),
      // ⚠️`surface` is the Stack's UNPOSITIONED child and the highlight is
      // the positioned one, never the other way round: a Stack whose
      // children are ALL positioned takes the smallest size its
      // constraints allow, which in a rail collapsed this whole panel and
      // left its pill sitting on top of its own canvas, unhittable.
      builder: (context, candidate, rejected) => Stack(
        fit: StackFit.expand,
        children: [
          surface,
          if (candidate.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaPagePainter extends CustomPainter {
  const _MediaPagePainter({
    required this.image,
    required this.docSize,
    required this.paperFill,
    required this.viewport,
    required this.effectiveRatio,
  });

  /// The page raster; null draws the paper alone (a PDF page still
  /// rendering).
  final ui.Image? image;

  /// Document space — the image draws scaled INTO this rect, so a
  /// higher-tier PDF raster stays sharp under zoom.
  final ui.Size docSize;

  final bool paperFill;
  final CanvasViewport viewport;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap.
  final double effectiveRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // P8's ONE transform. ⛔The snap already happened at the host, so the
    // ratio here keeps the helper's own snap idempotent.
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
    final docRect = Rect.fromLTWH(0, 0, docSize.width, docSize.height);
    if (paperFill) {
      canvas.drawRect(docRect, Paint()..color = const Color(0xFFFFFFFF));
    }
    final page = image;
    if (page != null) {
      canvas.drawImageRect(
        page,
        Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
        docRect,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MediaPagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.docSize != docSize ||
        oldDelegate.paperFill != paperFill ||
        oldDelegate.viewport != viewport ||
        oldDelegate.effectiveRatio != effectiveRatio;
  }
}
