import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../debug/measurement_mode.dart';
import '../debug/repaint_cause.dart';

/// Bakes its child into ONE image and blits that until the child actually
/// changes.
///
/// ## Why this exists
///
/// A `RepaintBoundary` stops a subtree from being re-RECORDED on the UI
/// thread. It does NOT stop the raster thread from re-executing that
/// subtree's display list every frame — the pixels survive between
/// frames only if the engine's raster cache happens to hold them, which
/// for a panel-sized picture it generally does not.
///
/// That gap is not theoretical here. Measured on the real app, hovering
/// the pen over an EMPTY canvas cost 27.6 ms/frame of raster, of which
/// **24.0 ms was panels that were not changing at all** — a timesheet
/// re-drawing 334 lines and 111 text paragraphs, a preset list, a
/// settings column. The UI thread meanwhile sat at 0.5 ms: nothing was
/// being rebuilt or re-recorded. Every one of those frames existed only
/// because the mouse had moved a few pixels somewhere else.
///
/// A picture cache would buy nothing — replaying a display list is
/// exactly what already happens. Only a RASTER collapses N ops into one
/// `drawImageRect`.
///
/// ## The contract
///
/// > **Capture whenever `paint()` runs. Never capture otherwise.**
///
/// That is the whole invalidation story, and it cannot go stale, because
/// this render object is a repaint boundary and Flutter only calls
/// `paint()` on a boundary it has marked dirty. Everything that should
/// invalidate already routes through that dirty bit —
/// `CustomPainter.shouldRepaint`, a painter's `repaint` listenable, a
/// rebuild, a relayout (`layout()` ends in `markNeedsPaint`). Ancestor
/// scrolls, pans and transforms do NOT dirty us, and that is the win.
///
/// Nothing is asked of the caller. A panel wrapped in this does not have
/// to remember to invalidate, and a panel that is genuinely alive is
/// handled by [maxConsecutiveCaptures] below rather than by a checklist.
///
/// ## 🚨 The one invariant, and why it is enforced instead of documented
///
/// **A subtree under a [StaticRaster] must not contain another repaint
/// boundary.** `markNeedsPaint` stops at the first boundary it reaches
/// and adds THAT node to the dirty list; it never walks on to an ancestor
/// boundary. Once we have captured and dropped the child's layers, an
/// inner boundary's layer is detached, so `_skippedPaintingOnLayer` walks
/// up, stops at the first *attached* ancestor — us — and does not mark
/// it. The inner subtree would then be frozen forever.
///
/// So this does not document the rule and hope: it LOOKS, every time it
/// is about to capture, and falls back to painting through when it finds
/// one. A panel with an inner boundary silently loses the optimisation
/// instead of silently showing stale pixels, and [debugNestedBoundary]
/// says which panels are leaving something on the table.
///
/// Cheap by construction: the walk only runs on the frames where we were
/// going to repaint the whole subtree anyway.
///
/// ## 🚨 The second invariant: a baked subtree may not paint outside its
/// own box
///
/// Baking captures `Offset.zero & size` and blits it back into
/// `offset & size`, so it is a hard clip. Painting through is NOT — a
/// `RenderProxyBox` clips nothing. So a child that draws past its own
/// bounds (an overflowing label, an elevation shadow, a `CustomPainter`
/// reaching outside its box, a negative `Positioned`) looks DIFFERENT
/// baked than unbaked, and will appear and disappear as the surface
/// stands itself down and comes back.
///
/// That is not a freeze, but it is a difference a person would report as
/// one. The install sites that sit inside a `ClipRect` already agree
/// either way; the ones that do not are relying on their content
/// staying inside its box.
class StaticRaster extends SingleChildRenderObjectWidget {
  const StaticRaster({
    super.key,
    required this.debugLabel,
    this.enabled = true,
    this.maxConsecutiveCaptures = 3,
    required Widget super.child,
  });

  /// Names this surface in diagnostics. Use the panel's name.
  final String debugLabel;

  /// Caller kill-switch, for a surface that is known to be alive for a
  /// while (a live drag, a playback session). Usually unnecessary —
  /// [maxConsecutiveCaptures] notices on its own.
  final bool enabled;

