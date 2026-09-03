part of '../brush_canvas_panel.dart';

/// THE VIEWPORT THE PANEL LOOKS THROUGH — its own or the owner's, the
/// one it publishes, the last input it saw, and the editor viewport size
/// it remembers for fitting.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: five fields of its
/// own and four methods that read them. It reaches the panel through
/// `_state`.
class _CanvasPanelViewport {
  _CanvasPanelViewport(this._state);

  final _BrushCanvasPanelState _state;

  /// The panel's OWN storage, used only when no owner supplied one.
  ///
  /// The view is a notifier rather than a plain field because the settings
  /// list is an overlay route built once when it opens, so nothing in
  /// there would ever see a rotation land or a flip toggle. A knob that
  /// does not show its own state is a knob nobody can read.
  /// ⚠️`late`, so [widget] is readable: [BrushCanvasPanel.viewport] is the
  /// SEED, taken once here. Null stays null and the getter below resolves
  /// it to the identity.
  late final ValueNotifier<CanvasViewport?> _ownViewport = ValueNotifier(
    _state.widget.viewport,
  );

  /// 🎯**Where the view actually lives — ONE object, not a copy.**
  ///
  /// The panel used to take the view as a VALUE and keep a copy, pushing
  /// changes back through a callback and re-applying the prop whenever it
  /// differed from the last value it had emitted. That is two sources of
  /// truth with a marker between them, and the marker meant two different
  /// things in the two places that wrote it — "what the owner gave me" in
  /// the re-apply and "what I gave the owner" in the publish. The moment
  /// an owner was a frame late, the panel read its own emission as a
  /// stale prop and reverted its own change. That is one measured defect
  /// (a document tab absorbing a UI-scale change) and one near miss (a
  /// zoom press discarding a ratio correction) from the same line.
  ///
  /// ⛔Every owner ALREADY held a `ValueNotifier` — the workspace's three
  /// document viewports and the media slot's — so this is not a new
  /// concept, it is the end of unwrapping one and re-wrapping it.
  ValueNotifier<CanvasViewport?> get viewportNotifier =>
      _state.widget.viewportController ?? _ownViewport;

  /// The view in LOGICAL units — what every painter, every hit test and
  /// every gesture in this panel works in.
  ///
  /// 🎯**The stored form is DEVICE units; this is the projection.** The
  /// panel is the only boundary the two units meet at: read here, write in
  /// the setter, and nothing in between has to know a ratio exists.
  ///
  /// 🚨What that buys is the whole of the exclusion, for free. A ratio
  /// change — a new UI scale, a window dragged to another monitor — moves
  /// the projection and not the stored value, so the artwork keeps every
  /// device pixel it had. There is no re-zoom to run, no anchor to pick,
  /// and, crucially, **nothing that has to be MOUNTED to happen**: a closed
  /// document tab comes back at the percentage it left at because its value
  /// never meant anything ratio-dependent in the first place.
  ///
  /// ⛔The three mechanisms this replaced are gone, not disabled: the
  /// re-zoom (`rescaledFrom`), the held value that carried it through the
  /// build it was noticed in, and the post-frame commit that got it out of
  /// that build. Each existed only because the stored number moved.
  ///
  /// ⚠️`null` is "nobody has framed this yet", and in device units that is
  /// exactly `CanvasViewport()` — one artwork pixel per device pixel. The
  /// bare constructor was the WRONG value in render units; it is the right
  /// one here, which is the clearest sign the unit belongs at the storage.
  ///
  /// 🎯**[BrushCanvasPanel.unframedFit] is the SECOND answer to that same
  /// `null`.** An owner that has a framing in mind for a view nobody has
  /// framed hands over the RECT, not a viewport, and the fit resolves HERE,
  /// at the read — so the very first build that sees it already paints
  /// fitted. Nothing is stored, so nothing has to wait for the frame to end
  /// to store it, and there is nothing to put back afterwards.
  CanvasViewport get _viewport {
    final stored = viewportNotifier.value;
    if (stored != null) {
      return _state._zoomScale.fromDevice(stored);
    }
    final unframed = _state.widget.unframedFit;
    if (unframed == null) {
      return _state._zoomScale.fromDevice(CanvasViewport());
    }
    // ⛔No `fromDevice`: [_fittedInto] works in the LAYOUT box's own
    // coordinates, which are already the logical units this getter owes.
    return _state._fittedInto(_resolvedVisibleRect(), canvasRect: unframed);
  }

