import 'dart:async';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/sync_image_upload.dart';
import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/composite_tree.dart';
import '../native/app_gpu_engine.dart';
import '../native/screen_texture.dart';
import '../services/camera_frame_corners.dart' show CameraView;
import '../services/camera_projection_matrix.dart';
import '../services/cel_looks.dart';
import '../services/playback/frame_demand.dart';
import '../services/viewport_transform_matrix.dart' show viewportOfSimilarity;
import 'canvas/canvas_layer_stack_view.dart'
    show CanvasStackRow, EngineStackScreen, FramePage;
import 'canvas/fx_plugin_stages.dart';
import 'canvas/viewport_canvas_transform.dart' show applyViewportTransform;
import 'editor_session_manager.dart';
import 'playback/camera_shot.dart' show clipToTheCanvas;
import 'playback/frame_pictures.dart';

/// What a shot lays over its picture, in CANVAS space under the view the
/// picture is shown through — handed the scale that view rasters a canvas
/// pixel at, which a `Canvas` will not tell anyone: a pass that rasters a
/// picture of its own (an SE tag with its row's effects) asks it as a
/// folder does.
typedef CameraOverlayPass = void Function(ui.Canvas canvas, double rasterScale);

/// [frame]'s one picture of [nodes] ([FramePictures.pictureOf]) shown
/// through [view] onto a raster of [output] pixels and read back — on
/// [ground], cut at the canvas's edge where [cutsToTheCanvas] says
/// ([clipToTheCanvas]; a film shows no pasteboard, 「페이스트보드는 포함 안
/// 시킴」), and [over] laid over it through the same view.
///
/// 🚨★★★ONE DOOR FOR EVERY PICTURE OF A FRAME THAT GOES TO A FILE OR A
/// PANEL (7′, exports on the engine — 유저 11-08 「지금화면이랑
/// 맞출필요는없어 … 바뀌고 나서만 동일하면되」): a panel's print, a film's
/// frame, a still, a layered file's row, a cel. Each is the picture the
/// engine keeps of the frame, as the canvas shows it ([EngineStackScreen
/// .show]: the view snapped, the display's filter for the scale) — so a
/// still and a panel through one view on one paper are one picture, to the
/// byte. ↩️An export composited its rows again on Flutter, each through the
/// camera (`CameraFrameRenderService.renderThroughCamera`), and a panel's
/// picture came out a few levels apart from the still beside it.
///
/// A frame there is no picture to cut from — its page alone, one a canvas
/// holds as its own over what no cel stores — is drawn as its cels stand
/// ([FramePictures.drawingNow]), through the same view.
///
/// On [frame]'s page, or [page] where the picture is drawn on another
/// ([FramePictures.keyOfStack]): a file's rows on the ground it is made on.
///
/// 🚨★★★ITS CELS ARE LOOKS ([CelLooks]; `gpu-canonical-store-Q10`, 유저
/// 2026-11-10 「추천대로 법 지키도록」): what a shot reads leaves the store as
/// it found it. Held by [looks] where a run holds them across its frames,
/// else for this shot alone.
///
/// ⚠️[nodes] are asked of the frame after its movie cels are hydrated
/// (`MovieCelHydrator.hydrate`): where a movie's picture was laid is part
/// of where its row lies.
Future<ui.Image> frameShot(
  EditorSessionManager session, {
  required FramePictures pictures,
  required List<CompositeNode<CanvasStackRow>> nodes,
  required DemandedPicture frame,
  FramePage? page,
  required CameraView view,
  required CanvasSize output,
  required ui.Color ground,
  bool cutsToTheCanvas = true,
  CameraOverlayPass? over,
  CelLooks? looks,
}) async {
  final looking = looks ?? CelLooks(session.renderCaches.brushFrameStore);
  final picture = await pictures.pictureOf(
    nodes,
    frame,
    shouldAbort: _stays,
    page: page,
    looks: looking,
  );
  GpuSurface? target;
  ui.Image? shot;
  ui.Picture? recorded;
  try {
    final asItStands = picture == null
        ? await pictures
              .readInStack(nodes, frame, page: page, looks: looking)
              .then(
                (_) => pictures.drawingNow(
                  nodes,
                  frame,
                  page: page,
                  looks: looking,
                ),
              )
        : null;
    final onTheRaster = panelViewOnRaster(view, output);
    final tools = await session.renderCaches.framePictureStore.tools;
    final raster = target = ScreenTexture.surfaceOf(
      appGpuEngine,
      output.width,
      output.height,
    );
    final size = (output.width, output.height);
    Future<void> showOn(GpuTarget onto) async {
      if (picture != null) {
        picture.show(onto, size, viewport: onTheRaster, devicePixelRatio: 1);
        return;
      }
      final screen = EngineStackScreen(tools.composite, tools.letters);
      try {
        // Its plug-ins' steps run first, as a picture's are when it is
        // laid (🗣️I-132-Q34 a).
        await FxPluginStages.recordedThrough<void>(
          () => screen.compose(asItStands!.frame),
          discard: (_) {},
        );
        screen.show(onto, size, viewport: onTheRaster, devicePixelRatio: 1);
      } finally {
        screen.free();
      }
    }

    await showOn(raster);
    shot = pictureOf(
      PremultipliedRows(raster.read(), output.width, output.height),
    );
    final bounds = ui.Offset.zero &
        ui.Size(output.width.toDouble(), output.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, bounds)
      ..drawRect(bounds, ui.Paint()..color = ground)
      ..save();
    if (cutsToTheCanvas) {
      clipToTheCanvas(canvas, frame.cut.canvasSize, onTheRaster, 1);
    }
    canvas
      ..drawImage(shot, ui.Offset.zero, ui.Paint())
      ..restore();
    if (over != null) {
      applyViewportTransform(canvas, onTheRaster);
      over(canvas, onTheRaster.zoom.abs());
    }
    recorded = recorder.endRecording();
    final made = await recorded.toImage(output.width, output.height);
    if (asItStands?.thrown case (final error, final stack)) {
      made.dispose();
      Error.throwWithStackTrace(error, stack);
    }
    return made;
  } finally {
    recorded?.dispose();
    target?.free();
    shot?.dispose();
    // 🚨Shot, the picture is left as the shot found it: one a step of the
    // run wants or a screen holds stays, and one made for the shot alone
    // goes ([PlaybackCacheBudget.letGoUnwanted]) — the shot's hold on it
    // released ([FramePictures.pictureOf]), whatever became of the shot.
    if (picture != null) {
      session.playbackRig.playbackCache.letGoUnwanted(
        pictures.keyOfStack(nodes, frame, page: page),
      );
      picture.release();
    }
  }
}

bool _stays() => false;

/// Where [view] lays the canvas on a raster of [output] pixels — its
/// camera's projection onto it, a device pixel the raster's: what every
/// [frameShot] is drawn through, and a conte picture's live one
/// (`ContePictureLive`).
///
/// 🚨ONE SPELLING OF IT (conte-picture-print-and-live-part-at-edges, 유저
/// 11-07 「0 으로 맞춘다」). ↩️The live one reached the same map by another
/// road — through the paper, the slot's scale and then the box's — and
/// stood its camera at the middle of the frame's height scaled to the
/// box, where the print's stands at the middle of its raster's rounded
/// height: apart wherever the raster's height is rounded (a camera frame
/// or a moving camera's region off the raster's aspect).
CanvasViewport panelViewOnRaster(CameraView view, CanvasSize output) =>
    viewportOfSimilarity(
      cameraProjectionMatrix(view.pose, view.frameSize, outputSize: output),
    )!;