  /// After this many captures on consecutive frames, stop trying and
  /// paint through until the surface goes quiet again.
  ///
  /// Capturing costs a full paint PLUS a full-surface copy, so a surface
  /// that changes every frame is strictly slower snapshotted than not.
  /// This is what lets the wrapper be applied everywhere without a
  /// per-caller audit of "but does it animate?" — the ones that animate
  /// opt themselves out, every frame, for free.
  final int maxConsecutiveCaptures;

  /// Global off switch. Painting goes straight through when false, so a
  /// suspicious rendering can be A/B'd against the same build.
  static final ValueNotifier<bool> globallyEnabled = ValueNotifier<bool>(true);

  /// Every attached bake in the app.
  ///
  /// Qt documents the cost of this exact mechanism and warns about
  /// exactly the way we use it — `layer.enabled` costs `width × height ×
  /// 4` of GPU memory per layer, loses batching across the boundary, and
  /// "a scene with many layered items may have performance problems".
  /// We install bakes on two blanket funnels so a new panel gets one for
  /// free, which is the right default and also the shape Qt warns about.
  ///
  /// A default you cannot see the price of is a default you will regret,
  /// so the price is on screen: [censusBytes] and [censusCaptures] feed
  /// the Frame Stats readout.
  static final Set<RenderStaticRaster> census = <RenderStaticRaster>{};

  /// Bytes currently held by all live bakes.
  static int get censusBytes {
    var total = 0;
    for (final raster in census) {
      total += raster.rasterBytes;
    }
    return total;
  }

  /// Bakes taken since the app started, across every surface. Differenced
  /// over time this is the rate — the number that says a surface is
  /// re-baking on the pointer rather than on a change.
  static int get censusCaptures {
    var total = 0;
    for (final raster in census) {
      total += raster.captureCount;
    }
    return total;
  }

  @override
  RenderStaticRaster createRenderObject(BuildContext context) {
    return RenderStaticRaster(
      debugLabel: debugLabel,
      enabled: enabled,
      maxConsecutiveCaptures: maxConsecutiveCaptures,
      devicePixelRatio: _devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStaticRaster renderObject,
  ) {
    renderObject
      ..debugLabel = debugLabel
      ..enabled = enabled
      ..maxConsecutiveCaptures = maxConsecutiveCaptures
      ..devicePixelRatio = _devicePixelRatioOf(context);
  }

  /// The `MediaQuery` value when there is one, the view's own otherwise.
  /// Every panel has a `MediaQuery` above it, but a primitive that
  /// throws when used slightly off the beaten path is a primitive people
  /// stop reaching for.
  static double _devicePixelRatioOf(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.of(context).devicePixelRatio;
}

/// How a surface sits on the device pixel grid, which is what decides
/// whether its bake is a copy or a resample.
@immutable
class _GridFit {
  const _GridFit({required this.shift, required this.scale});

  /// How far the surface's top-left corner sits INTO the device pixel it
  /// begins in, in the surface's own logical units. Zero when the surface
  /// already starts on a whole pixel.
  final Offset shift;

  /// One logical unit of the surface, in device pixels — the view's ratio
  /// times any scale an ancestor applies.
  final double scale;
}

class RenderStaticRaster extends RenderProxyBox {
  RenderStaticRaster({
    required this.debugLabel,
    required bool enabled,
    required int maxConsecutiveCaptures,
    required double devicePixelRatio,
  }) : _enabled = enabled,
       _maxConsecutiveCaptures = maxConsecutiveCaptures,
       _devicePixelRatio = devicePixelRatio;

  /// The point of the whole class: our own layer, so Flutter's dirty bit
  /// is the invalidation signal and an ancestor's repaint does not reach
  /// the child.
  @override
  bool get isRepaintBoundary => true;

  /// Names this surface in diagnostics; carries no behaviour.
  String debugLabel;

  bool _enabled;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    _dropRaster();
    markNeedsPaint();
  }

  int _maxConsecutiveCaptures;
  int get maxConsecutiveCaptures => _maxConsecutiveCaptures;
  set maxConsecutiveCaptures(int value) {
    if (_maxConsecutiveCaptures == value) {
      return;
    }
    _maxConsecutiveCaptures = value;
    _streak = 0;
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) {
      return;
    }
    _devicePixelRatio = value;
    _dropRaster();
    markNeedsPaint();
  }

