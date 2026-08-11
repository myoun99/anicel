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
import '../widgets/app_icon_button.dart';
import '../widgets/drag_value_label.dart';
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

  /// The workspace-owned "what to view" signal (media browser opens land
  /// here).
  final ValueListenable<MediaViewerRequest?> request;

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

  /// A loose file opened from the panel itself — wins until the next
  /// browser open replaces it.
  MediaViewerRequest? _localRequest;

  MediaViewerRequest? get _currentRequest =>
      _localRequest ?? widget.request.value;

  // Loaded content: exactly one of these families is live.
  List<DecodedImageFrame>? _frames;
  PdfDocumentHandle? _pdf;
  final Map<int, _RenderedPdfPage> _pdfPageCache = {};
  String? _message;

  int _page = 0;

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

  void _onRequestChanged() {
    // A browser open replaces a loose file — latest intent wins.
    _localRequest = null;
    _load(widget.request.value);
  }

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
    setState(() {
      _disposeContent();
      _page = 0;
    });
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
      setState(() => _page = next);
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
    _localRequest = MediaViewerRequest(path: path, kind: kind);
    await _load(_localRequest);
  }

  static void _noDrag(double units) {}

  /// Every widget key in this panel, built from [MediaViewerTabHost.viewerId]
  /// — the ONE place the prefix is applied, so a second viewer cannot end
  /// up sharing a key with the first.
  String _key(String suffix) => '${widget.viewerId}-$suffix';

  List<Widget> _bottomBarLeading(int pageIndex, int pageCount) {
    final strings = AppText.strings;
    final paged = pageCount > 1;
    return [
      AppIconButton(
        keyValue: _key('previous-page-button'),
        tooltip: strings.cnPreviousPage,
        icon: const Icon(Icons.chevron_left),
        onPressed: paged && pageIndex > 0
            ? () => _turnToPage(pageIndex - 1)
            : null,
      ),
      DragValueLabel(
        keyValue: _key('page-readout'),
        inputKeyValue: _key('page-input'),
        text: '${pageCount == 0 ? 0 : pageIndex + 1} / $pageCount',
        tooltip: strings.sheetPageDrag,
        width: 48,
        textStyle: const TextStyle(fontSize: 11),
        unitsPerPixel: 1 / 8,
        onDragDelta: paged
            ? (units) => _turnToPage(pageIndex + units.round())
            : _noDrag,
        onEditSubmit: (text) {
          if (!paged) {
            return;
          }
          final parsed = int.tryParse(text.split('/').first.trim());
          if (parsed != null) {
            _turnToPage(parsed - 1);
          }
        },
      ),
      AppIconButton(
        keyValue: _key('next-page-button'),
        tooltip: strings.cnNextPage,
        icon: const Icon(Icons.chevron_right),
        onPressed: paged && pageIndex < pageCount - 1
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
      bottomBarLeading: [
        AppIconButton(
          keyValue: _key('open-file-button'),
          tooltip: strings.mediaViewerOpenFile,
          icon: const Icon(Icons.file_open_outlined),
          size: AppIconButtonSize.strip,
          onPressed: _pickLooseFile,
        ),
        ..._bottomBarLeading(pageIndex, pageCount),
      ],
      bottomBarLeadingToken: (pageIndex, pageCount),
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

    return ColoredBox(
      key: ValueKey<String>(_key('panel')),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: panel,
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
