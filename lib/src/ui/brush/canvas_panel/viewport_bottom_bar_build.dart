part of '../brush_canvas_panel.dart';

/// ONE BUILD OF THE CANVAS VIEWPORT'S BOTTOM BAR — the view controls
/// (fit, reset, zoom out/in, the zoom readout), the host verbs, the paper
/// / pasteboard / backdrop swatches, and the width budget that decides
/// which of them fold into the flyout.
///
/// 🚨A collaborator carved out of `_CanvasViewportBottomBar` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `build` was 453 lines with seven
/// widget-builder closures inside it, scoring 77 on the meter.
/// Constructed PER BUILD; it reaches the bar through `_bar`.
class _BottomBarBuild {
  _BottomBarBuild(this._bar);

  final _CanvasViewportBottomBar _bar;

  late final ColorScheme _colorScheme;
  late final CanvasZoomScale _zoomScale;
  late final List<PanelFlyoutItem> _hostVerbs;

  late final bool _hasViewControls;
  late final bool _hostVerbsCanUnfold;
  late final List<Widget> _colorControls;
  late final double _colorsWidth;
  late final double _viewControlsWidth;

  Widget build(BuildContext context) {
    _colorScheme = Theme.of(context).colorScheme;
    // Normalized for display: multi-turn accumulation shows as its
    // visible angle.

    // ROTATION/FLIP cluster (UI-R18 #20, left→right): rotate-left, the
    // ALWAYS-ON angle readout (drag = 1°/px, double-tap = type), rotate-
    // right, straighten, flip-H, flip-V. Rotate buttons accent by the
    // rotation SIGN (#18); flips accent while active (#19).
    // Built PER VIEWPORT, not once: these live in the settings list, which
    // is an overlay route the panel's own rebuilds never reach. Handing
    // them the live view is what lets the accent follow the rotation
    // while the list is open — see [PanelFlyoutRow.builder].
    _hasViewControls =
        _bar.onRotateCcw != null ||
        _bar.onRotateByDrag != null ||
        _bar.onRotateCw != null ||
        _bar.onRotateReset != null ||
        _bar.onFlipHorizontal != null ||
        _bar.onFlipVertical != null;

    // THE VIEW CLUSTER (UI-R18 #17/#20, left→right): fit, 1:1, −, the zoom
    // readout (drag = 1%/px, double-tap = type), +.
    //
    // Built one control at a time rather than as a block, because past Fit
    // each of them folds on its own schedule. Fit is the one control with
    // no gesture that replaces it — a runaway view is walked back with Fit
    // or with the panbars, and the panbars are only useful once you can
    // see the paper — so it is the one thing here that never folds.

    // 100% = one artwork pixel per DEVICE pixel (유저 확정 2026-08-21,
    // matching Photoshop/Clip Studio/Krita). The readout is the ONLY place
    // in this file that speaks display units; `onZoomSet` takes the render
    // zoom, as every other zoom verb does.
    _zoomScale = CanvasZoomScale.of(context);

    // THE HOST'S OWN VERBS, unfolded. A flyout item already carries
    // everything a button needs — the key tests hold it by, the label its
    // tooltip wears, its glyph, and whether it is live — so the pill can
    // show the very same verb the gear would list.
    //
    // ⚠️All or nothing. A host that puts a ROW or a header in its settings
    // is describing a list rather than a set of verbs, and half a list on
    // the pill would be a shape nobody asked for; the same goes for an item
    // with no glyph, which has nothing to be a button with.
    _hostVerbs = _bar.hostSettings.whereType<PanelFlyoutItem>().toList();
    _hostVerbsCanUnfold =
        _hostVerbs.isNotEmpty &&
        _hostVerbs.length == _bar.hostSettings.length &&
        _hostVerbs.every((verb) => verb.icon != null);

    // The host's own vocabulary is [AppIconButtonSize.strip] — every host
    // spells its leading controls that way — so a verb that comes out of
    // the gear has to land beside them looking like one of them.

    // R28 #9: the surface colors sit immediately right of the scrollbar
    // ("색 바꾸는 버튼 위치는 밑의 가로스크롤바의 바로오른쪽에"). Both use the
    // shared round-swatch control, so the picker looks and behaves the
    // same here as anywhere else the app asks for a color.
    final onPaper = _bar.onPaperColorChanged;
    final onPasteboard = _bar.onPasteboardColorChanged;
    final onBackdrop = _bar.onBackdropColorChanged;
    _colorControls = <Widget>[
      if (onPaper != null)
        ColorSwatchButton(
          currentColorOf: _bar.currentColorOf,
          keyValue: 'canvas-paper-color-button',
          tooltip: AppText.strings.viewCanvasColor,
          color: _bar.paperColor,
          onChanged: onPaper,
          // F-114: each of the three planes can be absent, and its alpha is
          // real.
          none: _bar.paperNone,
          onNone: _bar.onPaperNone,
          keepsAlpha: true,
        ),
      if (onPasteboard != null) ...[
        const SizedBox(width: 4),
        ColorSwatchButton(
          currentColorOf: _bar.currentColorOf,
          keyValue: 'canvas-pasteboard-color-button',
          tooltip: AppText.strings.viewPasteboardColor,
          color: _bar.pasteboardColor,
          onChanged: onPasteboard,
          none: _bar.pasteboardNone,
          onNone: _bar.onPasteboardNone,
          keepsAlpha: true,
        ),
      ],
      // 제일오른쪽에 배경색 (유저, R3 #4) — outermost swatch for the
      // outermost plane, so the three read out from the paper in the same
      // order they are stacked on screen.
      if (onBackdrop != null) ...[
        const SizedBox(width: 4),
        ColorSwatchButton(
          currentColorOf: _bar.currentColorOf,
          keyValue: 'canvas-backdrop-color-button',
          tooltip: AppText.strings.viewBackdropColor,
          color: _bar.backdropColor,
          // ↩️It was opaque BY CONTRACT here — 「the stage's final answer, and
          // an alpha there would only re-ask the question」 — until F-114 (유저
          // 2026-09-15): 「페이스트보드, 백그라운드 설정에도 동일적용」, 「없음버튼
          // 누르면 없는상태 … 페이스트보드도 백그라운드도 동일하게」. The model
          // stopped forcing the alpha in step (b); this door forced it back.
          // Like the two planes beside it: absent, and a real alpha.
          onChanged: onBackdrop,
          none: _bar.backdropNone,
          onNone: _bar.onBackdropNone,
          keepsAlpha: true,
        ),
      ],
    ];

    // WHAT EACH GROUP COSTS THE PILL. These are the widths of widgets this
    // bar builds itself, so they are read off the widgets rather than
    // budgeted — [_leadingControlBudget] is the guess, and only the host's
    // own controls need one.
    final swatchCount = <Object?>[
      onPaper,
      onPasteboard,
      onBackdrop,
    ].where((handler) => handler != null).length;
    _colorsWidth = swatchCount == 0
        ? 0.0
        : swatchCount * _CanvasViewportBottomBar._swatchWidth +
              (swatchCount - 1) * _CanvasViewportBottomBar._swatchGap;
    _viewControlsWidth =
        (_bar.onRotateCcw != null
            ? _CanvasViewportBottomBar._ownIconWidth
            : 0.0) +
        (_bar.onRotateByDrag != null
            ? _CanvasViewportBottomBar._rotationReadoutWidth
            : 0.0) +
        (_bar.onRotateCw != null
            ? _CanvasViewportBottomBar._ownIconWidth
            : 0.0) +
        (_bar.onRotateReset != null
            ? _CanvasViewportBottomBar._ownIconWidth
            : 0.0) +
        (_bar.onFlipHorizontal != null
            ? _CanvasViewportBottomBar._ownIconWidth
            : 0.0) +
        (_bar.onFlipVertical != null
            ? _CanvasViewportBottomBar._ownIconWidth
            : 0.0);

    // Non-empty clusters _joined by hairlines — so a host that supplies no
    // leading controls (or a rotation-disabled host with no view controls)
    // never shows a _divider with nothing on one side.

    // THE PILL, and there is no longer a second shape. It has no scrollbar
    // to stretch — those float on the panel's own edges — so it is as wide
    // as what it holds, and FOLDS clusters into the gear rather than
    // scrolling when the panel cannot pay for them (띠는 스크롤하지 않는다: a
    // scrolling strip hands drags to its scroll arena before its children
    // ever see them).
    return SizedBox(
      height: _CanvasViewportBottomBar.height,
      child: LayoutBuilder(builder: _layout),
    );
  }

