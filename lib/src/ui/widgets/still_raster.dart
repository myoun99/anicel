import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../debug/measurement_mode.dart';
import '../effective_device_pixel_ratio.dart';
import '../look_only_frames.dart' show aClockLooksInThisFrame;
import 'raster_grid_fit.dart';
import 'static_raster.dart';

/// A REGION of the window drawn from ONE image while it stays the same —
/// the raster cache Impeller does not have.
///
/// ## Why this exists (유저 2026-09-25, raster-cache-when-still-Q1:
/// 「가만히 있는 동안만 한 장으로」)
///
/// Impeller keeps no raster cache and Windows redraws the whole window
/// every frame, so every draw op of every panel is paid again on every
/// frame — 1,446 of them in the user's layout, 898 in the timeline alone,
/// about 13 ms of raster CPU on a frame where nothing moved (09-25, the
/// real app, 2544×1361). A stroke changes the canvas and nothing else, yet
/// the timeline and the side panels were drawn from scratch under every
/// dab. The measurement build that held each dock region as one image once
/// it had stayed the same for three frames drew an idle frame in 2.2 ms
/// instead of 13.5, and a stroke frame in 5.8 ms instead of 19.6. This
/// class, the canvas left out, measured 28.3 → 5.6 ms idle and 37.5 →
/// 14.6 ms mid-stroke, in alternating pairs within one run of the same
/// app on a machine other sessions were loading (09-25).
///
/// ⚠️The price: an image composited from an offscreen is not bit-for-bit
/// what painting in place gives — 225 of 3.46 million window pixels, 221
/// of them by 1/255 and none by more than 5/255, at translucent edges of
/// the panels (the same run). The user took it for the panels. The canvas
/// is the one thing whose pixels may never move
/// (「결과 절대 바뀌면 안되는건 캔버스뿐임」), so a region showing it is
/// never drawn from an image ([enabled]).
///
/// 🚨That last sentence was first written as "no canvas is under one of
/// these", and it was false: the canvas is a TAB, of the floor dock, and
/// the first real-app run found the floor's region holding a 12 MB image of
/// it. The measurement build behind the decision wrapped the floor too. A
/// claim about what a blanket wrapper does NOT cover is checked against
/// the regions it actually made.
///
/// ## How it knows the region has not changed
///
/// ★BY THE LAYER TREE, not by its own paint. [StaticRaster] captures on
/// its own `paint()`, so a repaint boundary below it freezes (its class
/// doc says how) and it has to refuse to bake over one. A dock region is
/// FULL of boundaries — scroll viewports, list items, the timeline's rows —
/// so this one looks one level lower: every frame, Flutter re-adds to the
/// scene exactly the layers under which something changed, and retains the
/// rest. A region that is re-added has changed (or was moved, which the
/// grid fit judges); a region that is retained has not. The image is taken
/// after [stillFrames] frames of being retained — in the frame it changed
/// in while a clock looks ([_StillLayer._waitNow]) — for the next frame, or
/// for the frame itself where only its ticks moved in it; and dropped the
/// moment the region is re-added with a different layer tree
/// ([_StillLayer._signatureOf] says what "different" covers).
///
/// Content that changes without the layer tree knowing — an external
/// texture, a platform view, a follower pinned to a leader elsewhere, a
/// backdrop filter reading what is behind the region, a layer type this
/// file does not know — makes the region stand down for as long as it
/// holds one.
///
/// ## Where it is, and where not
///
/// Around each DOCK REGION ([EditorDockHost] — every rail group and the
/// floating bottom region), which is where the measurement found the
/// frames going. Only on Impeller ([cachePays]); on Skia the engine's own
/// raster cache and [StaticRaster]'s bakes stay what they were measured
/// as, and this is a boundary with a clip.
class StillRaster extends SingleChildRenderObjectWidget {
  const StillRaster({
    super.key,
    required this.debugLabel,
    this.enabled = true,
    required Widget super.child,
  });

  /// Names this region in diagnostics. Use the dock's id.
  final String debugLabel;

  /// False while the region shows content whose pixels may not come from
  /// an image — the canvas. The region paints, and holds no image.
  final bool enabled;

  /// Frames a region has to stay the same for before its image is taken —
  /// the Skia raster cache's own "stable for three frames".
  static const int stillFrames = 3;

  /// The most a region that keeps changing right after its image is taken
  /// has to wait: each image thrown away before it paid for itself doubles
  /// the wait, up to this.
  static const int maxStillFrames = 48;

  /// The frames an image has to live to pay for itself — the snapshot that
  /// took it is a fixed price, whatever the region waited before it.
  ///
  /// ↩️It was twice the wait: a region backed off to [maxStillFrames] had to
  /// keep an image 96 frames before its wait came down again, and a playing
  /// timeline turns a page every ~65 — it waited 48 frames after every
  /// page, and drew from its image on 261 frames of 1,562 (10-12, cut 302,
  /// 144Hz).
  static const int framesToPay = 2 * stillFrames;

  /// Whether the engine keeps no raster cache of its own — the one engine
  /// fact [StaticRaster.capturePays] reads too, asked as its own question:
  /// that one is "does a capture on every change pay", this one is "does a
  /// capture once the region is still pay".
  static bool get cachePays =>
      debugCachePaysOverride ?? ui.ImageFilter.isShaderFilterSupported;

  /// Lets a test take the Impeller branch on the Skia test renderer. Null
  /// asks the engine.
  @visibleForTesting
  static bool? debugCachePaysOverride;

  /// Every attached region, for the memory census and Frame Stats.
  static final Set<RenderStillRaster> census = <RenderStillRaster>{};

  /// Bytes the regions' images hold right now.
  static int get censusBytes {
    var total = 0;
    for (final region in census) {
      total += region.rasterBytes;
    }
    return total;
  }

  /// Images taken since the app started.
  static int get censusCaptures => _capturesEver;
  static int _capturesEver = 0;

  /// The frame the last image of ANY region was taken on — one a frame. A
  /// snapshot cost a fixed price on the real Windows app (1.6–2.0 ms of
  /// raster whatever its size, 2026-09-25) and one that grows with its
  /// pixels on the Surface (Impeller GLES, 3567×2166: 5–31 ms, the 18–31 ms
  /// ones 3.0–3.7 M pixels — 10-27, F-244-drag-start), and the regions one
  /// pick changes become still together: taken on the same frame, their
  /// prices landed on it at once.
  static int? _lastCaptureFrame;

