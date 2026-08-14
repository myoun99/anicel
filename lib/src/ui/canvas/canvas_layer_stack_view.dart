import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/collection_equality.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../debug/input_inspector.dart';
import '../dev_profile.dart';
import '../playback/layer_frame_image_cache.dart';
import 'bitmap_surface_painter.dart';
import 'composite_effect_paint.dart';
import 'display_resample.dart';
import 'selection_float_overlay.dart';
import 'static_composite_bake.dart';
import 'layer_image_draw.dart';
import 'paper_background.dart';
import 'viewport_canvas_transform.dart';

/// One node of the editing canvas's composite tree.
///
/// The stack used to be two FLAT lists — below the active layer and above
/// it — painted by two sibling widgets with the interactive view between
/// them. A folder's group buffer is one `saveLayer`, and a saveLayer
/// cannot span three sibling painters, so drawing inside a blended folder
/// could never match playback. The tree (with the ACTIVE layer as a node
/// of its own, [CanvasActiveLayerNode]) is what lets one painter close the
/// buffer it opened.
sealed class CanvasLayerStackNode {
  const CanvasLayerStackNode();
}

/// A cached layer image.
final class CanvasLayerImageNode extends CanvasLayerStackNode {
  const CanvasLayerImageNode(this.request);

  final CanvasLayerImageRequest request;
}

