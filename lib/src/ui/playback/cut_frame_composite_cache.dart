import 'dart:ui' as ui;

import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/playback_quality.dart';
import '../../services/brush_frame_store.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../canvas/composite_effect_paint.dart';
import '../canvas/deferred_image_disposal.dart';
import '../canvas/layer_image_draw.dart';
import '../debug/input_inspector.dart';
import 'layer_frame_image_cache.dart';
import 'playback_cache_budget.dart';

/// Resolves the store key of a layer frame within [cut] (production impl
/// lives on the session, which knows project/track ids).
typedef CutBrushFrameKeyResolver =
    BrushFrameKey Function(Cut cut, LayerId layerId, FrameId frameId);

/// The frame range being played (or about to play) that budget eviction
/// must not touch.
class PlaybackProtectedRange {
  const PlaybackProtectedRange({
    required this.cutId,
    required this.startFrame,
    required this.endFrame,
    required this.quality,
  });

  final CutId cutId;
  final int startFrame;
  final int endFrame;
  final PlaybackQuality quality;

  bool contains(CutId cutId, int frameIndex, PlaybackQuality quality) {
    return cutId == this.cutId &&
        quality == this.quality &&
        frameIndex >= startFrame &&
        frameIndex <= endFrame;
  }
}

class _CompositeEntry {
  _CompositeEntry({required this.image});

  final ui.Image image;

  /// The index keys pointing at this image — the reference count AND the
  /// reverse index in one. Eviction used to rediscover these by scanning
  /// the whole index per candidate and comparing SIGNATURES, whose `==`
  /// walks every layer node — O(candidates × index × layers), inside a
  /// function that runs after every warmed frame.
  final Set<(CutId, int, PlaybackQuality)> indexKeys =
      <(CutId, int, PlaybackQuality)>{};

  int lastUsed = 0;
}

/// Level-2 playback cache: `(cut, frameIndex, quality)` → composited
/// canvas-space `ui.Image`, GPU-composed from [LayerFrameImageCache] images.
///
/// Composites self-validate through [CutFrameCompositeSignature]; held
/// exposures produce equal signatures and therefore share one stored image
/// (content addressing + reference counting). The camera is never baked in,
/// so camera edits leave every composite valid.
class CutFrameCompositeCache {
  CutFrameCompositeCache({
    required this.layerImages,
    required this.frameStore,
    required this.frameKeyOf,
  });

  final LayerFrameImageCache layerImages;
  final BrushFrameStore frameStore;
  final CutBrushFrameKeyResolver frameKeyOf;

  // R8: the fx switches are model state on the cut, so nothing about them
  // is held here — they reach the signature through the plan, which
  // self-invalidates any cached frame whose pixels they change.
  final Map<(CutId, int, PlaybackQuality), CutFrameCompositeSignature> _index =
      {};
  final Map<CutFrameCompositeSignature, _CompositeEntry> _images = {};
  int _useCounter = 0;
  bool _disposed = false;

  /// Running byte total, adjusted where images enter and leave — the
  /// getter used to WALK the whole map, and the eviction loop read it per
  /// candidate: O(entries²) in a function that runs after every warmed
  /// frame.
  int _estimatedBytes = 0;

  CutFrameCompositeSignature _signatureFor(
    Cut cut,
    int frameIndex,
    PlaybackQuality quality,
  ) {
    return computeCutFrameCompositeSignature(
      cut: cut,
      frameIndex: frameIndex,
      quality: quality,
      revisionOf: (layerId, frameId) =>
          frameStore
              .frameOrNull(frameKeyOf(cut, layerId, frameId))
              ?.sourceRevision ??
          0,
    );
  }

  /// The cached composite when its stored signature still matches the cut's
  /// current state; `null` on miss or staleness.
  ///
  /// C2 — THE SIGNATURE IS THE ADDRESS, AND THE INDEX IS ONLY THE
  /// ACCELERATOR. A frame whose index key was never filed can still be
  /// answered by content: held exposures share one signature, so the
  /// image baked for frame 0 IS frame 1's image, and a covering-layer cut
  /// is one entry answering every frame. Before this, those frames read
  /// "cold" until the warm loop visited each one just to file a key —
  /// the readiness bar lied by omission at exactly the frames that were
  /// already paid for.
  ///
  /// The hit adopts the key (`_pointIndexAt`), which is load-bearing, not
  /// cosmetic: pins and protected ranges test an entry's `indexKeys`, so
  /// an unfiled frame would be an unprotectable frame.
  ///
  /// ⚠️Cost shape: a MISS now computes one signature where the bare index
  /// miss used to return free — but every miss path that matters was
  /// already paying it (prepare computes the signature to build; the
  /// readiness bar resolves the same shared visit for its empty-frame
  /// answer). The hit path pays exactly what it always did: one
  /// signature, one compare.
  ui.Image? validCompositeOrNull({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
  }) {
    final indexKey = (cut.id, frameIndex, quality);
    final fresh = _signatureFor(cut, frameIndex, quality);
    final entry = _images[fresh];
    if (entry == null) {
      return null;
    }
    if (_index[indexKey] != fresh) {
      _pointIndexAt(indexKey, fresh);
    }
    entry.lastUsed = ++_useCounter;
    return entry.image;
  }