  @override
  RenderStillRaster createRenderObject(BuildContext context) =>
      RenderStillRaster(
        debugLabel: debugLabel,
        enabled: enabled,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStillRaster renderObject,
  ) {
    renderObject
      ..debugLabel = debugLabel
      ..enabled = enabled
      ..devicePixelRatio = EffectiveDevicePixelRatio.of(context);
  }
}

/// Why a region is being painted instead of drawn from its image.
enum StillStandDown {
  /// Drawn from its image, or about to be.
  none,

  /// Changed within the last few frames — correct, and the common case.
  changing,

  /// Not on this engine ([StillRaster.cachePays]).
  renderer,

  /// Showing content whose pixels may not come from an image
  /// ([StillRaster.enabled]).
  optedOut,

  /// Zero-size box.
  empty,

  /// Rotated or non-uniformly scaled: there is no 1:1 blit.
  unlocatable,

  /// Holds content the layer tree cannot vouch for — a texture, a platform
  /// view, a follower, a backdrop filter, a layer type this file does not
  /// know.
  unvouched,

  /// The engine refused the capture.
  captureFailed,
}

class RenderStillRaster extends RenderProxyBox {
  RenderStillRaster({
    required this.debugLabel,
    required bool enabled,
    required double devicePixelRatio,
  }) : _enabled = enabled,
       _devicePixelRatio = devicePixelRatio;

  /// Names this region in diagnostics; carries no behaviour.
  String debugLabel;

  /// See [StillRaster.enabled]. Turning it off drops the image at once
  /// rather than at the next change.
  bool get enabled => _enabled;
  bool _enabled;
  set enabled(bool value) {
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    _restart();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// Why the region last painted instead of drawing its image.
  StillStandDown get standDown => _standDown;
  StillStandDown _standDown = StillStandDown.renderer;

  /// Images taken since this region attached.
  @visibleForTesting
  int get debugCaptureCount => _captureCount;
  int _captureCount = 0;

  /// Whether the last scene drew this region from its image.
  @visibleForTesting
  bool get debugDrawnFromImage => _drawnFromImage;
  bool _drawnFromImage = false;

  /// How many frames drawn from the image asked where the region sits the
  /// full way — a transform to the root — before building the scene,
  /// rather than cheaply.
  @visibleForTesting
  int get debugFullPlacementChecks => _fullPlacementChecks;
  int _fullPlacementChecks = 0;

  /// The moving ticks the region could not draw live between its strata,
  /// each with why — where it stands, and the layer above it whose effect
  /// is the group's.
  List<String> get debugTickRefusals => _tickRefusals;
  List<String> _tickRefusals = const [];

  /// The boxes of the ticks drawn live between the strata, in the order the
  /// region paints them — empty while it paints.
  @visibleForTesting
  List<Size> get debugLiveTicks => [
    for (final (:tick, path: _, reach: _)
        in _layer?._strata?.ticks ?? const <_Tick>[])
      tick.size,
  ];

  /// How the region sat on the device pixel grid when its image was
  /// taken, for tests that need to prove the image was a copy and not a
  /// resample. Null while it paints.
  @visibleForTesting
  Offset? get debugGridShift => _layer?._strata?.fit.shift;

  /// What the region's image holds, in bytes — zero while it paints.
  int get rasterBytes => _layer?._strata?.bytes ?? 0;

  _StillLayer? get _layer => layer as _StillLayer?;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) =>
      oldLayer is _StillLayer ? oldLayer : _StillLayer(this);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    StaticRaster.ensureFrameClock();
    StillRaster.census.add(this);
    MeasurementMode.showRepaints.addListener(_restart);
  }

  @override
  void detach() {
    StillRaster.census.remove(this);
    MeasurementMode.showRepaints.removeListener(_restart);
    _layer?._drop();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    StillRaster.census.remove(this);
    MeasurementMode.showRepaints.removeListener(_restart);
    super.dispose();
  }

  void _restart() {
    _layer?._drop();
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  /// Paints the region, clipped to its own box — the box its image covers,
  /// so the two ways of showing it cannot disagree about what is inside
  /// ([RenderStaticRaster]'s paint-through, for the same reason).
  @override
  void paint(PaintingContext context, Offset offset) {
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clipLayer.layer,
    );
  }

  /// Whether this region may be drawn from an image at all right now, and
  /// if not, why.
  StillStandDown _gate() {
    if (!StillRaster.cachePays) {
      return StillStandDown.renderer;
    }
    if (!_enabled) {
      return StillStandDown.optedOut;
    }
    if (!hasSize || size.isEmpty) {
      return StillStandDown.empty;
    }
    return StillStandDown.none;
  }

  RasterGridFit? _gridFit() =>
      attached ? RasterGridFit.of(this, _devicePixelRatio) : null;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', debugLabel));
    properties.add(EnumProperty<StillStandDown>('standDown', _standDown));
    properties.add(IntProperty('captures', _captureCount));
  }
}

/// A tick a region draws live between its strata, with the layers between
/// the region and it, and what of the region it can reach
/// ([_Strata._reach]).
typedef _Tick = ({TickSceneLayer tick, List<ContainerLayer> path, Rect reach});

/// A picture of the region's, with the layers between the region and it,
/// and what of the region it can reach ([_Strata._reach]).
typedef _Leaf = ({
  PictureLayer picture,
  List<ContainerLayer> path,
  Rect reach,
});

/// The region's layer: it hands the scene either its children or, while
/// they stay the same, its STRATA — what it paints between one moving tick
/// and the next, each a part of one image — with the moving ticks drawn
/// live between them ([TickSceneLayer]).
class _StillLayer extends OffsetLayer {
  _StillLayer(this._owner);

  final RenderStillRaster _owner;

  /// The region's strata as last taken, and what its layer tree was, its
  /// live ticks aside, when they were.
  _Strata? _strata;
  List<Object?>? _imageSignature;

