import 'dart:ui' as ui;

import '../models/cut.dart';
import '../models/layer_blend_mode.dart';
import '../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../services/camera_frame_corners.dart' show pictureView;
import '../services/camera_projection_matrix.dart';
import '../services/layer_pose_paint.dart' show applyCameraProjection;
import '../services/playback/frame_demand.dart';
import '../services/viewport_transform_matrix.dart' show viewportOfSimilarity;
import 'canvas/display_resample.dart' show filterQualityForDisplayScale;
import 'canvas/layer_image_draw.dart' show drawPosedLayerImage;
import 'editor_session_manager.dart';
import 'export/export_frame_renderer.dart' show exportFrameGround;
import 'playback/camera_shot.dart' show outlineThrough, shotClipOnScreen;

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
/// Drawn through the camera as a film draws a row's picture
/// ([CameraFrameRenderService.renderThroughCamera]: its projection, the
/// display's filter for the scale, a texel copy where the camera moves
/// pixels whole), cut at the canvas's edge as a film is
/// (「페이스트보드는 포함 안 시킴」), on [exportFrameGround]. A frame there is
/// no picture to cut from — its page alone, one a canvas holds as its own
/// over what no cel stores — is drawn as its cels stand
/// ([FramePictures.drawingNow]), as a screen draws it.
///
/// ↩️It was composed again for the panel, every row at the canvas's size
/// (`ExportFrameRenderer.renderPicture`) — 🔬S5_BA cut 352, 68 rows: about
/// 180 Mpx a picture, seconds of a Surface Pro 11's GPU each time the pen
/// came up — and showed the pasteboard inside the camera's frame, which a
/// film cuts.
class PanelPictures {
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
    final view = pictureView((
      pose: session.camera.cameraPoseForCut(cut, frameIndex),
      frameSize: session.camera.cameraFrameSize,
    ), region);
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
    final projection = cameraProjectionMatrix(
      view.pose,
      view.frameSize,
      outputSize: output,
    );
    final scale = output.width / view.frameSize.width * view.pose.zoom;
    final frame = ui.Offset.zero &
        ui.Size(output.width.toDouble(), output.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, frame)
      ..drawRect(frame, ui.Paint()..color = exportFrameGround);
    final shot = shotClipOnScreen(
      outlineThrough(cut.canvasSize, projection),
      // An output pixel is the device's.
      1,
    );
    canvas.clipPath(
      ui.Path()..addPolygon(shot.corners, true),
      doAntiAlias: shot.behavior == ui.Clip.antiAlias,
    );
    // Its own handle: the picture's image is let go of when a write
    // replaces it, or the budget the picture.
    final image = picture?.image.clone();
    if (picture != null) {
      applyCameraProjection(
        canvas,
        view.pose,
        view.frameSize,
        outputSize: output,
      );
      drawPosedLayerImage(
        canvas,
        pieces: [(image: image!, worldRect: picture.extent)],
        extent: picture.extent,
        placement: null,
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        paper: cut.canvasSize.canvasRect,
        texelScale:
            cameraMovesPixelsWhole(
              view.pose,
              view.frameSize,
              outputSize: output,
            )
            ? scale
            : null,
        filterQuality: filterQualityForDisplayScale(scale),
      );
    } else {
      asItStands!.frame.paintOnScreen(
        canvas,
        frame.size,
        viewport: viewportOfSimilarity(projection)!,
        devicePixelRatio: 1,
      );
    }
    final recorded = recorder.endRecording();
    try {
      final made = await recorded.toImage(output.width, output.height);
      if (asItStands?.thrown case (final error, final stack)) {
        made.dispose();
        Error.throwWithStackTrace(error, stack);
      }
      return made;
    } finally {
      recorded.dispose();
      image?.dispose();
      // 🚨What a panel made is held on the playback line as the warmer's
      // pictures are, and no further: let go of past it, a picture no step
      // wants first — a panel's (`letGoWantedLatest`). A store lays what it
      // is asked and weighs nothing; the warmer weighs before it makes, and
      // a storyboard of fifty cuts would have laid fifty frames past it.
      session.playbackRig.playbackCache.enforcePlaybackCacheBudget();
    }
  }
}

bool _stays() => false;

/// The frame a panel of [cut] at [frameIndex] is cut from, and a conte
/// picture drawn live stands on (`ContePictureLive`) — its print and it one
/// picture: on its paper, no ghost, as a canvas standing on it shows it.
DemandedPicture panelFrame(Cut cut, int frameIndex) => (
  cut: cut,
  frameIndex: frameIndex,
  paintPaper: true,
  ghosts: FrameGhosts.none,
);
