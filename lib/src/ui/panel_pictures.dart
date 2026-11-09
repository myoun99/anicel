import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart';
import '../native/app_gpu_engine.dart';
import '../native/screen_texture.dart';
import '../services/camera_frame_corners.dart' show CameraView, pictureView;
import '../services/camera_projection_matrix.dart';
import '../services/playback/frame_demand.dart';
import '../services/viewport_transform_matrix.dart' show viewportOfSimilarity;
import 'editor_session_manager.dart';
import 'export/export_frame_renderer.dart' show exportFrameGround;
import 'playback/camera_shot.dart' show clipToTheCanvas;
import 'canvas/canvas_layer_stack_view.dart' show EngineStackScreen;

/// A panel's picture — a storyboard block's, a conte cell's, on screen and
/// on a page written to a file: [render]s [cut] at a frame through its
/// camera, or over the canvas a conte cell's moving camera sweeps
/// ([pictureView]), so many pixels wide.
///
/// 🚨★★★CUT FROM THE FRAME'S ONE PICTURE (F-533-Q8, 유저 2026-11-05:
/// 「프레임 그림에서 잘라 쓴다」 · 「재료가 둘? … 최대한 하나로 통합하고싶음」 ·
/// 「콘티용지패널의 그림도 그렇고 최대한 하나만 쓰는방향으로 하자.
/// 효율적으로」): the picture the frame's maker keeps of it
/// ([FramePictures.pictureOf]) — the canvas's own wherever the panel stacks
/// the frame as the canvas does, the cut's rows on its paper with no ghost,
/// so a panel of the frame a pen is on composes nothing. It stacks the
/// cut's rows alone, no V row's fx and no track's SE row (R4 「변형은
/// 블록의 것이 아니다」; ⛔the printed picture carries no V row,
/// `EditingCanvas._underTheCutsFx`): a frame the canvas shows under them is
/// a picture of its own.
///
/// Shown where the camera lays the canvas on the raster as a conte
/// picture's live one shows it ([EngineStackScreen.show]: the view snapped,
/// the display's filter for the scale), cut at the canvas's edge as it is
/// ([clipToTheCanvas]; a film shows no pasteboard either, 「페이스트보드는
/// 포함 안 시킴」), on [exportFrameGround]. A frame there is no picture to
/// cut from — its page alone, one a canvas holds as its own over what no
/// cel stores — is drawn as its cels stand ([FramePictures.drawingNow]),
/// through the same view.
///
/// 🚨★★★THE PRINT IS ITS LIVE ONE (conte-picture-print-and-live-part-at-
/// edges, 유저 11-07 「0 으로 맞춘다」 — F-215 「on하든off하든 바뀌는게
/// 없어야」). ↩️It was drawn as a film draws a row's picture
/// ([CameraFrameRenderService.renderThroughCamera]: the camera's projection
/// unsnapped, a texel copy where it moved pixels whole) and cut on the
/// camera's own outline: 🔬half a pixel from the live one wherever the
/// camera put the canvas between pixels — every slanted line in an
/// odd-sized shot — and an edge's pixel apart where it saw past the canvas.
/// So a panel is a film's frame only where the camera lands on whole
/// pixels; elsewhere it is that frame snapped to the panel's grid.
///
/// ↩️It was composed again for the panel, every row at the canvas's size
/// (`ExportFrameRenderer.renderPicture`) — 🔬S5_BA cut 352, 68 rows: about
/// 180 Mpx a picture, seconds of a Surface Pro 11's GPU each time the pen
/// came up — and showed the pasteboard inside the camera's frame, which a
/// film cuts.
class PanelPictures {
  /// [pixels] — premultiplied RGBA, [width] × [height] — as an image.
  static Future<ui.Image> _imageOf(Uint8List pixels, int width, int height) {
    final image = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    return image.future;
  }

  PanelPictures({required this.session, this.giveWay});

  final EditorSessionManager session;

  /// Waited for before a picture is read and made — a panel's stands behind
  /// the hand ([PlaybackPrerenderScheduler.untilQuiet], F-533). None where
  /// someone waits for it: a page written to a file.
  final Future<void> Function()? giveWay;