  /// What the settings flyout lists for this fold: the host's own
  /// settings when its verbs are folded, then every control the width
  /// budget folded away — reset, the zoom steps, the view controls, the
  /// colour swatches.
  List<PanelFlyoutEntry> _settingsEntries(_PillFold fold) {
    return <PanelFlyoutEntry>[
      // The host's own verbs first: they are about the DOCUMENT, and
      // everything below is about looking at it.
      if (_bar.hostSettings.isNotEmpty && !fold.showHostVerbs) ...[
        ..._bar.hostSettings,
        const PanelFlyoutDivider(),
      ],
      if (!fold.showReset)
        PanelFlyoutItem(
          keyValue: 'canvas-viewport-reset',
          label: AppText.strings.viewResetView,
          icon: Icons.crop_free,
          onSelected: _bar.onReset,
        ),
      // ⛔Only where they exist to begin with. A panel that is not on
      // the floor has no zoom steps at any width — they are the
      // floor's, and listing them here would hand every rail panel
      // two controls it never had.
      if (_bar.onFloor && !fold.showZoomSteps) ...[
        PanelFlyoutItem(
          keyValue: 'canvas-viewport-zoom-out',
          label: editorActionLabel(EditorActionIds.canvasZoomOut),
          shortcuts: const [EditorActionIds.canvasZoomOut],
          icon: Icons.zoom_out,
          onSelected: _bar.onZoomOut,
        ),
        PanelFlyoutItem(
          keyValue: 'canvas-viewport-zoom-in',
          label: editorActionLabel(EditorActionIds.canvasZoomIn),
          shortcuts: const [EditorActionIds.canvasZoomIn],
          icon: Icons.zoom_in,
          onSelected: _bar.onZoomIn,
        ),
      ],
      // Asked as a PREDICATE, not by building the row and measuring
      // it: the row is six tooltipped buttons and this runs on every
      // bar build, so "is there anything to show" was costing a
      // throwaway widget list.
      if (_hasViewControls && !fold.showViewControls) ...[
        const PanelFlyoutDivider(),
        PanelFlyoutRow(
          keyValue: 'canvas-settings-view-row',
          listenable: _bar.liveViewport,
          builder: (_) => Row(
            mainAxisSize: MainAxisSize.min,
            children: _viewControlsFor(
              _zoomScale.fromDevice(
                _bar.liveViewport.value ?? CanvasViewport(),
              ),
            ),
          ),
        ),
      ],
      if (_colorControls.isNotEmpty && !fold.showColors) ...[
        const PanelFlyoutDivider(),
        PanelFlyoutRow(
          keyValue: 'canvas-settings-color-row',
          builder: (_) =>
              Row(mainAxisSize: MainAxisSize.min, children: _colorControls),
        ),
      ],
    ];
  }