  ui.Image? _raster;
  Size? _rasterSourceSize;
  _GridFit? _rasterFit;

  /// Why the last capture attempt gave up, if it did. Diagnostics only.
  String? debugCaptureRefusal;

  /// True when the last capture attempt found a repaint boundary in the
  /// subtree and gave up. Surfaced for diagnostics, not for logic.
  bool get debugNestedBoundary => _nestedBoundary;
  bool _nestedBoundary = false;

  /// WHICH boundary stood the bake down, and where it sits.
  ///
  /// Without this the failure is a bare "paints through" and finding the
  /// cause means grepping a panel's whole subtree for `RepaintBoundary`
  /// — and the ones that bite are usually not written by hand at all
  /// (`ListView`/`ReorderableListView` wrap every item in one by
  /// default). Naming the render object turns a search into a reading.
  String? get debugNestedBoundaryPath => _nestedBoundaryPath;
  String? _nestedBoundaryPath;

  /// True when the surface has been changing every frame and the
  /// wrapper has stood itself down.
  bool get debugStoodDown => _streak >= _maxConsecutiveCaptures;

  /// Captures since this object was attached. Lets a test prove that a
  /// pointer moving elsewhere does not re-bake the panel.
  @visibleForTesting
  int captureCount = 0;

  /// Bakes by what the app was doing at the time.
  ///
  /// The report says WHICH panels re-bake and HOW OFTEN; this says WHY,
  /// as far as a correlational answer can. `pointer` appearing here at
  /// all is the finding — it means a panel is being re-baked because the
  /// mouse moved somewhere else entirely, which is the exact cost this
  /// whole thing exists to remove and is invisible by every other means.
  final Map<String, int> captureCauses = <String, int>{};

  int _streak = 0;
  Duration? _lastCaptureFrame;

  /// What this surface's image costs, in bytes. Zero when it is painting
  /// through.
  int get rasterBytes {
    final source = _rasterSourceSize;
    return _raster == null || source == null
        ? 0
        : (source.width * source.height * 4).round();
  }

