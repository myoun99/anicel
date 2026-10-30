import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/signed_memo.dart';
import '../models/brush_frame_cache_invalidation.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../native/qa_native_engine.dart';
import '../services/playback/editor_cache_invalidation_hub.dart';
import 'media/shown_rasters.dart';
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
///
/// The REGION is what a conte cell whose camera moves shows instead of the
/// camera's view: the canvas that camera sweeps (`SheetPicture.canvasRegion`
/// — 유저 2026-09-29: 「일단 카메라 팬대로 해당 코마에서 보여주고」). The
/// same frame over another canvas is another picture, so it joins the key;
/// null is the camera's view.
typedef StoryboardThumbnailKey = ({
  CutId cutId,
  int frameIndex,
  ui.Rect? region,
  int width,
});

/// The resolver the storyboard's rows and the conte's page ask while they
/// PAINT — only for what their window shows, saying how many device pixels
/// tall they draw the picture ([shownHeight]), and over which canvas
/// [region] where it is not the camera's view ([StoryboardThumbnailKey]).
/// The width that buys is the store's answer, never the surface's.
typedef StoryboardThumbnailResolver =
    ui.Image? Function(
      Cut cut,
      int frameIndex, {
      required double shownHeight,
      ui.Rect? region,
    });

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
///
/// [pending] says whether a picture a surface asked for is still to come.
/// ⚠️Ask it once the surfaces have PAINTED: a landing empties what was
/// asked, and the repaint it sets off is what asks again for a picture
/// still behind — heard where the landing is, it answers no for that one.
typedef StoryboardThumbnails = ({
  StoryboardThumbnailResolver resolve,
  Listenable landed,
  bool Function() pending,
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
/// a panel scrolled away is never rendered at all ([ShownRasters.want] —
/// the law of every picture drawn as large as it is shown, since 10-30).
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
/// is also how a deleted cut's pictures leave. They are held as the
/// viewer holds its pages ([ShownRasters] — 유저 10-30 「붙잡는 곳 하나」).
class StoryboardCutThumbnailStore extends ChangeNotifier {
  StoryboardCutThumbnailStore({
    required Future<ui.Image> Function(
      Cut cut,
      int frameIndex,
      int width,
      ui.Rect? region,
    )
    render,
    required ui.Size Function() originalSize,
    EditorCacheInvalidationHub? invalidationHub,
    this.onHeldBytesChanged,
  }) : _render = render,
       _originalSize = originalSize,
       _hub = invalidationHub {
    _hub?.addBrushFrameListener(_onBrushFrameInvalidated);
  }

  /// ↩️It could answer null — a panel with nothing to draw, remembered
  /// apart from a picture. The camera-view render always answers a picture
  /// (`ExportFrameRenderer.renderPicture`); only tests ever answered null.
  final Future<ui.Image> Function(
    Cut cut,
    int frameIndex,
    int width,
    ui.Rect? region,
  )
  _render;

  /// The size a picture has at its fullest — the camera frame it renders
  /// through, or the region it shows at a pixel a pixel. No width past it
  /// is ever asked for.
  final ui.Size Function() _originalSize;
  final EditorCacheInvalidationHub? _hub;

  /// What is held, each at the signature it was rendered at — let go past
  /// the budget the least recently asked for first ([ShownRasters.use]),
  /// never the one that just landed. A picture let go takes its signature
  /// with it, so the next [thumbnailFor] renders it again: kept apart, the
  /// signature told the panel it was already rendered, and it stayed an
  /// empty block for good.
  ///
  /// ↩️A picture replaced or let go was disposed after the next frame, for
  /// a `RawImage` of the previous build that might still draw it
  /// (a83c0ad5f); the rows and the cells paint it since d676622b6, asking
  /// on every paint, and a picture already painted holds its own.
  late final ShownRasters<StoryboardThumbnailKey, String> _pictures =
      ShownRasters(
        budget: _budget,
        // Nothing plays the panels.
        wantedAt: (_) => null,
        lastUsed: (key) => _pictures.usedAt(key),
        rebuild: (change) => change(),
        mounted: () => !_disposed,
        report: (bytes) => onHeldBytesChanged?.call(bytes),
        ended: notifyListeners,
      );
  final Map<CutId, int> _editGenerations = {};
  bool _disposed = false;

  /// Whether a picture a surface asked for is still to come: a render runs
  /// or waits to. What the conte's live pictures wait on before they stand
  /// down (F-215), and what a test waits on, as the timeline's tiles do —
  /// silence for N ms misreads a slow render for a finished one.
  bool get pending => _pictures.pending;

  /// Told whenever [thumbnailBytes] changes, so an owner the memory census
  /// CAN reach is able to report a store that lives in a widget State.
  final void Function(int bytes)? onHeldBytesChanged;

  /// One viewer's share of this device, halved by the memory warning — see
  /// the class doc for why a viewer's.
  final ViewerRasterBudget _budget = ViewerRasterBudget(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  /// What the held pictures cost resident, 4 bytes a pixel.
  int get thumbnailBytes => _pictures.heldBytes;

  /// What a surface takes to draw these pictures: [thumbnailFor], this
  /// store as what says one landed, and whether one is still to come.
  late final StoryboardThumbnails thumbnails = (
    resolve: thumbnailFor,
    landed: this,
    pending: () => pending,
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
    ui.Rect? region,
  }) {
    final key = (
      cutId: cut.id,
      frameIndex: frameIndex,
      region: region,
      width: pictureRenderWidthFor(
        shownHeight,
        region?.size ?? _originalSize(),
      ),
    );
    // Asked for: to the young end of the eviction order.
    _pictures
      ..want(key, _signatureFor(cut), () => _rendered(cut, key))
      ..use(key);
    return _pictures.imageOf(key) ??
        _pictures.sharpestOf(
          (held) =>
              held.cutId == key.cutId &&
              held.frameIndex == key.frameIndex &&
              held.region == key.region,
        );
  }

  /// [key]'s picture of [cut]. A failure is remembered at the signature it
  /// was asked at: silently swallowing AND forgetting re-kicked the same
  /// failing render on every rebuild (a hot loop behind a permanently empty
  /// block). The next CONTENT change retries; the failure itself is
  /// surfaced.
  Future<ui.Image> _rendered(Cut cut, StoryboardThumbnailKey key) =>
      Future.sync(
        () => _render(cut, key.frameIndex, key.width, key.region),
      ).onError<Object>((error, stack) {
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
        Error.throwWithStackTrace(error, stack);
      });

  /// The OS says memory is tight: halve, never below one viewer page, and
  /// give back what no longer fits. Idempotent — see [ViewerRasterBudget].
  void respondToMemoryPressure() {
    final before = _pictures.heldBytes;
    _pictures.heardMemoryPressure();
    if (_pictures.heldBytes != before) {
      // Panels still showing an evicted picture ask again — for another
      // width of it, or to render it again.
      notifyListeners();
    }
  }

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
  final SignedMemo<int, String> _signatures = SignedMemo('cut signatures');

  /// How many signatures were spelled — the cost [_signatures] keeps off
  /// every paint.
  @visibleForTesting
  int get debugSignaturesSpelled => _spelled;
  int _spelled = 0;

  String _signatureFor(Cut cut) {
    final generation = _editGenerations[cut.id] ?? 0;
    return _signatures.resolve(
      cut,
      generation,
      () => _spellSignature(cut, generation),
    );
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

  @override
  void dispose() {
    _disposed = true;
    _hub?.removeBrushFrameListener(_onBrushFrameInvalidated);
    // Tells the census nothing is held.
    _pictures.clear();
    super.dispose();
  }
}