  /// Returns a valid composite, building it when missing or stale. Frames
  /// with no drawn content composite to a fully transparent image.
  Future<ui.Image> prepareComposite({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
  }) async {
    final signature = _signatureFor(cut, frameIndex, quality);
    final indexKey = (cut.id, frameIndex, quality);

    final existing = _images[signature];
    if (existing != null) {
      _pointIndexAt(indexKey, signature);
      existing.lastUsed = ++_useCounter;
      return existing.image;
    }

    final image = await _composeImage(cut, signature);
    return _storeComposed(indexKey, signature, image!);
  }

  /// [prepareComposite] that can stand down mid-build: [shouldAbort] is
  /// checked between per-layer prepares; an abort returns null with nothing
  /// cached, and the caller retries when its own signal says so (the warm
  /// loop once the editor is quiet, the parked track stack on the next
  /// parking move). Abandonable work only — the always-on display paths
  /// keep [prepareComposite] (R13-3).
  Future<ui.Image?> prepareCompositeInterruptible({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
    required bool Function() shouldAbort,
  }) async {
    final signature = _signatureFor(cut, frameIndex, quality);
    final indexKey = (cut.id, frameIndex, quality);

    final existing = _images[signature];
    if (existing != null) {
      _pointIndexAt(indexKey, signature);
      existing.lastUsed = ++_useCounter;
      return existing.image;
    }

    final image = await _composeImage(cut, signature, shouldAbort: shouldAbort);
    if (image == null) {
      return null;
    }
    if (_disposed) {
      // Torn down while composing: caching into the disposed maps would
      // leak the image forever (dispose never runs again).
      DeferredImageDisposer.instance.retire(image);
      return null;
    }
    return _storeComposed(indexKey, signature, image);
  }

  /// The store step both prepare paths share. The compose awaited, so a
  /// CONCURRENT prepare for the same signature may have stored meanwhile —
  /// held exposures share one signature across frame indexes, and the
  /// warmer runs in parallel with on-demand display requests. The first
  /// store wins: overwriting would orphan its entry while index keys still
  /// hold reference counts on it, and the orphan's image could never be
  /// released (the leak the parked track stack surfaced).
  ui.Image _storeComposed(
    (CutId, int, PlaybackQuality) indexKey,
    CutFrameCompositeSignature signature,
    ui.Image image,
  ) {
    final landed = _images[signature];
    if (landed != null) {
      image.dispose();
      landed.lastUsed = ++_useCounter;
      _pointIndexAt(indexKey, signature);
      return landed.image;
    }
    final entry = _CompositeEntry(image: image)..lastUsed = ++_useCounter;
    _images[signature] = entry;
    _estimatedBytes += estimatedImageBytes(image.width, image.height);
    _pointIndexAt(indexKey, signature);
    return image;
  }