  /// What the region's layer tree was, every tick's own layers aside, and
  /// where it sat, the last time it was re-added — a re-add that only a
  /// tick asked for changes nothing that is still.
  List<Object?>? _lastSignature;
  RasterGridFit? _lastFit;

  /// The frame this region was last re-added with a change of its own.
  int _changedAt = 0;

  /// The ticks whose own drawing changed in the frame under way — each
  /// moved alone unless the region changed in it too ([_moving]).
  final List<TickSceneLayer> _changedTicks = [];

  /// The frame its current image was taken, for the back-off.
  int? _capturedAt;
  int _stillFramesNeeded = StillRaster.stillFrames;
  bool _watching = false;

  static int get _frame => StaticRaster.debugFrameSerial;

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    final capturedAt = _capturedAt;
    if (capturedAt != null) {
      // 🚨An image thrown away before it paid for itself doubles the wait
      // for the next one; one that lived long enough resets it. A region
      // that changes every few frames — a pointer sweeping across a row of
      // buttons — would otherwise be captured after every stillness and
      // dropped before its second use, each capture a whole render of the
      // region on the raster thread. Counted from the CAPTURE, so an image
      // thrown away before it was ever drawn counts as the waste it is.
      final lived = _frame - capturedAt;
      _stillFramesNeeded = lived < StillRaster.framesToPay
          ? (_stillFramesNeeded * 2).clamp(
              StillRaster.stillFrames,
              StillRaster.maxStillFrames,
            )
          : StillRaster.stillFrames;
    }
    _strata?.dispose();
    _strata = null;
    _imageSignature = null;
    _capturedAt = null;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final strata = _strata;
    if (strata != null && _stillShows(strata)) {
      _drawFrom(strata, builder);
      _noteWhoMovedAlone();
      return;
    }
    final dropped = strata != null;
    if (dropped) {
      _drop();
    }
    // 🚨A re-add only a tick asked for changed nothing the strata would
    // hold: the region is still for as long as the rest of it is. One that
    // moved it is a change like any — or a region dragged across the screen
    // would be taken again on every frame of the drag.
    final signature = _signatureOf((_) => true);
    final fit = _owner._gridFit();
    if (signature == null ||
        !listEquals(signature, _lastSignature) ||
        fit != _lastFit) {
      // 🚨A region that stood still long enough for an image taken at the
      // shortest wait to have paid, and was waiting longer, waits that
      // shortest wait again — an image it never took could not say so
      // ([_drop]). Backed off past its own stillness, a region stays there:
      // a playing timeline turned a page every ~65 frames at 144Hz (10-12),
      // and the same page at a lower refresh rate is fewer frames than the
      // most a region waits.
      if (!dropped &&
          _frame - _changedAt >=
              StillRaster.stillFrames + StillRaster.framesToPay) {
        _stillFramesNeeded = StillRaster.stillFrames;
      }
      _changedAt = _frame;
    }
    _lastSignature = signature;
    _lastFit = fit;
    _noteWhoMovedAlone();
    _owner._drawnFromImage = false;
    final gate = _owner._gate();
    _owner._standDown = gate == StillStandDown.none
        ? StillStandDown.changing
        : gate;
    if (gate == StillStandDown.none) {
      // 🚨A REGION RE-ADDED ONCE IT STOOD STILL PAST ITS WAIT IS TAKEN IN
      // THAT FRAME, BEFORE IT IS DRAWN (F-244-drag-start, 10-27). Only its
      // ticks moved: one that stood still when the strata were taken —
      // the rows a block drag carries, at its first step — or a live one
      // gone still drops them, the rest of the region as it was, and the
      // frame's own check took the strata again right AFTER this frame, which
      // was drawn live in between. 🔬On the Surface (profile, Impeller GLES,
      // 3567×2166) that live frame was 26–46 ms of raster and the image after
      // it 18–31, at the start of every block, row, comma and [+] drag. Taken
      // here, the frame is drawn from the new strata, the moving ticks live
      // in them.
      if (_mayTake && _capture()) {
        _drawFrom(_strata!, builder);
        return;
      }
      _watch();
    }
    super.addToScene(builder);
  }

  /// Hands the scene [strata] in place of the region's children.
  void _drawFrom(_Strata strata, ui.SceneBuilder builder) {
    engineLayer = builder.pushOffset(
      offset.dx,
      offset.dy,
      oldLayer: engineLayer as ui.OffsetEngineLayer?,
    );
    strata.addTo(builder);
    builder.pop();
    _owner._drawnFromImage = true;
    _owner._standDown = StillStandDown.none;
  }

  /// 🚨Runs on EVERY layer of the tree before every frame's scene is
  /// built, retained or not — the one place this layer hears about a frame
  /// in which only an ANCESTOR moved. That moves the region as a whole
  /// without re-adding this layer, and an image drawn on a new sub-pixel
  /// phase is a resample ([RasterGridFit]), so a region drawn from an
  /// image asks to be re-added whenever it no longer sits where its image
  /// was taken.
  ///
  /// ⚠️Asked cheaply first ([_measurePlacement]): building a transform to
  /// the root for every region on every frame measured ~28 µs a region on
  /// the real Windows app (09-25) and left a matrix behind each time — the
  /// full fit is asked only when the layers above have moved.
  ///
  /// Under a follower the question waits for [addToScene]: a follower's
  /// paint transform is the one it was last ADDED with, so asked here it
  /// is a frame old — the region would show a resample for that frame.
  @override
  void updateSubtreeNeedsAddToScene() {
    final strata = _strata;
    if (strata != null) {
      if (!_measurePlacement()) {
        markNeedsAddToScene();
      } else if (_nowDx != _placedDx ||
          _nowDy != _placedDy ||
          _nowBelowTransforms != _placedBelowTransforms) {
        _owner._fullPlacementChecks += 1;
        if (_owner._gridFit() != strata.fit) {
          markNeedsAddToScene();
        } else {
          _keepPlacement();
        }
      }
    }
    super.updateSubtreeNeedsAddToScene();
  }

  // Where the layers above put this one: [_measurePlacement] writes the
  // `_now` fields, [_keepPlacement] makes them the `_placed` ones.
  double _nowDx = 0;
  double _nowDy = 0;
  int _nowBelowTransforms = 0;
  double _placedDx = double.nan;
  double _placedDy = double.nan;
  int _placedBelowTransforms = 0;

  /// Where the layers above put this one, into the `_now` fields: the
  /// offsets above summed up to each transform, and each such sum with the
  /// transform that moves it — by identity — folded into one number. A
  /// walk of a few parents that allocates nothing. False when something
  /// above places it by other means — a follower.
  ///
  /// ⚠️Summed only between transforms: under a scale, an ancestor moving
  /// one way and a descendant moving the other by as much leave one sum of
  /// all offsets unchanged while the region moved.
  ///
  /// Its own offset is not in it: that moving re-adds this layer, and
  /// [addToScene] asks the full fit then.
  bool _measurePlacement() {
    var dx = 0.0;
    var dy = 0.0;
    var below = 0;
    for (var layer = parent; layer != null; layer = layer.parent) {
      switch (layer) {
        case FollowerLayer():
          return false;
        case TransformLayer():
          below = Object.hash(
            below,
            dx.hashCode,
            dy.hashCode,
            identityHashCode(layer.transform),
          );
          // A transform layer's own offset lands after its transform.
          dx = layer.offset.dx;
          dy = layer.offset.dy;
        case OffsetLayer():
          dx += layer.offset.dx;
          dy += layer.offset.dy;
        case LeaderLayer():
          dx += layer.offset.dx;
          dy += layer.offset.dy;
        default:
      }
    }
    _nowDx = dx;
    _nowDy = dy;
    _nowBelowTransforms = below;
    return true;
  }

  void _keepPlacement() {
    _placedDx = _nowDx;
    _placedDy = _nowDy;
    _placedBelowTransforms = _nowBelowTransforms;
  }

  /// Whether [strata] still show the region: the gate is open, the region
  /// sits on the same device pixels, the layer tree under it is the one
  /// they were taken of, its live ticks aside — and every tick drawn live
  /// still moves: one that stood still for [_movingFor] frames is taken
  /// into its stratum with the next strata.
  bool _stillShows(_Strata strata) =>
      _owner._gate() == StillStandDown.none &&
      _owner._gridFit() == strata.fit &&
      listEquals(_signatureOf(strata.live.contains), _imageSignature) &&
      strata.live.every(_moving);

  /// How long a tick that changed stays one that moves: a film frame's
  /// tick changes every few refreshes, a row's tile landing once.
  static const int _movingFor = StillRaster.maxStillFrames;

  /// Whether [tick] changed what it holds in the last [_movingFor] frames
  /// WHILE THE REST OF THE REGION STOOD STILL — in a frame the region had
  /// no change of its own in. One that changes only with the region moves
  /// with it, and is taken with the rest: a playing timeline's rows each
  /// hold a tick that a page turn moves with the page, and nothing else.
  /// ↩️Read live for the 48 frames after every page, they were taken into
  /// the strata in an image of their own when those ran out — two images a
  /// page (10-12, cut 302). ↩️Asked as "changed after the region's own
  /// last change", a tick a film frame changed the frame before a page
  /// turn read as standing still: taken into the strata, which the next
  /// film frame threw away — two images a page again, and the first film
  /// frame after every turn drawn live (10-12, cut 302: 55 of 55).
  bool _moving(TickSceneLayer tick) =>
      _frame - tick._movedAloneAt <= _movingFor;

  /// Marks the ticks that changed in this frame as moved alone, unless the
  /// region changed in it too. A tick looked at for the first time is a
  /// layer new to the region, which is a change of the region's: a tick
  /// never moves alone on its first look.
  void _noteWhoMovedAlone() {
    if (_changedAt != _frame) {
      for (final tick in _changedTicks) {
        tick._movedAloneAt = _frame;
      }
    }
    _changedTicks.clear();
  }

  /// The frames the region stands still before its image is taken.
  ///
  /// 🚨WHILE A CLOCK LOOKS, THE SHORTEST WAIT IS NONE (유저 2026-10-11:
  /// 「144hz든 몇이든 확실하게 근본/구조적으로 해결하도록」). A page turn is
  /// drawn the frame after the film frame that carried the playhead out,
  /// and the next film frame can come the refresh after it — at 60Hz a
  /// 24fps film changes every two or three — so an image taken after a wait
  /// comes after that film frame, and it draws the whole region live.
  /// 🔬10-12, cut 302 at 144Hz: the first film frame after a turn came 2–5
  /// frames after it, the image 4 — 22 of 24 drawn live, their raster p50
  /// 12ms against 6 from the image. Taken in the turn's own frame, the image
  /// is rendered right after that frame, in the quiet before the film's.
  /// What a wait guards — a region changed again a frame or two later — the
  /// back-off still does: only the shortest wait is taken off, and a region
  /// a run keeps changing waits what its thrown-away image taught it.
  int get _waitNow =>
      _stillFramesNeeded -
      (aClockLooksInThisFrame() ? StillRaster.stillFrames : 0);

  /// Whether an image taken now may be first drawn in the frame [_frame]
  /// reads: the region has stood still past its wait by then, and no other
  /// region's image is first drawn in it ([StillRaster._lastCaptureFrame]).
  bool get _mayTake =>
      _frame - _changedAt > _waitNow &&
      StillRaster._lastCaptureFrame != _frame;

  void _watch() {
    if (_watching) {
      return;
    }
    _watching = true;
    void check(Duration _) {
      _watching = false;
      if (!attached || _strata != null) {
        return;
      }
      if (_owner._gate() != StillStandDown.none) {
        return;
      }
      // The frame clock ticks after the scene is built, so [_frame] here
      // already reads the next frame — the one that draws what is taken.
      if (_mayTake) {
        if (_capture()) {
          // The scene still holds the children: re-add this layer so the
          // next frame draws the strata instead.
          //
          // ⛔NOT A FRAME OF ITS OWN (2026-09-25, H40). One asked for here
          // shows nothing new — the image is of what is already on screen —
          // and its frame counted as still for every other region, which
          // then took ITS image and asked for another: a brush pick with the
          // settings open grew nine frames longer, ~20 ms more of UI thread,
          // and the images taken in a row landed on the stroke that followed
          // (worst frame 48 → 63 ms). The next frame that comes anyway draws
          // it.
          markNeedsAddToScene();
        }
        return;
      }
      _watching = true;
      SchedulerBinding.instance.addPostFrameCallback(check);
    }

    SchedulerBinding.instance.addPostFrameCallback(check);
  }

  /// Takes the region's strata as the scene last had it — every stratum a
  /// part of ONE image, aligned to the device pixel grid — for the frame
  /// [_frame] reads to show; false where the region cannot be taken.
  ///
  /// The ticks drawn live are the ones moving ([_moving]): a tick that
  /// is not is painted into its stratum like anything else, and its
  /// moving later is a change of the region's.
  bool _capture() {
    final fit = _owner._gridFit();
    if (fit == null) {
      _owner._standDown = StillStandDown.unlocatable;
      return false;
    }
    final layout = _Strata.layoutOf(this, _moving);
    _owner._tickRefusals = layout.refusals;
    final signature = layout.refusals.isEmpty
        ? _signatureOf(layout.live.contains)
        : null;
    if (signature == null) {
      _owner._standDown = StillStandDown.unvouched;
      return false;
    }
    try {
      if (!supportsRasterization()) {
        _owner._standDown = StillStandDown.unvouched;
        return false;
      }
      StillRaster._lastCaptureFrame = _frame;
      _strata = _Strata.take(
        layout,
        _owner.size,
        fit,
        tint: MeasurementMode.showRepaints.value
            ? MeasurementMode.repaintTint(_owner._captureCount)
            : null,
      );
      _owner._captureCount += 1;
      if (_measurePlacement()) {
        _keepPlacement();
      }
      _imageSignature = signature;
      _capturedAt = _frame;
      StillRaster._capturesEver += 1;
    } on Object catch (error, stack) {
      _refused(error, stack);
      return false;
    }
    return true;
  }

  /// Painting is always available and always correct, so a refused capture
  /// costs the saving and nothing else — but it is reported.
  void _refused(Object error, StackTrace stack) {
    _owner._standDown = StillStandDown.captureFailed;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'anicel',
        context: ErrorDescription(
          'taking the image of StillRaster(${_owner.debugLabel}) — '
          'painting instead',
        ),
      ),
    );
  }

  /// What the region's layer tree IS, as values to compare — every layer
  /// by identity, and every property a layer can change in place (Flutter
  /// re-adds a layer whose property changes, and this is what says the
  /// re-add changed something). A tick [live] says is drawn live counts by
  /// itself and its place, not by what it draws. Null when the tree holds
  /// content that can change with no layer knowing — then there is nothing
  /// to vouch for.
  ///
  /// Each tick it passes is told what it draws ITSELF
  /// ([TickSceneLayer._looked]) — a tick inside it counted by itself and its
  /// place, not by what it draws — which is how the region knows which of
  /// its ticks move: one moves when its own drawing changes, whichever ticks
  /// inside it the region draws live. ↩️It was told what it held as the walk
  /// counted it, the ticks inside it in or out by [live], so an outer tick
  /// read as moved whenever two walks asked with different ticks live.
  List<Object?>? _signatureOf(bool Function(TickSceneLayer tick) live) {
    final region = <Object?>[];
    // [own]: what the nearest tick around [layer] draws itself.
    bool walk(Layer layer, List<Object?> out, List<Object?>? own) {
      own?.add(layer);
      out.add(layer);
      if (layer case TickSceneLayer(:final offset)) {
        final held = <Object?>[offset];
        final itsOwn = <Object?>[offset];
        for (var child = layer.firstChild;
            child != null;
            child = child.nextSibling) {
          if (!walk(child, held, itsOwn)) {
            return false;
          }
        }
        if (layer._looked(itsOwn)) {
          _changedTicks.add(layer);
        }
        if (!live(layer)) {
          out.addAll(held);
        }
        return true;
      }
      final from = out.length;
      switch (layer) {
        case PictureLayer(:final picture):
          out.add(picture);
        // A backdrop filter draws what is BEHIND the region, which an
        // image of the region alone does not even contain.
        case TextureLayer() ||
            PlatformViewLayer() ||
            PerformanceOverlayLayer() ||
            FollowerLayer() ||
            BackdropFilterLayer():
          return false;
        // A leader only says where it is — for followers elsewhere, which
        // find it through the layer tree whether or not it was re-added.
        // What it draws is its children.
        case LeaderLayer(:final offset):
          out.add(offset);
        case TransformLayer(:final transform, :final offset):
          out
            ..add(offset)
            ..addAll(transform?.storage ?? const <double>[]);
        case OpacityLayer(:final alpha, :final offset):
          out
            ..add(alpha)
            ..add(offset);
        case ImageFilterLayer(:final imageFilter, :final offset):
          out
            ..add(imageFilter)
            ..add(offset);
        case OffsetLayer(:final offset):
          out.add(offset);
        case ClipRectLayer(:final clipRect, :final clipBehavior):
          out
            ..add(clipRect)
            ..add(clipBehavior);
        case ClipRRectLayer(:final clipRRect, :final clipBehavior):
          out
            ..add(clipRRect)
            ..add(clipBehavior);
        case ClipRSuperellipseLayer(
          :final clipRSuperellipse,
          :final clipBehavior,
        ):
          out
            ..add(clipRSuperellipse)
            ..add(clipBehavior);
        case ClipPathLayer(:final clipPath, :final clipBehavior):
          out
            ..add(clipPath)
            ..add(clipBehavior);
        case ColorFilterLayer(:final colorFilter):
          out.add(colorFilter);
        case ShaderMaskLayer(:final shader, :final maskRect, :final blendMode):
          out
            ..add(shader)
            ..add(maskRect)
            ..add(blendMode);
        case AnnotatedRegionLayer():
          break;
        case ContainerLayer() when layer.runtimeType == ContainerLayer:
          break;
        default:
          // A layer type this file does not know could change what it
          // draws in a way nothing here would compare.
          return false;
      }
      own?.addAll(out.getRange(from, out.length));
      if (layer is ContainerLayer) {
        for (var child = layer.firstChild;
            child != null;
            child = child.nextSibling) {
          if (!walk(child, out, own)) {
            return false;
          }
        }
      }
      return true;
    }

    for (var child = firstChild; child != null; child = child.nextSibling) {
      if (!walk(child, region, null)) {
        return null;
      }
    }
    return region;
  }
}

