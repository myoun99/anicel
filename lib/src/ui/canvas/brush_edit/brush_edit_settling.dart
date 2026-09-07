part of '../interactive_brush_edit_canvas_view.dart';

/// SETTLING — after a stroke lands, the window in which the committed
/// tiles are decoded and the stand-ins are released: the bounds being
/// settled, the deadline, the recheck interval and the fallback timer that
/// ends it either way.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, Round 6, 2026-09-03). Measured before cutting:
/// five fields of its own and three methods that are their only writers.
/// It reaches the view through `_state`.
class _BrushEditSettling {
  _BrushEditSettling(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  bool _settling = false;

  Timer? _settlingFallbackTimer;

  /// Canvas region the settling stroke touched: only ITS tiles gate the
  /// overlay handoff (checking the whole surface stalled the drop on
  /// unrelated tiles, and the old flat 300ms give-up then revealed stale
  /// pre-stroke tiles — the "part of the stroke blinks" bug).
  DirtyRegion? _settlingBounds;

  /// Ends the settle window: the flag, the bounds and the fallback timer.
  ///
  /// The four fields belong here, so the teardown does too — the overlay
  /// used to write them out itself, twice.
  void endWindow() {
    _settling = false;
    _settlingBounds = null;
    _settlingFallbackTimer?.cancel();
    _settlingFallbackTimer = null;
  }

  /// Lets go of every stand-in whose committed tile can now paint itself.
  ///
  /// A barrier, not a clock: the release is driven by decodes landing, so
  /// it cannot fire early, and it cannot leak when the work runs long.
  void releaseSettledStandIns() {
    if (!_state._overlay._overlayModel.hasStandIns || !_state.mounted) {
      return;
    }
    final surface = _state.widget.sessionState.canvasState.currentSurface;
    final cache = BitmapTileImageCache.instance;
    _state._overlay._overlayModel.releaseStandIns((coord) {
      final tile = surface.tileAt(coord);
      // ⚠️ No tile is NOT "settled". The commit reaches this widget's
      // session state a rebuild later than it reaches the store, so
      // between the handoff's miss and that rebuild the coordinate the
      // stamp just wrote to can still be absent here — and letting go
      // then is letting go before anything can paint it. A stand-in that
      // never finds a tile is bounded by the next reset.
      return tile != null && cache.imageFor(tile) != null;
    });
  }

  /// How long the settling safety cap keeps waiting for tile decodes
  /// before force-dropping the overlay. Purely a stuck-state escape hatch:
  /// dropping EARLY is what used to blink parts of big strokes back to
  /// their pre-stroke tiles (the old 300ms flat timeout fired before slow
  /// decodes finished), so the deadline is generous and the periodic
  /// re-check below re-requests decodes instead of giving up.
  static const Duration _settlingDeadline = Duration(seconds: 2);

  static const Duration _settlingRecheckInterval = Duration(milliseconds: 50);

  void _beginSettling() {
    _settling = true;
    // The overlay stops being the stroke and starts being a stand-in —
    // the painter needs to know, so it can prefer a committed tile that
    // has caught up over an image that is a revision behind it.
    _state._overlay._overlayModel.settling = true;
    _settlingFallbackTimer?.cancel();
    var waited = Duration.zero;
    _settlingFallbackTimer = Timer.periodic(_settlingRecheckInterval, (timer) {
      if (!_state.mounted || !_settling) {
        timer.cancel();
        return;
      }
      waited += _settlingRecheckInterval;
      if (waited >= _settlingDeadline) {
        timer.cancel();
        _state._overlay.resetOverlay();
        return;
      }
      // Belt and braces against a missed decode notification: re-request
      // the stroke tiles' decodes and re-run the handoff check.
      requestSettlingDecodes();
      _state._onTileImagesChanged();
    });
    // Check after the parent rebuild delivers the post-commit session state;
    // checking synchronously would consult the pre-commit surface and clear
    // the overlay immediately, reintroducing the flash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestSettlingDecodes();
      _state._onTileImagesChanged();
    });
  }

  /// The committed-surface tiles the settling stroke touched (all tiles
  /// when the bounds are unknown).
  List<BitmapTile> settlingTiles() {
    return settlingTilesForBounds(
      surface: _state.widget.sessionState.canvasState.currentSurface,
      bounds: _settlingBounds,
    );
  }

  void requestSettlingDecodes() {
    if (!_settling || !_state.mounted) {
      return;
    }
    // Budgeted starts (R18 B-1): a canvas-covering stroke used to start
    // EVERY touched tile's decode in this one call — each start is a
    // synchronous tile copy + 65k-pixel premultiply, a pen-up hitch at
    // heavy sizes. Chunks chain instead: every decode completion notifies
    // the cache listener below, which re-requests the next chunk until
    // [allDecoded] releases the overlay (the overlay keeps the stroke on
    // screen throughout, so the handoff stays atomic and invisible).
    var budget = BitmapTileImageCache.decodeStartBudget;
    for (final tile in settlingTiles()) {
      if (!BitmapTileImageCache.instance.needsDecodeStart(tile)) {
        continue;
      }
      BitmapTileImageCache.instance.ensureDecoded(
        tile,
        staleScope: (_state.widget.layerId, _state.widget.frameId),
      );
      budget -= 1;
      if (budget <= 0) {
        break;
      }
    }
  }
}
