import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/movie_cel.dart';
import '../../models/timeline_coverage.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../text/se_name_tag_paint.dart';
import '../../services/playback/playback_frame_mapping.dart'
    show
        TrackStackContribution,
        TransitionContribution,
        resolveTrackStackContributions,
        resolveTransitionContributions,
        sourceOverWeights,
        trackGroupSourceOverWeights;
import '../camera/camera_frame_render_service.dart';
import '../../services/composite_effect_paint.dart'
    show alphaOnly, resolveCompositeEffectPlan;
import '../canvas/subtree_image_composite.dart' show steppedForChain;
import '../editor_session_manager.dart';
import '../playback/playback_frame_painter.dart';
import '../track_effect_paint_policy.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'export_cel_group_plan.dart';
import 'export_plan.dart';
import 'offscreen_raster.dart';

/// Renders export output at full quality straight from the brush store, so
/// exports never depend on the playback quality setting or its caches.
///
/// Surfaces are cached per cut and retained per FRAME's covering set: a
/// single-cut stream holds one cut's cels at a time (as before), and the
/// stack bake (R3a) holds one cut per covering track while streaming.
class ExportFrameRenderer {
  ExportFrameRenderer({
    required this.session,
    CameraFrameRenderService? renderService,
    this.applyLayerFx = true,
    ui.Color background = const ui.Color(0xFFFFFFFF),
  }) : renderService =
           renderService ?? CameraFrameRenderService(background: background);

  final EditorSessionManager session;
  final CameraFrameRenderService renderService;

  /// The export dialog's 'Apply layer FX' toggle: true (default) exports
  /// WYSIWYG with playback (per-layer fx switches respected); false
  /// bypasses EVERY layer's FX — raw cels at their static opacity, no
  /// transforms. The cut fade and the camera work are cut-level and stay.
  final bool applyLayerFx;

  /// Cel surfaces per cut. Single-cut streams retain exactly one cut, as
  /// before; the STACK bake (R3a) interleaves every covering track's cut
  /// within one frame, so retention follows the frame's covering SET —
  /// "the last cut seen" would thrash the whole store per frame.
  final Map<CutId, Map<(LayerId, FrameId), BitmapSurface?>> _surfacesByCut =
      {};

  BitmapSurface? _surfaceFor(Cut cut, Layer layer, Frame frame) {
    // 🚨A MOVIE's pictures are read through, never held here: a stream
    // holds its cut's surfaces for the whole run, and a movie is a
    // full-canvas picture per FRAME — a 30-second take would pin every one
    // of them past the store's byte budget. The store keeps what its budget
    // allows; [_hydrate] puts back what a frame needs.
    if (movieCelOf(frame.id) != null) {
      return _readSurface(cut, layer, frame);
    }
    final surfaces = _surfacesByCut.putIfAbsent(cut.id, () => {});
    return surfaces.putIfAbsent(
      (layer.id, frame.id),
      () => _readSurface(cut, layer, frame),
    );
  }

  BitmapSurface? _readSurface(Cut cut, Layer layer, Frame frame) {
    final frameKey = session.brushFrameKeyForCut(cut, layer.id, frame.id);
    // R19 P3b: the baked raster is the truth — a READ-ONLY reference
    // (valid display cache first, else baked; the coordinator donates
    // on every commit, undo and redo). Nothing is stored back, so
    // batch exports don't grow the shared cache; null = an empty cel.
    return session.renderCaches.brushFrameStore.currentSurfaceWithoutReplay(
      frameKey,
      canvasSize: cut.canvasSize,
    );
  }

  /// How many surfaces the renderer holds right now (test hook) — a movie's
  /// pictures are never among them.
  @visibleForTesting
  int get debugHeldSurfaceCount {
    var held = 0;
    for (final surfaces in _surfacesByCut.values) {
      for (final surface in surfaces.values) {
        if (surface != null) {
          held += 1;
        }
      }
    }
    return held;
  }

  /// Decodes the movie pictures [cut] shows at [frameIndex] before its
  /// composite is planned: export walks frames nobody is looking at, so
  /// nothing else will have (the playback warmer awaits the same call).
  Future<void> _hydrate(Cut cut, int frameIndex) =>
      session.movieCels.hydrate(cut, frameIndex);