/// What a region paints, cut into strata at the ticks drawn live: each
/// stratum's pictures with the layers above them, the ticks between the
/// strata — as a list and as a set — and the live ticks that could not be
/// cut out, each with why.
typedef _Layout = ({
  List<List<_Leaf>> strata,
  List<_Tick> ticks,
  Set<TickSceneLayer> live,
  List<String> refusals,
});

/// Where each stratum's part sits in the one image — null for a stratum
/// that reaches nothing — and the image's size, in device pixels.
typedef _Packing = ({List<Offset?> at, Size size});

/// A region's STRATA as taken — what it paints between one live tick and
/// the next, each a part of ONE image — and the ticks drawn live between
/// them: how they are taken and handed to the scene. [_StillLayer] says
/// when.
class _Strata {
  _Strata._({
    required this.image,
    required List<ui.Picture?> pictures,
    required this.ticks,
    required this.live,
    required this.fit,
  }) : _pictures = pictures;

  /// The one image every stratum is a part of.
  final ui.Image image;

  /// A picture per stratum that puts its part of [image] back, null where
  /// the stratum paints nothing — one more than [ticks].
  final List<ui.Picture?> _pictures;

  /// The ticks drawn live between the strata, in the order the region
  /// paints them — and the same ticks as a set, for the signature.
  final List<_Tick> ticks;
  final Set<TickSceneLayer> live;

