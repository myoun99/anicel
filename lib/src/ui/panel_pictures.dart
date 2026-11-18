import 'dart:async';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

import '../models/cut.dart';
import '../services/camera_frame_corners.dart' show CameraView, pictureView;
import '../services/playback/frame_demand.dart';
import 'editor_session_manager.dart';
import 'export/export_frame_renderer.dart' show exportFrameGround;
import 'frame_shots.dart';

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
/// Shot as every picture of a frame that goes to a file is
/// ([frameOnTheEngine]), on [exportFrameGround].
///
/// 🚨★★★THE PRINT IS ITS LIVE ONE (conte-picture-print-and-live-part-at-
/// edges, 유저 11-07 「0 으로 맞춘다」 — F-215 「on하든off하든 바뀌는게
/// 없어야」). ↩️It was drawn as a film draws a row's picture
/// (`CameraFrameRenderService.renderThroughCamera`: the camera's projection
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
  }) => pictureOfShot(frame(cut, frameIndex, width: width, region: region));

  /// [render]'s frame as the engine keeps it, for the caller to free: what a
  /// writer that reads it back itself takes (a conte PDF's cell, read once
  /// as its file keeps it).
  Future<GpuShown> frame(
    Cut cut,
    int frameIndex, {
    required int width,
    ui.Rect? region,
  }) async {
    final view = panelView(session, cut, frameIndex, region);
    await giveWay?.call();
    await session.movieCels.hydrate(cut, frameIndex);
    return frameOnTheEngine(
      session,
      pictures: session.playbackRig.framePictures,
      nodes: session.editingCanvas
          .stackAt(cut: cut, frameIndex: frameIndex, drawingLayerId: null)
          .nodes,
      frame: panelFrame(cut, frameIndex),
      view: view,
      output: view.frameSize.scaledToWidth(width),
      ground: exportFrameGround,
    );
  }
}

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

/// The frame a panel of [cut] at [frameIndex] is cut from, and a conte
/// picture drawn live stands on (`ContePictureLive`) — its print and it one
/// picture: on its paper, no ghost, as a canvas standing on it shows it.
DemandedPicture panelFrame(Cut cut, int frameIndex) => (
  cut: cut,
  frameIndex: frameIndex,
  paintPaper: true,
  ghosts: FrameGhosts.none,
);