  /// Cuts whose FX-stripped view has already been built (memoized: the
  /// stream renders the same cut for many frames).
  final Map<CutId, Cut> _fxStrippedByCut = {};

  /// The cut as this RENDER should see it. With [applyLayerFx] on — the
  /// default, and what the video/PNG paths use — that is the cut itself, so
  /// the render is WYSIWYG with playback down to the rows' own fx switches.
  ///
  /// With it OFF (the cel exports: "cels stay raw artwork") every row's
  /// transform switch and every effect's switch read false, which is the
  /// master toggle expressed as DATA. Cheaper to reason about than an
  /// override threaded through the plan, and impossible for another route
  /// to forget: the plan renders exactly the cut it is given.
  Cut _cutForRender(Cut cut) {
    if (applyLayerFx) {
      return cut;
    }
    return _fxStrippedByCut.putIfAbsent(
      cut.id,
      () => cut.copyWith(
        layers: [
          for (final layer in cut.layers)
            layer.copyWith(
              transformEnabled: false,
              effects: [
                for (final effect in layer.effects) effect.copyWith(enabled: false),
              ],
            ),
        ],
      ),
    );
  }

  void _retainSurfacesFor(Iterable<CutId> cutIds) {
    final keep = cutIds.toSet();
    _surfacesByCut.removeWhere((cutId, _) => !keep.contains(cutId));
  }

  /// Holds the cels of every cut about to be drawn and returns each
  /// contribution's UNIT ALPHA: its own share of the frame times its
  /// track's static opacity and fade.
  ///
  /// ⚠️Both bakes below need exactly this before they can weigh anything,
  /// and they weigh it differently afterwards ([sourceOverWeights] within
  /// one canvas, [trackGroupSourceOverWeights] across tracks). The half
  /// they share is here; the half they don't stays at the call site.
  List<double> _retainAndUnitAlphas(
    List<({Cut cut, double opacity})> contributions, {
    Iterable<CutId> alsoRetain = const [],
  }) {
    _retainSurfacesFor([
      ...alsoRetain,
      for (final contribution in contributions) contribution.cut.id,
    ]);
    return [
      for (final contribution in contributions)
        contribution.opacity *
            session.opacityVerbs.trackStaticOpacityForCut(contribution.cut.id),
    ];
  }

  /// Canvas-space composites for the stack bake: TRANSPARENT backing, so
  /// an upper track's frame never blanks the tracks below — the paper
  /// belongs to the bottom covered track and the assembler paints it.
  static const CameraFrameRenderService _stackRenderService =
      CameraFrameRenderService(background: ui.Color(0x00000000));

  /// The multi-track layout, built once per export run (the project is
  /// frozen while a run streams).
  List<StoryboardTimelineLayoutEntry>? _stackLayout;

