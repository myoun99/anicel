import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
  void updateRenderObject(BuildContext context, RenderStaticRaster renderObject) {
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

  /// True when the last capture attempt found a repaint boundary in the
  /// subtree and gave up. Surfaced for diagnostics, not for logic.
  bool get debugNestedBoundary => _nestedBoundary;
  bool _nestedBoundary = false;

  /// True when the surface has been changing every frame and the
  /// wrapper has stood itself down.
  bool get debugStoodDown => _streak >= _maxConsecutiveCaptures;

  /// Captures since this object was attached. Lets a test prove that a
  /// pointer moving elsewhere does not re-bake the panel.
  @visibleForTesting
  int captureCount = 0;

  int _streak = 0;
  Duration? _lastCaptureFrame;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    StaticRaster.globallyEnabled.addListener(_onGloballyEnabledChanged);
  }

  @override
  void detach() {
    StaticRaster.globallyEnabled.removeListener(_onGloballyEnabledChanged);
    _dropRaster();
    super.detach();
  }

  @override
  void dispose() {
    StaticRaster.globallyEnabled.removeListener(_onGloballyEnabledChanged);
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
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      _dropRaster();
      return;
    }
    if (!_enabled || !StaticRaster.globallyEnabled.value) {
      _dropRaster();
      super.paint(context, offset);
      return;
    }

    // Reaching paint() means Flutter marked us dirty. Two frames in a
    // row means the surface is alive, not static.
    _noteCaptureFrame();
    if (_streak >= _maxConsecutiveCaptures) {
      _dropRaster();
      super.paint(context, offset);
      return;
    }

    _nestedBoundary = _childHasRepaintBoundary();
    if (_nestedBoundary) {
      _dropRaster();
      super.paint(context, offset);
      return;
    }

    _dropRaster();
    final captured = _captureChild();
    if (captured == null) {
      // A platform view in the subtree cannot be rasterized. The repo
      // has none today, but "none today" is not a contract.
      super.paint(context, offset);
      return;
    }
    _raster = captured;
    _rasterSourceSize = size * _devicePixelRatio;
    captureCount += 1;

    _blit(context, offset);
  }

  void _blit(PaintingContext context, Offset offset) {
    final image = _raster!;
    final sourceSize = _rasterSourceSize!;
    // 1:1 by construction — the image was captured at exactly
    // `size * devicePixelRatio` and is drawn back into exactly `size` at
    // the same ratio — so there is nothing to resample and
    // `FilterQuality.none` is both the fastest and the SHARPEST choice.
    // Anything else would soften a panel full of small text for no gain.
    context.canvas.drawImageRect(
      image,
      Offset.zero & sourceSize,
      offset & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// Paints the child into a detached layer and takes its picture. The
  /// routine is the SDK's (`SnapshotWidget._paintAndDetachToImage`) —
  /// this is not the place to invent one.
  ui.Image? _captureChild() {
    final offsetLayer = OffsetLayer();
    final context = PaintingContext(offsetLayer, Offset.zero & size);
    super.paint(context, Offset.zero);
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    if (!offsetLayer.supportsRasterization()) {
      offsetLayer.dispose();
      return null;
    }
    final image = offsetLayer.toImageSync(
      Offset.zero & size,
      pixelRatio: _devicePixelRatio,
    );
    offsetLayer.dispose();
    return image;
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

  bool _childHasRepaintBoundary() {
    final start = child;
    if (start == null) {
      return false;
    }
    if (start.isRepaintBoundary) {
      return true;
    }
    var found = false;
    void walk(RenderObject node) {
      if (found) {
        return;
      }
      node.visitChildren((RenderObject descendant) {
        if (found) {
          return;
        }
        if (descendant.isRepaintBoundary) {
          found = true;
          return;
        }
        walk(descendant);
      });
    }

    walk(start);
    return found;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', debugLabel));
    properties.add(FlagProperty('enabled', value: _enabled, ifFalse: 'disabled'));
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