  /// The bar for the room it was given: the fold decides which controls
  /// stay on the pill and which go to the flyout, and a bare pill drops
  /// the leading controls too.
  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final room = constraints.maxWidth;
    // EVERY threshold pays for the host's own controls first. They
    // are the panel's reason for having a pill at all — the page you
    // are on, the sheet you are reading — so the view controls fold
    // around them rather than the other way round. The bar cannot
    // measure widgets it did not build, so it budgets generously:
    // over-budgeting folds a little early, under-budgeting OVERFLOWS
    // onto the artwork, which is what a narrow rail did.
    final owed =
        _bar.leading.length * _CanvasViewportBottomBar._leadingControlBudget;

    // What is out at this width — the fold ladder, as a value.
    final fold = _PillFold.fit(
      room: room,
      owed: owed,
      onFloor: _bar.onFloor,
      hasLeading: _bar.leading.isNotEmpty,
      colorsWidth: _colorsWidth,
      hasViewControls: _hasViewControls,
      viewControlsWidth: _viewControlsWidth,
      hostVerbsCanUnfold: _hostVerbsCanUnfold,
      hostVerbCount: _hostVerbs.length,
      hostSettingsListed: _bar.hostSettings.isNotEmpty,
    );
    // Last of all the host's controls go too — but Fit never does.
    // With the docked bar gone this is its only home, and a panel
    // narrow enough to lose it is exactly the panel that needs it.
    //
    // ⚠️This threshold has to budget `owed` like the others. It did
    // not, and that left a band — measured at 206..250px of rail —
    // where the pill kept all seven of the timesheet's controls and
    // then pushed Fit out past the capsule's own clip: invisible and
    // unhittable, in the one panel width the comment above promises
    // it to. Below 206 `bare` finally tripped and it came back, so
    // the button blinked out and in as the rail was dragged.
    final bare =
        room <
        _bar.leading.length * _CanvasViewportBottomBar._leadingControlFloor +
            _CanvasViewportBottomBar._essentialBudget;

