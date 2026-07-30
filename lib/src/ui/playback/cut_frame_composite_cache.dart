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
import '../canvas/layer_pose_paint.dart';
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
  int referenceCount = 0;
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
    this.fxBypassedLayerIdsOf,
  });

  final LayerFrameImageCache layerImages;
  final BrushFrameStore frameStore;
  final CutBrushFrameKeyResolver frameKeyOf;

  /// The session's live fx-bypass view state (the layer-label fx switch);
  /// it joins every signature, so flipping a switch self-invalidates the
  /// affected composites. Null = nothing bypassed.
  final Set<LayerId> Function()? fxBypassedLayerIdsOf;

  final Map<(CutId, int, PlaybackQuality), CutFrameCompositeSignature> _index =
      {};
  final Map<CutFrameCompositeSignature, _CompositeEntry> _images = {};
  int _useCounter = 0;
  bool _disposed = false;

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
      fxBypassedLayerIds: fxBypassedLayerIdsOf?.call() ?? const {},
    );
  }

  /// The cached composite when its stored signature still matches the cut's
  /// current state; `null` on miss or staleness.
  ui.Image? validCompositeOrNull({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
  }) {
    final stored = _index[(cut.id, frameIndex, quality)];
    if (stored == null) {
      return null;
    }
    final entry = _images[stored];
    if (entry == null || stored != _signatureFor(cut, frameIndex, quality)) {
      return null;
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
            if (pass.drawsUnfilteredFirst) {
              await paintNodes(children);
              if (aborted) {
                return;
              }
            }
            canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
            await paintNodes(children);
            canvas.restore();
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
            final layerPose = layer.pose;
            if (layerPose != null) {
              canvas.save();
              applyLayerPoseTransform(
                canvas,
                layerPose,
                cut.canvasSize,
                anchorPoint: layer.anchorPoint,
                rasterScale: scale,
              );
            }
            final layerPaint = ui.Paint()
              ..filterQuality = ui.FilterQuality.low
              ..color = ui.Color.fromRGBO(0, 0, 0, layer.opacity)
              // R26 #30: the layer blend applies at composite time,
              // exactly like every other route.
              ..blendMode = layer.blendMode.paintBlendMode;
            // R6: the row's effects filter its own picture before the
            // opacity/blend meet the stack. The images here are ALREADY at
            // this quality tier's raster, so a canvas-pixel blur radius
            // has to be scaled with them — otherwise a half-size preview
            // would show a double-strength blur.
            resolveCompositeEffectPaint(
              layer.effects,
              rasterScale: scale,
            ).applyTo(layerPaint);
            final worldRect = layerImage.worldRect;
            if (worldRect.left == 0 &&
                worldRect.top == 0 &&
                layerImage.image.width == (worldRect.width * scale).round() &&
                layerImage.image.height ==
                    (worldRect.height * scale).round()) {
              // Canvas-extent image at this raster's resolution — the exact
              // legacy draw (bytes pinned by the composite parity suites).
              canvas.drawImage(layerImage.image, ui.Offset.zero, layerPaint);
            } else {
              // Pasteboard-extent image: map src onto its world rect
              // (raster scale applied). The canvas-sized toImage below
              // crops the off-canvas remainder, so playback/export stay
              // stage-only.
              canvas.drawImageRect(
                layerImage.image,
                ui.Rect.fromLTWH(
                  0,
                  0,
                  layerImage.image.width.toDouble(),
                  layerImage.image.height.toDouble(),
                ),
                ui.Rect.fromLTWH(
                  worldRect.left * scale,
                  worldRect.top * scale,
                  worldRect.width * scale,
                  worldRect.height * scale,
                ),
                layerPaint,
              );
            }
            if (layerPose != null) {
              canvas.restore();
            }
        }
      }
    }

    await paintNodes(signature.nodes);
    if (aborted) {
      recorder.endRecording().dispose();
      return null;
    }
    final picture = recorder.endRecording();
    try {
      // Last check before the big slice: the full-canvas rasterization is
      // the composite's dominant cost (raster-thread contention included).
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      return await picture.toImage(raster.width, raster.height);
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

  int get estimatedBytes {
    var total = 0;
    for (final entry in _images.values) {
      total += estimatedImageBytes(entry.image.width, entry.image.height);
    }
    return total;
  }

  /// Evicts least-recently-used composites until at or under [maxBytes],
  /// never touching frames inside any of the [protect] ranges (the playing
  /// playlist may span several cuts).
  void enforceBudget({
    required int maxBytes,
    List<PlaybackProtectedRange> protect = const [],
  }) {
    if (estimatedBytes <= maxBytes) {
      return;
    }
    final protectedSignatures = <CutFrameCompositeSignature>{};
    if (protect.isNotEmpty) {
      for (final entry in _index.entries) {
        final isProtected = protect.any(
          (range) => range.contains(entry.key.$1, entry.key.$2, entry.key.$3),
        );
        if (isProtected) {
          protectedSignatures.add(entry.value);
        }
      }
    }

    final evictable =
        _images.entries
            .where((entry) => !protectedSignatures.contains(entry.key))
            .toList()
          ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final candidate in evictable) {
      if (estimatedBytes <= maxBytes) {
        break;
      }
      final stale = _index.entries
          .where((entry) => entry.value == candidate.key)
          .map((entry) => entry.key)
          .toList();
      for (final key in stale) {
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

  void _pointIndexAt(
    (CutId, int, PlaybackQuality) indexKey,
    CutFrameCompositeSignature signature,
  ) {
    final previous = _index[indexKey];
    if (previous == signature) {
      return;
    }
    if (previous != null) {
      _releaseSignature(previous);
    }
    _index[indexKey] = signature;
    _images[signature]!.referenceCount += 1;
  }

  void _releaseIndexEntry((CutId, int, PlaybackQuality) indexKey) {
    final signature = _index.remove(indexKey);
    if (signature != null) {
      _releaseSignature(signature);
    }
  }

  void _releaseSignature(CutFrameCompositeSignature signature) {
    final entry = _images[signature];
    if (entry == null) {
      return;
    }
    entry.referenceCount -= 1;
    if (entry.referenceCount <= 0) {
      _images.remove(signature);
      DeferredImageDisposer.instance.retire(entry.image);
    }
  }
}
