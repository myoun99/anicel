import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/brush_frame_cache_invalidation.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../native/qa_native_engine.dart';
import '../services/playback/editor_cache_invalidation_hub.dart';
import 'media/viewer_raster_budget.dart';

/// One picture the storyboard shows: a cut, composited at one of its
/// frames.
///
/// A cut used to have exactly one, so the cut was the key. It has one per
/// PANEL now — the conte's cells are panels of the cut, and each shows the
/// composite at its own division — so the frame joins the key. A cut with
/// no storyboard row still has a single panel and therefore a single
/// picture, which is the old behaviour arriving as a special case of the
/// new one.
/// How big a panel's picture is asked for.
///
/// The axis that was missing (user, 2026-08-06: the conte's picture cells
/// looked like a quarter of what they should — *"항상 풀퀄리티로 보고싶어"*).
/// One store serves both panels ON PURPOSE — a cell and its strip block are
/// one render, never two that must be kept in step — but they want
/// different resolutions: the strip draws blocks a finger wide, the conte
/// draws a printed frame that also exports. So the SIZE joins the key
/// rather than the strip's number being raised for everyone.
enum StoryboardThumbnailTier {
  /// The timeline strip's blocks.
  strip(128),

  /// A printed sheet's picture cell — the width the conte PDF already
  /// renders its cells at, so screen and export agree.
  sheet(640);

  const StoryboardThumbnailTier(this.width);

  final int width;
}

typedef StoryboardThumbnailKey = ({
  CutId cutId,
  int frameIndex,
  StoryboardThumbnailTier tier,
});

/// The build-time resolver the panel and the conte call.
typedef StoryboardThumbnailResolver =
    ui.Image? Function(Cut cut, int frameIndex, {StoryboardThumbnailTier tier});

/// Renders and caches the small composites the storyboard's panels show.
///
/// [thumbnailFor] is a synchronous build-time resolver: it returns whatever
/// is cached (possibly stale, possibly null) and kicks one async render at
/// thumbnail resolution when the panel's signature changed. Renders finish
/// → [notifyListeners] → the panel rebuilds with the fresh image.
///
/// Invalidation: a structural signature (canvas size, duration, per-layer
/// visibility/opacity/frames/EXPOSURES, camera track, layer transforms and
/// the cut fade — everything the camera-view render consumes) plus a
/// per-cut edit generation bumped by the hub's brush-frame events (stroke
/// commit / undo / redo). Camera work, transform-lane edits and exposure
/// moves used to be signature-blind (R4-⑩): a cut whose thumbnail first
/// rendered empty stayed a white block forever unless a stroke landed.
///
/// The edit generation stays keyed by CUT: a stroke lands somewhere in the
/// cut and the hub says which cut, so every panel of it re-renders. That is
/// correct rather than merely convenient — a drawing may be exposed under
/// several panels at once.
///
/// 🚨★★BOUNDED IN BYTES since 2026-09-11. It used to hold every panel ever
/// looked at — at the conte's 640px, about 0.9MB a 16:9 cell — until the
/// workspace closed, and nothing counted it: no budget, no census row, and
/// a deleted cut's pictures stayed. It now takes ONE VIEWER'S SHARE of the
/// device ([ViewerRasterBudget]): like the viewer's pages, these pictures
/// are a view of the drawings that re-renders on demand, so they answer to
/// the same device law and hear the same memory warning instead of a
/// third number. The least recently asked-for picture goes first — which
/// is also how a deleted cut's pictures leave.
class StoryboardCutThumbnailStore extends ChangeNotifier {
  StoryboardCutThumbnailStore({
    required Future<ui.Image?> Function(Cut cut, int frameIndex, int width)
    render,
    EditorCacheInvalidationHub? invalidationHub,
    this.onHeldBytesChanged,
  }) : _render = render,
       _hub = invalidationHub {
    _hub?.addBrushFrameListener(_onBrushFrameInvalidated);
  }

  final Future<ui.Image?> Function(Cut cut, int frameIndex, int width) _render;
  final EditorCacheInvalidationHub? _hub;

  final Map<StoryboardThumbnailKey, ui.Image> _images = {};
  final Map<StoryboardThumbnailKey, String> _renderedSignatures = {};
  final Map<CutId, int> _editGenerations = {};
  final Set<StoryboardThumbnailKey> _rendering = {};
  bool _disposed = false;

  /// Told whenever [thumbnailBytes] changes, so an owner the memory census
  /// CAN reach is able to report a store that lives in a widget State — the
  /// same shape as `DisplayBufferCache.onHeldBytesChanged`.
  final void Function(int bytes)? onHeldBytesChanged;