  /// Null only when [shouldAbort] fired (never without one).
  Future<ui.Image?> _composeImage(
    Cut cut,
    CutFrameCompositeSignature signature, {
    bool Function()? shouldAbort,
  }) async {
    final raster = scaledCanvasSize(cut.canvasSize, signature.quality);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final scale = raster.width / cut.canvasSize.width;
    final rasterBounds = ui.Rect.fromLTWH(
      0,
      0,
      raster.width.toDouble(),
      raster.height.toDouble(),
    );
    var aborted = false;

    Future<void> paintNodes(List<CompositeNodeSignature> nodes) async {
      for (final node in nodes) {
        if (aborted) {
          return;
        }
        if (shouldAbort?.call() ?? false) {
          aborted = true;
          return;
        }
        switch (node) {
          case CompositeGroupSignature(
            :final children,
            :final opacity,
            :final blendMode,
            :final effects,
          ):
            // R27 #29: the members compose into ONE buffer and the
            // folder's opacity/blend land on it once — overlapping
            // members inside a multiply folder stop darkening where they
            // cross. Only a folder that NEEDS this ever becomes a group
            // node, so a plain 통과 folder costs no saveLayer at all.
            final groupEffects = resolveCompositeEffectPaint(
              effects,
              rasterScale: scale,
            );
            final groupPaint = ui.Paint()
              ..color = ui.Color.fromRGBO(0, 0, 0, opacity)
              ..blendMode = blendMode.paintBlendMode;
            groupEffects.applyTo(groupPaint);
            canvas.saveLayer(
              // R6: a group blur must be allowed to bleed in from just
              // outside the raster, so the buffer grows by its spread.
              effectBufferBounds(rasterBounds, groupEffects),
              groupPaint,
            );
            await paintNodes(children);
            canvas.restore();
          case CompositeAdjustmentSignature(
            :final children,
            :final effects,
            :final mix,
          ):
            // R6b: the scope into one buffer, the row's chain onto it. The
            // radii scale with this quality tier's raster like every other
            // blur here.
            final pass = resolveAdjustmentScopePass(
              bounds: rasterBounds,
              effects: effects,
              mix: mix,
              rasterScale: scale,
            );
            if (pass.crossfades) {
              canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
              canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
              await paintNodes(children);
              canvas.restore();
              if (aborted) {
                canvas.restore(); // Close the crossfade buffer we opened.
                return;
              }
            }
            canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
            await paintNodes(children);
            canvas.restore();
            if (pass.crossfades) {
              canvas.restore();
            }
          case CompositeLeafSignature(:final layer):
            final layerImage = await layerImages.prepare(
              key: frameKeyOf(cut, layer.layerId, layer.frameId),
              canvasSize: cut.canvasSize,
              quality: signature.quality,
              shouldAbort: shouldAbort,
            );
            if (layerImage == null) {
              // Null is EITHER an empty frame (skip the layer) or an abort
              // from inside the layer build — disambiguate and bail on
              // abort.
              if (shouldAbort?.call() ?? false) {
                aborted = true;
                return;
              }
              continue;
            }
            // Layer transforms apply at composite time; the pose is
            // canvas-space, adapted to this quality tier's raster scale.
            // Folder FX is already COMPOSED into this pose by the shared
            // visit (an affine transform distributes over compositing, so
            // it needs no buffer) — one pose, every route identical.
            //
            // R6: the row's effects filter its own picture before the
            // opacity/blend meet the stack, and the images here are
            // ALREADY at this quality tier's raster — so the scale reaches
            // the effect resolver too, or a half-size preview would show a
            // double-strength blur.
            final worldRect = layerImage.worldRect;
            drawPosedLayerImage(
              canvas,
              image: layerImage.image,
              worldRect: worldRect,
              canvasSize: cut.canvasSize,
              pose: layer.pose,
              anchorPoint: layer.anchorPoint,
              opacity: layer.opacity,
              blendMode: layer.blendMode,
              effects: layer.effects,
              rasterScale: scale,
              // A4: today's value, now in writing — bilinear, as this
              // route has always sampled.
              filterQuality: ui.FilterQuality.low,
              // A canvas-extent image at this raster's resolution takes
              // the legacy whole-image draw, whose bytes the composite
              // parity suites pin. A pasteboard-extent one maps src onto
              // its world rect instead; the canvas-sized toImage below
              // crops the off-canvas remainder, so playback and export
              // stay stage-only either way.
              drawAtOrigin:
                  worldRect.left == 0 &&
                  worldRect.top == 0 &&
                  layerImage.image.width == (worldRect.width * scale).round() &&
                  layerImage.image.height == (worldRect.height * scale).round(),
            );
        }
      }
    }

    // S1 — the composite's cost, split at its only seam: the Dart-side
    // walk (layer prepares included) versus the full-canvas
    // rasterization. 「빔이 느리게 차」 is one number until this says which
    // half it lives in. Inspector-gated: release builds pay nothing while
    // it is hidden, and the release iPad is exactly where it must read.
    // ⛔The watch wraps the awaited `toImage`, never a `toImageSync` —
    // sync recording returns before the raster work runs and the watch
    // would read ~0 (계측기 거짓말 세 번째 얼굴).
    final walkWatch = InputInspector.visible.value
        ? (Stopwatch()..start())
        : null;
    await paintNodes(signature.nodes);
    if (aborted) {
      recorder.endRecording().dispose();
      return null;
    }
    final picture = recorder.endRecording();
    walkWatch?.stop();
    try {
      // Last check before the big slice: the full-canvas rasterization is
      // the composite's dominant cost (raster-thread contention included).
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      final imageWatch = walkWatch == null ? null : (Stopwatch()..start());
      final image = await picture.toImage(raster.width, raster.height);
      if (walkWatch != null) {
        InputInspector.note(
          'cmp ${raster.width}x${raster.height} '
          'walk ${walkWatch.elapsedMilliseconds}ms '
          'img ${imageWatch!.elapsedMilliseconds}ms',
        );
      }
      return image;
    } finally {
      picture.dispose();
    }
  }

