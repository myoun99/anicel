import 'package:flutter/widgets.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../../models/transition_geometry.dart' show TransitionVeil;
import '../../services/se_name_tag_plan.dart';
import '../../services/composite_effect_paint.dart' show alphaOnly;
import '../canvas/display_resample.dart';
import '../../services/layer_pose_paint.dart';
import '../canvas/paper_background.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../text/se_name_tag_paint.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';
import 'transition_veil_paint.dart';

/// Paints what a frame lays around its picture inside the canvas panel
/// viewport — the paper, the stage's apron, the letterbox past a camera's
/// frame, and the names and veils over it. The picture is never this
/// painter's: on screen it is the canvas's own rows (`CameraShot`,
/// `CanvasTrackStackView`), and in a film the cut drawn through its camera
/// (`ExportFrameRenderer._stackUnit`) — each laid between a painter of what
/// goes under it and a painter of what goes over it.
///
/// Canvas mode ([cameraPose] null) draws in canvas space under the
/// interactive [viewport] transform — the exact framing the editing canvas
/// uses, so panel zoom/pan keep working during playback. The blank-canvas
/// placeholder paints its paper with it.
///
/// Camera mode looks through the pose instead: the camera's output frame
/// takes the canvas's place under the SAME viewport transform (zoom/pan keep
/// working here too), everything outside it letterboxed dark, and what is
/// laid in canvas space is projected with the transform the export renderer
/// uses.
///
/// ↩️It drew the cut's composite too — the playback cache's picture, and a
/// film's — until the screen played the canvas's rows
/// (playback-plays-the-screen-material) and the film drew its cut through
/// the camera as the canvas does (card video-export-speed-Q2, 유저
/// 2026-10-13: 「캔버스 규칙으로」).
class PlaybackFramePainter extends CustomPainter with RepaintOnProps {
  const PlaybackFramePainter({
    required this.canvasSize,
    this.viewport,
    this.cameraPose,
    this.cameraFrameSize,
    this.imageOpacity = 1,
    this.veils = const [],
    // R28 #9: the one paper constant, not a repeated literal.
    this.paperColor = const Color(ProjectBackground.defaultPaperArgb),
    this.paperBackground,
    this.pasteboardColor,
    this.pasteboardNone = false,
    this.pasteboardReach = PasteboardReach.whole,
    this.checkersAbsentPlanes = false,
    this.paintPaper = true,
    this.paintLetterbox = true,
    this.seNameTags = const [],
    this.devicePixelRatio = 1.0,
  }) : assert(
         cameraPose == null || cameraFrameSize != null,
         'Camera mode needs the camera frame size.',
       );

  final CanvasSize canvasSize;

  /// Pan/zoom of the panel viewport; identity when null.
  final CanvasViewport? viewport;

  /// Non-null = look through the camera.
  final CameraPose? cameraPose;
  final CanvasSize? cameraFrameSize;

  /// The screens one-sided transitions lay over this cut's WHOLE unit — the
  /// camera frame, or the canvas without a camera — in order, each its
  /// color at its opacity ([cutTransitionVeilsAt], F-192). They are part of
  /// the unit, so the unit's own thinning — the stage's fade, which the
  /// unit's caller lays around all of it, or [imageOpacity] above the
  /// stage — thins them with it.
  ///
  /// ↩️F-192 (유저 2026-09-27) took the one-sided transitions out of the
  /// fade: 「컷의 페이드인은 애초에 쌩 검은화면에서 바뀐단거였음. 화이트인은
  /// 쌩 흰화면에서 바뀌는거고 … 백그라운드색을 바꾸는거말고 구조적으로」. An
  /// F.I/F.O/W.I/W.O no longer thins the unit — it lays its own screen over
  /// it. What still thins it is the O.L's dissolve and the track's own
  /// opacity, which are transparency (R3b, "fade is transparency": what a
  /// fade reveals is whatever lies BEHIND the cut — the tracks below, then
  /// the backdrop — never a painted-on wash).
  final List<TransitionVeil> veils;

  /// How thin the cut's own contribution is laid over the stage — its names
  /// and veils here, its picture beside them. A stacked track above the
  /// stage fades through this, so that fading away it reveals the stage;
  /// the stage's own fade takes its paper and apron along, and is laid
  /// around the whole unit by its caller. 1 costs nothing.
  final double imageOpacity;

  /// What a camera view shows past its frame — the stage's floor there.
  static const Color letterboxColor = Color(0xFF15191C);
  final Color paperColor;

