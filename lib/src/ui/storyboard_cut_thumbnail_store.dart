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
import 'media/viewer_render_tier.dart';

/// One picture the storyboard shows: a cut, composited at one of its
/// frames, at one width.
///
/// A cut used to have exactly one, so the cut was the key. It has one per
/// PANEL now — the conte's cells are panels of the cut, and each shows the
/// composite at its own division — so the frame joins the key. A cut with
/// no storyboard row still has a single panel and therefore a single
/// picture, which is the old behaviour arriving as a special case of the
/// new one.
///
/// The WIDTH is the axis that was missing (user, 2026-08-06: the conte's
/// picture cells looked like a quarter of what they should —
/// *"항상 풀퀄리티로 보고싶어"*). One store serves both panels ON PURPOSE — a
/// cell and its strip block are one render, never two that must be kept in
/// step — but they show it at different sizes, so the size joins the key.
/// ↩️It was two fixed tiers (a strip block's 128 and a sheet cell's 640),
/// and a zoomed-in cell or a tall V row stretched the picture past the
/// pixels it had; it is now the size the surface SHOWS it at
/// ([pictureRenderWidthFor] — 유저 2026-09-25 「화면이 필요한 만큼(최대
/// 원본)」, and for the cut blocks 「같은로직으로 법 통일」).
typedef StoryboardThumbnailKey = ({CutId cutId, int frameIndex, int width});

/// The resolver the storyboard's rows and the conte's page ask while they
/// PAINT — only for what their window shows, saying how many device pixels
/// tall they draw the picture ([shownHeight]). The width that buys is the
/// store's answer, never the surface's.
typedef StoryboardThumbnailResolver =
    ui.Image? Function(Cut cut, int frameIndex, {required double shownHeight});

/// A surface's panel pictures: [resolve] asked while it paints, and
/// [landed] told when a render lands or a picture is let go — ONE value,
/// so no surface can draw the pictures without hearing when they change.
///
/// ↩️The storyboard and the conte heard a landing by REBUILDING their
/// whole tab (the store sat in each tab's listenable merge) — at I-22's
/// ten-minute zoom every cut on the film lands one, and each rebuilt the
/// storyboard's ruler, rows and chrome. The folded storyboard row took the
/// resolver alone and heard nothing: its pictures showed whenever
/// something else happened to repaint it. The painters that ask are the
/// ones that repaint now.
typedef StoryboardThumbnails = ({
  StoryboardThumbnailResolver resolve,
  Listenable landed,
});

