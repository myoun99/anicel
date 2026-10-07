import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../services/cache_invalidation_executor.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import 'brush_canvas_panel.dart';
import 'canvas_book.dart';

/// [paperView] — a sheet panel's view as it is KEPT, in the paper's pixels
/// — as the sheet's own units read it: a unit is [paperScale] pixels of the
/// paper ([SheetCanvasPanel.paperScale]).
///
/// The one way across, for the panel itself and for a host that reads the
/// view it keeps (the conte's opening page).
CanvasViewport sheetUnitsView(CanvasViewport paperView, double paperScale) =>
    paperScale == 1
    ? paperView
    : paperView.copyWith(zoom: paperView.zoom * paperScale);

/// A PAPER panel: [BrushCanvasPanel] as the sheets mount it — no editing
/// coordinator, no frame keys, a host-local invalidation sink, a view that
/// never rotates, and a viewport snapped ONCE before any stratum reads it.
///
/// ONE recipe for the four sheet panels (the timesheet's paged and gap
/// panels, the conte, the cut envelope), which each typed it out and each
/// carried the P8 decision below. What differs are values: the paper's
/// size, the bars' contents, the fit rect, an auto-frame request, the
/// stroke gate, and the [content] Stack a host lays over the snapped view.
///
/// 🚨★★★THE CANVAS IS THE PAPER'S PIXELS; THE SHEET SPEAKS ITS OWN UNITS
/// (F-294, 유저 2026-10-05: 「타임시트 용지패널 용지크기 너무 작음」 · 「이런
/// 패널들은 사이즈 생각할때 dpi를 기준으로 생각할거야」). A sheet is laid in
/// units of its own — the timesheet's rows, the conte's points — and its
/// paper is a size in PIXELS (`SheetPaper`); [paperScale] is the pixels a
/// unit takes. Everything a host hands in is in its units, and this is the
/// ONE place they become pixels: the canvas the panel shows, where its view
/// stops, what Fit frames, where a turn of the book goes. The view the panel
/// keeps is in pixels — 100% is a pixel of the paper to a pixel of the
/// screen, as on the drawing canvas — and [content] is handed that view as
/// its units read it ([sheetUnitsView]), so no painter, ink window or
/// editor over the sheet knows the paper has a resolution at all.
///
/// ↩️The canvas WAS the sheet's units, one for one: a conte page was a
/// canvas 595 pixels across and a timesheet 1096, and the handwriting kept a
/// pixel a unit was as coarse as that.
///
/// 🚨★★★SNAPPED ONCE, HERE (P8, 유저 답 `host` 2026-08-28).
///
/// The paper below and the ink windows above BOTH derive from
/// this. A painter that snapped for itself and an ink window
/// that snapped for itself would land on the same device grid
/// from different starting values — `round(pan) + zoom*left`
/// versus `round(pan + zoom*left)` — and part company by up to a
/// whole device pixel at fractional pans, which reads as the ink
/// jumping off the box the moment the pen lifts. One value
/// cannot drift from itself.
///
/// Snapped AS THE SHEET'S UNITS READ IT: every painter over the sheet takes
/// the view through `applyViewportTransform`, whose own snap must find
/// nothing left to move — and the phase it snaps to is read off the zoom it
/// is handed.
class SheetCanvasPanel extends StatefulWidget {
  const SheetCanvasPanel({
    super.key,
    required this.cacheInvalidationSink,
    required this.sheetSize,
    this.paperScale = 1,
    required this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.bottomBarLeading = const <Widget>[],
    this.pageStrip = const <Widget>[],
    this.bottomBarHostToken,
    this.fitFocusRect,
    this.unframedFit,
    this.autoFrame,
    required this.viewLimit,
    this.book,
    this.strokeHold,
    this.brushSwitch,
    required this.drawingOn,
    required this.content,
  });

  final CacheInvalidationSink cacheInvalidationSink;

  /// The sheet's whole document — its paper and the margin round it — in
  /// the sheet's own units.
  final Size sheetSize;

  /// The paper's pixels a unit of the sheet takes (F-294). One where the
  /// sheet is laid straight in its paper's pixels — the cut envelope's
  /// form, ruled onto whatever paper it is given.
  final double paperScale;