  /// Where the region sat on the device pixel grid when they were taken.
  final RasterGridFit fit;

  /// What [image] holds, in bytes.
  int get bytes => image.width * image.height * 4;

  /// The pictures [region] paints in the order it paints them, cut into
  /// strata at every tick [live] says is drawn live, each picture in the
  /// lowest stratum it can be drawn in ([_lowest]) — with a refusal where a
  /// live tick stands under a layer whose effect is the GROUP's (a fade, a
  /// filter, a mask): cut there, the group would be drawn as parts.
  static _Layout layoutOf(
    ContainerLayer region,
    bool Function(TickSceneLayer tick) live,
  ) {
    final strata = <List<_Leaf>>[[]];
    final ticks = <_Tick>[];
    final drawnLive = <TickSceneLayer>{};
    final refusals = <String>[];
    final path = <ContainerLayer>[];
    // A tick moving is drawn live WHOLE, the ticks inside it with it. One
    // that moves only because a tick inside it does is not moving — a tick
    // is asked what it draws itself ([_StillLayer._signatureOf]) — and the
    // walk goes on into it to that one. ↩️The innermost moving tick was
    // always the one drawn live, and an outer tick that moved on its own
    // was taken into the strata it left again on its next move: the
    // timeline's command bar, changing with every film frame, held ticks
    // that moved too, and the playing timeline took its image five times in
    // fifteen frames (10-12).
    void visit(Layer layer, Matrix4 toRegion, Rect clip) {
      switch (layer) {
        case TickSceneLayer() when live(layer):
          final under = path.where((above) => !_splits(above));
          if (under.isNotEmpty) {
            refusals.add(
              '${_spot(layer.offset & layer.size)} (${layer.debugCreator}): '
              'under ${under.first.runtimeType}',
            );
          }
          // Its box, not what it holds now: what it holds changes on every
          // frame it is drawn live.
          ticks.add((
            tick: layer,
            path: List.of(path),
            reach: _reach(toRegion, layer.offset & layer.size, clip),
          ));
          drawnLive.add(layer);
          strata.add([]);
        case PictureLayer():
          final leaf = (
            picture: layer,
            path: List.of(path),
            reach: _reach(toRegion, layer.canvasBounds, clip),
          );
          strata[_lowest(leaf, strata, ticks)].add(leaf);
        case ContainerLayer():
          final inner = _inside(layer, toRegion);
          final within = _clipped(layer, toRegion, clip);
          path.add(layer);
          for (var child = layer.firstChild;
              child != null;
              child = child.nextSibling) {
            visit(child, inner, within);
          }
          path.removeLast();
        default:
      }
    }

    for (var child = region.firstChild;
        child != null;
        child = child.nextSibling) {
      visit(child, Matrix4.identity(), Rect.largest);
    }
    return (
      strata: strata,
      ticks: ticks,
      live: drawnLive,
      refusals: refusals,
    );
  }

