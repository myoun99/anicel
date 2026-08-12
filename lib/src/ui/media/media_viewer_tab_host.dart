import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
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
    this.onViewportChanged,
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
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Injectable loose-file picker (tests).
  final Future<String?> Function()? filePicker;

  @override
  State<MediaViewerTabHost> createState() => _MediaViewerTabHostState();
}

/// One lazily rendered PDF page: the raster and the scale it was
/// rendered at (stale-while-revalidate — a wrong-scale image still draws
/// while the right one renders).
class _RenderedPdfPage {
  const _RenderedPdfPage({required this.scale, required this.image});

  final double scale;
  final ui.Image image;
}

class _MediaViewerTabHostState extends State<MediaViewerTabHost> {
  /// Commit sink required by the panel API; the viewer never invalidates
  /// playback caches.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  MediaViewerRequest? get _currentRequest => widget.request.value;

  // Loaded content: exactly one of these families is live.
  List<DecodedImageFrame>? _frames;
  PdfDocumentHandle? _pdf;
  final Map<int, _RenderedPdfPage> _pdfPageCache = {};
  String? _message;

  /// Read-only here — the workspace holds it (see
  /// [MediaViewerTabHost.position]) and [_turnToPage] asks it to move.
  int get _page => widget.position;

  /// Guards every async landing against a newer load.
  int _generation = 0;

  /// Renders in flight, one marker per (page, scale) — landings remove
  /// their own marker, so a stale landing can never wipe a newer one.
  final Set<(int, double)> _pdfRendersInFlight = {};