  /// The view, in the PAPER'S PIXELS — as [viewportController] holds it and
  /// [onViewportChanged] reports it.
  final CanvasViewport? viewport;
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;
  final List<Widget> bottomBarLeading;
  final List<Widget> pageStrip;
  final Object? bottomBarHostToken;
  final Rect? fitFocusRect;

  /// What a view nobody has framed yet is fitted to
  /// ([BrushCanvasPanel.unframedFit]) — the conte's page in its book.
  final Rect? unframedFit;
  final CanvasAutoFrameRequest? autoFrame;

  /// The sheet's paper, where the view stops ([BrushCanvasPanel.viewLimit],
  /// F-201). ⚠️Required, so a sheet cannot forget to say it: null only
  /// for a panel with no paper on it — the timesheet's no-cut gap.
  final Rect? viewLimit;

  /// The sheet's pages and the page its reader is on
  /// ([BrushCanvasPanel.book], F-201).
  final CanvasBook? book;

  /// The sheet's live-stroke hold, raised by its ink windows. The panel
  /// holds navigation on it while [drawingOn], and lets it go when drawing
  /// turns off under the pen.
  final SheetStrokeHold? strokeHold;

  /// Whether this sheet's DRAWING is on — its ink windows are mounted — and
  /// the sheet's answer to [BrushCanvasPanel.runsTheSelectedTool] (F-80).
  ///
  /// ⛔Asked separately from [strokeHold] on purpose. That one says a stroke
  /// is LIVE right now, and reading its NULLNESS as 「this sheet takes no
  /// tool」 made one flag answer two questions (유저 2026-09-16: 「법
  /// 통일할수있을거같은데」).
  final bool drawingOn;

  /// THE SHEET'S BRUSH SWITCH — 「브러시 허용」, at the head of the bar: whether
  /// the brush draws on this sheet (유저 2026-09-25: 「잉크 허용이아니라
  /// 직관적으로 브러시 허용으로 바꾸고, 버튼 법 통일하고, 기본값 off로」).
  ///
  /// ↩️Each sheet host built its own copy of this button — two with English
  /// words pinned in code, one icon for on and another for off (selection
  /// is COLOUR alone here), and the timesheet alone started on. One button
  /// now, one word, and every sheet starts with it off.
  ///
  /// [keyPrefix] names the sheet it sits on (`timesheet`, `conte`,
  /// `envelope`). Null shows no switch — a host with no way to flip it.
  final ({bool allowed, ValueChanged<bool> onChanged, String keyPrefix})?
  brushSwitch;

  /// The sheet's strata, laid over the SNAPPED viewport — the view as the
  /// sheet's units read it.
  final Widget Function(BuildContext context, CanvasViewport viewport) content;

  @override
  State<SheetCanvasPanel> createState() => _SheetCanvasPanelState();
}

class _SheetCanvasPanelState extends State<SheetCanvasPanel> {
  @override
  void didUpdateWidget(covariant SheetCanvasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drawing going off unmounts the ink windows — the pen that was down on
    // one will never be lifted there.
    if (oldWidget.drawingOn && !widget.drawingOn) {
      oldWidget.strokeHold?.releaseAfterFrame();
    }
  }

  /// [rect], of the sheet's units, on the paper's pixels.
  Rect? _onPaper(Rect? rect) {
    final scale = widget.paperScale;
    return rect == null
        ? null
        : Rect.fromLTRB(
            rect.left * scale,
            rect.top * scale,
            rect.right * scale,
            rect.bottom * scale,
          );
  }

  /// The paper's pixels the sheet's whole document takes.
  CanvasSize get _canvasSize => CanvasSize(
    width: (widget.sheetSize.width * widget.paperScale).ceil(),
    height: (widget.sheetSize.height * widget.paperScale).ceil(),
  );

  /// The host's auto-frame request, on the paper's pixels.
  CanvasAutoFrameRequest? get _autoFrameOnPaper {
    final request = widget.autoFrame;
    return request == null
        ? null
        : CanvasAutoFrameRequest(
            token: request.token,
            rect: _onPaper(request.rect)!,
            panOnly: request.panOnly,
          );
  }

