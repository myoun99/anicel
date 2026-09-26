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
class SheetCanvasPanel extends StatefulWidget {
  const SheetCanvasPanel({
    super.key,
    required this.cacheInvalidationSink,
    required this.canvasSize,
    required this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.bottomBarLeading = const <Widget>[],
    this.pageStrip = const <Widget>[],
    this.bottomBarHostToken,
    this.fitFocusRect,
    this.autoFrame,
    this.strokeHold,
    this.brushSwitch,
    required this.drawingOn,
    required this.content,
  });

  final CacheInvalidationSink cacheInvalidationSink;
  final CanvasSize canvasSize;
  final CanvasViewport? viewport;
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;
  final List<Widget> bottomBarLeading;
  final List<Widget> pageStrip;
  final Object? bottomBarHostToken;
  final Rect? fitFocusRect;
  final CanvasAutoFrameRequest? autoFrame;

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

  /// The sheet's strata, laid over the SNAPPED viewport.
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

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final brush = widget.brushSwitch;
    return BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: widget.cacheInvalidationSink,
      canvasSize: widget.canvasSize,
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      // The sheet's ink/header overlays speak zoom/pan only — the paper
      // never rotates (the timesheet's rule; P8 is the drawing canvas's).
      allowViewRotation: false,
      // F-179: a sheet is a printed page on the canvas panel's backdrop.
      hasPasteboard: false,
      bottomBarLeading: [
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
      ],
      pageStrip: widget.pageStrip,
      // The switch is built HERE, so its state joins the host's token here —
      // a host that forgot it would get a switch the memo serves stale.
      // Null stays null: that asks for a bar rebuilt every time.
      bottomBarHostToken: widget.bottomBarHostToken == null
          ? null
          : (widget.bottomBarHostToken, brush?.allowed),
      fitFocusRect: widget.fitFocusRect,
      autoFrame: widget.autoFrame,
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
      contentOverride: (context, rawViewport) => widget.content(
        context,
        renderSnappedViewport(
          rawViewport,
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
