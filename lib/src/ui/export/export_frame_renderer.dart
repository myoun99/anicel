import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../../services/playback/playback_frame_mapping.dart'
    show resolveTrackStackPositions;
import '../camera/camera_frame_render_service.dart';
import '../canvas/layer_pose_paint.dart';
import '../editor_session_manager.dart';
import '../playback/playback_frame_painter.dart';
import '../storyboard_cut_fade_policy.dart';
import '../storyboard_timeline_layout.dart';
import 'export_cel_group_plan.dart';
import 'export_plan.dart';

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
    final surfaces = _surfacesByCut.putIfAbsent(cut.id, () => {});
    return surfaces.putIfAbsent((layer.id, frame.id), () {
      final frameKey = session.brushFrameKeyForCut(cut, layer.id, frame.id);
      // R19 P3b: the baked raster is the truth — a READ-ONLY reference
      // (valid display cache first, else baked; the coordinator donates
      // on every commit, undo and redo). Nothing is stored back, so
      // batch exports don't grow the shared cache; null = an empty cel.
      return session.brushFrameStore.currentSurfaceWithoutReplay(
        frameKey,
        canvasSize: cut.canvasSize,
      );
    });
  }

  void _retainSurfacesFor(Iterable<CutId> cutIds) {
    final keep = cutIds.toSet();
    _surfacesByCut.removeWhere((cutId, _) => !keep.contains(cutId));
  }

  /// Canvas-space composites for the stack bake: TRANSPARENT backing, so
  /// an upper track's frame never blanks the tracks below — the paper
  /// belongs to the bottom covered track and the assembler paints it.
  late final CameraFrameRenderService _stackRenderService =
      CameraFrameRenderService(background: const ui.Color(0x00000000));

  /// The multi-track layout, built once per export run (the project is
  /// frozen while a run streams).
  List<StoryboardTimelineLayoutEntry>? _stackLayout;

  /// One composited frame. [ExportSizeMode.canvas] renders the identity
  /// camera over the cut's own canvas size (centered, zoom 1, no rotation),
  /// which is exactly the raw canvas at 1:1 pixels on the white paper.
  /// [outputSize] scales the same view down (storyboard thumbnails); null
  /// exports at full size.
  Future<ui.Image> renderComposite(
    ExportFrameTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
  }) {
    final cut = task.cut;
    // The single-cut streams' retention: one cut's cels at a time.
    _retainSurfacesFor([cut.id]);
    final pose = mode == ExportSizeMode.camera
        ? session.cameraPoseForCut(cut, task.frameIndex)
        : CameraPose(
            center: CanvasPoint(
              x: cut.canvasSize.width / 2,
              y: cut.canvasSize.height / 2,
            ),
          );
    return renderService.renderThroughCamera(
      // The fx-bypass switches apply here too (AE semantics: the layer fx
      // switch affects the render) — WYSIWYG with playback. The dialog's
      // 'Apply layer FX' master toggle bypasses every layer at once.
      nodes: planCutFrameCompositeTree(
        cut: cut,
        frameIndex: task.frameIndex,
        surfaceResolver: (layer, frame) => _surfaceFor(cut, layer, frame),
        fxBypassedLayerIds: applyLayerFx
            ? session.fxBypassedLayerIds
            : {for (final layer in cut.layers) layer.id},
      ),
      pose: pose,
      cameraFrameSize: mode == ExportSizeMode.camera
          ? session.cameraFrameSize
          : cut.canvasSize,
      outputSize: outputSize,
    );
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
  /// Transform, AE precomp semantics), then the fade TARGET color
  /// (cutFadeTargetColor) at (1 − fade) on top. PNG sequences deliberately
  /// stay unposed and unfaded (they are compositing sources).
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
      // A leading-gap frame: nothing plays — the project background,
      // exactly what playback shows in the gap (R10-⑥). Opaque codecs
      // bake the fallback; an alpha master keeps the gap transparent.
      final size = mode == ExportSizeMode.camera
          ? session.cameraFrameSize
          : task.cut.canvasSize;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (!preserveAlpha) {
        canvas.drawRect(
          ui.Rect.fromLTWH(
            0,
            0,
            size.width.toDouble(),
            size.height.toDouble(),
          ),
          ui.Paint()..color = ui.Color(session.projectBackground.argb),
        );
      }
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(size.width, size.height);
      } finally {
        picture.dispose();
      }
    }
    final image = await renderComposite(task, mode);
    final fade = task.cut.fadeOpacityAt(task.frameIndex);
    final poseActive = cutPoseIsActive(task.cut);
    if (fade >= 1 && !poseActive) {
      return image;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // Black ground: the pose can uncover the output edges; without a pose
    // the frame covers everything and the ground never shows. An alpha
    // master leaves the uncovered edges transparent instead.
    if (!preserveAlpha) {
      canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xFF000000));
    }
    if (poseActive) {
      final space = CanvasSize(width: image.width, height: image.height);
      canvas.save();
      applyLayerPoseTransform(
        canvas,
        cutPoseAt(task.cut, task.frameIndex, space),
        space,
        anchorPoint: cutAnchorPointAt(task.cut, task.frameIndex),
      );
    }
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    if (poseActive) {
      canvas.restore();
    }
    if (fade < 1) {
      canvas.drawRect(
        bounds,
        ui.Paint()
          ..color = cutFadeTargetColor(
            task.cut,
          ).withValues(alpha: (1 - fade).clamp(0.0, 1.0)),
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(image.width, image.height);
    } finally {
      picture.dispose();
      image.dispose();
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
    final positions = resolveTrackStackPositions(
      layout: layout,
      globalFrameIndex: globalFrame,
    );
    _retainSurfacesFor([
      task.cut.id,
      for (final position in positions) position.cutId,
    ]);

    final size = session.cameraFrameSize;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (!preserveAlpha) {
      // The GROUND, everywhere the stack leaves uncovered: gap frames,
      // the camera reaching past a canvas edge, a posed cut sliding off.
      // One fill — the project background — where the old bake had three
      // different answers (background, renderer white, black). An alpha
      // master stays transparent instead.
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
        ui.Paint()..color = ui.Color(session.projectBackground.argb),
      );
    }
    final images = <ui.Image>[];
    try {
      for (var i = 0; i < positions.length; i += 1) {
        final position = positions[i];
        final cut = position.cut;
        final image = await _stackRenderService.renderThroughCamera(
          nodes: planCutFrameCompositeTree(
            cut: cut,
            frameIndex: position.localFrameIndex,
            surfaceResolver: (layer, frame) => _surfaceFor(cut, layer, frame),
            fxBypassedLayerIds: applyLayerFx
                ? session.fxBypassedLayerIds
                : {for (final layer in cut.layers) layer.id},
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
        final fade = cut.fadeOpacityAt(position.localFrameIndex);
        final poseActive = cutPoseIsActive(cut);
        PlaybackFramePainter(
          image: image,
          canvasSize: cut.canvasSize,
          cameraPose: session.cameraPoseForCut(cut, position.localFrameIndex),
          cameraFrameSize: size,
          cutPose: poseActive
              ? cutPoseAt(cut, position.localFrameIndex, size)
              : null,
          cutAnchorPoint: poseActive
              ? cutAnchorPointAt(cut, position.localFrameIndex)
              : null,
          paperBackground: session.projectBackground,
          // The stage is the bottom covered track's: its paper, its
          // full-frame wash. Tracks above composite transparently and
          // fade their OWN contribution (the parked stack's sentence).
          paintPaper: i == 0,
          // The output IS the camera frame — there is no outside to
          // letterbox, and an alpha master needs the ground transparent.
          paintLetterbox: false,
          fadeOpacity: i == 0 ? fade : 1,
          imageOpacity: i == 0 ? 1 : fade,
          fadeColor: cutFadeTargetColor(cut),
        ).paint(
          canvas,
          ui.Size(size.width.toDouble(), size.height.toDouble()),
        );
      }
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(size.width, size.height);
      } finally {
        picture.dispose();
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
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
          // members' blends apply.
          blendMode: task.members[i].blendMode,
        ),
      );
    }
    if (layers.isEmpty) {
      return null;
    }
    CameraPose pose;
    if (mode == ExportSizeMode.camera) {
      var firstExposure = 0;
      for (final block in drawingBlocks(task.baseLayer.timeline)) {
        if (block.frameId == task.baseFrame.id) {
          firstExposure = block.startIndex;
          break;
        }
      }
      pose = session.cameraPoseForCut(task.cut, firstExposure);
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
          ? session.cameraFrameSize
          : task.cut.canvasSize,
      outputSize: outputSize,
    );
  }

  /// One cel exactly as drawn, no compositing; `null` when the frame has no
  /// artwork (the export loop skips the file). [transparent] keeps the
  /// background empty; otherwise the cel sits on the white paper at the
  /// cut's canvas size.
  Future<ui.Image?> renderCel(ExportCelTask task, {bool transparent = true}) {
    final surface = _surfaceFor(task.cut, task.layer, task.frame);
    if (surface == null) {
      return Future<ui.Image?>.value();
    }
    if (transparent) {
      return bitmapSurfaceToImage(surface);
    }
    return renderService.renderThroughCamera(
      layers: [CutFrameCompositeLayer(surface: surface, opacity: 1)],
      pose: CameraPose(
        center: CanvasPoint(
          x: task.cut.canvasSize.width / 2,
          y: task.cut.canvasSize.height / 2,
        ),
      ),
      cameraFrameSize: task.cut.canvasSize,
    );
  }
}