  /// Token that changes once per successfully LOADED document — drives
  /// the panel's auto-reframe so a preserved deep zoom/pan from the
  /// previous asset can never leave the new one entirely off-screen.
  Object? _loadedToken;

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
    final frames = _frames;
    _frames = null;
    if (frames != null) {
      for (final frame in frames) {
        frame.image.dispose();
      }
    }
    for (final page in _pdfPageCache.values) {
      page.image.dispose();
    }
    _pdfPageCache.clear();
    _pdfRendersInFlight.clear();
    final pdf = _pdf;
    _pdf = null;
    pdf?.dispose();
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
    switch (request.kind) {
      case MediaAssetKind.audio:
      case MediaAssetKind.video:
        setState(() {
          _message = strings.mediaViewerCannotDisplay;
        });
      case MediaAssetKind.image:
        final List<DecodedImageFrame> frames;
        try {
          final bytes = await File(request.path).readAsBytes();
          frames = await decodeImageFrames(bytes);
        } on Object {
          if (mounted && generation == _generation) {
            setState(() {
              _message = strings.mediaViewerLoadFailed;
            });
          }
          return;
        }
        if (!mounted || generation != _generation) {
          for (final frame in frames) {
            frame.image.dispose();
          }
          return;
        }
        setState(() {
          _frames = frames;
          _loadedToken = generation;
        });
      case MediaAssetKind.pdf:
        final PdfDocumentHandle? document;
        try {
          document = await PdfRenderService.open(request.path);
        } on Object {
          if (mounted && generation == _generation) {
            setState(() {
              _message = strings.mediaViewerLoadFailed;
            });
          }
          return;
        }
        if (!mounted || generation != _generation) {
          await document?.dispose();
          return;
        }
        setState(() {
          if (document == null) {
            // The honest-absence state: there is no Dart fallback for a
            // PDF rasterizer, so the panel SAYS so.
            _message = strings.mediaViewerNoPdfRenderer;
          } else {
            _pdf = document;
            _loadedToken = generation;
          }
        });
    }
  }

  // --- PDF lazy rendering (§6-m: the visible page at the current zoom) --

  /// The render scale for [zoom]: powers of two so a settled zoom reuses
  /// its raster, capped so one page never exceeds ~16M pixels.
  double _pdfRenderScaleFor(double zoom, ui.Size pageSize) {
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

  void _ensurePdfPageRendered(int pageIndex, double scale) {
    final pdf = _pdf;
    if (pdf == null) {
      return;
    }
    final cached = _pdfPageCache[pageIndex];
    if (cached != null && cached.scale == scale) {
      return;
    }
    // One marker PER (page, scale): a shared single slot got wiped by
    // whichever render landed first, and the wipe re-issued duplicates
    // of work already queued on PDFium's serial worker.
    if (!_pdfRendersInFlight.add((pageIndex, scale))) {
      return;
    }
    final generation = _generation;
    final pageSize = pdf.pageSize(pageIndex);
    () async {
      final ui.Image image;
      try {
        image = await pdf.renderPage(
          pageIndex,
          width: (pageSize.width * scale).round().clamp(1, 1 << 13).toInt(),
          height: (pageSize.height * scale).round().clamp(1, 1 << 13).toInt(),
        );
      } on Object {
        if (mounted && generation == _generation) {
          setState(() => _pdfRendersInFlight.remove((pageIndex, scale)));
        }
        return;
      }
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _pdfRendersInFlight.remove((pageIndex, scale));
        _pdfPageCache[pageIndex]?.image.dispose();
        _pdfPageCache[pageIndex] = _RenderedPdfPage(scale: scale, image: image);
        // Keep the pages nearest the one on screen, drop the rest (a
        // 100-page conte must not accumulate). Drain in a LOOP excluding
        // the just-landed page: a landing for a page already paged away
        // from is itself the farthest entry, and a single-shot eviction
        // that skipped it ratcheted the cache up scrub after scrub.
        while (_pdfPageCache.length > 4) {
          final farthest = _pdfPageCache.keys
              .where((page) => page != pageIndex)
              .reduce((a, b) => (a - _page).abs() >= (b - _page).abs() ? a : b);
          _pdfPageCache.remove(farthest)?.image.dispose();
        }
      });
    }();
  }

  // --- Paging ------------------------------------------------------------

  int get _pageCount {
    final pdf = _pdf;
    if (pdf != null) {
      return pdf.pageCount;
    }
    final frames = _frames;
    if (frames != null) {
      return frames.length;
    }
    return 0;
  }

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
    widget.onRequestPicked?.call(
      MediaViewerRequest(path: path, kind: kind),
    );
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

    // Document space: the page/frame being shown.
    final pdf = _pdf;
    final frames = _frames;
    ui.Size docSize;
    if (pdf != null && pageCount > 0) {
      docSize = pdf.pageSize(pageIndex);
    } else if (frames != null && frames.isNotEmpty) {
      final image = frames[pageIndex].image;
      docSize = ui.Size(image.width.toDouble(), image.height.toDouble());
    } else {
      docSize = const ui.Size(640, 480);
    }

    // The lazy render for the visible page, at the current zoom's tier.
    ui.Image? pageImage;
    if (pdf != null && pageCount > 0) {
      final zoom = widget.viewport?.zoom ?? 1.0;
      final scale = _pdfRenderScaleFor(zoom, docSize);
      _ensurePdfPageRendered(pageIndex, scale);
      pageImage = _pdfPageCache[pageIndex]?.image;
    } else if (frames != null && frames.isNotEmpty) {
      pageImage = frames[pageIndex].image;
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
      autoFrame: message == null && _loadedToken != null
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
                    paperFill: pdf != null || frames != null,
                    viewport: viewport,
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
  });

  /// The page raster; null draws the paper alone (a PDF page still
  /// rendering).
  final ui.Image? image;

  /// Document space — the image draws scaled INTO this rect, so a
  /// higher-tier PDF raster stays sharp under zoom.
  final ui.Size docSize;

  final bool paperFill;
  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(viewport.panX, viewport.panY);
    canvas.scale(viewport.zoom, viewport.zoom);
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
        oldDelegate.viewport != viewport;
  }
}