  /// The project PAPER (R10-⑥); when set it wins over [paperColor] —
  /// alpha included (R3b): a thinned paper reveals the pasteboard and the
  /// backdrop behind it.
  final ProjectBackground? paperBackground;

  /// The PASTEBOARD fill behind the paper (R3b, camera mode only): the
  /// bottom covered track's stage fills its whole output frame with this
  /// before the paper lands — the cut unit the fade thins is
  /// pasteboard + paper + picture. Null = no stage fill (upper tracks, and
  /// canvas mode — where the stage's planes are the editing canvas's,
  /// `StagePlanesPainter`, laid under this).
  final Color? pasteboardColor;

  /// Whether the pasteboard is ABSENT (F-114) — [pasteboardColor] is then
  /// the kept colour, and nothing of it is painted.
  final bool pasteboardNone;

  /// How far the pasteboard reaches past the paper (I-109): the unit seen
  /// through no camera, and where the camera sees the apron.
  final PasteboardReach pasteboardReach;

  /// Whether an absent plane — the paper ([ProjectBackground.none]) or the
  /// pasteboard ([pasteboardNone]) — shows the checkerboard where it would
  /// be, the way the editing canvas shows it (유저 2026-09-15: 「없음버튼 누르면
  /// 없는상태. 즉 해당 용지부분이 체크무늬되도록」). ON SCREEN ONLY: the export
  /// leaves it false, and an absent plane prints nothing.
  final bool checkersAbsentPlanes;

  /// False = no paper at all (playlist GAPS, UI-R9 #2): the panel's own
  /// background shows through — the same void the gap-parked scrub
  /// preview shows. There is no cut in a gap, so there is no paper.
  final bool paintPaper;

  /// False = camera mode fills nothing outside the frame (stays
  /// transparent). The multitrack stack paints one frame per track: only
  /// the bottom one letterboxes, the ones above composite over it.
  final bool paintLetterbox;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap. The
  /// canvas panel wires it so playback frames land on the SAME device
  /// grid the editing stack snaps to — entering/leaving playback must not
  /// hop the picture by a sub-pixel. Export passes no [viewport], so the
  /// default never reaches pixels there.
  final double devicePixelRatio;

  /// The SE rows' on-canvas NAME TAGS at this frame (R5b, §6-z15), drawn
  /// directly over the composite — never baked into it (the camera's
  /// rule): the text comes from the SE frames themselves, so a rename shows
  /// instantly without invalidating one cached composite. Each stands in
  /// its shot ([ResolvedSeNameTag.shot]), so through the camera projection
  /// it holds its place in the frame (I-67-Q1).
  final List<ResolvedSeNameTag> seNameTags;