  /// One composited frame. [ExportSizeMode.canvas] renders the identity
  /// camera over the cut's own canvas size (centered, zoom 1, no rotation),
  /// which is exactly the raw canvas at 1:1 pixels on the white paper.
  /// [outputSize] scales the same view down (storyboard thumbnails); null
  /// exports at full size.
  /// [withNameTags] draws the SE rows' on-canvas name tags over the
  /// picture (R5b) — ON for presentation renders (the アフレコ video),
  /// OFF for compositing sources: PNG sequences already stay unposed and
  /// unfaded for the same reason, and a thumbnail has no room for them.
  Future<ui.Image> renderComposite(
    ExportFrameTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
    bool withNameTags = false,
  }) async {
    final cut = task.cut;
    // The single-cut streams' retention: one cut's cels at a time.
    _retainSurfacesFor([cut.id]);
    await _hydrate(cut, task.frameIndex);
    final pose = mode == ExportSizeMode.camera
        ? session.camera.cameraPoseForCut(cut, task.frameIndex)
        : CameraPose(
            center: CanvasPoint(
              x: cut.canvasSize.width / 2,
              y: cut.canvasSize.height / 2,
            ),
          );
    return renderService.renderThroughCamera(
      // The rows' own fx switches apply here too (AE semantics: the layer
      // fx switch affects the render) — WYSIWYG with playback. They live on
      // the layers now (R8), so the dialog's 'Apply layer FX' master toggle
      // is expressed by rendering an FX-STRIPPED VIEW of the cut rather
      // than by threading an override through the plan.
      nodes: planCutFrameCompositeTree(
        cut: _cutForRender(cut),
        frameIndex: task.frameIndex,
        surfaceResolver: (layer, frame) => _surfaceFor(cut, layer, frame),
      ),
      pose: pose,
      cameraFrameSize: mode == ExportSizeMode.camera
          ? session.camera.cameraFrameSize
          : cut.canvasSize,
      outputSize: outputSize,
      overlayPass: !withNameTags
          ? null
          : (canvas) {
              final tags = session.seEntries.seNameTagsForCutFrame(cut, task.frameIndex);
              if (tags.isNotEmpty) {
                paintSeNameTags(
                  canvas,
                  tags: tags,
                  canvasSize: cut.canvasSize,
                );
              }
            },
    );
  }

  /// The BACKDROP ground (R3b) under a video frame — and nothing at all
  /// when [preserveAlpha].
  ///
  /// ⛔THE GROUND IS THE VIDEO'S FLOOR AND THE GUARD IS THE MASTER'S. An
  /// opaque codec bakes the stage's floor everywhere the picture leaves
  /// uncovered — gap frames, a posed stage sliding off, a fade thinning
  /// the stack away — while an alpha master must stay transparent. Four
  /// renders wrote the pair out, and one that forgot the guard bakes an
  /// opaque floor into a master somebody asked to keep clear.
  void _paintBackdropGround(
    ui.Canvas canvas,
    ui.Rect bounds, {
    required bool preserveAlpha,
  }) {
    final project = session.repository.requireProject();
    // A backdrop that is NONE (F-114) prints nothing, the way an alpha
    // master leaves it out: the plane is not there.
    if (preserveAlpha || project.backdropNone) {
      return;
    }
    canvas.drawRect(bounds, ui.Paint()..color = ui.Color(project.backdropArgb));
  }

  /// [renderComposite] with the cut-level pose and fade baked in for VIDEO
  /// frames — MP4 carries no alpha (yuv420p drops the channel without
  /// blending) and no display-time compositor, so both must land in the
  /// RGB values.
  ///
  /// CAMERA-frame video is the TRACK STACK now (R3a): every track covering
  /// the frame's global index composites bottom-up through the very
  /// painter playback and the parked canvas use, so the bake cannot
  /// disagree with the screen — a selected-track gap covered by another
  /// track prints that track's picture instead of the old background-only
  /// frame. The frame PLAN (and the audio pairing built from it) still
  /// walks the selected track's axis; only the pixels widen to the whole
  /// stage.
  ///
  /// CANVAS-size video keeps the single-cut bake: each cut renders in its
  /// OWN canvas space, and there is no shared space to stack differently
  /// sized canvases in (the camera frame is that space). The bake mirrors
  /// playback: the finished frame posed over the output space (V track
  /// Transform, AE precomp semantics), thinned by the fade (R3b:
  /// transparency over the backdrop, no target-color wash). PNG sequences
  /// deliberately stay unposed and unfaded (they are compositing
  /// sources).
  ///
  /// [preserveAlpha] (ProRes 4444 α): gap frames and the uncovered ground
  /// stay TRANSPARENT instead of baking an opaque backing — the fade
  /// still paints toward its target color (a fade IS opaque paint).
  Future<ui.Image> renderCompositeForVideo(
    ExportFrameTask task,
    ExportSizeMode mode, {
    bool preserveAlpha = false,
  }) async {
    if (mode == ExportSizeMode.camera) {
      return _renderTrackStackForVideo(task, preserveAlpha: preserveAlpha);
    }
    if (task.isGap) {
      // A leading-gap frame: nothing plays — the BACKDROP (R3b), exactly
      // what playback shows in the gap. Opaque codecs bake the floor; an
      // alpha master keeps the gap transparent.
      final size = mode == ExportSizeMode.camera
          ? session.camera.cameraFrameSize
          : task.cut.canvasSize;
      return rasterizeOffscreen(
        width: size.width,
        height: size.height,
        paint: (canvas) => _paintBackdropGround(
          canvas,
          ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
          preserveAlpha: preserveAlpha,
        ),
      );
    }
    // A transition reaching across this frame's boundary puts a SECOND cut
    // here, and canvas space is shared whenever the two agree on their canvas
    // size — which two cuts of one track normally do. Only differing sizes
    // keep the single-cut bake, because then there is no shared space to mix
    // in (the camera frame is that space, and that is the camera path above).
    final overlap = await _canvasSpaceTransitionFrame(
      task,
      preserveAlpha: preserveAlpha,
    );
    if (overlap != null) {
      return overlap;
    }
    // The presentation render: the アフレコ name tags belong in the video
    // (their row's eye is the switch).
    final image = await renderComposite(task, mode, withNameTags: true);
    // The V effects are TRACK data on the global axis (R4).
    final trackFrame = session.rowSpans.trackGlobalFrameOf(
      task.cut.id,
      task.frameIndex,
    );
    // The V row's fx MASTER reaches the OUTPUT, like every fx switch since
    // R8 ("a bypass that vanished on reload while a per-effect bypass
    // survived" is exactly what R8 refused). It gates the effect chain —
    // never the STATIC opacity, which is a compositing property and not an fx
    // (R9 #21).
    final trackFxEnabled = session.effectsAndFx.isCutFxEnabled(task.cut.id);
    // No animated track fade any more; the transition row's ramp lands in
    // [_canvasSpaceTransitionFrame] above, on the frames it actually covers.
    final fade = session.opacityVerbs.trackStaticOpacityForCut(task.cut.id);
    final trackEffects = trackEffectsAt(
      session.effectsAndFx.trackEffectsForCut(task.cut.id),
      trackFrame,
      enabled: trackFxEnabled,
    );
    if (fade >= 1 && trackEffects.isEmpty) {
      return image;
    }
    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    try {
      return await rasterizeOffscreen(
        width: image.width,
        height: image.height,
        paint: (canvas) {
          // The BACKDROP ground (R3b): a fade thins the frame down to it.
          // An alpha master leaves it transparent instead.
          _paintBackdropGround(canvas, bounds, preserveAlpha: preserveAlpha);
          // The fade is transparency (R3b): the frame thins as one layer
          // over the ground; no target-color wash.
          if (fade < 1) {
            canvas.saveLayer(bounds, ui.Paint()..color = alphaOnly(fade));
          }
          final framePaint = ui.Paint();
          // The chain filters the cut's finished picture, under the fade —
          // the same order the screen draws it in.
          //
          // 🚨AND A KEY IN IT NEEDS ITS OWN RASTER. `image` is the cut's
          // finished picture at its own size and the export draws it 1:1,
          // so the steps run at scale 1 — the one route where the ratio is
          // not a question.
          final plan = resolveCompositeEffectPlan(trackEffects);
          plan.finalPaint.applyTo(framePaint);
          final stepped = steppedForChain(
            image: image,
            plan: plan,
            canvasExtent: task.cut.canvasSize.width.toDouble(),
          );
          canvas.drawImage(stepped, ui.Offset.zero, framePaint);
          if (!identical(stepped, image)) {
            stepped.dispose();
          }
          if (fade < 1) {
            canvas.restore();
          }
        },
      );
    } finally {
      image.dispose();
    }
  }

  /// The cuts this frame is mixed from and the space they share — null when
  /// only one cut contributes (the ordinary bake) or when the contributors
  /// disagree on their canvas size, which leaves no shared space to mix in.
  ///
  /// The weights come out already source-over composed, and the surfaces of
  /// every contributing cut are retained before the caller starts drawing.
  ({
    List<TransitionContribution> contributions,
    CanvasSize size,
    List<double> weights,
    int globalFrame,
  })?
  _sharedTransitionSpace(ExportFrameTask task) {
    final layout = _stackLayout ??= buildStoryboardTimelineLayout(
      session.repository.requireProject(),
    );
    final own = layout.where((entry) => entry.cutId == task.cut.id).firstOrNull;
    if (own == null) {
      return null;
    }
    // This cut's own TRACK axis: a transition is a track's, so the partner can
    // only come from here.
    final entries = [
      for (final entry in layout)
        if (entry.trackId == own.trackId) entry,
    ];
    final globalFrame = own.startFrame + task.frameIndex;
    final contributions = resolveTransitionContributions(
      playlist: entries,
      spans: session.transitions.transitionSpansOfTrack(own.trackId),
      globalFrameIndex: globalFrame,
    );
    if (contributions.length < 2) {
      return null;
    }
    final size = contributions.first.cut.canvasSize;
    for (final contribution in contributions) {
      if (contribution.cut.canvasSize != size) {
        return null;
      }
    }
    final unitAlphas = _retainAndUnitAlphas([
      for (final contribution in contributions)
        (cut: contribution.cut, opacity: contribution.opacity),
    ]);
    return (
      contributions: contributions,
      size: size,
      weights: sourceOverWeights(unitAlphas),
      globalFrame: globalFrame,
    );
  }

  /// A CANVAS-size video frame that two cuts share, because a transition
  /// reaches across the boundary here — null when this frame has only one
  /// contribution (the ordinary bake) or when the contributing cuts disagree
  /// on their canvas size (no shared space to mix in).
  ///
  /// Each cut is drawn with its own track pose, chain and unit weight, in the
  /// order the resolver returns them (leaving cut first) — the camera path's
  /// rules, in canvas space instead of the camera frame.
  Future<ui.Image?> _canvasSpaceTransitionFrame(
    ExportFrameTask task, {
    required bool preserveAlpha,
  }) async {
    final shared = _sharedTransitionSpace(task);
    if (shared == null) {
      return null;
    }
    final contributions = shared.contributions;
    final size = shared.size;
    final weights = shared.weights;
    final globalFrame = shared.globalFrame;

    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      size.width.toDouble(),
      size.height.toDouble(),
    );
    final images = <ui.Image>[];
    try {
      return await rasterizeOffscreen(
        width: size.width,
        height: size.height,
        paint: (canvas) async {
          _paintBackdropGround(canvas, bounds, preserveAlpha: preserveAlpha);
          for (var i = 0; i < contributions.length; i += 1) {
            final contribution = contributions[i];
            final cut = contribution.cut;
            final image = await renderComposite(
              ExportFrameTask(
                cut: cut,
                frameIndex: contribution.localFrameIndex,
              ),
              ExportSizeMode.canvas,
              withNameTags: true,
            );
            images.add(image);
            final weight = weights[i].clamp(0.0, 1.0);
            if (weight < 1) {
              canvas.saveLayer(bounds, ui.Paint()..color = alphaOnly(weight));
            }
            final framePaint = ui.Paint();
            // The V row's chain on this contribution, keys included — the
            // dissolve weights what the chain made, not what it started
            // from.
            final dissolvePlan = resolveCompositeEffectPlan(
              trackEffectsAt(
                session.effectsAndFx.trackEffectsForCut(cut.id),
                globalFrame,
                enabled: session.effectsAndFx.isCutFxEnabled(cut.id),
              ),
            );
            dissolvePlan.finalPaint.applyTo(framePaint);
            final steppedFrame = steppedForChain(
              image: image,
              plan: dissolvePlan,
              canvasExtent: cut.canvasSize.width.toDouble(),
            );
            canvas.drawImage(steppedFrame, ui.Offset.zero, framePaint);
            if (!identical(steppedFrame, image)) {
              steppedFrame.dispose();
            }
            if (weight < 1) {
              canvas.restore();
            }
          }
        },
      );
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }

  /// The camera-frame video frame as the display's track stack (R3a).
  ///
  /// The task's cut names the frame's GLOBAL index (its layout start plus
  /// the local index — negative for a leading-gap task, which lands inside
  /// the gap exactly); every track covering that index renders its cut's
  /// CANVAS-SPACE composite (transparent backing) and hands it to
  /// [PlaybackFramePainter] with the stack's own rules — paper on the
  /// bottom covered track only, full-frame fade wash there, upper tracks
  /// thinning their own contribution. One painter for screen and bake.
  Future<ui.Image> _renderTrackStackForVideo(
    ExportFrameTask task, {
    required bool preserveAlpha,
  }) async {
    final layout = _stackLayout ??= buildStoryboardTimelineLayout(
      session.repository.requireProject(),
    );
    var globalFrame = task.frameIndex;
    for (final entry in layout) {
      if (entry.cutId == task.cut.id) {
        globalFrame = entry.startFrame + task.frameIndex;
        break;
      }
    }
    final positions = resolveTrackStackContributions(
      layout: layout,
      spansOf: session.transitions.transitionSpansOfTrack,
      globalFrameIndex: globalFrame,
    );
    // The unit alphas, and then the source-over weights that make the stack
    // read as that mix (see [sourceOverWeights]) — grouped by track here,
    // because an upper track thins only its own contribution.
    final unitAlphas = _retainAndUnitAlphas(
      [
        for (final position in positions)
          (cut: position.cut, opacity: position.opacity),
      ],
      alsoRetain: [task.cut.id],
    );
    final weights = trackGroupSourceOverWeights(positions, unitAlphas);

    final size = session.camera.cameraFrameSize;
    final images = <ui.Image>[];
    try {
      return await rasterizeOffscreen(
        width: size.width,
        height: size.height,
        paint: (canvas) => _paintTrackStack(
          canvas,
          size: size,
          positions: positions,
          weights: weights,
          images: images,
          preserveAlpha: preserveAlpha,
        ),
      );
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }

  /// The track stack painted onto [canvas], each position loaded as it is
  /// drawn — every picture it loads goes into [images] so the caller can
  /// dispose them once the raster has read them.
  Future<void> _paintTrackStack(
    ui.Canvas canvas, {
    required CanvasSize size,
    required List<TrackStackContribution> positions,
    required List<double> weights,
    required List<ui.Image> images,
    required bool preserveAlpha,
  }) async {
    // The BACKDROP (R3b), everywhere the stack leaves uncovered: gap
    // frames, a posed stage sliding off, a fade thinning the stack away.
    _paintBackdropGround(
      canvas,
      ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
      preserveAlpha: preserveAlpha,
    );
    for (var i = 0; i < positions.length; i += 1) {
      final position = positions[i];
      final cut = position.cut;
      await _hydrate(cut, position.localFrameIndex);
      final image = await _stackRenderService.renderThroughCamera(
        nodes: planCutFrameCompositeTree(
          cut: _cutForRender(cut),
          frameIndex: position.localFrameIndex,
          surfaceResolver: (layer, frame) => _surfaceFor(cut, layer, frame),
        ),
        // The IDENTITY camera: a canvas-space composite, exactly what
        // the playback cache holds — the painter below projects it
        // through the cut's real camera, so the camera is never baked
        // into the composite itself (playback's own rule).
        pose: CameraPose(
          center: CanvasPoint(
            x: cut.canvasSize.width / 2,
            y: cut.canvasSize.height / 2,
          ),
        ),
        cameraFrameSize: cut.canvasSize,
      );
      images.add(image);
      // Track effects at the frame's GLOBAL position (R4) — the stack's
      // own axis — with the row's fx master gating them (R8's rule; the
      // static opacity is not an fx and stays).
      final trackFxEnabled = session.effectsAndFx.isCutFxEnabled(cut.id);
      final weight = weights[i];
      // The stage belongs to the bottom covered TRACK, and to every
      // contribution of it: an O.L is a 場面転換, so the arriving cut brings
      // its own paper and the weights cross-fade the whole screen. Keyed to
      // the bottom CONTRIBUTION this baked a superimpose.
      final isStage = position.isBottomTrack;
      PlaybackFramePainter(
        image: image,
        canvasSize: cut.canvasSize,
        // The multitrack video path projects here, so the tags ride
        // this painter instead of the identity-camera composite above —
        // one draw, in the same canvas space as every other surface.
        seNameTags: session.seEntries.seNameTagsForCutFrame(
          cut,
          position.localFrameIndex,
        ),
        cameraPose: session.camera.cameraPoseForCut(cut, position.localFrameIndex),
        cameraFrameSize: size,
        // No cutPose/cutAnchorPoint: the V row has no transform.
        cutEffects: trackEffectsAt(
          session.effectsAndFx.trackEffectsForCut(cut.id),
          position.globalFrameIndex,
          enabled: trackFxEnabled,
        ),
        paperBackground: session.projectSettings.projectBackground,
        paintPaper: isStage,
        // The alpha matrix (user 2026-07-29): alpha masters exclude the
        // backdrop AND the pasteboard — they are compositing sources,
        // and the paper carries its own alpha. A pasteboard that is NONE
        // (F-114) prints nothing either: the plane is not there.
        pasteboardColor:
            isStage &&
                !preserveAlpha &&
                !session.repository.requireProject().pasteboardNone
            ? ui.Color(session.repository.requireProject().pasteboardArgb)
            : null,
        // The output IS the camera frame — there is no outside to
        // letterbox, and an alpha master needs the ground transparent.
        paintLetterbox: false,
        fadeOpacity: isStage ? weight : 1,
        imageOpacity: isStage ? 1 : weight,
      ).paint(
        canvas,
        ui.Size(size.width.toDouble(), size.height.toDouble()),
      );
    }
  }

  /// One LABEL-GROUP cel (EX5): the gated members' frames composited
  /// bottom-up at their static opacities — a delivery cel is the stack
  /// (기준+어태치), not the pieces. Null when NO member has artwork.
  /// The renderer's background carries the channel choice (transparent
  /// for RGBA, the picked backing for RGB); [ExportSizeMode.camera]
  /// crops through the camera at the base cel's FIRST exposure (a cel
  /// has no time of its own — where it first shows is the honest frame).
  Future<ui.Image?> renderCelGroup(
    ExportCelGroupTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
  }) async {
    _retainSurfacesFor([task.cut.id]);
    // A cel has no time of its own, so the group's FX sample at the base
    // cel's FIRST exposure — the same honest frame the camera pose uses.
    var firstExposure = 0;
    for (final block in drawingBlocks(task.baseLayer.timeline)) {
      if (block.frameId == task.baseFrame.id) {
        firstExposure = block.startIndex;
        break;
      }
    }
    final layers = <CutFrameCompositeLayer>[];
    for (var i = 0; i < task.members.length; i += 1) {
      final frame = task.memberFrames[i];
      if (frame == null) {
        continue;
      }
      final surface = _surfaceFor(task.cut, task.members[i], frame);
      if (surface == null) {
        continue;
      }
      layers.add(
        CutFrameCompositeLayer(
          surface: surface,
          opacity: task.members[i].opacity,
          // R26 #30: the delivery cel is the stack as composited — the
          // members' blends apply. R6: their EFFECTS ride the same fx
          // gates every other route uses — the dialog's master toggle and
          // the row's own fx switch.
          //
          // The cel tab's master toggle used to be a hardcoded false ("cels
          // stay raw artwork"); 유저 2026-08-27 made it the tab's own switch,
          // defaulting ON — see [CelsExportSpec.applyLayerFx]. An artist who
          // wants raw line art back turns it off, which is what the other
          // tabs always allowed. Blend and static opacity are display
          // properties and stay either way.
          blendMode: task.members[i].blendMode,
          effects: applyLayerFx
              ? resolveLayerEffectsAt(
                  // Each effect's own switch (R8) gates it from here.
                  effects: task.members[i].effects,
                  frameIndex: firstExposure,
                )
              : const [],
        ),
      );
    }
    if (layers.isEmpty) {
      return null;
    }
    CameraPose pose;
    if (mode == ExportSizeMode.camera) {
      pose = session.camera.cameraPoseForCut(task.cut, firstExposure);
    } else {
      pose = CameraPose(
        center: CanvasPoint(
          x: task.cut.canvasSize.width / 2,
          y: task.cut.canvasSize.height / 2,
        ),
      );
    }
    return renderService.renderThroughCamera(
      layers: layers,
      pose: pose,
      cameraFrameSize: mode == ExportSizeMode.camera
          ? session.camera.cameraFrameSize
          : task.cut.canvasSize,
      outputSize: outputSize,
    );
  }

}