  /// How this surface sat on the device pixel grid at the last bake, for
  /// tests that need to prove the blit was a copy and not a resample.
  @visibleForTesting
  Offset? get debugGridShift => _rasterFit?.shift;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    StaticRaster.census.add(this);
    StaticRaster.globallyEnabled.addListener(_onGloballyEnabledChanged);
    MeasurementMode.showRepaints.addListener(_onGloballyEnabledChanged);
  }

  @override
  void detach() {
    StaticRaster.census.remove(this);
    StaticRaster.globallyEnabled.removeListener(_onGloballyEnabledChanged);
    MeasurementMode.showRepaints.removeListener(_onGloballyEnabledChanged);
    _dropRaster();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    StaticRaster.census.remove(this);
    StaticRaster.globallyEnabled.removeListener(_onGloballyEnabledChanged);
    MeasurementMode.showRepaints.removeListener(_onGloballyEnabledChanged);
    _dropRaster();
    super.dispose();
  }

  void _onGloballyEnabledChanged() {
    _dropRaster();
    markNeedsPaint();
  }

  void _dropRaster() {
    _raster?.dispose();
    _raster = null;
    _rasterSourceSize = null;
    _rasterFit = null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // The guard runs FIRST, whatever else is true, so [debugNestedBoundary]
    // describes this frame and not some earlier one. It is the only thing
    // that tells anyone a panel quietly stopped being free, and a
    // diagnostic that is right on some paths and stale on others is worse
    // than none — the enforcement test reads it to decide whether a panel
    // needs a reason on the allowlist.
    _nestedBoundary = _childHasRepaintBoundary();

    if (size.isEmpty) {
      _dropRaster();
      // Paint through rather than return. A zero-size box normally paints
      // nothing, but a child is free to paint outside its box, and
      // vanishing for a layout pass is a worse default than doing what
      // the unbaked tree would have done.
      _paintThrough(context, offset);
      return;
    }
    if (!_enabled || !StaticRaster.globallyEnabled.value) {
      _dropRaster();
      _paintThrough(context, offset);
      return;
    }

    // Reaching paint() means Flutter marked us dirty. Two frames in a
    // row means the surface is alive, not static.
    _noteCaptureFrame();
    if (_streak >= _maxConsecutiveCaptures) {
      _dropRaster();
      _paintThrough(context, offset);
      return;
    }

    if (_nestedBoundary) {
      _dropRaster();
      _paintThrough(context, offset);
      return;
    }

    final fit = _gridFit();
    if (fit == null) {
      // A rotation or a non-uniform scale between us and the screen. There
      // is no 1:1 blit to be had, and a resampled one would not be the
      // same pixels — see [_GridFit].
      debugCaptureRefusal = 'not axis-aligned to the device pixel grid';
      _dropRaster();
      _paintThrough(context, offset);
      return;
    }

    _dropRaster();
    final captured = _captureChild(fit);
    if (captured == null) {
      // Either a platform view the engine cannot rasterize, or a capture
      // the engine refused. Painting through is always available and
      // always correct — see [_captureChild].
      _paintThrough(context, offset);
      return;
    }
    _raster = captured;
    _rasterFit = fit;
    _rasterSourceSize = Size(
      captured.width.toDouble(),
      captured.height.toDouble(),
    );
    debugCaptureRefusal = null;
    captureCount += 1;
    if (RepaintCause.collecting) {
      final cause = RepaintCause.attribute();
      captureCauses[cause] = (captureCauses[cause] ?? 0) + 1;
    }

    _blit(context, offset);
  }

  /// Paints the child WITHOUT baking — and clips it to the same box the
  /// bake would have.
  ///
  /// That clip is the point. Baking captures `Offset.zero & size`, so it
  /// is a hard clip; a proxy box painting through is not. A child that
  /// draws past its own bounds therefore looked different baked than
  /// not — and since a surface stands itself down the moment it starts
  /// changing every frame, the difference appeared and disappeared while
  /// someone worked.
  ///
  /// ⚠️The onion panel's missing band, which this was written for, turned
  /// out NOT to be an overflow — it was the unaligned blit that
  /// [_GridFit] now fixes. The clip below is still right, and it was
  /// still not enough on its own; the two facts are unrelated and were
  /// filed as one for a round.
  ///
  /// The fix is not to hunt down every widget that overflows by a
  /// hairline. It is to make the two modes agree BY CONSTRUCTION, so
  /// that switching between them can never change a pixel and the
  /// invariant stops being something anyone has to know. Clipping is the
  /// stricter of the two behaviours, and it is the one already in force
  /// whenever the bake is active — which is nearly always.
  void _paintThrough(PaintingContext context, Offset offset) {
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clipLayer.layer,
    );
  }

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  void _blit(PaintingContext context, Offset offset) {
    final image = _raster!;
    final sourceSize = _rasterSourceSize!;
    final fit = _rasterFit!;
    // 1:1, and NOT by construction — by [_GridFit] having put it there.
    //
    // The whole image goes back, at the whole-device-pixel corner the
    // capture was aligned to, at exactly the scale it was taken at. Every
    // source pixel therefore lands on exactly one device pixel, which is
    // what makes `FilterQuality.none` both the fastest and the SHARPEST
    // choice rather than a snapping resample. The destination reaches up
    // to one device pixel above and left of `offset & size`; that margin
    // is the transparent slack [_GridFit.shift] describes, because the
    // capture clips the child to its own box exactly as painting through
    // does.
    context.canvas.drawImageRect(
      image,
      Offset.zero & sourceSize,
      Rect.fromLTWH(
        offset.dx - fit.shift.dx,
        offset.dy - fit.shift.dy,
        image.width / fit.scale,
        image.height / fit.scale,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
    if (MeasurementMode.showRepaints.value) {
      // Settings ▸ Show Repaints. The tint cycles per bake, so a surface
      // re-baking every frame STROBES and one that baked once sits
      // still. Borrowed from Krita's `KisRepaintDebugger` (shipped in
      // production) and Blender's `G.debug_value == 888`.
      context.canvas.drawRect(
        offset & size,
        Paint()..color = _repaintTints[captureCount % _repaintTints.length],
      );
    }
  }

  static const List<Color> _repaintTints = <Color>[
    Color(0x3300E5FF),
    Color(0x33FF4081),
    Color(0x33FFEA00),
    Color(0x3300E676),
  ];

  /// Paints the child into a detached layer and takes its picture, or
  /// returns null if the engine will not give us one. The routine is the
  /// SDK's (`SnapshotWidget._paintAndDetachToImage`) — this is not the
  /// place to invent one.
  ///
  /// 🚨A THROW HERE WOULD BLANK THE PANEL, so it cannot be allowed out.
  /// `PaintingContext.repaintCompositedChild` clears `_needsPaint`
  /// BEFORE calling `paint`, and its `catch` reports the exception
  /// without re-dirtying anything — while `_dropRaster()` has already
  /// thrown the previous image away and the layer has already had its
  /// children removed. The result would be an empty, CLEAN layer: a
  /// blank panel that stays blank until something inside it happens to
  /// dirty itself. `toImageSync` can throw for reasons that are none of
  /// our business (a lost GPU context, an allocation the driver
  /// refuses), and the size that provoked it will still be there next
  /// frame, so it would throw again.
  ///
  /// Painting through is always available and always correct, so a
  /// failed capture costs the optimisation and nothing else.
  ui.Image? _captureChild(_GridFit fit) {
    final offsetLayer = OffsetLayer();
    try {
      // Grown by the sub-pixel slack so the image covers WHOLE device
      // pixels at both ends, and the child painted at `fit.shift` so it
      // lands on the same pixel grid it would have unbaked.
      final bounds = Offset.zero & (size + fit.shift);
      final context = PaintingContext(offsetLayer, bounds);
      // The clip painting through pushes, pushed here too, so the two
      // modes cannot disagree about what is inside the box — including on
      // the boundary row, where a box that is a fractional number of
      // device pixels tall has one.
      context.pushClipRect(
        needsCompositing,
        fit.shift,
        Offset.zero & size,
        super.paint,
      );
      // ignore: invalid_use_of_protected_member
      context.stopRecordingIfNeeded();
      if (!offsetLayer.supportsRasterization()) {
        debugCaptureRefusal = 'unrasterizable subtree';
        return null;
      }
      return offsetLayer.toImageSync(bounds, pixelRatio: fit.scale);
    } catch (error, stack) {
      debugCaptureRefusal = 'threw: $error';
      // Reported, not swallowed silently: a capture that keeps failing
      // is a real condition someone should see, and the panel keeps
      // working meanwhile.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'anicel',
          context: ErrorDescription(
            'baking StaticRaster($debugLabel) at $size — painting through',
          ),
        ),
      );
      return null;
    } finally {
      // `finally`, because the early return above used to leak this
      // layer on every unrasterizable subtree and a throw would have
      // leaked it too.
      offsetLayer.dispose();
    }
  }

  /// Bumps [_streak] when this capture lands on the frame after the last
  /// one, and resets it when the surface has been quiet.
  ///
  /// The frame timestamp is only read inside a frame's persistent
  /// callbacks — `paint` also runs outside frames (an ancestor's
  /// `toImage`, a thumbnail capture) and `currentFrameTimeStamp` is not
  /// valid there.
  void _noteCaptureFrame() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final last = _lastCaptureFrame;
    // Two display frames' worth of slack, so this reads "back to back"
    // at 60Hz and at 120Hz alike without needing to know the rate.
    const consecutive = Duration(milliseconds: 34);
    if (last != null && now - last <= consecutive) {
      _streak += 1;
    } else {
      _streak = 0;
    }
    _lastCaptureFrame = now;
  }

  /// Where this surface's top-left corner sits on the device pixel grid,
  /// or null when no 1:1 blit exists at all.
  ///
  /// 🚨This is the difference between a bake that COPIES and a bake that
  /// RESAMPLES, and getting it wrong is invisible in the one configuration
  /// people usually test in.
  ///
  /// `toImageSync` rounds the image UP to whole pixels, and the blit lands
  /// wherever layout puts the box. So unless the box's device-space origin
  /// AND size are both whole pixels, `FilterQuality.none` snaps every
  /// column and row to its nearest neighbour. Measured, both ways:
  ///
  ///  * a panel half a device pixel off the grid: **1483 pixels wrong
  ///    across 12 whole columns**, worst channel 128 — entire hairlines
  ///    and glyph stems jumping a pixel;
  ///  * a panel whose height is not a whole number of device pixels: the
  ///    whole bottom row wrong, worst channel 127.
  ///
  /// Neither is exotic. The second happens to EVERY panel at the 125%,
  /// 150% and 175% display scalings Windows ships, and the first whenever
  /// a splitter leaves a dock on a fractional pixel. At 100% and 200% both
  /// vanish, which is exactly why this survived: the parity test rendered
  /// at a whole ratio, on whole bounds, at a whole offset.
  ///
  /// So the capture is aligned instead: grown to cover whole device pixels
  /// and painted with [_GridFit.shift] so the content keeps the sub-pixel
  /// phase it would have had unbaked.
  _GridFit? _gridFit() {
    final ratio = _devicePixelRatio;
    if (!ratio.isFinite || ratio <= 0) {
      return null;
    }
    // Logical global pixels, not device ones — `getTransformTo(null)`
    // stops at the root render object and the view's own ratio is applied
    // after it.
    final Matrix4 toGlobal = getTransformTo(null);
    final double? uniformScale = _uniformScaleOf(toGlobal);
    if (uniformScale == null) {
      return null;
    }
    // One of OUR logical units, in device pixels: the ancestors' scale
    // takes it to global logical units and the view's ratio from there.
    final double scale = uniformScale * ratio;
    if (!scale.isFinite || scale <= 0) {
      return null;
    }
    // `origin` is already in global logical units, so it needs the view's
    // ratio and not the ancestors' scale a second time.
    final Offset origin = MatrixUtils.transformPoint(toGlobal, Offset.zero);
    final double left = origin.dx * ratio;
    final double top = origin.dy * ratio;
    if (!left.isFinite || !top.isFinite) {
      return null;
    }
    return _GridFit(
      shift: Offset(
        (left - left.floorToDouble()) / scale,
        (top - top.floorToDouble()) / scale,
      ),
      scale: scale,
    );
  }

  /// The scale in [transform] when it is a translation and a single
  /// positive uniform scale, and null for anything else — a rotation, a
  /// skew, a mirror, a scale that differs per axis. Those can still be
  /// baked, but not as a pixel-for-pixel copy, so the surface paints
  /// through instead of quietly resampling itself.
  static double? _uniformScaleOf(Matrix4 transform) {
    final Float64List m = transform.storage;
    const double epsilon = 1e-6;
    bool zero(double value) => value.abs() < epsilon;
    if (!zero(m[1]) ||
        !zero(m[2]) ||
        !zero(m[3]) ||
        !zero(m[4]) ||
        !zero(m[6]) ||
        !zero(m[7]) ||
        !zero(m[8]) ||
        !zero(m[9]) ||
        !zero(m[11]) ||
        (m[15] - 1).abs() > epsilon) {
      return null;
    }
    final double sx = m[0];
    final double sy = m[5];
    if (sx <= 0 || (sx - sy).abs() > epsilon) {
      return null;
    }
    return sx;
  }

  bool _childHasRepaintBoundary() {
    _nestedBoundaryPath = null;
    final start = child;
    if (start == null) {
      return false;
    }
    if (start.isRepaintBoundary) {
      _nestedBoundaryPath = start.runtimeType.toString();
      return true;
    }
    final trail = <RenderObject>[];
    RenderObject? found;
    void walk(RenderObject node) {
      if (found != null) {
        return;
      }
      node.visitChildren((RenderObject descendant) {
        if (found != null) {
          return;
        }
        if (descendant.isRepaintBoundary) {
          found = descendant;
          return;
        }
        trail.add(descendant);
        walk(descendant);
        if (found == null) {
          trail.removeLast();
        }
      });
    }

    walk(start);
    if (found == null) {
      return false;
    }
    _nestedBoundaryPath = <String>[
      start.runtimeType.toString(),
      for (final node in trail) node.runtimeType.toString(),
      found.runtimeType.toString(),
    ].join(' > ');
    return true;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', debugLabel));
    properties.add(
      FlagProperty('enabled', value: _enabled, ifFalse: 'disabled'),
    );
    properties.add(IntProperty('captures', captureCount));
    properties.add(
      FlagProperty(
        'nestedBoundary',
        value: _nestedBoundary,
        ifTrue: 'painting through: subtree has its own repaint boundary',
      ),
    );
    properties.add(
      FlagProperty(
        'stoodDown',
        value: debugStoodDown,
        ifTrue: 'painting through: surface changes every frame',
      ),
    );
  }
}