  /// The sheet's book, its pages on the paper's pixels — the reader's page
  /// is the host's own notifier still.
  CanvasBook? get _bookOnPaper {
    final book = widget.book;
    return book == null
        ? null
        : CanvasBook(
            pages: book.pages.scaledBy(widget.paperScale),
            reading: book.reading,
          );
  }

  /// The head of the bar: the brush switch, then the host's own commands.
  List<Widget> get _barLeading {
    final brush = widget.brushSwitch;
    return [
      if (brush != null)
        AppIconButton(
          keyValue: '${brush.keyPrefix}-brush-toggle-button',
          tooltip: AppText.strings.sheetBrushAllow,
          icon: const Icon(Icons.brush),
          isSelected: brush.allowed,
          size: AppIconButtonSize.strip,
          onPressed: () => brush.onChanged(!brush.allowed),
        ),
      ...widget.bottomBarLeading,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final scale = widget.paperScale;
    return BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: widget.cacheInvalidationSink,
      canvasSize: _canvasSize,
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      // The sheet's ink/header overlays speak zoom/pan only — the paper
      // never rotates (the timesheet's rule; P8 is the drawing canvas's).
      allowViewRotation: false,
      // F-179 · F-272: a sheet is a printed page — no pasteboard, on black.
      canvasBase: true,
      bottomBarLeading: _barLeading,
      pageStrip: widget.pageStrip,
      // The switch is built HERE, so its state joins the host's token here —
      // a host that forgot it would get a switch the memo serves stale.
      // Null stays null: that asks for a bar rebuilt every time.
      bottomBarHostToken: widget.bottomBarHostToken == null
          ? null
          : (widget.bottomBarHostToken, widget.brushSwitch?.allowed),
      fitFocusRect: _onPaper(widget.fitFocusRect),
      unframedFit: _onPaper(widget.unframedFit),
      autoFrame: _autoFrameOnPaper,
      viewLimit: _onPaper(widget.viewLimit),
      book: _bookOnPaper,
      contentStrokeActive: widget.drawingOn ? widget.strokeHold : null,
      // F-80: a sheet runs the selected tool while its drawing is ON. With
      // it off nothing here can act, so the panel makes a plain primary
      // press pan — one that no control on the sheet has taken (a timesheet
      // head cell, a conte cell) — and one finger pans as the viewer does
      // (I-14).
      oneFingerAction: widget.drawingOn
          ? null
          : CanvasTouchDragAction.navigate,
      runsTheSelectedTool: widget.drawingOn,
      contentOverride: (context, paperView) => widget.content(
        context,
        renderSnappedViewport(
          sheetUnitsView(paperView, scale),
          EffectiveDevicePixelRatio.of(context),
        ),
      ),
    );
  }
}

/// A sheet's LIVE-STROKE HOLD: raised while the pen is down on the sheet's
/// ink. The panel holds navigation on it, and [brushInput] carries it to the
/// session's brush-input hold — the one a canvas stroke raises, which defers
/// seeks and cut switches under the pen (R15-⑤) and keeps the prerender
/// warmer off the frame.
///
/// ↩️ONE for the three sheets. The timesheet and the conte each typed this
/// out — the notifier, the warm-hold listener, the let-go when the brush
/// went off, the let-go on teardown — and the envelope kept the bare
/// notifier and did none of it, so a stroke on a 봉투 neither deferred a cut
/// switch nor held the warmer.
class SheetStrokeHold extends ValueNotifier<bool> {
  SheetStrokeHold({required ValueChanged<bool> brushInput})
    : _brushInput = brushInput,
      super(false) {
    addListener(_tellBrushInput);
  }

  final ValueChanged<bool> _brushInput;
  bool _disposed = false;

  void _tellBrushInput() => _brushInput(value);

  /// Lets go of a stroke whose ink window is gone.
  ///
  /// 🚨AFTER the frame. The sheet learns its drawing went off in the middle
  /// of a build, and this hold's listeners reach widgets outside that build
  /// — the brush-input hold bumps the timeline's cel tint, whose toolbar
  /// rebuilds on it. Letting go right there is the 「setState during build」
  /// red screen R13-4 met when the canvas view did the same.
  void releaseAfterFrame() {
    if (!value) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        value = false;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // Never leak an open brush-input hold through a mid-stroke teardown.
    if (value) {
      _brushInput(false);
    }
    super.dispose();
  }
}
