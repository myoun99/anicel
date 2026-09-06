part of '../editor_session_manager.dart';

/// The TEXT-CEL BAKES — text cels are baked to pixels in a background sweep
/// so the canvas draws them like any other cel — as their own object: what
/// was baked, what is dirty, and the sweep that catches up.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and eight
/// session members touched. It reaches the session through `_session`.
class _TextCelBakes {
  _TextCelBakes(this._session);

  final EditorSessionManager _session;

  /// Canonical cel key → the exact inputs its stored raster was rendered
  /// from. The CONTENT itself, not a hash — equality gates skipping a
  /// re-bake, and a ~29-bit hash collision would freeze a stale
  /// projection silently. Entries whose cel stops being a text frame are
  /// pruned, never clear-baked — a rasterized text layer KEEPS its
  /// pixels.
  final Map<BrushFrameKey, (TextCelContent?, CanvasSize)> _textCelBakedContent =
      {};

  bool _textCelSweepDirty = false;

  Future<void>? _textCelSweep;

  /// Test hook: awaits the in-flight bake sweep (projection settles).
  @visibleForTesting
  Future<void> get debugTextCelSweepDone => _textCelSweep ?? Future.value();

  void scheduleTextCelBakeSweep() {
    _textCelSweepDirty = true;
    _textCelSweep ??= Future.microtask(_runTextCelBakeSweeps);
  }

  /// Saves snapshot the store synchronously, so an in-flight bake must
  /// land first — otherwise the archive pairs NEW parameters with the OLD
  /// raster, and the first-sight trust after reload cements the stale
  /// picture forever.
  Future<void> flushTextCelBakes() async {
    while (_textCelSweep != null) {
      await _textCelSweep;
    }
  }

  Future<void> _runTextCelBakeSweeps() async {
    try {
      while (_textCelSweepDirty && !_session._disposed) {
        _textCelSweepDirty = false;
        await _sweepTextCelBakesOnce();
      }
    } finally {
      _textCelSweep = null;
    }
  }

  /// Catches one text cel up with its text: null when the session was
  /// disposed mid-bake (stop touching the stores), else whether the bake
  /// changed anything. Linked banks share one physical projection, so a
  /// key the sweep has seen is skipped.
  Future<bool?> _bakeOneTextCel(Cut cut, Layer layer, Frame frame) async {
    if (_session._disposed) {
      return null; // Mid-sweep dispose: stop touching the stores.
    }
    final raw = _session.brushFrameKeyForCut(cut, layer.id, frame.id);
    final key = _sweepRegistry.canonicalCelKey(raw);
    if (!_sweepSeen.add(key)) {
      return false; // Linked banks share one physical projection.
    }
    final baked = await _catchUpTextCel(cut, frame, raw: raw, key: key);
    if (baked == null) {
      return null; // Disposed mid-bake: stop touching the stores.
    }
    return baked;
  }

  /// The sweep in flight: the registry it resolves keys through and the
  /// keys it has already baked (linked banks share one projection).
  late LayerLinkRegistry _sweepRegistry;
  final _sweepSeen = <BrushFrameKey>{};

  Future<void> _sweepTextCelBakesOnce() async {
    final project = _session.repository.currentProject;
    if (project == null) {
      _textCelBakedContent.clear();
      return;
    }
    _sweepRegistry = project.linkRegistry;
    _sweepSeen.clear();
    var changed = false;
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          if (layer.kind != LayerKind.text) {
            continue;
          }
          for (final frame in layer.frames) {
            final baked = await _bakeOneTextCel(cut, layer, frame);
            if (baked == null) {
              return;
            }
            changed = changed || baked;
          }
        }
      }
    }
    _textCelBakedContent.removeWhere((key, _) => !_sweepSeen.contains(key));
    if (changed && !_session._disposed) {
      _session.notifyChanged();
    }
  }

  /// One text cel caught up to its parameters: true when the store's
  /// pixels changed, false when they already matched (or were trusted on
  /// first sight), null when the session disposed mid-bake.
  Future<bool?> _catchUpTextCel(
    Cut cut,
    Frame frame, {
    required BrushFrameKey raw,
    required BrushFrameKey key,
  }) async {
    final content = frame.textContent;
    final baked = (content, cut.canvasSize);
    final known = _textCelBakedContent[key];
    if (known == baked) {
      return false;
    }
    if (known == null &&
        content != null &&
        content.text.isNotEmpty &&
        _session.brushFrameStore.celHasRenderableContent(raw)) {
      // First sight of a cel that already carries pixels (a loaded
      // project): trust the stored projection instead of paying a
      // full re-render on open (saves flush in-flight bakes, so an
      // archive can never pair new params with an old raster). A
      // pasted/duplicated cel arrives with an EMPTY store bank and
      // falls through to the bake.
      _textCelBakedContent[key] = baked;
      return false;
    }
    var changed = false;
    if (content == null || content.text.isEmpty) {
      // The parameters went (undo of a set, cleared text): the
      // projection goes with them — the cel reads blank again.
      // ONLY for cels this sweep itself baked: a drawn cel that
      // arrives on a text row through a cross-row move has no
      // entry here, and blank-baking it would destroy artwork
      // undo cannot restore.
      if (known != null) {
        bakeCelSurface(
          _session.brushFrameStore,
          raw,
          BitmapSurface(canvasSize: cut.canvasSize),
        );
        changed = true;
      }
    } else {
      final rendered = await renderTextCelImage(
        content: content,
        canvas: cut.canvasSize,
      );
      try {
        if (_session._disposed) {
          return null;
        }
        final surface = await rasterizeImageToSurface(
          image: rendered.image,
          canvas: cut.canvasSize,
          fit: MediaFitMode.none,
          // The render already clipped to the pasteboard wall —
          // its own placement keeps off-canvas overflow alive,
          // like any oversized drop.
          placement: rendered.placement,
        );
        if (_session._disposed) {
          return null;
        }
        bakeCelSurface(_session.brushFrameStore, raw, surface);
        changed = true;
      } finally {
        rendered.image.dispose();
      }
    }
    _textCelBakedContent[key] = baked;
    return changed;
  }

  /// The active text cel's parameters (null on blank cells and non-text
  /// rows) — the text editor dialog's read side.
  TextCelContent? get selectedTextCelContent =>
      _session.activeLayer?.kind == LayerKind.text
      ? _session.selectedFrame?.textContent
      : null;

  /// Commits the text editor's result onto the selected cel: one undo,
  /// linked-cut mirror, projection re-baked by the sweep.
  void setTextCelContentForSelectedFrame(TextCelContent content) {
    final layer = _session.activeLayer;
    final frame = _session.selectedFrame;
    if (layer == null || layer.kind != LayerKind.text || frame == null) {
      return;
    }
    _session.timelineController.setTextContentForFrame(
      layerId: layer.id,
      frameId: frame.id,
      textContent: content,
    );
    _session.notifyChanged();
  }
}
