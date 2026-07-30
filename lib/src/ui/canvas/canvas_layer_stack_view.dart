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
import '../dev_profile.dart';
import '../playback/layer_frame_image_cache.dart';
import 'bitmap_surface_painter.dart';
import 'composite_effect_paint.dart';
import 'layer_pose_paint.dart';
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
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  /// The active row's effective opacity (the interactive view used to
  /// apply this itself, through the panel's content-opacity wrap).
  final double opacity;
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
    this.paintPaper = false,
    this.paperBackground = ProjectBackground.defaultBackground,
  });

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

  @override
  void dispose() {
    for (final entry in _images.values) {
      entry.clone.dispose();
    }
    _images.clear();
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
        _images.remove(key)!.clone.dispose();
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
        held?.clone.dispose();
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
              held.clone.dispose();
              _images.remove(layer.frameKey);
              changed = true;
            }
            continue;
          }
          if (held == null || !identical(held.source, image.image)) {
            held?.clone.dispose();
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
            _images.remove(key)!.clone.dispose();
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
          :final pose,
          :final anchorPoint,
          :final effects,
        ):
          if (widget.activeSurfacePainter == null) {
            continue;
          }
          out.add(
            _PaintActiveSurface(
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
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _LayerStackPainter(
          nodes: _resolvedTree(widget.nodes),
          activeSurfacePainter: widget.activeSurfacePainter,
          canvasSize: widget.canvasSize,
          viewport: widget.viewport,
          paintPaper: widget.paintPaper,
          paperBackground: widget.paperBackground,
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
    required this.pose,
    required this.anchorPoint,
    required this.effects,
  });

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

class _LayerStackPainter extends CustomPainter {
  _LayerStackPainter({
    required this.nodes,
    required this.activeSurfacePainter,
    required this.canvasSize,
    required this.viewport,
    required this.paintPaper,
    required this.paperBackground,
  }) : super(repaint: activeSurfacePainter);

  final List<_PaintNode> nodes;

  /// Draws the ACTIVE layer's live surface in place. Its own repaint
  /// Listenable (tile cache + stroke overlay) drives this painter too, so
  /// a stroke step still repaints without a widget rebuild.
  final BitmapSurfacePainter? activeSurfacePainter;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final bool paintPaper;
  final ProjectBackground paperBackground;

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
    if (paintPaper) {
      paintProjectPaper(canvas, canvasRect, paperBackground);
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

    void paintNodes(List<_PaintNode> list) {
      for (final node in list) {
        // Poses apply at composite time — the stack shows the same picture
        // playback composes (route parity).
        final nodePose = switch (node) {
          _PaintImage(:final pose) => pose,
          _PaintActiveSurface(:final pose) => pose,
          _PaintGroup() => null,
        };
        final nodeAnchor = switch (node) {
          _PaintImage(:final anchorPoint) => anchorPoint,
          _PaintActiveSurface(:final anchorPoint) => anchorPoint,
          _PaintGroup() => null,
        };
        if (nodePose != null) {
          canvas.save();
          applyLayerPoseTransform(
            canvas,
            nodePose,
            canvasSize,
            anchorPoint: nodeAnchor,
          );
        }
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
            paintNodes(children);
            canvas.restore();
          case _PaintActiveSurface(:final effects):
            // The live surface, drawn by the SAME painter the standalone
            // interactive view uses — the canvas is already
            // viewport-transformed, so only the content body runs.
            //
            // R6: the row's own effects need a buffer here, because the
            // surface painter draws MANY tiles and a filter must see the
            // assembled picture (a per-tile blur would show seams).
            final activeEffects = resolveCompositeEffectPaint(effects);
            if (activeEffects.isNotEmpty) {
              final activePaint = Paint();
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
            canvas.restore();
            if (activeEffects.isNotEmpty) {
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
            final paint = Paint()
              ..filterQuality = FilterQuality.low
              ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
              // R26 #30: the layer blend applies at composite time — the
              // stack shows the same picture playback composes.
              ..blendMode = blendMode.paintBlendMode;
            // Onion-skin Colors mode: the ghost CONVERTS fully to the tint
            // — every drawn pixel takes the tint's RGB, only alpha
            // survives (TVPaint's look, R11-①; modulate kept light artwork
            // un-tinted). The paint alpha above still fades the whole
            // ghost.
            if (tint != null) {
              paint.colorFilter = ColorFilter.mode(
                Color(tint),
                BlendMode.srcIn,
              );
            }
            // R6: the row's effects filter its own picture. Ghosts resolve
            // to no effects at all, which is what keeps them from fighting
            // the tint above for this paint's colorFilter slot.
            resolveCompositeEffectPaint(effects).applyTo(paint);
            // Dest = the image's WORLD rect: the canvas rect for plain
            // cels (legacy path, unchanged bytes), grown for pasteboard
            // content so off-canvas artwork of non-active layers shows at
            // its position.
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
              worldRect,
              paint,
            );
        }
        if (nodePose != null) {
          canvas.restore();
        }
      }
    }

    paintNodes(nodes);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LayerStackPainter oldDelegate) {
    return oldDelegate.canvasSize != canvasSize ||
        oldDelegate.viewport != viewport ||
        oldDelegate.paintPaper != paintPaper ||
        !identical(
          oldDelegate.activeSurfacePainter,
          activeSurfacePainter,
        ) ||
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
          if (x.pose != y.pose ||
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
        default:
          return false;
      }
    }
    return true;
  }
}
