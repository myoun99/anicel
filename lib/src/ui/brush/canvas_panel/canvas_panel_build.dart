part of '../brush_canvas_panel.dart';

/// ONE BUILD OF THE BRUSH CANVAS PANEL — the shell around the viewport,
/// the viewport's size, and the gesture layer that owns every pointer on
/// the canvas (strokes, the selection, the manipulators, pan and zoom).
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `build` was 415 lines with a
/// 315-line gesture-layer closure nested two builders deep, scoring 75 on
/// the meter. Constructed PER BUILD; it reaches the state through
/// `_state`.
class _PanelBuild {
  _PanelBuild(this._state);

  final _BrushCanvasPanelState _state;

  Widget build(BuildContext context) {
    // 🚨The marker is an INPUT marker, and that is the whole fix.
    //
    // It used to be written from two places with two different meanings —
    // "what the caller gave me" here, and "what I gave the caller" in the
    // publish path. So the moment the panel moved the view, the marker
    // became the panel's own emission, the caller's prop (still a frame
    // behind) compared as DIFFERENT, and the panel reverted its own
    // change. That is one measured defect and one near miss from a single
    // line. Written only here, it means what the condition needs: take the
    // prop when the CALLER changed it, and never when the panel did.
    if (_state.widget.viewport != null &&
        _state.widget.viewport !=
            _state._viewportState._lastSeenViewportInput) {
      _state._viewportState._lastSeenViewportInput = _state.widget.viewport;
      // ⛔Straight into the notifier, NOT through `_viewport` — the prop is
      // already in DEVICE units, and the setter's job is to convert INTO
      // them. Going through it would multiply by the ratio a second time.
      _state._viewportState._publishingViewport = true;
      _state._viewportState.viewportNotifier.value = _state.widget.viewport;
      _state._viewportState._publishingViewport = false;
    }
    return Padding(
      key: const ValueKey<String>('brush-canvas-panel'),
      // Zero: panels sit flush against the dock and the timeline (the
      // shell draws its own chrome).
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: _panelBox,
      ),
    );
  }

  // One VIEWPORT layout's state: assigned on every layout of the viewport
  // (the LayoutBuilder may lay out more than once per build) and read by the
  // gesture layer built in the same call — so `late`, not `late final`. The
  // nullable ones are copied into locals where a null check must promote.
  late Size _viewportSize;
  late Widget _canvasView;
  late Widget Function(BuildContext context, CanvasViewport viewport)?
  _overlayBuilder;
  late CanvasUnderlayBuilder? _underlayBuilder;
  late ValueListenable<bool>? _contentStrokeActive;
  late bool _selectionLayerActive;
  late CanvasSelectionRegion? _idleSelection;

  /// The viewport for the room the shell gives it: the canvas view, the
  /// gesture layer that owns every pointer on it, and the ants of an idle
  /// selection while a painting tool is armed.
  Widget _viewport(BuildContext context, BoxConstraints viewportConstraints) {
    _viewportSize = Size(
      viewportConstraints.maxWidth,
      viewportConstraints.maxHeight,
    );
    _state._viewportState.rememberEditorViewportSize(_viewportSize);

    _canvasView = _state._buildViewportContent(context);
    _overlayBuilder = _state.widget.viewportOverlayBuilder;
    _underlayBuilder = _state.widget.viewportUnderlayBuilder;
    _contentStrokeActive = _state.widget.contentStrokeActive;

    // R26 #15: selection works with NO frame under the
    // playhead too — the region is view state, and every
    // pixel op (lift/fill/draw-inside) already guards the
    // missing coordinator itself.
    _selectionLayerActive = canvasToolSelects(
      _state.widget.brushToolState.tool,
    );
    // R28-S: with a painting tool armed the panel paints the
    // committed region's ants itself (the interaction layer
    // is not mounted, but the selection still exists).
    _idleSelection = _state._selectionSeat.idleSelectionRegion;

    final contentStrokeActive = _contentStrokeActive;
    return SizedBox.expand(
      key: const ValueKey<String>('brush-canvas-editor-viewport'),
      // Pan/zoom input lives on the panel — not the interactive
      // canvas — so navigation keeps working when the viewport
      // shows the blank paper or playback instead of a frame.
      child: contentStrokeActive == null
          ? _gestureLayer(context, false)
          : ValueListenableBuilder<bool>(
              valueListenable: contentStrokeActive,
              builder: (context, active, _) => _gestureLayer(context, active),
            ),
    );
  }

  /// The panel's box for the space it was given: the shell around the
  /// viewport, sized to the constraints (the canvas size when unbounded).
  Widget _panelBox(BuildContext context, BoxConstraints constraints) {
    final fallbackSize = Size(
      _state.widget.canvasSize.width.toDouble(),
      _state.widget.canvasSize.height.toDouble(),
    );
    final boundedWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : fallbackSize.width;
    final boundedHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : fallbackSize.height + _CanvasViewportBottomBar.height;

    return SizedBox(
      width: boundedWidth,
      height: boundedHeight,
      child: _CanvasEditorPanelShell(
        rightStripBar: _state._shellBars.memoizedRightStripBar(),
        horizontalStripBar: _state._shellBars
            .memoizedHorizontalStripBar(),
        bottomBar: _state._shellBars.memoizedBottomBar(),
        pageStrip: _state.widget.pageStrip,
        // The capsules float INSIDE what the panels left over.
        cover: _state.widget.floorCover,
        railBand: _state.widget.floorRailBand,
        bottomOverlaySpan: _state.widget.floorBottomOverlaySpan,
        child: LayoutBuilder(builder: _viewport),
      ),
    );
  }

  /// What sits on the artwork inside the pointer census — [_toolDeck],
  /// behind the pan hold's gate (I-15): while the 「이동」 key is held the
  /// deck takes no pointer at all, so every tool stands down for the pan at
  /// once, and the hand says what a press will do.
  Widget _cursorDeck(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: CanvasPanHold.held,
    builder: (context, held, deck) => MouseRegion(
      opaque: false,
      cursor: held ? SystemMouseCursors.grab : MouseCursor.defer,
      child: IgnorePointer(ignoring: held, child: deck),
    ),
    child: _toolDeck(context),
  );

  /// The bare canvas when no cursor visual is armed, else the deck —
  /// underlay, canvas, overlay, the tap layer, the tool cursors, the
  /// selection layer and the idle ants.
  Widget _toolDeck(BuildContext context) {
    final overlayBuilder = _overlayBuilder;
    final underlayBuilder = _underlayBuilder;
    final idleSelection = _idleSelection;
    return
    // 🐛The FILL cursor was missing from this
    // list, and the omission is not cosmetic:
    // with fill armed `_toolTapHandler()`
    // returns null (R22-A sends the dab
    // through the stroke pipeline) and
    // `canvasToolPaints(fill)` is false, so
    // every other conjunct held and the whole
    // Stack was skipped — taking the bucket
    // icon AND the region that hides the
    // system cursor with it. The three hosts
    // that pass no underlay or overlay (the
    // conte, the cut envelope, the timesheet)
    // sit in this branch permanently, so the
    // fill cursor was simply dead there.
    //
    // The invariant to keep: the Stack is
    // built whenever ANY cursor predicate is
    // true, so a tracker is mounted whenever
    // a visual is.
    overlayBuilder == null &&
        underlayBuilder == null &&
        _state._tap.toolTapHandler() == null &&
        !_selectionLayerActive &&
        idleSelection == null &&
        !_state._toolCursor.eyedropperCursorActive &&
        !_state._toolCursor.fillCursorActive &&
        !_state._toolCursor.brushCursorActive
    ? _canvasView
    : Stack(
        children: [
          if (underlayBuilder != null)
            Positioned.fill(
              child: underlayBuilder(
                context,
                _state._viewportState._viewport,
                // ★ONE PLACE DECIDES WHETHER THERE IS A PAINTER, and
                // it is the builder. This call site used to ask the VERB
                // coordinator first — a second copy of the same decision,
                // with the ROW question mixed in — so standing on a
                // property lane never even asked, and the live row sat in
                // the composite tree with nobody to paint it. 🗣️유저
                // 2026-09-12: 「레이어에 서있을땐 그림 제대로 보이는데
                // 트랜스폼에 서면 그림이 사라져」. The builder answers null
                // by itself when there is nothing to paint.
                _state._activeSurfacePainter(),
                _state._selectionFloat,
              ),
            ),
          Positioned.fill(child: _canvasView),
          if (overlayBuilder != null)
            Positioned.fill(
              child: overlayBuilder(
                context,
                _state._viewportState._viewport,
              ),
            ),
          // Non-painting tools (P5 eyedropper / P6
          // fill): one tap layer ABOVE the canvas
          // absorbs the pointer so no stroke starts.
          if (_state._tap.toolTapHandler() != null)
            _state._tap.toolTapLayer(),
          // Eyedropper cursor (R11-②): crosshair +
          // a hover swatch of the color under the
          // pointer — for the tool AND the Alt-held
          // temporary pick. Translucent: picks fall
          // through to the tap layer / canvas below.
          if (_state._toolCursor.eyedropperCursorActive)
            ..._state._eyedropperCursorLayers(),
          // R26 #23: the fill tool wears the bucket.
          if (_state._toolCursor.fillCursorActive)
            ..._state._fillCursorLayers(),
          // The painting tools wear their own
          // footprint: an outline of the tip that
          // follows the pointer, so a stroke can be
          // aimed before it starts.
          if (_state._toolCursor.brushCursorActive)
            ..._state._brushCursorLayers(),
          // The P9 selection tools own the pointer
          // while active (marquee/lasso/move) —
          // strokes cannot start below the layer.
          if (_selectionLayerActive)
            _state._selectionLayer(underlayBuilder),
          // R28-S: the selection is a DOCUMENT
          // fact, so its ants stay on screen under
          // every other tool too — that is what
          // makes "선택하고 다른 툴" legible (R26
          // #18). Purely decorative: the layer
          // above owns all interaction.
          if (idleSelection != null)
            _state._idleSelectionAnts(idleSelection),
        ],
    );
  }

  Widget _gestureLayer(BuildContext context, bool contentStrokeIsActive) {
    final hud = _state.widget.flipHud;
    final layer = CanvasViewportGestureLayer(
      viewport: _state._viewportState._viewport,
      onViewportChanged: _state._viewportState.setViewport,
      rotationEnabled: _state.widget.allowViewRotation,
      oneFingerAction: _state.widget.oneFingerAction,
      flipHud: hud,
      // PEN-7b: the control-mode touch slots — flip
      // dispatches shell actions, brush size drives the
      // tool state (both threaded from the workspace).
      onInvokeAction: _state.widget.onInvokeAction,
      onBrushSizeDragStart: _state.widget.onBrushSizeDragStart,
      onBrushSizeDragUpdate: _state.widget.onBrushSizeDragUpdate,
      onBrushSizeDragEnd: _state.widget.onBrushSizeDragEnd,
      strokeActive:
          _state._strokeActive ||
          _state._selectionDragActive ||
          contentStrokeIsActive,
      touchLocked: _state._transformDragActive,
      // Nothing drawn in the viewport (canvas, playback
      // frames, camera overlay) may paint outside the panel.
      child: ClipRect(
        // ★★THE CURSOR DECK (유저, R4 #3: 커서가 살짝 늦게
        // 따라오는 게 아니라 진짜 렉이 있다, 60fps여야 하는데
        // 20fps로 보이는 느낌).
        //
        // The tool cursor used to be a `Positioned` SIBLING
        // of the artwork inside one Stack. Moving it marked
        // that Stack for layout, layout marks for paint, and
        // `PaintingContext.paintChild` branches on
        // `child.isRepaintBoundary` AND NOTHING ELSE — a
        // painter's `shouldRepaint` is consulted only when
        // its instance is swapped, never on the walk. So
        // every unboundaried sibling re-ran its painter on
        // every pointer event: `CanvasLayerStackView`
        // (paper + every layer below + onion ghosts, with a
        // `saveLayer` per group buffer), `_StagePlanes`, the
        // selection layer. That is the ~20fps.
        //
        // Two widgets:
        //
        //  (B) puts the moving `Positioned`s in a Stack of
        //      their own, so the cursor's layout dirt never
        //      reaches the Stack the artwork is in;
        //  (C) gives the artwork a cached LAYER, which is
        //      the actual fix — measured at 8 canvas
        //      re-records over 8 moves without it and 0
        //      with it.
        //
        // ⛔A third boundary, wrapping this whole thing to
        // stop paint escalating past the `ClipRect`, was
        // designed and then REMOVED: it changed no
        // measurement. Paint above the viewport still climbs
        // once per move (the shell floor and the capsules
        // re-record; the artwork does not), and that
        // boundary did not stop it — with or without it the
        // count was identical. Shipping it would have been a
        // claim the numbers do not support. The remaining
        // escalation is unexplained and cheap; it is written
        // down rather than papered over.
        //
        // ⚠️The rule for (B)'s children is: every one either
        // paints nothing or carries its own boundary. The
        // `SizedBox.shrink()` a cursor returned while its
        // notifier was null satisfied the first half — and
        // KEEPING that shrink was what preserved the R3 #8
        // oracle (`findsNothing` before the pointer has been
        // anywhere), which is why this was a Stack of widgets
        // and not a custom render object gated in `paint`.
        //
        // 🚨★★★F-130 (2026-09-15) made it that render object
        // after all — `ToolCursorSprite`, its own boundary,
        // moving its inner layer by offset with no build, no
        // layout and no paint per move — because a Stack of
        // `Positioned`s still rebuilt three widgets, re-laid
        // this Stack out and re-recorded everything between
        // the shell boundary and here on every pointer event
        // (measured). The R3 #8 oracle did not die with the
        // shrink: it is `RenderToolCursorSprite.debugPosition`,
        // null for exactly the reason `findsNothing` used to
        // be.
        //
        // ⛔Do NOT boundary the underlay or the overlay. It
        // would be a real further win during a stroke, and
        // it would also blind the cost oracle, which counts
        // a painter mounted through `viewportUnderlayBuilder`
        // precisely because the paint walk still reaches it.
        child: SizedBox.expand(
          child: Stack(
            key: const ValueKey<String>('canvas-cursor-deck'),
            fit: StackFit.expand,
            // NO CLIP: a `Stack` clips only WHEN a child
            // overflows, so its clip layer would come and go
            // as the cursor crosses the panel edge — a layer
            // the tree does not need, since the `ClipRect`
            // one level up already owns that promise.
            //
            // ⚠️This used to carry a justification that was
            // simply FALSE: "a compositing-bits update
            // propagates past repaint boundaries by design".
            // It does not — `markNeedsCompositingBitsUpdate`
            // stops the moment `parent.isRepaintBoundary`
            // (rendering/object.dart:3206). The clip was
            // never the escalation path; the escalation was
            // ordinary `markNeedsPaint`, and it stops at the
            // shell boundary. Keeping the widget, dropping
            // the story.
            clipBehavior: Clip.none,
            children: [
              // ★The artwork layer sits on the DEVICE-PIXEL
              // grid — and as of R11 it does so BY
              // CONSTRUCTION, with nothing here to make it
              // true.
              //
              // An `IntegralLayerOffset` used to wrap this
              // boundary. It measured its own accumulated
              // offset after each frame and cancelled the
              // fraction, which worked in the settled state
              // and failed on the frame OF an ancestor
              // layout change — a post-frame measurement is
              // one frame behind exactly when a tool panel
              // opens or the active layer switches, which
              // are the moments the artwork was seen to hop
              // (#1106, device 2026-08-17). R11 quantizes
              // every app-chosen offset from the window
              // origin down, in LAYOUT, so this boundary is
              // integral on the change frame too;
              // `canvas_boundary_on_grid_test.dart` measures
              // it there.
              //
              // ⛔What is NOT retired: `#1101`'s in-picture
              // PAN snap (`renderSnappedViewport`). It owns
              // pan jitter — our own fractional-phase blits,
              // recorded inside the picture — which is a
              // different phenomenon from the layer offset
              // this paragraph is about.
              RepaintBoundary(
                key: const ValueKey<String>('canvas-content-boundary'),
                // The stage's outer planes (R3b): the BACKDROP
                // fills the panel and the PASTEBOARD lies on it
                // where the pasteboard actually is, RGBA and
                // project data (R28 #9 reversed) — thinning it
                // reveals the floor, on screen exactly as in an
                // export. The alpha-preview toggle swaps BOTH for
                // the checkerboard: an alpha export excludes them,
                // so the preview must too.
                child: _StagePlanes(
                  backdropArgb: _state._stageBackdropArgb,
                  pasteboardArgb: _state._stagePasteboardArgb,
                  canvasSize: _state.widget.canvasSize,
                  viewport: _state._viewportState._viewport,
                  // R27 #17: a passive census of where the pointer
                  // is — button-held moves included — so a cursor
                  // that arms mid-gesture knows where to appear.
                  // Translucent and handler-only: it consumes
                  // nothing.
                  child: MouseRegion(
                    // The census's other half: WHEN THE POINTER
                    // LEAVES. Everything below only ever learns
                    // where the pointer is; without an exit the
                    // last position stayed authoritative for ever,
                    // and a tool cursor armed afterwards would draw
                    // itself where the hand used to be.
                    opaque: false,
                    hitTestBehavior: HitTestBehavior.translucent,
                    onEnter: (event) =>
                        _state._hoverDevicesInside.add(event.device),
                    onExit: (event) {
                      // A departing device releases its OWN
                      // hold only. It may not decide the aim
                      // is nobody's while a second hoverer
                      // or a pressed pointer still has it.
                      if (!_state._hoverDevicesInside.remove(event.device)) {
                        return;
                      }
                      if (_state._tap.aimIsHeld) {
                        return;
                      }
                      _state._forgetCanvasPointer();
                    },
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerHover: (event) => _state._noteCanvasPointer(
                        event.localPosition,
                        kind: event.kind,
                      ),
                      onPointerDown: (event) {
                        _state._tap.beginCanvasPointer(event);
                        _state._noteCanvasPointer(
                          event.localPosition,
                          kind: event.kind,
                        );
                      },
                      onPointerMove: (event) => _state._noteCanvasPointer(
                        event.localPosition,
                        kind: event.kind,
                      ),
                      // …and the exit above is the whole
                      // story ONLY for pointers Flutter
                      // reports an exit for. A finger, a
                      // pen TAIL or an `unknown` device
                      // writes through this same census
                      // and then leaves without a word, so
                      // the ring stayed where the hand had
                      // been — for ever. For those, the
                      // contact ending IS the exit.
                      onPointerUp: _state._tap.endCanvasPointer,
                      onPointerCancel: _state._tap.endCanvasPointer,
                      child: _cursorDeck(context),
                    ),
                  ),
                ),
              ),
              ..._state._toolCursor.toolCursorLayers(),
            ],
          ),
        ),
      ),
    );
    if (hud == null) {
      return layer;
    }
    // Above the gesture layer, in the same box: the anchor
    // the gesture reports is already in these coordinates.
    return Stack(
      fit: StackFit.expand,
      children: [
        layer,
        FlipHudOverlay(controller: hud),
      ],
    );
  }
}