  /// Where [layer] puts its children, from where it stands in the region.
  static Matrix4 _inside(ContainerLayer layer, Matrix4 toRegion) {
    final inner = toRegion.clone();
    switch (layer) {
      case TransformLayer(:final transform, :final offset):
        inner
          ..translateByDouble(offset.dx, offset.dy, 0, 1)
          ..multiply(transform ?? Matrix4.identity());
      case OffsetLayer(:final offset) || LeaderLayer(:final offset):
        inner.translateByDouble(offset.dx, offset.dy, 0, 1);
      default:
    }
    return inner;
  }

  /// Whether what stands under [layer] can be drawn in parts as the region
  /// had it — a tick live apart from its strata, a picture in a lower
  /// stratum than the one it was painted in — because what [layer] does to
  /// its children is done to each part alike. A fade, a filter or a mask is
  /// done to the GROUP: drawn apart, overlapping parts would show through
  /// each other.
  static bool _splits(ContainerLayer layer) => switch (layer) {
    OpacityLayer(:final alpha) => alpha == null || alpha == 255,
    ColorFilterLayer() ||
    ImageFilterLayer() ||
    ShaderMaskLayer() ||
    BackdropFilterLayer() => false,
    _ => true,
  };

  /// 🚨A PICTURE IS DRAWN UNDER EVERY LIVE TICK IT DOES NOT TOUCH (10-27,
  /// F-244-drag-start ③): which of two things is drawn first shows only
  /// where they overlap. A stratum was every picture painted between two
  /// live ticks, its part of the image the box all of them reach — so a
  /// splitter, two scrollbars and the dock's tab strip, painted after the
  /// timeline's cursor, made the top stratum as tall as the region, and
  /// with the ground and the rows under it the image was 2.9–3.6 times the
  /// region it shows (🔬the Surface: 3.0–3.7M pixels for a dock of 1.02M,
  /// taken in 11–60 ms at each drag's start — 저장 10-27). [leaf] goes down
  /// past a live tick, and past the pictures already in the stratum above
  /// that tick, only where it touches none of them, so nothing that
  /// overlaps is drawn in another order; and never out of a group whose
  /// effect is the group's ([_splits]).
  ///
  /// ⚠️As good as the reach: a picture reaches its boundary's whole box,
  /// whatever it drew (a picture says no more of itself), so a mark painted
  /// after a tick in a large boundary still holds its stratum at that box.
  /// Such a mark gets a layer of its own size — the timeline's frame area
  /// edge, cut-end line and out-of-cut wash, and the dock's tab strip
  /// (10-27).
  static int _lowest(
    _Leaf leaf,
    List<List<_Leaf>> strata,
    List<_Tick> ticks,
  ) {
    var at = strata.length - 1;
    if (!leaf.path.every(_splits)) {
      return at;
    }
    while (at > 0 &&
        !_touch(leaf.reach, ticks[at - 1].reach) &&
        !strata[at].any((above) => _touch(leaf.reach, above.reach))) {
      at -= 1;
    }
    return at;
  }