  /// One viewer's share of this device, halved by the memory warning — see
  /// the class doc for why a viewer's.
  final ViewerRasterBudget _budget = ViewerRasterBudget(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  int _heldBytes = 0;

  /// What the held pictures cost resident, 4 bytes a pixel.
  int get thumbnailBytes => _heldBytes;

  /// The cached thumbnail for [cut] at [frameIndex]; kicks an async
  /// (re)render when the signature changed, returning the stale image
  /// meanwhile.
  ui.Image? thumbnailFor(
    Cut cut,
    int frameIndex, {
    StoryboardThumbnailTier tier = StoryboardThumbnailTier.strip,
  }) {
    final key = (cutId: cut.id, frameIndex: frameIndex, tier: tier);
    final signature = _signatureFor(cut, frameIndex);
    if (_renderedSignatures[key] != signature && !_rendering.contains(key)) {
      _rendering.add(key);
      _startRender(cut, key, signature);
    }
    final held = _images.remove(key);
    if (held != null) {
      // Asked for: to the young end of the eviction order.
      _images[key] = held;
    }
    return held;
  }

  void _startRender(Cut cut, StoryboardThumbnailKey key, String signature) {
    unawaited(
      _render(cut, key.frameIndex, key.tier.width)
          .then((image) {
            _rendering.remove(key);
            if (_disposed) {
              image?.dispose();
              return;
            }
            final previous = _images.remove(key);
            if (previous != null) {
              _heldBytes -= ViewerRasterBudget.costOf(previous);
              _retire(previous);
            }
            if (image != null) {
              _images[key] = image;
              _heldBytes += ViewerRasterBudget.costOf(image);
            }
            // A signature change DURING the render re-kicks on the rebuild
            // this notify triggers.
            _renderedSignatures[key] = signature;
            _evictBeyondBudget();
            _reportHeldBytes();
            notifyListeners();
          })
          .catchError((Object error, StackTrace stack) {
            _rendering.remove(key);
            // Remember the failed signature: silently swallowing AND
            // forgetting re-kicked the same failing render on every
            // rebuild (a hot loop behind a permanently empty block). The
            // next CONTENT change retries; the failure itself is surfaced.
            _renderedSignatures[key] = signature;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'storyboard thumbnails',
                context: ErrorDescription(
                  'rendering the storyboard thumbnail for cut '
                  '${cut.id.value} at frame ${key.frameIndex}',
                ),
              ),
            );
          }),
    );
  }

  /// Lets go of the least recently asked-for pictures until the held ones
  /// fit the budget — never the newest, which is what a panel just asked
  /// for (the same rule as every other cache here).
  void _evictBeyondBudget() {
    while (_heldBytes > _budget.byteBudget && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      _heldBytes -= ViewerRasterBudget.costOf(image);
      _retire(image);
      // 🚨The signature goes WITH the picture. Kept, it would tell the next
      // [thumbnailFor] that this panel is already rendered, and the panel
      // would stay an empty block for good.
      _renderedSignatures.remove(oldest);
    }
  }

  /// The OS says memory is tight: halve, never below one viewer page, and
  /// give back what no longer fits. Idempotent — see [ViewerRasterBudget].
  void respondToMemoryPressure() {
    if (!_budget.respondToMemoryPressure()) {
      return;
    }
    final before = _images.length;
    _evictBeyondBudget();
    if (_images.length != before) {
      _reportHeldBytes();
      // Panels still showing an evicted picture must rebuild before it is
      // disposed — [_retire] waits for the next frame, and this notify is
      // what puts a rebuild into that frame.
      notifyListeners();
    }
  }

  void _reportHeldBytes() => onHeldBytesChanged?.call(_heldBytes);

  /// Coalesces invalidation-driven notifies: a stroke commits MANY hub
  /// events, one microtask notify covers them all.
  bool _invalidationNotifyScheduled = false;

  void _onBrushFrameInvalidated(BrushFrameCacheInvalidation invalidation) {
    final cutId = invalidation.frameKey.cutId;
    _editGenerations[cutId] = (_editGenerations[cutId] ?? 0) + 1;
    // Rendering stays lazy (the next thumbnailFor call sees the bumped
    // signature) but the notify must fire HERE: brush strokes never notify
    // the session, so without it nothing rebuilt a visible storyboard and
    // freshly drawn artwork never reached its thumbnail (the R5-⑩
    // "thumbnails never show up" device report).
    if (_invalidationNotifyScheduled || _disposed) {
      return;
    }
    _invalidationNotifyScheduled = true;
    scheduleMicrotask(() {
      _invalidationNotifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  String _signatureFor(Cut cut, int frameIndex) {
    final buffer = StringBuffer()
      ..write(cut.canvasSize.width)
      ..write('x')
      ..write(cut.canvasSize.height)
      ..write('#')
      ..write(_editGenerations[cut.id] ?? 0)
      ..write('#')
      ..write(cut.duration)
      ..write('#f')
      ..write(frameIndex)
      // The thumbnail renders THROUGH the camera: camera work must
      // re-render it (was signature-blind — R4-⑩). The fade component is
      // gone with the cut transform (R4): the effects are TRACK data and
      // never bake into the thumbnail's composite.
      ..write('#cam')
      ..write(cut.camera.track.hashCode);
    for (final layer in cut.layers) {
      buffer
        ..write('|')
        ..write(layer.id.value)
        ..write(':')
        ..write(layer.isVisible)
        ..write(':')
        ..write(layer.opacity)
        ..write(':')
        ..write(layer.frames.length)
        ..write(':')
        ..write(layer.frames.isEmpty ? '' : layer.frames.first.id.value)
        // Layer transforms apply at composite time — lane edits must
        // re-render (was signature-blind — R4-⑩).
        ..write(':')
        ..write(layer.transformTrack.hashCode)
        // Same rule for the blend and the R6 effect chain: both change the
        // composited pixels and nothing else in this signature would move.
        ..write(':')
        ..write(layer.blendMode.name)
        ..write(':')
        ..write(Object.hashAll(layer.effects))
        // Which frame is EXPOSED at the thumbnail index is timeline data;
        // exposure-only edits used to leave a stale thumb (documented gap,
        // now closed). Deterministic fold over the entries — Map itself
        // hashes by identity.
        ..write(':')
        ..write(_timelineDigest(layer));
    }
    return buffer.toString();
  }

  int _timelineDigest(Layer layer) {
    var digest = 0;
    for (final entry in layer.timeline.entries) {
      digest = Object.hash(digest, entry.key, entry.value);
    }
    return digest;
  }

  /// Disposes a replaced image AFTER the next frame paints: a RawImage from
  /// the previous build may still reference it during the current one.
  void _retire(ui.Image image) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      image.dispose();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _hub?.removeBrushFrameListener(_onBrushFrameInvalidated);
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _heldBytes = 0;
    _reportHeldBytes();
    super.dispose();
  }
}