/// Renders and caches the composites the storyboard's panels show.
///
/// [thumbnailFor] is a synchronous paint-time resolver: it returns whatever
/// is cached (possibly stale, possibly null) and puts the panel on the list
/// of what to render, at the width the surface's size asks, when its
/// signature changed. Renders finish → [notifyListeners] → the painters
/// that asked repaint with the fresh image ([thumbnails]).
///
/// 🚨★★★ONE RENDER AT A TIME, AND ONLY WHAT IS SHOWN NOW (2026-09-28 —
/// 유저: 「fu파일로, 콘티패널 v행 크기 늘리던 도중에 튕겻어」). Every ask
/// used to start its own render on the spot. A render thaws its cut's cels
/// at the CANVAS's size whatever width it is asked for (2540×1654 in the
/// user's film), and growing the V rows walks up the picture ladder, so
/// each step asked every panel on screen afresh: measured on that film
/// (13 cuts, 26 panels, the whole film on screen), one second of dragging
/// the rows from the floor to 400 had 104 renders running at once, and the
/// first 26 alone took the process from 674MB to 1244MB. That is the
/// crash on a tablet. Now an ask only puts the panel on the list, one
/// render runs, and when it ends the list is emptied: its landing repaints
/// every surface that asks (they have to, to show it), and they ask again
/// for exactly what they show NOW — a width the hand has already passed or
/// a panel scrolled away is never rendered at all.
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
    required ui.Size Function() originalSize,
    EditorCacheInvalidationHub? invalidationHub,
    this.onHeldBytesChanged,
  }) : _render = render,
       _originalSize = originalSize,
       _hub = invalidationHub {
    _hub?.addBrushFrameListener(_onBrushFrameInvalidated);
  }

  final Future<ui.Image?> Function(Cut cut, int frameIndex, int width) _render;

  /// The size a picture has at its fullest — the camera frame it renders
  /// through. No width past it is ever asked for.
  final ui.Size Function() _originalSize;
  final EditorCacheInvalidationHub? _hub;

  final Map<StoryboardThumbnailKey, ui.Image> _images = {};
  final Map<StoryboardThumbnailKey, String> _renderedSignatures = {};
  final Map<CutId, int> _editGenerations = {};

  /// What the surfaces asked to have rendered since the last render ended,
  /// in the order they asked — each with the cut and the signature it was
  /// asked at.
  final Map<StoryboardThumbnailKey, ({Cut cut, String signature})> _wanted =
      {};

  /// The one render running, if any. It is not asked for again while it
  /// runs: its landing repaints the surfaces, which ask again then if the
  /// panel moved on meanwhile.
  StoryboardThumbnailKey? _rendering;
  bool _nextScheduled = false;
  bool _disposed = false;

  /// Whether a render runs or waits to. ⚠️TEST ONLY — what a test waits
  /// on, as the timeline's tiles do: silence for N ms misreads a slow
  /// render for a finished one.
  @visibleForTesting
  bool get debugBusy => _rendering != null || _wanted.isNotEmpty;

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

  /// What a surface takes to draw these pictures: [thumbnailFor], and this
  /// store as what says one landed.
  late final StoryboardThumbnails thumbnails = (
    resolve: thumbnailFor,
    landed: this,
  );

  /// The cached picture of [cut] at [frameIndex] for a surface drawing it
  /// [shownHeight] device pixels tall; asks for a (re)render when that
  /// width's signature changed, returning the stale image meanwhile.
  ///
  /// A width that has never landed shows the panel's picture at another
  /// width until it does — 유저 2026-09-25 took exactly that as the cost of
  /// the answer (「확대한 직후 잠깐 이전 해상도가 보였다가 선명해진다」), and
  /// it is never an empty cell for a frame.
  ui.Image? thumbnailFor(
    Cut cut,
    int frameIndex, {
    required double shownHeight,
  }) {
    final key = (
      cutId: cut.id,
      frameIndex: frameIndex,
      width: pictureRenderWidthFor(shownHeight, _originalSize()),
    );
    final signature = _signatureFor(cut);
    if (_renderedSignatures[key] != signature && key != _rendering) {
      _wanted[key] = (cut: cut, signature: signature);
      _scheduleNext();
    }
    final held = _images.remove(key);
    if (held != null) {
      // Asked for: to the young end of the eviction order.
      _images[key] = held;
      return held;
    }
    return _standInFor(key);
  }

  /// The sharpest picture of [key]'s panel held at another width. Not
  /// moved in the eviction order: a stand-in stays as old as it was, so it
  /// is the first to go once the right width is in.
  ui.Image? _standInFor(StoryboardThumbnailKey key) {
    ui.Image? sharpest;
    for (final entry in _images.entries) {
      if (entry.key.cutId == key.cutId &&
          entry.key.frameIndex == key.frameIndex &&
          (sharpest == null || entry.value.width > sharpest.width)) {
        sharpest = entry.value;
      }
    }
    return sharpest;
  }

  /// Starts the next render off the paint that asked — a microtask, so a
  /// picture can land within a frame or two.
  void _scheduleNext() {
    if (_rendering != null || _nextScheduled) {
      return;
    }
    _nextScheduled = true;
    scheduleMicrotask(_renderNext);
  }

  /// The panel asked for first, rendered alone.
  void _renderNext() {
    _nextScheduled = false;
    if (_disposed || _rendering != null || _wanted.isEmpty) {
      return;
    }
    final key = _wanted.keys.first;
    final ask = _wanted.remove(key)!;
    _rendering = key;
    unawaited(
      Future.sync(() => _render(ask.cut, key.frameIndex, key.width)).then(
        (image) => _landed(key, ask.signature, image),
        onError: (Object error, StackTrace stack) {
          // Remember the failed signature: silently swallowing AND
          // forgetting re-kicked the same failing render on every
          // rebuild (a hot loop behind a permanently empty block). The
          // next CONTENT change retries; the failure itself is surfaced.
          _renderedSignatures[key] = ask.signature;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'storyboard thumbnails',
              context: ErrorDescription(
                'rendering the storyboard thumbnail for cut '
                '${ask.cut.id.value} at frame ${key.frameIndex}',
              ),
            ),
          );
          _renderEnded();
        },
      ),
    );
  }

  void _landed(StoryboardThumbnailKey key, String signature, ui.Image? image) {
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
    // A signature change DURING the render re-kicks on the repaint the
    // notify below triggers.
    _renderedSignatures[key] = signature;
    _evictBeyondBudget();
    _reportHeldBytes();
    _renderEnded();
  }

  /// A render is over, landed or failed: the list goes, and the notify
  /// makes every surface that asks repaint and ask again for what it shows
  /// now — which is the next list.
  void _renderEnded() {
    _rendering = null;
    if (_disposed) {
      return;
    }
    _wanted.clear();
    notifyListeners();
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
      // Panels still showing an evicted picture must repaint before it is
      // disposed — [_retire] waits for the next frame, and this notify is
      // what puts a repaint into that frame.
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
    // "thumbnails never show up" device report). It repaints the painters
    // that ask now, which is what asks again.
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

  /// [_signatureFor]'s answer per cut INSTANCE, with the edit generation it
  /// was spelled at. A cut is immutable — an edit is a new instance — so an
  /// instance's signature moves only with the generation, which carries the
  /// pixel edits no model does: a stroke leaves the cut as it was. ⚡I-22:
  /// at the ten-minute floor every panel of the film is asked for on every
  /// paint, and each ask spelled the cut's whole layer stack again and
  /// folded every timeline.
  final Expando<({int generation, String signature})> _signatures =
      Expando();

  /// How many signatures were spelled — the cost [_signatures] keeps off
  /// every paint.
  @visibleForTesting
  int get debugSignaturesSpelled => _spelled;
  int _spelled = 0;

  String _signatureFor(Cut cut) {
    final generation = _editGenerations[cut.id] ?? 0;
    final held = _signatures[cut];
    if (held != null && held.generation == generation) {
      return held.signature;
    }
    final signature = _spellSignature(cut, generation);
    _signatures[cut] = (generation: generation, signature: signature);
    return signature;
  }

  /// What every panel's picture of [cut] is made of — alike for all of
  /// them: a panel's frame is its KEY. ↩️The frame was spelled in here too
  /// (since the key took it, 3e46410fa), which made the same cut a string
  /// per panel.
  String _spellSignature(Cut cut, int generation) {
    _spelled += 1;
    final buffer = StringBuffer()
      ..write(cut.canvasSize.width)
      ..write('x')
      ..write(cut.canvasSize.height)
      ..write('#')
      ..write(generation)
      ..write('#')
      ..write(cut.duration)
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
    _wanted.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _heldBytes = 0;
    _reportHeldBytes();
    super.dispose();
  }
}
