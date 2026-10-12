import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../debug/measurement_mode.dart';
import '../effective_device_pixel_ratio.dart';
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
/// after [stillFrames] frames of being retained, and dropped the moment the
/// region is re-added with a different layer tree
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
  /// snapshot is a fixed price (1.6–2.0 ms of raster on the real Windows
  /// app, whatever its size, 2026-09-25), and the regions one pick changes
  /// become still together: taken on the same frame, their prices landed on
  /// it at once.
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

  /// Switched off by [StaticRaster.globallyEnabled].
  disabled,

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
    for (final (:tick, path: _) in _layer?._ticks ?? const <_Tick>[])
      tick.size,
  ];

  /// How the region sat on the device pixel grid when its image was
  /// taken, for tests that need to prove the image was a copy and not a
  /// resample. Null while it paints.
  @visibleForTesting
  Offset? get debugGridShift => _layer?._imageFit?.shift;

  /// What the region's image holds, in bytes — zero while it paints.
  int get rasterBytes {
    final image = _layer?._image;
    return image == null ? 0 : image.width * image.height * 4;
  }

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
    StaticRaster.globallyEnabled.addListener(_restart);
    MeasurementMode.showRepaints.addListener(_restart);
  }

  @override
  void detach() {
    StillRaster.census.remove(this);
    StaticRaster.globallyEnabled.removeListener(_restart);
    MeasurementMode.showRepaints.removeListener(_restart);
    _layer?._drop();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    StillRaster.census.remove(this);
    StaticRaster.globallyEnabled.removeListener(_restart);
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
    if (!StaticRaster.globallyEnabled.value) {
      return StillStandDown.disabled;
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
/// the region and it.
typedef _Tick = ({TickSceneLayer tick, List<ContainerLayer> path});

/// A picture of the region's, with the layers between the region and it,
/// and where those layers put it.
typedef _Leaf = ({
  PictureLayer picture,
  List<ContainerLayer> path,
  Matrix4 toRegion,
});

/// The region's layer: it hands the scene either its children or, while
/// they stay the same, its STRATA — what it paints between one moving tick
/// and the next, each a part of one image — with the moving ticks drawn
/// live between them ([TickSceneLayer]).
class _StillLayer extends OffsetLayer {
  _StillLayer(this._owner);

  final RenderStillRaster _owner;

  /// The one image every stratum is a part of.
  ui.Image? _image;

  /// A picture per stratum that puts its part of [_image] back, null where
  /// the stratum paints nothing — one more than [_ticks].
  List<ui.Picture?> _strata = const [];
  RasterGridFit? _imageFit;
  List<Object?>? _imageSignature;

  /// The ticks drawn live between the strata, in the order the region
  /// paints them — and the same ticks as a set, for the signature.
  List<_Tick> _ticks = const [];
  Set<TickSceneLayer> _live = const {};

  /// What the region's layer tree was, every tick's own layers aside, and
  /// where it sat, the last time it was re-added — a re-add that only a
  /// tick asked for changes nothing that is still.
  List<Object?>? _lastSignature;
  RasterGridFit? _lastFit;

  /// The frame this region was last re-added with a change of its own.
  int _changedAt = 0;

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
      _stillFramesNeeded = lived < 2 * _stillFramesNeeded
          ? (_stillFramesNeeded * 2).clamp(
              StillRaster.stillFrames,
              StillRaster.maxStillFrames,
            )
          : StillRaster.stillFrames;
    }
    for (final stratum in _strata) {
      stratum?.dispose();
    }
    _image?.dispose();
    _strata = const [];
    _image = null;
    _imageFit = null;
    _imageSignature = null;
    _ticks = const [];
    _live = const {};
    _capturedAt = null;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_image != null && _stillShowsImage()) {
      engineLayer = builder.pushOffset(
        offset.dx,
        offset.dy,
        oldLayer: engineLayer as ui.OffsetEngineLayer?,
      );
      for (var i = 0; i < _strata.length; i += 1) {
        final stratum = _strata[i];
        if (stratum != null) {
          builder.addPicture(Offset.zero, stratum);
        }
        if (i < _ticks.length) {
          _addTick(builder, _ticks[i]);
        }
      }
      builder.pop();
      _owner._drawnFromImage = true;
      _owner._standDown = StillStandDown.none;
      return;
    }
    if (_image != null) {
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
      _changedAt = _frame;
    }
    _lastSignature = signature;
    _lastFit = fit;
    _owner._drawnFromImage = false;
    final gate = _owner._gate();
    _owner._standDown = gate == StillStandDown.none
        ? StillStandDown.changing
        : gate;
    if (gate == StillStandDown.none) {
      _watch();
    }
    super.addToScene(builder);
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
    if (_image != null) {
      if (!_measurePlacement()) {
        markNeedsAddToScene();
      } else if (_nowDx != _placedDx ||
          _nowDy != _placedDy ||
          _nowBelowTransforms != _placedBelowTransforms) {
        _owner._fullPlacementChecks += 1;
        if (_owner._gridFit() != _imageFit) {
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

  /// Whether the strata still show the region: the gate is open, the
  /// region sits on the same device pixels, and the layer tree under it is
  /// the one they were taken of, its live ticks aside.
  bool _stillShowsImage() =>
      _owner._gate() == StillStandDown.none &&
      _owner._gridFit() == _imageFit &&
      listEquals(_signatureOf(_live.contains), _imageSignature);

  void _watch() {
    if (_watching) {
      return;
    }
    _watching = true;
    void check(Duration _) {
      _watching = false;
      if (!attached || _image != null) {
        return;
      }
      if (_owner._gate() != StillStandDown.none) {
        return;
      }
      // `>`: the frame clock ticks after the scene is built, so the frame
      // the region changed in already reads one here. And one image a
      // frame across every region ([StillRaster._lastCaptureFrame]).
      if (_frame - _changedAt > _stillFramesNeeded &&
          StillRaster._lastCaptureFrame != _frame) {
        _capture();
        return;
      }
      _watching = true;
      SchedulerBinding.instance.addPostFrameCallback(check);
    }

    SchedulerBinding.instance.addPostFrameCallback(check);
  }

  /// Takes the region's strata as the scene last had it — every stratum a
  /// part of ONE image, aligned to the device pixel grid — for the next
  /// frame to show.
  ///
  /// The ticks drawn live are the ones that moved while the rest of the
  /// region stood still; a tick that did not is painted into its stratum
  /// like anything else, and its moving later is a change of the region's.
  void _capture() {
    final fit = _owner._gridFit();
    if (fit == null) {
      _owner._standDown = StillStandDown.unlocatable;
      return;
    }
    final layout = _strataOf((tick) => tick._addedAt > _changedAt);
    final live = {
      for (final (:tick, path: _) in layout?.ticks ?? const <_Tick>[]) tick,
    };
    final signature = layout == null ? null : _signatureOf(live.contains);
    if (layout == null || signature == null) {
      _owner._standDown = StillStandDown.unvouched;
      return;
    }
    try {
      if (!supportsRasterization()) {
        _owner._standDown = StillStandDown.unvouched;
        return;
      }
      StillRaster._lastCaptureFrame = _frame;
      final taken = _atlasOf(layout.strata, fit);
      _owner._captureCount += 1;
      _image = taken.image;
      _strata = taken.strata;
      _imageFit = fit;
      if (_measurePlacement()) {
        _keepPlacement();
      }
      _imageSignature = signature;
      _ticks = layout.ticks;
      _live = live;
      _capturedAt = _frame;
      StillRaster._capturesEver += 1;
    } on Object catch (error, stack) {
      _refused(error, stack);
      return;
    }
    // The scene still holds the children: re-add this layer so the next
    // frame draws the strata instead.
    //
    // ⛔NOT A FRAME OF ITS OWN (2026-09-25, H40). One asked for here shows
    // nothing new — the image is of what is already on screen — and its
    // frame counted as still for every other region, which then took ITS
    // image and asked for another: a brush pick with the settings open grew
    // nine frames longer, ~20 ms more of UI thread, and the images taken in
    // a row landed on the stroke that followed (worst frame 48 → 63 ms).
    // The next frame that comes anyway draws it.
    markNeedsAddToScene();
  }

  /// The region's pictures in the order it paints them, cut into strata at
  /// every tick [live] says is drawn live — null when a live tick stands
  /// under a layer whose effect is the GROUP's (a fade, a filter, a mask):
  /// cut there, the group would be drawn as parts.
  ({List<List<_Leaf>> strata, List<_Tick> ticks})? _strataOf(
    bool Function(TickSceneLayer tick) live,
  ) {
    final strata = <List<_Leaf>>[[]];
    final ticks = <_Tick>[];
    final refusals = <String>[];
    final path = <ContainerLayer>[];
    // A tick a moving tick stands inside is added again with it whatever it
    // holds itself, so it reads as moving too: the one drawn live is the
    // innermost, and what the outer one holds beside it is in the strata.
    bool holdsLive(ContainerLayer layer) {
      for (var child = layer.firstChild;
          child != null;
          child = child.nextSibling) {
        if (child is TickSceneLayer && live(child)) {
          return true;
        }
        if (child is ContainerLayer && holdsLive(child)) {
          return true;
        }
      }
      return false;
    }

    void visit(Layer layer, Matrix4 toRegion) {
      switch (layer) {
        case TickSceneLayer() when live(layer) && !holdsLive(layer):
          final under = path.where((above) => !_splits(above));
          if (under.isNotEmpty) {
            refusals.add(
              '${_spot(layer.offset & layer.size)} (${layer.debugCreator}): '
              'under ${under.first.runtimeType}',
            );
          }
          ticks.add((tick: layer, path: List.of(path)));
          strata.add([]);
        case PictureLayer():
          strata.last.add((
            picture: layer,
            path: List.of(path),
            toRegion: toRegion,
          ));
        case ContainerLayer():
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
          path.add(layer);
          for (var child = layer.firstChild;
              child != null;
              child = child.nextSibling) {
            visit(child, inner);
          }
          path.removeLast();
        default:
      }
    }

    for (var child = firstChild; child != null; child = child.nextSibling) {
      visit(child, Matrix4.identity());
    }
    _owner._tickRefusals = refusals;
    return refusals.isEmpty ? (strata: strata, ticks: ticks) : null;
  }

  /// Whether a tick drawn live can stand under [layer] as the region had
  /// it — what [layer] does to its children is done to each part alike.
  /// A fade, a filter or a mask is done to the GROUP: on the strata and the
  /// tick apart, overlapping parts would show through each other.
  static bool _splits(ContainerLayer layer) => switch (layer) {
    OpacityLayer(:final alpha) => alpha == null || alpha == 255,
    ColorFilterLayer() ||
    ImageFilterLayer() ||
    ShaderMaskLayer() ||
    BackdropFilterLayer() => false,
    _ => true,
  };

  /// [strata] drawn into ONE image — each its own rows of it, cut to the
  /// device pixels its pictures reach — and a picture per stratum that puts
  /// its rows back where they were taken, 1:1.
  ///
  /// ⛔One image, not one a stratum: a snapshot costs a fixed price on the
  /// raster thread whatever its size (1.6–2.0 ms on the real Windows app,
  /// 09-25), and a region cut at every tick has several strata.
  ({ui.Image image, List<ui.Picture?> strata}) _atlasOf(
    List<List<_Leaf>> strata,
    RasterGridFit fit,
  ) {
    final size = _owner.size;
    final whole = Rect.fromLTWH(
      0,
      0,
      ((size.width + fit.shift.dx) * fit.scale).ceilToDouble(),
      ((size.height + fit.shift.dy) * fit.scale).ceilToDouble(),
    );
    Rect deviceOf(Rect logical) => Rect.fromLTRB(
      ((logical.left + fit.shift.dx) * fit.scale).floorToDouble(),
      ((logical.top + fit.shift.dy) * fit.scale).floorToDouble(),
      ((logical.right + fit.shift.dx) * fit.scale).ceilToDouble(),
      ((logical.bottom + fit.shift.dy) * fit.scale).ceilToDouble(),
    ).intersect(whole);
    Rect logicalOf(Rect device) => Rect.fromLTRB(
      device.left / fit.scale - fit.shift.dx,
      device.top / fit.scale - fit.shift.dy,
      device.right / fit.scale - fit.shift.dx,
      device.bottom / fit.scale - fit.shift.dy,
    );

    final rows = <Rect?>[];
    var width = 0.0;
    var height = 0.0;
    for (final leaves in strata) {
      Rect? reach;
      for (final (:picture, path: _, :toRegion) in leaves) {
        final drawn = MatrixUtils.transformRect(
          toRegion,
          picture.canvasBounds,
        );
        reach = reach == null ? drawn : reach.expandToInclude(drawn);
      }
      final device = reach == null ? null : deviceOf(reach);
      if (device == null || device.isEmpty) {
        rows.add(null);
        continue;
      }
      rows.add(device);
      width = width < device.width ? device.width : width;
      height += device.height;
    }

    final builder = ui.SceneBuilder();
    var y = 0.0;
    for (var i = 0; i < strata.length; i += 1) {
      final device = rows[i];
      if (device == null) {
        continue;
      }
      final place = Matrix4.translationValues(-device.left, y - device.top, 0)
        ..scaleByDouble(fit.scale, fit.scale, 1, 1)
        ..translateByDouble(fit.shift.dx, fit.shift.dy, 0, 1);
      builder
        ..pushTransform(place.storage)
        ..pushClipRect(logicalOf(device));
      _addLeaves(builder, strata[i]);
      builder
        ..pop()
        ..pop();
      y += device.height;
    }
    final scene = builder.build();
    final ui.Image image;
    try {
      image = scene.toImageSync(
        width.round().clamp(1, 1 << 15),
        height.round().clamp(1, 1 << 15),
      );
    } finally {
      scene.dispose();
    }

    final pictures = <ui.Picture?>[];
    y = 0;
    for (final device in rows) {
      if (device == null) {
        pictures.add(null);
        continue;
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final logical = logicalOf(device);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, y, device.width, device.height),
        logical,
        Paint()..filterQuality = FilterQuality.none,
      );
      if (MeasurementMode.showRepaints.value) {
        canvas.drawRect(
          logical,
          Paint()..color = MeasurementMode.repaintTint(_owner._captureCount),
        );
      }
      pictures.add(recorder.endRecording());
      y += device.height;
    }
    return (image: image, strata: pictures);
  }

  /// [leaves] added as the region had them — each under its layers, pushed
  /// again where the one before stood under others.
  static void _addLeaves(ui.SceneBuilder builder, List<_Leaf> leaves) {
    final pushed = <ContainerLayer>[];
    final counted = <bool>[];
    for (final (:picture, :path, toRegion: _) in leaves) {
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
  List<Object?>? _signatureOf(bool Function(TickSceneLayer tick) live) {
    final out = <Object?>[];
    bool walk(Layer layer) {
      out.add(layer);
      switch (layer) {
        case TickSceneLayer() when live(layer):
          return true;
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
      if (layer is ContainerLayer) {
        for (var child = layer.firstChild;
            child != null;
            child = child.nextSibling) {
          if (!walk(child)) {
            return false;
          }
        }
      }
      return true;
    }

    for (var child = firstChild; child != null; child = child.nextSibling) {
      if (!walk(child)) {
        return null;
      }
    }
    return out;
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
/// A still region is cut at every tick that moved while the rest of it
/// stood still, and each part between two of them is a part of the one
/// image the region keeps — so everything is drawn in the order it was
/// painted in, the ticks live in their places. ↩️The first way drew every
/// tick OVER one image of everything else, and a tick something painted
/// after it covered had to stay in the image: a picture layer's bounds are
/// its boundary's whole box, not what it drew, so nearly every tick in the
/// timeline read as covered and the region was never still (10-12).
class TickSceneLayer extends OffsetLayer {
  /// The box the tick paints in, at [offset] — for the region's
  /// diagnostics.
  Size size = Size.zero;

  /// The frame this tick was last added to a scene in — the frame it last
  /// changed, or was drawn live.
  int _addedAt = -1;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _addedAt = _StillLayer._frame;
    super.addToScene(builder);
  }
}