  /// [cut] at [frameIndex], [width] pixels wide — over the canvas [region]
  /// where it is not the camera's view.
  Future<ui.Image> render(
    Cut cut,
    int frameIndex, {
    required int width,
    ui.Rect? region,
  }) async {
    final view = panelView(session, cut, frameIndex, region);
    final output = view.frameSize.scaledToWidth(width);
    await giveWay?.call();
    await session.movieCels.hydrate(cut, frameIndex);
    final pictures = session.playbackRig.framePictures;
    final nodes = session.editingCanvas
        .stackAt(cut: cut, frameIndex: frameIndex, drawingLayerId: null)
        .nodes;
    final demanded = panelFrame(cut, frameIndex);
    final picture = await pictures.pictureOf(
      nodes,
      demanded,
      shouldAbort: _stays,
    );
    final asItStands = picture == null
        ? await pictures
              .readInStack(nodes, demanded)
              .then((_) => pictures.drawingNow(nodes, demanded))
        : null;
    final onTheRaster = panelViewOnRaster(view, output);
    final tools = await session.renderCaches.framePictureStore.tools;
    final target = ScreenTexture.surfaceOf(
      appGpuEngine,
      output.width,
      output.height,
    );
    final size = (output.width, output.height);
    ui.Image? shot;
    ui.Picture? recorded;
    try {
      void showOn(GpuTarget onto) {
        if (picture != null) {
          picture.show(
            onto,
            size,
            viewport: onTheRaster,
            devicePixelRatio: 1,
          );
          return;
        }
        final screen = EngineStackScreen(tools.composite, tools.letters);
        try {
          screen
            ..compose(asItStands!.frame)
            ..show(onto, size, viewport: onTheRaster, devicePixelRatio: 1);
        } finally {
          screen.free();
        }
      }

      showOn(target);
      shot = await _imageOf(target.read(), output.width, output.height);
      final frame = ui.Offset.zero &
          ui.Size(output.width.toDouble(), output.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, frame)
        ..drawRect(frame, ui.Paint()..color = exportFrameGround);
      clipToTheCanvas(canvas, cut.canvasSize, onTheRaster, 1);
      canvas.drawImage(shot, ui.Offset.zero, ui.Paint());
      recorded = recorder.endRecording();
      final made = await recorded.toImage(output.width, output.height);
      if (asItStands?.thrown case (final error, final stack)) {
        made.dispose();
        Error.throwWithStackTrace(error, stack);
      }
      return made;
    } finally {
      recorded?.dispose();
      target.free();
      shot?.dispose();
      // 🚨Cut, the picture is left as the panel found it: one a step of
      // the run wants or a screen holds stays, and one made for the panel
      // alone goes ([PlaybackCacheBudget.letGoUnwanted]).
      if (picture != null) {
        session.playbackRig.playbackCache.letGoUnwanted(
          pictures.keyOfStack(nodes, demanded),
        );
      }
    }
  }
}

bool _stays() => false;

/// What a panel of [cut] at [frameIndex] shows ([pictureView]): its camera
/// at the frame, or the canvas [region] a conte cell's moving camera
/// sweeps.
CameraView panelView(
  EditorSessionManager session,
  Cut cut,
  int frameIndex,
  ui.Rect? region,
) => pictureView((
  pose: session.camera.cameraPoseForCut(cut, frameIndex),
  frameSize: session.camera.cameraFrameSize,
), region);

/// Where [view] lays the canvas on a panel's raster of [output] pixels —
/// its camera's projection onto it, a device pixel the raster's: what a
/// panel's print is drawn through, and its live one (`ContePictureLive`).
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

/// The frame a panel of [cut] at [frameIndex] is cut from, and a conte
/// picture drawn live stands on (`ContePictureLive`) — its print and it one
/// picture: on its paper, no ghost, as a canvas standing on it shows it.
DemandedPicture panelFrame(Cut cut, int frameIndex) => (
  cut: cut,
  frameIndex: frameIndex,
  paintPaper: true,
  ghosts: FrameGhosts.none,
);