  /// What [bounds], put in the region by [toRegion], can show of it: where
  /// they land, cut to [clip] — empty where nothing of them shows.
  static Rect _reach(Matrix4 toRegion, Rect bounds, Rect clip) {
    final reach = MatrixUtils.transformRect(toRegion, bounds).intersect(clip);
    return reach.isEmpty ? Rect.zero : reach;
  }

  /// [clip] cut again to what [layer] clips its children to, from where it
  /// stands in the region.
  static Rect _clipped(ContainerLayer layer, Matrix4 toRegion, Rect clip) {
    final cut = switch (layer) {
      ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none =>
        clipRect,
      ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none =>
        clipRRect.outerRect,
      ClipRSuperellipseLayer(:final clipRSuperellipse?, :final clipBehavior)
          when clipBehavior != Clip.none =>
        clipRSuperellipse.outerRect,
      ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none =>
        clipPath.getBounds(),
      _ => null,
    };
    return cut == null
        ? clip
        : clip.intersect(MatrixUtils.transformRect(toRegion, cut));
  }

  /// Whether two reaches share a pixel — never where either is empty.
  static bool _touch(Rect a, Rect b) =>
      !a.isEmpty && !b.isEmpty && a.overlaps(b);

  /// [layout]'s strata drawn into ONE image — each its own part of it, cut
  /// to the device pixels its pictures reach ([_packed] says where) — and a
  /// picture per stratum that puts its part back where it was taken, 1:1
  /// ([fit]), with [tint] over each where the repaints are shown.
  ///
  /// ⛔One image, not one a stratum: a snapshot costs a price of its own on
  /// the raster thread besides its pixels (1.6–2.0 ms on the real Windows
  /// app whatever its size, 09-25; on the Surface the pixels outweigh it —
  /// [StillRaster._lastCaptureFrame]), and a region cut at every tick has
  /// several strata.
  static _Strata take(
    _Layout layout,
    Size size,
    RasterGridFit fit, {
    Color? tint,
  }) {
    final parts = _partsOf(layout.strata, size, fit);
    final packing = _packed(parts);
    final image = _imageOf(layout.strata, parts, packing, fit);
    final pictures = <ui.Picture?>[];
    for (var i = 0; i < parts.length; i += 1) {
      final device = parts[i];
      final at = packing.at[i];
      if (device == null || at == null) {
        pictures.add(null);
        continue;
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      fit.blitPart(canvas, image, at & device.size, fit.logicalOf(device));
      if (tint != null) {
        canvas.drawRect(fit.logicalOf(device), Paint()..color = tint);
      }
      pictures.add(recorder.endRecording());
    }
    return _Strata._(
      image: image,
      pictures: pictures,
      ticks: layout.ticks,
      live: layout.live,
      fit: fit,
    );
  }

  /// The device pixels each stratum's pictures reach in a region of [size]
  /// — its part of the image — or null for one that reaches none.
  static List<Rect?> _partsOf(
    List<List<_Leaf>> strata,
    Size size,
    RasterGridFit fit,
  ) {
    final whole = fit.devicePixelsOf(Offset.zero & size);
    final parts = <Rect?>[];
    for (final leaves in strata) {
      Rect? reach;
      for (final (picture: _, path: _, reach: drawn) in leaves) {
        if (!drawn.isEmpty) {
          reach = reach == null ? drawn : reach.expandToInclude(drawn);
        }
      }
      final device = reach == null
          ? null
          : fit.devicePixelsOf(reach).intersect(whole);
      parts.add(device == null || device.isEmpty ? null : device);
    }
    return parts;
  }

  /// Where each of [parts] goes in the one image, and the image's size:
  /// beside the parts before it or under them, whichever leaves the image
  /// smaller. ↩️Each went under the one before, and a narrow stratum
  /// stacked under a wide one took the wide one's whole width (10-27).
  static _Packing _packed(List<Rect?> parts) {
    var width = 0.0;
    var height = 0.0;
    final at = <Offset?>[];
    for (final device in parts) {
      if (device == null) {
        at.add(null);
        continue;
      }
      final wider = width < device.width ? device.width : width;
      final taller = height < device.height ? device.height : height;
      if ((width + device.width) * taller < wider * (height + device.height)) {
        at.add(Offset(width, 0));
        width += device.width;
        height = taller;
      } else {
        at.add(Offset(0, height));
        height += device.height;
        width = wider;
      }
    }
    return (at: at, size: Size(width, height));
  }

  /// [strata] drawn into their [parts], each where [packing] puts it in one
  /// image.
  static ui.Image _imageOf(
    List<List<_Leaf>> strata,
    List<Rect?> parts,
    _Packing packing,
    RasterGridFit fit,
  ) {
    final builder = ui.SceneBuilder();
    for (var i = 0; i < strata.length; i += 1) {
      final device = parts[i];
      final at = packing.at[i];
      if (device == null || at == null) {
        continue;
      }
      final place =
          Matrix4.translationValues(
              at.dx - device.left,
              at.dy - device.top,
              0,
            )
            ..scaleByDouble(fit.scale, fit.scale, 1, 1)
            ..translateByDouble(fit.shift.dx, fit.shift.dy, 0, 1);
      builder
        ..pushTransform(place.storage)
        ..pushClipRect(fit.logicalOf(device));
      _addLeaves(builder, strata[i]);
      builder
        ..pop()
        ..pop();
    }
    final scene = builder.build();
    try {
      return scene.toImageSync(
        packing.size.width.round().clamp(1, 1 << 15),
        packing.size.height.round().clamp(1, 1 << 15),
      );
    } finally {
      scene.dispose();
    }
  }

  /// The strata in the order the region paints them, each live tick drawn
  /// between the two it stands between.
  void addTo(ui.SceneBuilder builder) {
    for (var i = 0; i < _pictures.length; i += 1) {
      final stratum = _pictures[i];
      if (stratum != null) {
        builder.addPicture(Offset.zero, stratum);
      }
      if (i < ticks.length) {
        _addTick(builder, ticks[i]);
      }
    }
  }

  void dispose() {
    for (final stratum in _pictures) {
      stratum?.dispose();
    }
    image.dispose();
  }

  /// [leaves] added as the region had them — each under its layers, pushed
  /// again where the one before stood under others.
  static void _addLeaves(ui.SceneBuilder builder, List<_Leaf> leaves) {
    final pushed = <ContainerLayer>[];
    final counted = <bool>[];
    for (final (:picture, :path, reach: _) in leaves) {
      var common = 0;
      while (common < pushed.length &&
          common < path.length &&
          identical(pushed[common], path[common])) {
        common += 1;
      }
      while (pushed.length > common) {
        pushed.removeLast();
        if (counted.removeLast()) {
          builder.pop();
        }
      }
      for (var i = common; i < path.length; i += 1) {
        pushed.add(path[i]);
        counted.add(_push(builder, path[i]));
      }
      builder.addPicture(
        Offset.zero,
        picture.picture!,
        isComplexHint: picture.isComplexHint,
        willChangeHint: picture.willChangeHint,
      );
    }
    for (final pops in counted) {
      if (pops) {
        builder.pop();
      }
    }
  }

  /// [tick] drawn live, under the layers the region had above it — pushed
  /// again as the region pushed them, so it is clipped, moved and faded as
  /// it was in place.
  static void _addTick(ui.SceneBuilder builder, _Tick tick) {
    var pushed = 0;
    for (final layer in tick.path) {
      if (_push(builder, layer)) {
        pushed += 1;
      }
    }
    tick.tick.addToScene(builder);
    for (var i = 0; i < pushed; i += 1) {
      builder.pop();
    }
  }

  /// Pushes what [layer] does to its children, as its own `addToScene`
  /// would — false for a layer that pushes nothing.
  static bool _push(ui.SceneBuilder builder, ContainerLayer layer) {
    switch (layer) {
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        builder.pushClipRect(clipRect, clipBehavior: clipBehavior);
      case ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        builder.pushClipRRect(clipRRect, clipBehavior: clipBehavior);
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        builder.pushClipRSuperellipse(
          clipRSuperellipse,
          clipBehavior: clipBehavior,
        );
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        builder.pushClipPath(clipPath, clipBehavior: clipBehavior);
      case OpacityLayer(:final alpha?, :final offset):
        builder.pushOpacity(alpha, offset: offset);
      case ColorFilterLayer(:final colorFilter?):
        builder.pushColorFilter(colorFilter);
      case ImageFilterLayer(:final imageFilter?, :final offset):
        builder.pushImageFilter(imageFilter, offset: offset);
      case ShaderMaskLayer(:final shader?, :final maskRect?, :final blendMode?):
        builder.pushShaderMask(shader, maskRect, blendMode);
      case TransformLayer(:final transform?, :final offset):
        builder.pushTransform(
          (Matrix4.translationValues(offset.dx, offset.dy, 0)
                ..multiply(transform))
              .storage,
        );
      case OffsetLayer(:final offset) || LeaderLayer(:final offset):
        builder.pushOffset(offset.dx, offset.dy);
      default:
        return false;
    }
    return true;
  }

  /// [rect] in numbers — read the same in a profile build, where a [Rect]
  /// does not say what it is.
  static String _spot(Rect rect) =>
      '(${rect.left.round()}, ${rect.top.round()}) '
      '${rect.width.round()}×${rect.height.round()}';
}

/// 🚨WHAT A TICK MOVES IS DRAWN LIVE BETWEEN A STILL REGION'S STRATA, NOT IN
/// THEM (10-12, [TickLayer]'s layer): a cut playing changed the timeline's
/// dock on every film frame — its cursor, its playhead's writing, its
/// counter, each on a tick layer of its own — so the region was never still
/// and every frame drew all of it again. 🔬While a cut played the side
/// rails came from their images on 75 frames of 75 and the timeline's dock
/// on none; with the timeline folded, a playing frame's raster ran about
/// 1.5ms shorter (the user's layout, cut 302, 144Hz).
///
/// A still region is cut at every tick that is moving — that changed what
/// it holds within the last few dozen frames — and each part between two of
/// them is a part of the one image the region keeps, so everything that
/// overlaps is drawn in the order it was painted in, the ticks live in
/// their places (what touches nothing above it goes lower,
/// [_Strata._lowest]). ↩️The
/// first way drew every tick OVER one image of everything else, and a tick
/// something painted after it covered had to stay in the image: a picture
/// layer's bounds are its boundary's whole box, not what it drew, so nearly
/// every tick in the timeline read as covered and the region was never
/// still (10-12).
class TickSceneLayer extends OffsetLayer {
  /// The box the tick paints in, at [offset] — for the region's
  /// diagnostics.
  Size size = Size.zero;

  /// What the tick held the last time its region looked — its place, its
  /// layers and their pictures, as values — and the last frame it changed
  /// in ALONE, the rest of its region standing still ([_StillLayer._moving]).
  ///
  /// ⛔Not the frames it was added to a scene in: a tick is added again
  /// whenever anything under it changes, and a region drawing it live adds
  /// it on every frame itself.
  List<Object?>? _held;
  int _movedAloneAt = -_StillLayer._movingFor - 1;

  /// Whether what the tick holds changed since its region last looked.
  bool _looked(List<Object?> held) {
    if (listEquals(held, _held)) {
      return false;
    }
    _held = held;
    return true;
  }
}