  set _viewport(CanvasViewport value) {
    _publishingViewport = true;
    viewportNotifier.value = _state._zoomScale.toDevice(value);
    _publishingViewport = false;
  }

  /// The notifier this panel is currently subscribed to — [viewportNotifier]
  /// is a getter whose identity changes with the prop, so the object to
  /// UNSUBSCRIBE from has to be remembered rather than recomputed.
  ValueNotifier<CanvasViewport?>? _listenedViewport;

  /// True while the panel is writing the view itself.
  ///
  /// Its own writes ride a `setState` already, so hearing them back would
  /// only schedule a second build for the same change.
  bool _publishingViewport = false;

  /// Repaints when the OWNER moves the view.
  ///
  /// 🚨The hole this closes is the price of sharing the object. The view
  /// used to arrive as a PROP, so an owner that re-framed it rebuilt this
  /// panel by definition; now it writes into a notifier the panel merely
  /// reads, and nothing schedules a frame. Measured on the playback stop
  /// restore (`editor_canvas_area.dart` writes the pre-play view straight
  /// into the notifier): the value was right and the canvas kept painting
  /// the playback framing.
  ///
  void handleViewportMovedByOwner() {
    if (_publishingViewport || !_state.mounted) {
      return;
    }
    // The value already lives in the notifier — this call IS the repaint.
    _state._rebuild(() {});
  }

  /// The last value the CALLER handed us through [BrushCanvasPanel.viewport].
  ///
  /// ⛔An INPUT marker, written in `build` and nowhere else. Writing it
  /// from the publish path is what made the panel revert itself.
  CanvasViewport? _lastSeenViewportInput;

  Size? _editorViewportSize;

  void bindViewCommands() {
    _state.widget.viewCommands?.bind(
      _state,
      rotateBy: _rotateAroundCenter,
      toggleFlipHorizontal: _toggleFlipHorizontal,
      toggleFlipVertical: _toggleFlipVertical,
      resetRotation: _resetRotation,
    );
  }

  void _autoFrame(CanvasAutoFrameRequest request) {
    final visible = _resolvedVisibleRect();
    final next = request.panOnly
        ? _viewportRevealing(request.rect, visible)
        : _state._fittedInto(visible, canvasRect: request.rect);
    if (next == _viewport) {
      return;
    }
    setViewport(next);
  }