  void _paintPaper(Canvas canvas, Rect rect, {required bool antiAlias}) {
    if (!paintPaper) {
      return;
    }
    final background = paperBackground;
    if (background != null) {
      if (background.none && checkersAbsentPlanes) {
        paintAlphaCheckerboard(canvas, rect);
        return;
      }
      paintProjectPaper(canvas, rect, background, antiAlias: antiAlias);
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..color = paperColor
          ..isAntiAlias = antiAlias,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final pose = cameraPose;

    canvas.save();
    // CustomPaint does not clip: a zoomed/panned frame must never escape the
    // canvas viewport into neighboring panels.
    canvas.clipRect(Offset.zero & size);

    if (pose != null && paintLetterbox) {
      canvas.drawRect(Offset.zero & size, Paint()..color = letterboxColor);
    }
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      applyViewportTransform(
        canvas,
        resolvedViewport,
        devicePixelRatio: devicePixelRatio,
      );
    }
    final canvasRect = canvasSize.canvasRect;

    Rect? frameRect;
    if (pose != null) {
      // The camera's output frame takes the canvas's place in viewport
      // space; the projection inside it matches
      // CameraFrameRenderService.renderThroughCamera.
      final frameSize = cameraFrameSize!;
      frameRect = Rect.fromLTWH(
        0,
        0,
        frameSize.width.toDouble(),
        frameSize.height.toDouble(),
      );
      canvas.clipRect(frameRect);
    }
    // The cut's UNIT — what its fade thins and its transition's screen
    // covers: the camera's frame through the camera; seen through none, as
    // far as its pasteboard reaches — the plane and what is drawn on it
    // thin with the paper (conte-playback-hides-the-pasteboard). ↩️It was
    // the canvas there, while the film was cut at the canvas's edge.
    final unit = frameRect ?? canvasSize.pasteboardAt(pasteboardReach).rect;

    if (pose != null && pasteboardColor != null) {
      // The stage's apron: the camera sees the pasteboard wherever it
      // reaches past the paper — part of the cut unit, so it fades with
      // it. An ABSENT pasteboard (F-114) is the checkerboard on screen and
      // nothing at all anywhere else.
      //
      // Only as far as it reaches (I-109): past its wall the camera sees
      // what lies under the cut, as the canvas shows the backdrop there —
      // and with the pasteboard off, the paper alone. ↩️It filled the whole
      // frame, wherever the wall stood.
      canvas.save();
      canvas.clipPath(
        (Path()..addRect(canvasSize.pasteboardAt(pasteboardReach).rect))
            .transform(cameraProjectionMatrix(pose, cameraFrameSize!).storage),
      );
      if (!pasteboardNone) {
        canvas.drawRect(frameRect!, Paint()..color = pasteboardColor!);
      } else if (checkersAbsentPlanes) {
        paintAlphaCheckerboard(canvas, frameRect!);
      }
      canvas.restore();
    }
    // The canvas seen whole stands in for the editing stack's paper — the
    // blank canvas is this — so it cuts the canvas's boundary the way the
    // stack cuts it (`displayEdgeAntiAliased`, F-67-paper-edge), or a cel
    // coming and going would switch the edge line on and off. ↩️Through the
    // camera a paper kept the anti-aliased edge it had, projected — until
    // every road laid its paper with its rows (playback-picture-is-not-the-
    // canvas-picture, and a film since): through the camera this lays an
    // absent paper's checkerboard, which has no edge to cut.
    final edgeAntiAlias =
        resolvedViewport == null ||
        displayEdgeAntiAliased(resolvedViewport, devicePixelRatio);
    if (pose == null) {
      _paintPaper(canvas, canvasRect, antiAlias: edgeAntiAlias);
    } else {
      canvas.save();
      applyCameraProjection(canvas, pose, cameraFrameSize!);
      _paintPaper(canvas, canvasRect, antiAlias: edgeAntiAlias);
    }
    if (seNameTags.isNotEmpty) {
      // The tags belong to the cut's own contribution, so a stacked UPPER
      // track thins them with its picture: that track fades through
      // [imageOpacity] (only the stage's fade, laid around the whole unit,
      // carries the tags for free), and an annotation left fully opaque
      // over a fading picture reads as a bug.
      final thinning = imageOpacity < 1;
      if (thinning) {
        // Bounded by what is clipped already — through the camera, its
        // frame. ↩️It was bounded by [unit], which is in the frame's space,
        // here under the camera's projection in the canvas's: a camera that
        // looked away from the canvas's corner cut the thinned names away
        // whole (🧪10-13: 15,008 pixels at 1, none at a half).
        canvas.saveLayer(null, Paint()..color = alphaOnly(imageOpacity));
      }
      paintSeNameTags(
        canvas,
        tags: seNameTags,
        canvasSize: canvasSize,
        // Device pixels per canvas pixel under the view and, through the
        // camera, its projection — whose turn keeps scale, so its zoom is
        // the whole of it (as `renderThroughCamera` reads it).
        rasterScale:
            displayScaleOf(resolvedViewport?.zoom ?? 1, devicePixelRatio) *
            (pose?.zoom.abs() ?? 1),
      );
      if (thinning) {
        canvas.restore();
      }
    }
    if (pose != null) {
      canvas.restore();
    }
    // F-192: the transition's own screen over the whole unit, inside the
    // unit's fade so the stage's thinning takes it along; a track above the
    // stage thins it by its own weight, as it thins its picture.
    paintTransitionVeils(canvas, unit, veils, thinnedBy: imageOpacity);
    canvas.restore();
  }

  @override
  Object get props => (
    canvasSize,
    viewport,
    cameraPose,
    cameraFrameSize,
    ByList(veils),
    imageOpacity,
    paperColor,
    paperBackground,
    pasteboardColor,
    pasteboardNone,
    pasteboardReach,
    checkersAbsentPlanes,
    paintPaper,
    paintLetterbox,
    // The pan-phase snap reads it — a monitor move must repaint, not
    // keep the old phase.
    devicePixelRatio,
    seNameTagSignature(seNameTags),
  );
}