    // THE GEAR'S LIST: what folded, and nothing else. It builds on
    // the app's ONE popup shell rather than a surface of its own; see
    // [PanelFlyoutRow] for why that is not a detail.
    //
    // Items keep the key string of the button they stand in for,
    // which is the flyout's own convention — a test that pressed 1:1
    // gains a menu-open tap and nothing else.
    final settingsEntries = _settingsEntries(fold);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 4),
        ..._joined([
          <Widget>[
            if (!bare) ..._bar.leading,
            if (fold.showHostVerbs) ..._hostVerbButtons(),
          ],
          <Widget>[
            _fitButton(),
            if (fold.showReset) _resetButton(),
            if (fold.showZoomSteps) _zoomOutButton(),
            if (!fold.cramped) _zoomReadout(),
            if (fold.showZoomSteps) _zoomInButton(),
          ],
          if (fold.showViewControls)
            <Widget>[
              // INLINE, so it has to follow the view on its own. The
              // memo token deliberately does not carry rotation — it
              // left with these controls the day they moved into the
              // list — and putting it back would throw the whole pill
              // away on every frame of a rotate drag. The slice is
              // the three values the accents and the readout read.
              SlicedValueListenableBuilder<
                CanvasViewport?,
                (double, bool, bool)
              >(
                valueListenable: _bar.liveViewport,
                // ⚠️`null` is "not framed yet", and the identity it
                // resolves to has no rotation or flip — so the slice
                // is the same three values either way.
                slice: (view) => (
                  view?.rotationDegrees ?? 0,
                  view?.flipHorizontal ?? false,
                  view?.flipVertical ?? false,
                ),
                builder: (_, view) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _viewControlsFor(
                    _zoomScale.fromDevice(view ?? CanvasViewport()),
                  ),
                ),
              ),
            ],
          if (fold.showColors) _colorControls,
          // The gear NEVER folds — it is the only way to what is
          // inside it, so a width that dropped it would take the
          // rotate, the flip and the surface colours with it and say
          // nothing about where they went. It is simply not there
          // when nothing has folded.
          if (fold.anythingFolded)
            <Widget>[
              PanelFlyoutTrigger(
                key: const ValueKey<String>('canvas-viewport-settings'),
                tooltip: AppText.strings.panelSettings,
                padding: const EdgeInsets.all(6),
                entriesBuilder: () => settingsEntries,
                child: const Icon(Icons.tune, size: 16),
              ),
            ],
        ]),
        const SizedBox(width: 4),
      ],
    );
  }

  int _rotationDegreesOf(CanvasViewport v) =>
      (((v.rotationDegrees + 180) % 360) - 180).round();

  Widget _divider() => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: _colorScheme.outlineVariant,
  );

  List<Widget> _viewControlsFor(CanvasViewport viewport) {
    final rotationDegrees = _rotationDegreesOf(viewport);
    return <Widget>[
      if (_bar.onRotateCcw != null) _rotateCcwButton(rotationDegrees),
      if (_bar.onRotateByDrag != null)
        DragValueLabel(
          keyValue: 'canvas-viewport-rotation-label',
          text: '$rotationDegrees°',
          tooltip: AppText.strings.viewAngleDrag,
          width: 40,
          textStyle: const TextStyle(fontSize: 11),
          onDragDelta: _bar.onRotateByDrag!,
          onEditSubmit: (text) {
            final parsed = double.tryParse(text);
            if (parsed != null && _bar.onRotateByDrag != null) {
              _bar.onRotateByDrag!(parsed - viewport.rotationDegrees);
            }
          },
        ),
      if (_bar.onRotateCw != null) _rotateCwButton(rotationDegrees),
      if (_bar.onRotateReset != null)
        _bar._barIconButton(
          keyValue: 'canvas-viewport-rotate-reset',
          tooltip: AppText.strings.viewStraighten,
          icon: const Icon(Icons.refresh),
          onPressed: _bar.onRotateReset,
        ),
      if (_bar.onFlipHorizontal != null) _flipHorizontalButton(viewport),
      if (_bar.onFlipVertical != null)
        _bar._barIconButton(
          keyValue: 'canvas-viewport-flip-vertical',
          tooltip: AppText.strings.viewFlipVertical,
          icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
          onPressed: _bar.onFlipVertical,
          isSelected: viewport.flipVertical,
        ),
    ];
  }

  // R, Shift+R and H press these three (I-19), so each names its action —
  // the same one-button-one-method shape as the fit, 1:1 and zoom buttons.
  Widget _rotateCcwButton(int rotationDegrees) => _bar._barIconButton(
    keyValue: 'canvas-viewport-rotate-ccw',
    tooltip: AppText.strings.viewRotateLeft,
    shortcuts: const [EditorActionIds.canvasRotateCcw],
    icon: const Icon(Icons.rotate_left),
    onPressed: _bar.onRotateCcw,
    isSelected: rotationDegrees < 0,
  );

  Widget _rotateCwButton(int rotationDegrees) => _bar._barIconButton(
    keyValue: 'canvas-viewport-rotate-cw',
    tooltip: AppText.strings.viewRotateRight,
    shortcuts: const [EditorActionIds.canvasRotateCw],
    icon: const Icon(Icons.rotate_right),
    onPressed: _bar.onRotateCw,
    isSelected: rotationDegrees > 0,
  );

  Widget _flipHorizontalButton(CanvasViewport viewport) => _bar._barIconButton(
    keyValue: 'canvas-viewport-flip',
    tooltip: AppText.strings.viewFlipHorizontal,
    shortcuts: const [EditorActionIds.canvasFlipHorizontal],
    icon: const Icon(Icons.flip),
    onPressed: _bar.onFlipHorizontal,
    isSelected: viewport.flipHorizontal,
  );

  Widget _fitButton() => _bar._barIconButton(
    keyValue: 'canvas-viewport-fit',
    tooltip: AppText.strings.viewFitToView,
    icon: const Icon(Icons.fit_screen),
    onPressed: _bar.onFit,
  );

  Widget _resetButton() => _bar._barIconButton(
    keyValue: 'canvas-viewport-reset',
    tooltip: AppText.strings.viewResetView,
    icon: const Text(
      '1:1',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1),
    ),
    onPressed: _bar.onReset,
  );

  Widget _zoomOutButton() => _bar._barIconButton(
    keyValue: 'canvas-viewport-zoom-out',
    tooltip: editorActionLabel(EditorActionIds.canvasZoomOut),
    shortcuts: const [EditorActionIds.canvasZoomOut],
    icon: const Icon(Icons.zoom_out),
    onPressed: _bar.onZoomOut,
  );

  Widget _zoomInButton() => _bar._barIconButton(
    keyValue: 'canvas-viewport-zoom-in',
    tooltip: editorActionLabel(EditorActionIds.canvasZoomIn),
    shortcuts: const [EditorActionIds.canvasZoomIn],
    icon: const Icon(Icons.zoom_in),
    onPressed: _bar.onZoomIn,
  );

  Widget _zoomReadout() {
    final displayPercent = _zoomScale.display(_bar.viewport.zoom) * 100;
    return DragValueLabel(
      keyValue: 'canvas-viewport-zoom-label',
      inputKeyValue: 'canvas-viewport-zoom-input',
      text: '${displayPercent.round()}%',
      tooltip: AppText.strings.viewZoomDrag,
      width: _CanvasViewportBottomBar._zoomReadoutWidth,
      textStyle: const TextStyle(fontSize: 12),
      // ⛔No second bound here. `_zoomToAroundCenter` clamps in display
      // units for every absolute zoom verb, so the readout, the ± buttons
      // and a typed value all stop at the same number this label shows.
      onDragDelta: (units) =>
          _bar.onZoomSet(_zoomScale.render((displayPercent + units) / 100)),
      onEditSubmit: (text) {
        final parsed = double.tryParse(text.replaceAll('%', '').trim());
        if (parsed != null) {
          _bar.onZoomSet(_zoomScale.render(parsed / 100));
        }
      },
    );
  }

  List<Widget> _hostVerbButtons() => <Widget>[
    for (final verb in _hostVerbs)
      AppIconButton(
        keyValue: verb.keyValue,
        tooltip: verb.label,
        icon: Icon(verb.icon),
        size: AppIconButtonSize.strip,
        onPressed: verb.enabled ? verb.onSelected : null,
      ),
  ];

  List<Widget> _joined(List<List<Widget>> clusters) {
    final row = <Widget>[];
    for (final cluster in clusters) {
      if (cluster.isEmpty) {
        continue;
      }
      if (row.isNotEmpty) {
        row.add(_divider());
      }
      row.addAll(cluster);
    }
    return row;
  }
}