  /// Eagerly drops composites containing one layer frame (sink events).
  void invalidateWhereLayerFrame({
    required LayerId layerId,
    required FrameId frameId,
  }) {
    final stale = _index.entries
        .where(
          (entry) => entry.value.layers.any(
            (layer) => layer.layerId == layerId && layer.frameId == frameId,
          ),
        )
        .map((entry) => entry.key)
        .toList();
    for (final key in stale) {
      _releaseIndexEntry(key);
    }
  }

  void invalidateCut(CutId cutId) {
    final stale = _index.keys.where((key) => key.$1 == cutId).toList();
    for (final key in stale) {
      _releaseIndexEntry(key);
    }
  }

  int get estimatedBytes => _estimatedBytes;

  /// Evicts least-recently-used composites until at or under [maxBytes],
  /// never touching frames inside any of the [protect] ranges (the playing
  /// playlist may span several cuts).
  ///
  /// One pass over the IMAGES, using each entry's own reverse keys: no
  /// signature is hashed or compared here at all. The old shape re-walked
  /// the byte total per candidate and rediscovered each image's index keys
  /// by scanning the whole index with signature `==` — `listEquals` over
  /// every layer node — which made the enforcer O(entries² × layers) in
  /// the function that runs after every warmed frame. At 1500 cuts it was
  /// costlier than the work it freed.
  void enforceBudget({
    required int maxBytes,
    List<PlaybackProtectedRange> protect = const [],
  }) {
    if (_estimatedBytes <= maxBytes) {
      return;
    }
    bool isProtected(_CompositeEntry entry) {
      for (final key in entry.indexKeys) {
        // A pinned frame is on screen through a holder's clone —
        // playback's held frame, the parked track stack. Evicting it
        // returns no bytes and re-composites the exact picture being
        // shown.
        if (_pins.containsKey(key)) {
          return true;
        }
        for (final range in protect) {
          if (range.contains(key.$1, key.$2, key.$3)) {
            return true;
          }
        }
      }
      return false;
    }

    final evictable =
        _images.values.where((entry) => !isProtected(entry)).toList()
          ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final candidate in evictable) {
      if (_estimatedBytes <= maxBytes) {
        break;
      }
      for (final key in candidate.indexKeys.toList()) {
        _releaseIndexEntry(key);
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final key in _index.keys.toList()) {
      _releaseIndexEntry(key);
    }
  }

  // --- Display pins (A6) ----------------------------------------------
  //
  // Same contract as [LayerFrameImageCache]'s pins: a holder that clones
  // a composite (playback's held frame, the parked track stack) declares
  // the slot, eviction refuses it, and [pinnedBytes] reports what the
  // screen is actually holding.

  final Map<(CutId, int, PlaybackQuality), int> _pins = {};

  void retainPin((CutId, int, PlaybackQuality) indexKey) {
    _pins[indexKey] = (_pins[indexKey] ?? 0) + 1;
  }

  void releasePin((CutId, int, PlaybackQuality) indexKey) {
    final count = _pins[indexKey];
    if (count == null) {
      assert(false, 'releasePin without a matching retainPin: $indexKey');
      return;
    }
    if (count <= 1) {
      _pins.remove(indexKey);
    } else {
      _pins[indexKey] = count - 1;
    }
  }

  /// The bytes of every pinned slot's current image, counted once per
  /// DISTINCT image — held exposures share one image under many keys.
  int get pinnedBytes {
    var total = 0;
    final seen = <_CompositeEntry>{};
    for (final key in _pins.keys) {
      final signature = _index[key];
      if (signature == null) {
        continue;
      }
      final entry = _images[signature];
      if (entry != null && seen.add(entry)) {
        total += estimatedImageBytes(entry.image.width, entry.image.height);
      }
    }
    return total;
  }

  void _pointIndexAt(
    (CutId, int, PlaybackQuality) indexKey,
    CutFrameCompositeSignature signature,
  ) {
    final previous = _index[indexKey];
    if (previous == signature) {
      return;
    }
    if (previous != null) {
      _releaseSignature(previous, indexKey);
    }
    _index[indexKey] = signature;
    _images[signature]!.indexKeys.add(indexKey);
  }

  void _releaseIndexEntry((CutId, int, PlaybackQuality) indexKey) {
    final signature = _index.remove(indexKey);
    if (signature != null) {
      _releaseSignature(signature, indexKey);
    }
  }

  void _releaseSignature(
    CutFrameCompositeSignature signature,
    (CutId, int, PlaybackQuality) indexKey,
  ) {
    final entry = _images[signature];
    if (entry == null) {
      return;
    }
    entry.indexKeys.remove(indexKey);
    if (entry.indexKeys.isEmpty) {
      _images.remove(signature);
      _estimatedBytes -= estimatedImageBytes(
        entry.image.width,
        entry.image.height,
      );
      DeferredImageDisposer.instance.retire(entry.image);
    }
  }
}
