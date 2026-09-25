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

/// The region's layer: it hands the scene either its children or, while
/// they stay the same, one picture of one image of them.
class _StillLayer extends OffsetLayer {
  _StillLayer(this._owner);

  final RenderStillRaster _owner;

  ui.Image? _image;
  ui.Picture? _picture;
  RasterGridFit? _imageFit;
  List<Object?>? _imageSignature;

  /// The frame this region was last re-added with its children.
  int _changedAt = 0;

  /// The frame its current image was taken, for the back-off.
  int? _capturedAt;
  int _stillFramesNeeded = StillRaster.stillFrames;
  bool _watching = false;
  bool _capturing = false;

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
    _picture?.dispose();
    _image?.dispose();
    _picture = null;
    _image = null;
    _imageFit = null;
    _imageSignature = null;
    _capturedAt = null;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (!_capturing && _picture != null && _stillShowsImage()) {
      engineLayer = builder.pushOffset(
        offset.dx,
        offset.dy,
        oldLayer: engineLayer as ui.OffsetEngineLayer?,
      );
      builder.addPicture(Offset.zero, _picture!);
      builder.pop();
      _owner._drawnFromImage = true;
      _owner._standDown = StillStandDown.none;
      return;
    }
    if (!_capturing) {
      if (_picture != null) {
        _drop();
      }
      _changedAt = _frame;
      _owner._drawnFromImage = false;
      final gate = _owner._gate();
      _owner._standDown = gate == StillStandDown.none
          ? StillStandDown.changing
          : gate;
      if (gate == StillStandDown.none) {
        _watch();
      }
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
  @override
  void updateSubtreeNeedsAddToScene() {
    if (_picture != null && _owner._gridFit() != _imageFit) {
      markNeedsAddToScene();
    }
    super.updateSubtreeNeedsAddToScene();
  }

  /// Whether the image still shows the region: the gate is open, the
  /// region sits on the same device pixels, and the layer tree under it is
  /// the one the image was taken of.
  bool _stillShowsImage() =>
      _owner._gate() == StillStandDown.none &&
      _owner._gridFit() == _imageFit &&
      listEquals(_signatureOf(), _imageSignature);

  void _watch() {
    if (_watching) {
      return;
    }
    _watching = true;
    void check(Duration _) {
      _watching = false;
      if (!attached || _picture != null) {
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

  /// Takes the image of the region as the scene last had it, aligned to
  /// the device pixel grid, for the next frame to show.
  void _capture() {
    final fit = _owner._gridFit();
    if (fit == null) {
      _owner._standDown = StillStandDown.unlocatable;
      return;
    }
    final signature = _signatureOf();
    if (signature == null) {
      _owner._standDown = StillStandDown.unvouched;
      return;
    }
    final size = _owner.size;
    // Grown by the sub-pixel slack so the image covers WHOLE device pixels
    // at both ends — [RasterGridFit] says why that is the whole difference
    // between a copy and a resample.
    final bounds = Rect.fromLTWH(
      -fit.shift.dx,
      -fit.shift.dy,
      size.width + fit.shift.dx,
      size.height + fit.shift.dy,
    );
    _capturing = true;
    try {
      if (!supportsRasterization()) {
        _owner._standDown = StillStandDown.unvouched;
        return;
      }
      StillRaster._lastCaptureFrame = _frame;
      final image = toImageSync(bounds, pixelRatio: fit.scale);
      _owner._captureCount += 1;
      _image = image;
      _picture = _pictureOf(image, fit, size);
      _imageFit = fit;
      _imageSignature = signature;
      _capturedAt = _frame;
      StillRaster._capturesEver += 1;
    } on Object catch (error, stack) {
      _refused(error, stack);
      return;
    } finally {
      _capturing = false;
    }
    // The scene still holds the children: re-add this layer so the next
    // frame draws the image instead.
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

  /// The one picture the scene gets instead of the region: [image] put
  /// back where it was taken, under the Show Repaints tint when that is on.
  ui.Picture _pictureOf(ui.Image image, RasterGridFit fit, Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    fit.blit(canvas, image, Offset.zero);
    if (MeasurementMode.showRepaints.value) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = MeasurementMode.repaintTint(_owner._captureCount),
      );
    }
    return recorder.endRecording();
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
  /// re-add changed something). Null when the tree holds content that can
  /// change with no layer knowing — then there is nothing to vouch for.
  List<Object?>? _signatureOf() {
    final out = <Object?>[];
    bool walk(Layer layer) {
      out.add(layer);
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
}