  /// The minimal zoom-preserving pan that brings [rect] (canvas space)
  /// into the viewport with a small margin; when the rect cannot fully
  /// fit, its top-left edge wins. Under rotation/flip the rect's mapped
  /// AABB is what must land inside.
  CanvasViewport _viewportRevealing(Rect rect, Rect visible) {
    const margin = 24.0;
    var panX = _viewport.panX;
    var panY = _viewport.panY;
    final unpanned = _viewport.copyWith(panX: 0, panY: 0);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      final mapped = unpanned.canvasToViewport(
        CanvasPoint(x: corner.dx, y: corner.dy),
      );
      minX = math.min(minX, mapped.x);
      maxX = math.max(maxX, mapped.x);
      minY = math.min(minY, mapped.y);
      maxY = math.max(maxY, mapped.y);
    }
    // Reveal into the window, not into the box: the 24px breathing room is
    // worthless if it is measured against an edge that is covered.
    if (maxY + panY > visible.bottom - margin) {
      panY = visible.bottom - margin - maxY;
    }
    if (minY + panY < visible.top + margin) {
      panY = visible.top + margin - minY;
    }
    if (maxX + panX > visible.right - margin) {
      panX = visible.right - margin - maxX;
    }
    if (minX + panX < visible.left + margin) {
      panX = visible.left + margin - minX;
    }
    return _viewport.copyWith(panX: panX, panY: panY);
  }

  void rememberEditorViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    if (_editorViewportSize == size) {
      return;
    }
    final previous = _editorViewportSize;
    final insets = _state._framingInsets;
    // Both windows measured with the SAME cover, so the delta below is the
    // BOX's doing and nothing else. A cover that changed at the same time
    // is deliberately not counted — see [_reanchorAfterBoxChange].
    final before = previous == null
        ? null
        : canvasVisibleRect(previous, insets);
    _editorViewportSize = size;
    final after = canvasVisibleRect(size, insets);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_state.mounted) {
        return;
      }
      if (before != null) {
        _reanchorAfterBoxChange(before, after);
      }
      _state._rebuild(() {});
    });
  }

  /// Keeps what you are looking at where you are looking when the BOX
  /// changes size.
  ///
  /// Pan is a pure screen-space translation applied after zoom, rotation and
  /// flip, so a window whose centre moved by a delta is answered by moving
  /// pan by exactly that delta — nothing has to be unprojected.
  ///
  /// Only the FLOOR does this, and only for the box. Two deliberate limits:
  ///
  ///  * A docked panel has always let the artwork sit still against its
  ///    top-left corner, and nothing is asking it to change. The floor is the
  ///    one surface that grows by hundreds of pixels the moment a dock opens
  ///    or the window resizes, which is where "the drawing walked into the
  ///    corner" comes from.
  ///  * A COVER change is left alone on purpose. When a panel opens over the
  ///    canvas the artwork does not move on screen — only the window onto it
  ///    shrinks — and sliding the picture out from under a panel the user
  ///    just opened, or shifting it on every frame of a splitter drag, is a
  ///    motion nobody asked for.
  void _reanchorAfterBoxChange(Rect before, Rect after) {
    final dx = after.center.dx - before.center.dx;
    final dy = after.center.dy - before.center.dy;
    if (dx == 0 && dy == 0) {
      return;
    }
    setViewport(_viewport.translated(dx: dx, dy: dy));
  }

  void setViewport(CanvasViewport viewport) {
    _state._rebuild(() => _viewport = viewport.clamped());
    _syncViewportParent();
  }

  /// Tells the owner the view moved, in DEVICE pixels.
  ///
  /// ⚠️Notification ONLY. The value is already in the owner's notifier by
  /// the time this runs — writing a "last published" marker here is what
  /// used to make the panel revert itself.
  ///
  /// ⛔The STORED value, not `toDevice(_viewport)`: the two agree to within
  /// a float ulp, and handing out the one that is already in the notifier
  /// means a caller that echoes it straight back is a no-op rather than a
  /// change. It also keeps the rule with no exceptions — every viewport
  /// that crosses this panel's boundary, in either direction and through
  /// any of the three channels, is in device pixels.
  void _syncViewportParent() {
    final onChanged = _state.widget.onViewportChanged;
    if (onChanged == null) {
      return;
    }
    onChanged(viewportNotifier.value ?? CanvasViewport());
  }

  /// One press of the pill's − / +. Back with the buttons themselves
  /// (유저 확정 2026-08-13: 줌 버튼도 살림).
  void _zoomAroundCenter(double factor) {
    _zoomToAroundCenter(_viewport.zoom * factor);
  }

  void _zoomToAroundCenter(double nextZoom) {
    // The centre of what you can SEE, not of the box: anchoring on the box
    // walks the picture toward a covered edge one press at a time.
    final center = _resolvedVisibleRect().center;
    final anchor = ViewportPoint(x: center.dx, y: center.dy);
    _state._rebuild(() {
      // ⛔The clamp is in DISPLAY units, and it is the same one for every
      // absolute zoom verb. The ± buttons used to stop at the model's
      // RENDER rail while the readout stopped at 10–1600%, so on a 2×
      // tablet the buttons reached 3200% and then a one-pixel nudge of the
      // readout halved the view in a single step.
      _viewport = _viewport.zoomedAround(
        nextZoom: _state._zoomScale.clampRender(nextZoom),
        anchor: anchor,
      );
    });
    // ⚠️Through the shared publisher, not `onViewportChanged` directly:
    // that left `_lastWidgetViewport` stale for one build, and the
    // controlled re-apply on the next build would then overwrite — and
    // discard a ratio hold that had just been set.
    _syncViewportParent();
  }

  void _fitToView() {
    final canvasSize = _state.widget.canvasSize;
    final target =
        _state.widget.fitFocusRect ??
        Rect.fromLTWH(
          0,
          0,
          canvasSize.width.toDouble(),
          canvasSize.height.toDouble(),
        );
    _state._rebuild(() {
      _viewport = _state._fittedInto(
        _resolvedVisibleRect(),
        canvasRect: target,
      );
    });
    _syncViewportParent();
  }

  /// The panel's LAYOUT box — the surface you touch. Pan bars, the gesture
  /// layer and the shell memo want this one.
  Size _resolvedEditorViewportSize() {
    return _editorViewportSize ??
        Size(
          _state.widget.canvasSize.width.toDouble(),
          _state.widget.canvasSize.height.toDouble(),
        );
  }

  /// The window you LOOK THROUGH, in layout coordinates. Every verb that
  /// frames the artwork wants this one — see [canvasVisibleRect].
  Rect _resolvedVisibleRect() =>
      canvasVisibleRect(_resolvedEditorViewportSize(), _state._framingInsets);

  /// The 1:1 button. ⛔NOT `CanvasViewport()`: a bare zoom of 1.0 is one
  /// artwork pixel per LOGICAL pixel, which on a 1.5 display drew the
  /// artwork at 150% while the readout said 100%. The button's own glyph
  /// says "1:1" and now it means it — one artwork pixel, one device pixel,
  /// whatever the monitor and the UI scale are.
  void _resetView() {
    setViewport(_state._zoomScale.identityViewport);
  }

  ViewportPoint get _viewportCenterAnchor {
    final center = _resolvedVisibleRect().center;
    return ViewportPoint(x: center.dx, y: center.dy);
  }

  /// Rotates the VIEW by [degrees] around the viewport center (P8). The
  /// result snaps to 0° when within ±0.01° (float dust from gesture
  /// accumulations must not leave the AABB slow path armed forever).
  void _rotateAroundCenter(double degrees) {
    var next = _viewport.rotationDegrees + degrees;
    final normalized = ((next + 180) % 360) - 180;
    if (normalized.abs() < 0.01) {
      next = next - normalized;
    }
    setViewport(
      _viewport.rotatedAround(
        nextRotationDegrees: next,
        anchor: _viewportCenterAnchor,
      ),
    );
  }

  void _toggleFlipHorizontal() {
    setViewport(_viewport.flippedAround(anchor: _viewportCenterAnchor));
  }

  void _toggleFlipVertical() {
    setViewport(_viewport.flippedVerticalAround(anchor: _viewportCenterAnchor));
  }

  /// Straightens the rotation to 0° around the viewport center, keeping
  /// zoom/pan/flips (UI-R18 #20).
  void _resetRotation() {
    setViewport(
      _viewport.rotatedAround(
        nextRotationDegrees: 0,
        anchor: _viewportCenterAnchor,
      ),
    );
  }

  /// The angle-label drag (UI-R18 #21): one degree per pixel, anchored to
  /// the viewport center.
  void _rotateByDrag(double deltaDegrees) {
    _rotateAroundCenter(deltaDegrees);
  }

  /// Continues a stamp drag up to [point].
  ///
  /// Stamps go down one whole piece apart, so they touch without
  /// overlapping — which is why there is no spacing knob to get wrong, and
  /// why a soft edge cannot accumulate where two stamps stack.
  ///
  /// The remainder of the travel is deliberately NOT carried: the next
  /// move continues from the last stamp that actually landed, so a slow
  /// drag and a fast one lay the same number of stamps over the same
  /// distance.
  CanvasPoint canvasPointOf(PointerEvent event) => _viewport.viewportToCanvas(
    ViewportPoint(x: event.localPosition.dx, y: event.localPosition.dy),
  );
}