/// The ACTIVE layer's live surface — the one the brush is drawing into.
/// The painter delegates to the surface painter here, in place, so the
/// stroke lands inside whatever group buffer encloses it.
final class CanvasActiveLayerNode extends CanvasLayerStackNode {
  const CanvasActiveLayerNode({
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  /// The active row's effective opacity (the interactive view used to
  /// apply this itself, through the panel's content-opacity wrap).
  final double opacity;

  /// The active row's composite blend — the SAME field its cached twin
  /// [CanvasLayerImageRequest.blendMode] carries, because being the row you
  /// are drawing on is not a reason to composite differently.
  ///
  /// 🚨It was missing entirely until now, which is ㊱'s shape one field over:
  /// the value never reached the painter because there was nowhere to put
  /// it, so a multiply row went back to srcOver the moment you stood on it
  /// and the editing canvas disagreed with playback about the same frame.
  final LayerBlendMode blendMode;

  final TransformPose? pose;
  final CanvasPoint? anchorPoint;

  /// The active row's effect chain (R6) — the layer you are DRAWING on
  /// shows its own effects, so a stroke lands in the picture you can see.
  /// A blur wraps the live surface in its own buffer for exactly as long as
  /// the effect is there.
  final List<ResolvedLayerEffect> effects;
}

/// A FOLDER's group buffer: [children] compose into one buffer, then the
/// folder's opacity/blend land on it once (R27 #29).
final class CanvasLayerGroupNode extends CanvasLayerStackNode {
  const CanvasLayerGroupNode({
    required this.children,
    required this.opacity,
    required this.blendMode,
    this.effects = const [],
  });

  final List<CanvasLayerStackNode> children;
  final double opacity;
  final LayerBlendMode blendMode;

  /// The folder's effect chain (R6), applied once to the group buffer.
  final List<ResolvedLayerEffect> effects;
}

/// An ADJUSTMENT row's SCOPE (R6b): [children] compose into one buffer and
/// the row's [effects] filter it there — so a stroke drawn on a layer below
/// an adjustment reads through the grade while you draw it.
final class CanvasLayerAdjustmentNode extends CanvasLayerStackNode {
  const CanvasLayerAdjustmentNode({
    required this.children,
    required this.effects,
    required this.mix,
  });

  final List<CanvasLayerStackNode> children;
  final List<ResolvedLayerEffect> effects;

  /// The effect MIX (the row's opacity), 0…1.
  final double mix;
}

/// One non-active layer to composite around the interactive canvas.
class CanvasLayerImageRequest {
  const CanvasLayerImageRequest({
    required this.frameKey,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.tint,
    this.effects = const [],
  });

  final BrushFrameKey frameKey;

  /// EFFECTIVE opacity (static × animated Opacity sample).
  final double opacity;

  /// The layer's composite blend (R26 #30) — the editing stack paints it
  /// exactly like the composite routes.
  final LayerBlendMode blendMode;

  /// The layer's transform at the shown frame; null = identity. The stack
  /// paints it exactly like the composite routes — the ACTIVE layer shows
  /// its pose too, through the interactive view's draw-through wrap.
  final TransformPose? pose;

  /// The pose's anchor point; null = canvas center.
  final CanvasPoint? anchorPoint;

  /// ARGB tint MULTIPLIED over the artwork's colors (onion-skin Colors
  /// mode); null paints the artwork as-is.
  final int? tint;

  /// The row's effect chain (R6). Onion GHOSTS deliberately carry none:
  /// they are editing scaffolding, and the Colors-mode tint already owns
  /// this paint's colorFilter slot.
  final List<ResolvedLayerEffect> effects;
}

/// Paints the editing canvas's whole composite tree from the layer-frame
/// image cache, under the panel viewport transform — the ACTIVE layer
/// included, drawn in place through [activeSurfacePainter].
///
/// This is what makes the layers visible while editing, and (since the
/// merge) what lets a folder's group buffer wrap the layer you are drawing
/// on: one painter opens the `saveLayer` and closes it.
/// Paint-only: input always passes through to the canvas below.
class CanvasLayerStackView extends StatefulWidget {
  const CanvasLayerStackView({
    super.key,
    required this.nodes,
    required this.imageCache,
    required this.canvasSize,
    required this.viewport,
    this.activeSurfacePainter,
    this.floatOverlay,
    this.paintPaper = false,
    this.paperBackground = ProjectBackground.defaultBackground,
    this.debugDisableBake = false,
    this.debugDisableSingleBuffer = false,
  });

  /// 🚨(v) 2단계 — turns the single composite buffer OFF, so a test can
  /// render the SAME tree both ways and compare the pixels.
  ///
  /// ⚠️The comparison is only an identity at 1:1. That is not a weakness of
  /// the test, it is the change: above and below 100% the buffer resamples
  /// ONCE where the direct walk resampled every layer separately, and the
  /// pixels are supposed to differ there. So parity pins the composite —
  /// order, blending, paper, pasteboard — and a separate test pins the
  /// sampling law.
  @visibleForTesting
  final bool debugDisableSingleBuffer;

  /// 🚨(v) — turns the static bake OFF so a test can render the SAME tree
  /// both ways and compare the pixels.
  ///
  /// ★That comparison is the only contract worth having here: an
  /// optimisation is allowed to be faster, never to draw something else.
  /// It is a field rather than a global so the two renders can sit in one
  /// test, side by side, with nothing global to reset between them.
  @visibleForTesting
  final bool debugDisableBake;

  /// The selection's floating pixels (TS1), drawn in the active layer's slot
  /// so the rows above it occlude them. Null = nothing to draw there.
  final SelectionFloatOverlay? floatOverlay;

  /// The composite tree, bottom → top.
  final List<CanvasLayerStackNode> nodes;

  /// Draws the ACTIVE layer's live surface wherever a
  /// [CanvasActiveLayerNode] sits in [nodes]; null paints nothing there
  /// (hosts that still mount their own interactive view).
  final BitmapSurfacePainter? activeSurfacePainter;

  /// Every cached-image request under [nodes], depth-first bottom → top.
  Iterable<CanvasLayerImageRequest> get layers sync* {
    Iterable<CanvasLayerImageRequest> walk(
      List<CanvasLayerStackNode> list,
    ) sync* {
      for (final node in list) {
        switch (node) {
          case CanvasLayerImageNode(:final request):
            yield request;
          case CanvasLayerGroupNode(:final children):
            yield* walk(children);
          case CanvasLayerAdjustmentNode(:final children):
            yield* walk(children);
          case CanvasActiveLayerNode():
            break;
        }
      }
    }

    yield* walk(nodes);
  }

  final LayerFrameImageCache imageCache;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  /// The below-stack paints the paper so the interactive view can skip its
  /// own opaque background.
  final bool paintPaper;

  /// The project background the paper paints with (R10-⑥) — solid color
  /// or the transparent checkerboard.
  final ProjectBackground paperBackground;

  @override
  State<CanvasLayerStackView> createState() => _CanvasLayerStackViewState();
}

class _CanvasLayerStackViewState extends State<CanvasLayerStackView> {
  /// Cache image identity → our clone (+ the canvas-space rect the image
  /// covers — grown past the canvas when the cel has pasteboard tiles).
  /// Clones survive cache eviction (the cache may dispose its image at any
  /// time; a clone shares pixels with an independent lifetime).
  final Map<BrushFrameKey, ({ui.Image source, ui.Image clone, Rect worldRect})>
  _images = {};
  bool _preparing = false;
  bool _rerunRequested = false;

  @override
  void initState() {
    super.initState();
    _syncImagesWithCache();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant CanvasLayerStackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncImagesWithCache();
    _ensureImages();
  }

  /// 🚨(v) — the recording of everything a stroke cannot change.
  final StaticCompositeBake _bake = StaticCompositeBake();

  /// 🚨★★★ Bumped at EVERY `_images` mutation, and read into the bake's key.
  ///
  /// ⛔This is not belt-and-braces on top of the tree comparison. A recorded
  /// picture holds references to the `ui.Image` clones below, and those get
  /// `dispose()`d right here — replaying a picture after that is a dead
  /// handle. The tree comparison happens on the PAINTER's schedule and the
  /// dispose happens on the STATE's, so the two run at different moments;
  /// tying invalidation to the dispose ITSELF is what makes the window
  /// impossible rather than merely unlikely.
  int _imagesRevision = 0;

  void _dropImage(({ui.Image source, ui.Image clone, Rect worldRect}) held) {
    held.clone.dispose();
    _imagesRevision += 1;
  }

  @override
  void dispose() {
    for (final entry in _images.values) {
      entry.clone.dispose();
    }
    _images.clear();
    _bake.dispose();
    super.dispose();
  }

  /// Synchronous sweep BEFORE this frame's build: adopt every requested
  /// layer whose image is already valid in the cache and drop layers that
  /// left the request set.
  ///
  /// This is what keeps a layer switch flicker-free — the just-deactivated
  /// layer arrives here with a warm cache image (the prerender re-warms it
  /// after every stroke), and the async pass alone would paint it one frame
  /// late at best: the artwork visibly vanished and reappeared. The
  /// just-activated layer leaves the same frame, so it never double-draws
  /// under the interactive view.
  void _syncImagesWithCache() {
    labProbe('layerStackSyncSweep(${widget.layers.length})', _syncSweepBody);
  }

  void _syncSweepBody() {
    final wanted = <BrushFrameKey>{
      for (final layer in widget.layers) layer.frameKey,
    };
    for (final key in _images.keys.toList()) {
      if (!wanted.contains(key)) {
        _dropImage(_images.remove(key)!);
      }
    }
    for (final layer in widget.layers) {
      // Valid cache image, or a synchronous per-tile compose (the just-
      // deactivated layer's on-screen tiles are already decoded) — either
      // way the artwork paints THIS frame; only true cold misses fall to
      // the async pass.
      final image = widget.imageCache.prepareSyncOrNull(
        key: layer.frameKey,
        canvasSize: widget.canvasSize,
        quality: PlaybackQuality.full,
      );
      if (image == null) {
        continue;
      }
      final held = _images[layer.frameKey];
      if (held == null || !identical(held.source, image.image)) {
        if (held != null) _dropImage(held);
        _images[layer.frameKey] = (
          source: image.image,
          clone: image.image.clone(),
          worldRect: image.worldRect,
        );
      }
    }
  }

  Future<void> _ensureImages() async {
    if (_preparing) {
      // A rebuild changed the request set mid-flight; run once more after
      // the current pass so the stack converges on the latest layers.
      _rerunRequested = true;
      return;
    }
    _preparing = true;
    try {
      do {
        _rerunRequested = false;
        var changed = false;
        final wanted = <BrushFrameKey>{};
        for (final layer in List.of(widget.layers)) {
          wanted.add(layer.frameKey);
          final image = await widget.imageCache.prepare(
            key: layer.frameKey,
            canvasSize: widget.canvasSize,
            quality: PlaybackQuality.full,
          );
          if (!mounted) {
            return;
          }
          final held = _images[layer.frameKey];
          if (image == null) {
            if (held != null) {
              _dropImage(held);
              _images.remove(layer.frameKey);
              changed = true;
            }
            continue;
          }
          if (held == null || !identical(held.source, image.image)) {
            if (held != null) _dropImage(held);
            _images[layer.frameKey] = (
              source: image.image,
              clone: image.image.clone(),
              worldRect: image.worldRect,
            );
            changed = true;
          }
        }
        for (final key in _images.keys.toList()) {
          if (!wanted.contains(key)) {
            _dropImage(_images.remove(key)!);
            changed = true;
          }
        }
        if (changed && mounted) {
          setState(() {});
        }
      } while (_rerunRequested && mounted);
    } finally {
      _preparing = false;
    }
  }

  /// The tree with each image request replaced by the clone we hold —
  /// requests whose image is not ready yet simply drop out, and a group
  /// left empty by that drops with them (an empty buffer is a wasted
  /// saveLayer).
  List<_PaintNode> _resolvedTree(List<CanvasLayerStackNode> nodes) {
    final out = <_PaintNode>[];
    for (final node in nodes) {
      switch (node) {
        case CanvasLayerImageNode(:final request):
          final held = _images[request.frameKey];
          if (held == null) {
            continue;
          }
          out.add(
            _PaintImage(
              image: held.clone,
              worldRect: held.worldRect,
              opacity: request.opacity,
              blendMode: request.blendMode,
              pose: request.pose,
              anchorPoint: request.anchorPoint,
              tint: request.tint,
              effects: request.effects,
            ),
          );
        case CanvasActiveLayerNode(
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
          :final effects,
        ):
          if (widget.activeSurfacePainter == null) {
            continue;
          }
          out.add(
            _PaintActiveSurface(
              opacity: opacity,
              blendMode: blendMode,
              pose: pose,
              anchorPoint: anchorPoint,
              effects: effects,
            ),
          );
        case CanvasLayerGroupNode(
          :final children,
          :final opacity,
          :final blendMode,
          :final effects,
        ):
          final mapped = _resolvedTree(children);
          if (mapped.isEmpty) {
            continue;
          }
          out.add(
            _PaintGroup(
              children: mapped,
              opacity: opacity,
              blendMode: blendMode,
              effects: effects,
            ),
          );
        case CanvasLayerAdjustmentNode(
          :final children,
          :final effects,
          :final mix,
        ):
          final mapped = _resolvedTree(children);
          if (mapped.isEmpty) {
            continue;
          }
          out.add(
            _PaintAdjustment(children: mapped, effects: effects, mix: mix),
          );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _resolvedTree(widget.nodes);
    // 🚨(v) — the recordings survive only while everything they were
    // recorded against holds still.
    //
    // ⛔The set is deliberately the SAME one `shouldRepaint` compares, plus
    // [_imagesRevision]. Anything compared there and left out here is a slot
    // that keeps replaying after the thing it drew has changed — a stale
    // frame nobody can trace back to a cache, which is the failure mode
    // [[stale-tile-flicker-program]] is a whole file about.
    //
    // The ACTIVE surface is absent on purpose: a stroke step changes its
    // pixels and nothing else, and its pixels are the one thing never
    // recorded. That absence IS the optimisation.
    _bake.keepFor(
      Object.hash(
        _imagesRevision,
        widget.canvasSize,
        widget.viewport,
        widget.paintPaper,
        widget.paperBackground,
        _LayerStackPainter.treeSignature(nodes),
      ),
    );
    return IgnorePointer(
      child: CustomPaint(
        painter: _LayerStackPainter(
          nodes: nodes,
          activeSurfacePainter: widget.activeSurfacePainter,
          floatOverlay: widget.floatOverlay,
          canvasSize: widget.canvasSize,
          viewport: widget.viewport,
          paintPaper: widget.paintPaper,
          paperBackground: widget.paperBackground,
          bake: widget.debugDisableBake ? null : _bake,
          debugDisableSingleBuffer: widget.debugDisableSingleBuffer,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The painter's own node shape: the request tree with images resolved.
sealed class _PaintNode {
  const _PaintNode();
}

final class _PaintImage extends _PaintNode {
  const _PaintImage({
    required this.image,
    required this.worldRect,
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.tint,
    required this.effects,
  });

  final ui.Image image;
  final Rect worldRect;
  final double opacity;
  final LayerBlendMode blendMode;
  final TransformPose? pose;
  final CanvasPoint? anchorPoint;
  final int? tint;
  final List<ResolvedLayerEffect> effects;
}

final class _PaintActiveSurface extends _PaintNode {
  const _PaintActiveSurface({
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.effects,
  });

  /// ㊱: the active row's display opacity. It reached the node all along and
  /// stopped here — the field did not exist, so the live surface drew at full
  /// strength while every OTHER row honoured its slider.
  final double opacity;

  /// The same story as [opacity], one field over and one round later: the
  /// blend had no field on the node either, so it could not stop here — it
  /// never started. See [CanvasActiveLayerNode.blendMode].
  final LayerBlendMode blendMode;

  final TransformPose? pose;
  final CanvasPoint? anchorPoint;
  final List<ResolvedLayerEffect> effects;
}

final class _PaintGroup extends _PaintNode {
  const _PaintGroup({
    required this.children,
    required this.opacity,
    required this.blendMode,
    required this.effects,
  });

  final List<_PaintNode> children;
  final double opacity;
  final LayerBlendMode blendMode;
  final List<ResolvedLayerEffect> effects;
}

final class _PaintAdjustment extends _PaintNode {
  const _PaintAdjustment({
    required this.children,
    required this.effects,
    required this.mix,
  });

  final List<_PaintNode> children;
  final List<ResolvedLayerEffect> effects;
  final double mix;
}

/// One composited canvas-resolution raster and where it belongs.
///
/// [rect] is in canvas space and is whole-pixel aligned, so the src/dst pair
/// of the final `drawImageRect` is exact: the ONE resample the display is
/// entitled to happens in the viewport transform and nowhere else.
class _DisplayBuffer {
  const _DisplayBuffer({
    required this.image,
    required this.rect,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final ui.Image image;
  final Rect rect;
  final double pixelWidth;
  final double pixelHeight;
}

class _LayerStackPainter extends CustomPainter {
  _LayerStackPainter({
    required this.nodes,
    required this.activeSurfacePainter,
    required this.floatOverlay,
    required this.canvasSize,
    required this.viewport,
    required this.paintPaper,
    required this.paperBackground,
    this.bake,
    this.debugDisableSingleBuffer = false,
  }) : super(
         repaint: floatOverlay == null
             ? activeSurfacePainter
             : Listenable.merge(<Listenable?>[
                 activeSurfacePainter,
                 floatOverlay,
               ]),
       );

  /// The last line the T12 probe in [paint] emitted. Static: a
  /// [CustomPainter] is a fresh object every frame, so an instance field
  /// would only ever compare against itself.
  static String? _lastStackProbe;

  final List<_PaintNode> nodes;

  /// 🚨(v) — the recording of everything a stroke cannot change.
  ///
  /// Owned by the STATE, not by this painter: a `CustomPainter` is a fresh
  /// object every frame, so a cache held here would be recorded and thrown
  /// away in the same breath. Null keeps the original walk.
  final StaticCompositeBake? bake;

  /// Draws the ACTIVE layer's live surface in place. Its own repaint
  /// Listenable (tile cache + stroke overlay) drives this painter too, so
  /// a stroke step still repaints without a widget rebuild.
  final BitmapSurfacePainter? activeSurfacePainter;

  /// TS1: the selection float, drawn in the active layer's slot. Merged into
  /// the repaint above for the same reason the surface painter is — a drag
  /// step has to reach the canvas without a widget rebuild.
  final SelectionFloatOverlay? floatOverlay;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final bool paintPaper;
  final ProjectBackground paperBackground;

  /// See [CanvasLayerStackView.debugDisableSingleBuffer].
  final bool debugDisableSingleBuffer;

  /// The largest buffer side worth allocating, in canvas pixels.
  ///
  /// Not a quality setting — a floor under "is this still a good idea". A
  /// viewport zoomed far out over a 5×5 pasteboard asks for a buffer many
  /// times the screen, and rasterising that to resample it back down is
  /// strictly worse than letting each layer draw itself. The direct walk is
  /// always correct, so falling back to it costs only the sampling law, and
  /// only in a view where everything is tiny anyway.
  static const int _maxBufferSide = 8192;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(canvas, viewport);

    final canvasRect = Rect.fromLTWH(
      0,
      0,
      canvasSize.width.toDouble(),
      canvasSize.height.toDouble(),
    );
    // T12 field probe, one floor DOWN from the canvas area's.
    //
    // That one measures what the WIDGET decided; this measures what the
    // paint actually did, and the difference between them is the whole
    // question: past the cut's end line the paper is gone from the screen
    // while the widget above still answers `paper=true`. Only a probe here
    // can say whether this painter ran, what it was told, and whether the
    // paper it was told to draw is even visible ink — `paintProjectPaper`
    // returns without drawing when the colour's alpha is zero, and that is
    // an answer no widget-level value can show.
    //
    // Static because a `CustomPainter` is rebuilt every frame: an instance
    // field would compare against itself and print every time. ⚠️Not behind
    // an `assert` for the reason the sibling probe carries — release builds
    // are the ones that get reported. The visibility flag is the guard.
    if (InputInspector.visible.value) {
      final probe =
          'stack paint paper=$paintPaper'
          ' alpha=${Color(paperBackground.argb).a.toStringAsFixed(2)}'
          ' nodes=${nodes.length}'
          ' rect=${canvasRect.width.round()}x${canvasRect.height.round()}';
      if (probe != _lastStackProbe) {
        _lastStackProbe = probe;
        InputInspector.note(probe);
      }
    }
    // The group buffer's bounds are a SIZE HINT to the engine: it
    // allocates an offscreen that big. The pasteboard is 5×5 canvases —
    // 25× the area — so handing it over verbatim would make every folder
    // buffer 25× more expensive than the picture it holds. Only what is
    // ON SCREEN can matter, so intersect with the visible canvas-space
    // rect (the same rect the surface painter uses to prioritise decodes).
    final visibleRect = MatrixUtils.transformRect(
      viewportInverseTransformMatrix(viewport),
      Offset.zero & size,
    );
    final pasteboardRect = Rect.fromLTRB(
      canvasSize.pasteboardLeft.toDouble(),
      canvasSize.pasteboardTop.toDouble(),
      canvasSize.pasteboardRightExclusive.toDouble(),
      canvasSize.pasteboardBottomExclusive.toDouble(),
    );
    final groupBounds = visibleRect.isEmpty
        ? pasteboardRect
        : pasteboardRect.intersect(visibleRect);

    /// 🚨(v) — the body, with WHO PAINTS THE CHILDREN left open.
    ///
    /// It was `paintNodes` recursing straight into itself. The static bake
    /// needs the same body with a different child strategy (descend into
    /// the chain enclosing the active layer, replay a recording for
    /// everything else), and copying it would have split the folder
    /// `saveLayer` rules into two versions that then drift apart. One body,
    /// two strategies.
    void paintNodesWith(
      Canvas canvas,
      List<_PaintNode> list,
      void Function(Canvas canvas, List<_PaintNode> children) paintChildren,
    ) {
      for (final node in list) {
        // Poses apply at composite time — the stack shows the same picture
        // playback composes (route parity).
        final nodePose = switch (node) {
          _PaintImage(:final pose) => pose,
          _PaintActiveSurface(:final pose) => pose,
          _PaintGroup() || _PaintAdjustment() => null,
        };
        final nodeAnchor = switch (node) {
          _PaintImage(:final anchorPoint) => anchorPoint,
          _PaintActiveSurface(:final anchorPoint) => anchorPoint,
          _PaintGroup() || _PaintAdjustment() => null,
        };
        // The wrap straddles the live-surface node too, which HAS a pose
        // and no image — that is why the pose and the draw are separate
        // helpers rather than one.
        withLayerPose(
          canvas,
          pose: nodePose,
          canvasSize: canvasSize,
          anchorPoint: nodeAnchor,
          body: () {
            switch (node) {
              case _PaintGroup(
                :final children,
                :final opacity,
                :final blendMode,
                :final effects,
              ):
                // R27 #29: one buffer for the group, one blend on it — and
                // because the ACTIVE layer is a node in here, a stroke drawn
                // inside a blended folder finally reads the way it will play
                // back. R6: the folder's effect chain lands on the same buffer.
                final groupEffects = resolveCompositeEffectPaint(effects);
                final groupPaint = Paint()
                  ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
                  ..blendMode = blendMode.paintBlendMode;
                groupEffects.applyTo(groupPaint);
                canvas.saveLayer(
                  // The size hint grows by the blur's spread, so artwork just
                  // OUTSIDE the visible rect still bleeds in — without this the
                  // blur at the screen edge would change as you scroll.
                  effectBufferBounds(groupBounds, groupEffects),
                  groupPaint,
                );
                paintChildren(canvas, children);
                canvas.restore();
              case _PaintAdjustment(
                :final children,
                :final effects,
                :final mix,
              ):
                // R6b: the scope into one buffer, the row's chain onto it —
                // which is what lets a stroke drawn UNDER an adjustment read
                // through the grade while you draw it.
                final pass = resolveAdjustmentScopePass(
                  bounds: groupBounds,
                  effects: effects,
                  mix: mix,
                );
                if (pass.crossfades) {
                  canvas.saveLayer(
                    pass.bufferBounds,
                    pass.crossfadeLayerPaint!,
                  );
                  canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
                  paintChildren(canvas, children);
                  canvas.restore();
                }
                canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
                paintChildren(canvas, children);
                canvas.restore();
                if (pass.crossfades) {
                  canvas.restore();
                }
              case _PaintActiveSurface(
                :final opacity,
                :final blendMode,
                :final effects,
              ):
                // The live surface, drawn by the SAME painter the standalone
                // interactive view uses — the canvas is already
                // viewport-transformed, so only the content body runs.
                //
                // R6: the row's own effects need a buffer here, because the
                // surface painter draws MANY tiles and a filter must see the
                // assembled picture (a per-tile blur would show seams).
                //
                // ㊱: the OPACITY rides that same buffer — one alpha over the
                // assembled picture, exactly as a group node applies its own
                // (`Color.fromRGBO(0, 0, 0, opacity)` is an alpha-only paint).
                // The panel's content-opacity wrap cannot do this job in
                // merged mode: there the interactive view is input-only, so
                // the wrap dims a widget that paints nothing and the layer
                // you are drawing on stayed at full strength.
                //
                // The BLEND rides the same buffer for a reason of its own: the
                // surface painter draws many separate tiles, and a non-srcOver
                // blend applied per tile would compose each tile against the
                // rows below it independently — overlapping coverage inside one
                // row would then darken at the seams. One buffer, one blend, is
                // the same answer [_PaintGroup] already gives for a folder.
                final activeEffects = resolveCompositeEffectPaint(effects);
                final activeAlpha = opacity.clamp(0.0, 1.0).toDouble();
                final activeBlend = blendMode.paintBlendMode;
                final needsBuffer =
                    activeEffects.isNotEmpty ||
                    activeAlpha < 1 ||
                    activeBlend != BlendMode.srcOver;
                if (needsBuffer) {
                  final activePaint = Paint()
                    ..color = Color.fromRGBO(0, 0, 0, activeAlpha)
                    ..blendMode = activeBlend;
                  activeEffects.applyTo(activePaint);
                  canvas.saveLayer(
                    effectBufferBounds(
                      activeSurfacePainter!.pasteboardRect,
                      activeEffects,
                    ),
                    activePaint,
                  );
                }
                canvas.save();
                canvas.clipRect(activeSurfacePainter!.pasteboardRect);
                activeSurfacePainter!.paintContentInto(canvas);
                // 🚨TS1: the selection's FLOAT belongs here, right on top of
                // the surface it was lifted out of and UNDER everything
                // above that row. Drawn inside this slot's clip and its
                // effects/opacity buffer, because the pixels are that
                // layer's pixels — 유저 확정 A: 「프리뷰는 원래 그런거」, so a
                // half-opacity row previews a transform at half opacity,
                // which is what the commit will look like.
                //
                // ⚠️Inside the POSE wrap as well (the whole switch is). For
                // an unposed row that changes nothing; for a posed one the
                // float now travels with its layer instead of ignoring the
                // pose, but the drag delta rides through the pose matrix
                // with it — fine for translation, and worth an eye on a
                // scaled or rotated row.
                floatOverlay?.value?.paintInto(canvas);
                canvas.restore();
                if (needsBuffer) {
                  canvas.restore();
                }
              case _PaintImage(
                :final image,
                :final worldRect,
                :final opacity,
                :final blendMode,
                :final tint,
                :final effects,
              ):
                // Dest = the image's WORLD rect: the canvas rect for plain
                // cels, grown for pasteboard content so off-canvas artwork of
                // non-active layers shows at its position. The pose is already
                // applied by the wrap above, which this node shares with the
                // live surface — hence pose: null here rather than a second
                // save/restore around the same matrix.
                drawPosedLayerImage(
                  canvas,
                  image: image,
                  worldRect: worldRect,
                  canvasSize: canvasSize,
                  pose: null,
                  opacity: opacity,
                  blendMode: blendMode,
                  effects: effects,
                  // Onion-skin Colors mode: the ghost CONVERTS fully to the
                  // tint — every drawn pixel takes the tint's RGB, only alpha
                  // survives (TVPaint's look, R11-①; modulate kept light
                  // artwork un-tinted). The paint alpha still fades the whole
                  // ghost.
                  tint: tint,
                );
            }
          },
        );
      }
    }

    void paintNodes(Canvas canvas, List<_PaintNode> list) =>
        paintNodesWith(canvas, list, paintNodes);

    /// 🚨★★★ (v) 1단계 — paint the chain that ENCLOSES the active layer live,
    /// and replay a recording for everything else.
    ///
    /// ★The split axis is not "below / above". That was the flat pair this
    /// tree was built to replace: with the active layer inside a blended
    /// folder, three sibling painters could not share one `saveLayer` and
    /// the canvas disagreed with playback (see the file's own header).
    ///
    /// There is exactly ONE [_PaintActiveSurface] in the tree, so the path
    /// from the root to it is a chain of enclosing folders G1…Gn. At every
    /// level, the siblings BEFORE and AFTER the chain's child are static for
    /// the whole stroke — the stroke's pixels never pass through them — so
    /// they bake. The folders ON the chain stay live, because the stroke's
    /// pixels do go through their buffers.
    ///
    /// ⇒ 2n+2 recordings, and n is 0 or 1 in almost every project. At n=0
    /// that is precisely "one below, one above" — the naive split was not
    /// wrong, it was this rule's simplest case.
    ///
    /// ⚠️Depth identifies a level uniquely BECAUSE the chain is unique;
    /// that is what makes a bare depth a sound slot id.
    void paintSplit(Canvas canvas, List<_PaintNode> list, int depth) {
      final at = list.indexWhere(_enclosesActiveSurface);
      if (at < 0) {
        bake!.draw(canvas, 'd$depth:all', (into) => paintNodes(into, list));
        return;
      }
      if (at > 0) {
        bake!.draw(
          canvas,
          'd$depth:before',
          (into) => paintNodes(into, list.sublist(0, at)),
        );
      }
      paintNodesWith(canvas, [list[at]], (into, children) {
        paintSplit(into, children, depth + 1);
      });
      if (at < list.length - 1) {
        bake!.draw(
          canvas,
          'd$depth:after',
          (into) => paintNodes(into, list.sublist(at + 1)),
        );
      }
    }

    /// Everything this stack is, in CANVAS space: the paper and then the
    /// layers over it.
    ///
    /// Pulled out of `paint` so it can be run against the screen directly OR
    /// into a recorder. Those are the two halves of stage 2 and they must be
    /// the same body — a second copy is how "the buffer path draws something
    /// slightly different" starts.
    void paintPaperInto(Canvas into) {
      if (paintPaper) {
        paintProjectPaper(into, canvasRect, paperBackground);
      }
    }

    /// 🚨★★★ (v) 2단계 후반부 — THE BOTTOM OF THE STACK IS ONE BLIT.
    ///
    /// Stage 1 stopped the DART walk; the engine still replayed every draw
    /// in the recording, so a stroke on top of 500 layers re-executed 500
    /// draws and every folder's `saveLayer` per step. Rasterising the
    /// bottom collapses all of it to one image, and the raster is redone
    /// only when the bake key moves — which a stroke step never does.
    ///
    /// ⛔The BOTTOM only. Everything above the live surface stays a picture:
    /// a multiply up there has to blend against the stroke, and an image
    /// drawn `srcOver` cannot. Below the live surface the destination is
    /// empty, so flattening and replaying are the same picture — which is
    /// exactly what the parity suite pins.
    void paintBackdropSplit(Canvas into, Rect rect) {
      final at = nodes.indexWhere(_enclosesActiveSurface);
      if (at < 0) {
        bake!.drawRaster(into, 'd0:backdrop-all', rect, (c) {
          paintPaperInto(c);
          paintNodes(c, nodes);
        });
        return;
      }
      bake!.drawRaster(into, 'd0:backdrop', rect, (c) {
        paintPaperInto(c);
        paintNodes(c, nodes.sublist(0, at));
      });
      paintNodesWith(into, [nodes[at]], (c, children) {
        paintSplit(c, children, 1);
      });
      if (at < nodes.length - 1) {
        bake!.draw(
          into,
          'd0:after',
          (c) => paintNodes(c, nodes.sublist(at + 1)),
        );
      }
    }

    /// [rasterRect] is non-null only when this is composing the display
    /// buffer. The direct walk deliberately does NOT take the backdrop
    /// raster: it draws in screen space, so a flattened backdrop would be
    /// resampled by the CTM as one image while the rest of the stack was
    /// resampled layer by layer — a third sampling behaviour, in the
    /// fallback path, for no gain.
    void paintContent(Canvas into, {Rect? rasterRect}) {
      // ⛔No bake handed down (a host that does not own one, or a tree with
      // no live surface at all) keeps the original walk. The bake is an
      // optimisation, never a second way to be correct.
      if (bake == null || activeSurfacePainter == null) {
        paintPaperInto(into);
        paintNodes(into, nodes);
        return;
      }
      if (rasterRect != null) {
        paintBackdropSplit(into, rasterRect);
        return;
      }
      paintPaperInto(into);
      paintSplit(into, nodes, 0);
    }

    // 🚨★★★ (v) 2단계 — ONE BUFFER AT CANVAS RESOLUTION, RESAMPLED ONCE.
    //
    // Above this line every layer was drawn straight under the viewport
    // transform, so the CTM resampled each of them SEPARATELY and each one
    // brought its own `filterQuality`. That is why becoming the active
    // layer changed how a layer looked (T21): the live surface draws its
    // tiles at `none` and a cached layer image draws at `low`.
    //
    // Compositing at canvas resolution first makes the question disappear
    // rather than answering it consistently: there is exactly one image to
    // resample, so [filterQualityForDisplayScale] is the whole policy and
    // no layer is ever asked what it is.
    //
    // 📐The buffer is the VISIBLE canvas-space rect, not the pasteboard —
    // the pasteboard is 5×5 canvases and rasterising all of it would cost
    // 25× what is on screen. It is not the canvas rect either: artwork
    // parked on the pasteboard is visible and must composite with the rest
    // (유저 2026-08-15, 「페이스트보드도 룰러할때 보이게」).
    final buffer = _composeDisplayBuffer(groupBounds, paintContent);
    if (buffer == null) {
      paintContent(canvas);
    } else {
      try {
        canvas.drawImageRect(
          buffer.image,
          Offset.zero & Size(buffer.pixelWidth, buffer.pixelHeight),
          buffer.rect,
          Paint()
            ..filterQuality = filterQualityForDisplayScale(
              displayScaleOf(viewport.zoom),
            ),
        );
      } finally {
        // ⚠️Safe HERE and nowhere earlier: the draw above put the image into
        // this frame's display list, and the engine holds its own reference
        // to it from that moment. What `dispose` releases is this handle's
        // claim, not the pixels the list is going to replay.
        buffer.image.dispose();
      }
    }
    canvas.restore();
  }

  /// Rasterises [paintContent] over [bounds] at CANVAS resolution, or null
  /// when the stack should just paint itself onto the screen.
  ///
  /// Null is not a failure: an empty viewport (nothing on screen yet) and a
  /// buffer too large to be worth allocating are both cases where the
  /// direct walk is the better answer, and the direct walk is the one that
  /// was always correct.
  ///
  /// 🚨`toImageSync`, not `toImage`. The design said stage 2 needed a native
  /// surface because "Skia has no synchronous bytes-to-image path" — true,
  /// and about the wrong conversion. What this needs is DISPLAY LIST to
  /// image, which is synchronous from Dart and leaves the rasterisation
  /// deferred on the GPU. The repo already leans on that in the tile
  /// compose (`tiled_surface_compose`) and in the provisional tile pictures,
  /// where it is measured at 26-38us for a 256px tile.
  _DisplayBuffer? _composeDisplayBuffer(
    Rect bounds,
    void Function(Canvas into, {Rect? rasterRect}) paintContent,
  ) {
    if (debugDisableSingleBuffer || bounds.isEmpty) {
      return null;
    }
    // Whole pixels, and the DESTINATION is the rounded rect too — a src/dst
    // pair that disagree by a fraction of a pixel would resample the buffer
    // a second time and undo the point of having it.
    final rect = Rect.fromLTRB(
      bounds.left.floorToDouble(),
      bounds.top.floorToDouble(),
      bounds.right.ceilToDouble(),
      bounds.bottom.ceilToDouble(),
    );
    final width = rect.width.round();
    final height = rect.height.round();
    if (width <= 0 || height <= 0 || width > _maxBufferSide ||
        height > _maxBufferSide) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final into = Canvas(recorder);
    into.translate(-rect.left, -rect.top);
    paintContent(into, rasterRect: rect);
    final picture = recorder.endRecording();
    try {
      return _DisplayBuffer(
        image: picture.toImageSync(width, height),
        rect: rect,
        pixelWidth: width.toDouble(),
        pixelHeight: height.toDouble(),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Whether the live surface is this node, or anywhere inside it.
  static bool _enclosesActiveSurface(_PaintNode node) => switch (node) {
    _PaintActiveSurface() => true,
    _PaintGroup(:final children) => children.any(_enclosesActiveSurface),
    _PaintAdjustment(:final children) => children.any(_enclosesActiveSurface),
    _PaintImage() => false,
  };

  @override
  bool shouldRepaint(covariant _LayerStackPainter oldDelegate) {
    return oldDelegate.canvasSize != canvasSize ||
        oldDelegate.viewport != viewport ||
        oldDelegate.paintPaper != paintPaper ||
        // The paper's COLOR is painted here (see the `paintPaper` branch), so
        // it belongs in the gate beside the flag that turns it on. It was the
        // one value this painter drew and did not compare: changing the
        // project background left the editing canvas on its old paper until
        // something unrelated moved. `ProjectBackground` compares by argb, so
        // this costs an int compare, not an identity miss every frame — and
        // the sibling `playback_frame_painter` already gates on it.
        oldDelegate.paperBackground != paperBackground ||
        !identical(oldDelegate.activeSurfacePainter, activeSurfacePainter) ||
        !_treesMatch(oldDelegate.nodes, nodes);
  }

  static bool _treesMatch(List<_PaintNode> a, List<_PaintNode> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      final x = a[index];
      final y = b[index];
      switch ((x, y)) {
        case (_PaintImage(), _PaintImage()):
          x as _PaintImage;
          y as _PaintImage;
          if (!identical(x.image, y.image) ||
              x.worldRect != y.worldRect ||
              x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              x.pose != y.pose ||
              x.anchorPoint != y.anchorPoint ||
              x.tint != y.tint ||
              // R6: an effect edit changes the pixels and nothing else —
              // leaving it out here would repaint nothing (the whole tree
              // still "matches") and the canvas would go stale.
              !listEquals(x.effects, y.effects)) {
            return false;
          }
        case (_PaintActiveSurface(), _PaintActiveSurface()):
          x as _PaintActiveSurface;
          y as _PaintActiveSurface;
          // ㊱: the alpha belongs in the repaint gate too — a slider drag
          // changes NOTHING else about this node, so leaving it out would
          // paint the new value only when some unrelated fact moved (the
          // ㉘/㉞ shape: the value is right and the gate says "unchanged").
          if (x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              x.pose != y.pose ||
              x.anchorPoint != y.anchorPoint ||
              !listEquals(x.effects, y.effects)) {
            return false;
          }
        case (_PaintGroup(), _PaintGroup()):
          x as _PaintGroup;
          y as _PaintGroup;
          if (x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              !listEquals(x.effects, y.effects) ||
              !_treesMatch(x.children, y.children)) {
            return false;
          }
        case (_PaintAdjustment(), _PaintAdjustment()):
          x as _PaintAdjustment;
          y as _PaintAdjustment;
          // A new variant that falls to the default arm below would make
          // shouldRepaint answer true on EVERY frame the node is present —
          // a silent perf regression with no compile error. R6b's arm.
          if (x.mix != y.mix ||
              !listEquals(x.effects, y.effects) ||
              !_treesMatch(x.children, y.children)) {
            return false;
          }
        default:
          return false;
      }
    }
    return true;
  }

  /// 🚨(v) — [_treesMatch] as a VALUE, for the bake's key.
  ///
  /// ⛔It must fold in exactly what [_treesMatch] compares, and it lives
  /// here rather than beside the cache so the two are read together: a
  /// field added to a node and to `_treesMatch` but not to this one makes
  /// the recordings outlive the change they should have ended. The
  /// `default:` arm below is the same tripwire the comparison's is.
  ///
  /// ⚠️Images fold in by IDENTITY (`identityHashCode`), matching
  /// `identical()` above — two different decodes of the same artwork are
  /// two different pictures to draw.
  static int treeSignature(List<_PaintNode> list) {
    var hash = list.length;
    for (final node in list) {
      hash = Object.hash(hash, switch (node) {
        _PaintImage(
          :final image,
          :final worldRect,
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
          :final tint,
          :final effects,
        ) =>
          Object.hash(
            identityHashCode(image),
            worldRect,
            opacity,
            blendMode,
            pose,
            anchorPoint,
            tint,
            Object.hashAll(effects),
          ),
        _PaintActiveSurface(
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
          :final effects,
        ) =>
          Object.hash(
            opacity,
            blendMode,
            pose,
            anchorPoint,
            Object.hashAll(effects),
          ),
        _PaintGroup(
          :final opacity,
          :final blendMode,
          :final effects,
          :final children,
        ) =>
          Object.hash(
            opacity,
            blendMode,
            Object.hashAll(effects),
            treeSignature(children),
          ),
        _PaintAdjustment(:final mix, :final effects, :final children) =>
          Object.hash(mix, Object.hashAll(effects), treeSignature(children)),
      });
    }
    return hash;
  }
}
