import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project.dart' show defaultProjectBackdropArgb;
import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppColors;
import 'display_resample.dart' show displayEdgeAntiAliased, displayEdgeRect;
import 'paper_background.dart' show paintAbsentPlane;
import 'viewport_canvas_transform.dart' show applyViewportTransform;

/// One plane of the stage (R3b): its colour and whether it is there at all
/// (F-114) — one value, so a colour never travels without its absence.
typedef StagePlane = ({Color color, bool none});

/// The colour a project's backdrop or pasteboard is drawn in on screen.
///
/// 🗣️I-143-Q5 (유저 2026-10-30, 「바닥을 따라 밝게」): both start at the
/// floor (R3 #4 — 둘레와 바닥이 한 판), and a project stores that start as
/// the dark palette's floor. That value is read as 「the floor」, so a
/// project left at it follows the palette it is opened in; any other value
/// is the colour it says.
Color stageColorOnScreen(int argb) =>
    argb == defaultProjectBackdropArgb ? AppColors.backdrop : Color(argb);

/// The ground a canvas panel's shell lays under its stage — the one surface
/// with no panel behind it, so it states its own colour — and so what a
/// translucent backdrop shows through it on screen ([backdropOnScreen]).
Color stageGroundOf(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLowest;

/// The [backdrop] as the screen shows it: over the panel's [ground], once.
///
/// 🗣️F-114 (유저 2026-09-15): 「불투명도는 체크무늬는 안되고 진짜 불투명도를
/// 낮추는행위」 — a translucent backdrop is the backdrop thinner, and what
/// lies behind it shows: the panel's ground, laid once. Whatever lays the
/// backdrop again over planes the screen already has — the film over the
/// editing canvas, the fade's wash over the unit — lays THIS, opaque, so
/// nothing under it shows through twice. An ABSENT backdrop stays absent:
/// its checkerboard covers what is under it already.
///
/// ↩️The film laid the backdrop's own colour over the editing canvas's
/// planes and the wash took that colour at the fade's share: a translucent
/// backdrop played darker than it stood, a frame with no cut showed the
/// editing cut's pasteboard through it, and a fade thinned to a colour the
/// film never showed (a-translucent-backdrop-lies-twice-on-the-film,
/// measured 10-23).
StagePlane backdropOnScreen(StagePlane backdrop, Color ground) =>
    backdrop.none
    ? backdrop
    : (color: Color.alphaBlend(backdrop.color, ground), none: false);

/// One [plane] over [region], in the space the canvas is in: the
/// checkerboard in the screen's cells where the plane is absent
/// ([paintAbsentPlane] — [screen] is the canvas's transform at the
/// painter's box), otherwise its colour wherever that has any alpha — its
/// edge anti-aliased either way, so a plane turned off and on moves no
/// edge. The paper is not one of these planes: its edge is the canvas's,
/// cut by the display law, so its absence is laid by
/// [StagePlanesPainter] with [paintAbsentPlane] itself.
///
/// ONE way to lay a plane of the stage (F-114: 「페이스트보드도 백그라운드도
/// 동일하게」): the editing canvas's planes ([StagePlanesPainter]), the
/// film's floor with a camera or without, and the apron the camera sees.
/// ↩️Each spelled the switch of its own (fade-wash-ignores-an-absent-
/// backdrop's 「다섯 곳」, 2026-10-23).
void paintStagePlane(
  Canvas canvas,
  Rect region,
  StagePlane plane, {
  required Float64List screen,
}) {
  final (:color, :none) = plane;
  if (none) {
    paintAbsentPlane(canvas, region, screen: screen, antiAlias: true);
    return;
  }
  if (color.a <= 0) {
    return;
  }
  canvas.drawRect(region, Paint()..color = color);
}

/// The stage's planes behind a cut seen through no camera (R3b): the
/// BACKDROP over the box, the PASTEBOARD over the region it
/// occupies — a canvas-space rectangle, so it rides zoom, pan, rotation and
/// both flips like everything else on the stage — and the checkerboard
/// wherever a plane is ABSENT.
///
/// 🚨ONE PAINTER FOR EVERY CUT SEEN WITHOUT A CAMERA
/// (conte-playback-hides-the-pasteboard, 유저 10-13 「둘 다 보인다(편집
/// 캔버스처럼)」): the editing canvas lays its stage with it, and so does the
/// film's stage on the track stack — a run seen through no camera shows what
/// the canvas shows, past its edge too. ↩️It was the canvas panel's own, and
/// the film, cut at its canvas's edge, laid no pasteboard at all.
///
/// ★THE PASTEBOARD IS A PLACE, NOT A WASH (유저, R2 #3). Both planes used
/// to fill the whole panel, one over the other — which is a stack for
/// ALPHA and says nothing about where either one is. An opaque pasteboard
/// therefore covered the backdrop everywhere and forever: the user had
/// three colours in the settings and could only ever see two of them, and
/// changing the pasteboard repainted what they meant by "the background".
/// The pasteboard is now drawn only where the pasteboard IS, and the
/// backdrop is what lies beyond it.
///
/// 🚨★★★WHERE IT IS = THE DRAWING BOUND, [PasteboardBounds] (F-114, 유저
/// 2026-09-12: 「3x에서만 그려지는데 배경 색 설정하면 페이스트보드가 5x크기로
/// 보이고 … 그려지는건 제대로 3x인데. 법 나뉘어져있는거같으니 통일」). It
/// was a SHOWING number of its own — `Project.pasteboardMargin`, default 2.0
/// canvases per side, set in the project background window — kept apart on
/// the argument that at the drawing bound the backdrop only showed below
/// about 20% zoom. The bound became 3×3 at H2 (2026-08-22) while that number
/// stayed at five, so the plane showed a pasteboard two canvases wider than
/// anything could be drawn on. One wall now: the plane stops exactly where
/// ink stops — at the project's pasteboard size since I-109
/// ([pasteboardReach]), the very wall the floor's pictures stand behind.
///
/// 🚨F-114 (유저 2026-09-15: 「없음버튼 누르면 없는상태. 즉 해당 용지부분이
/// 체크무늬되도록. 페이스트보드도 백그라운드도 동일하게」): an ABSENT plane is
/// the checkerboard over exactly the region that plane would fill — one rule
/// for the three ([paintStagePlane]). A paper that is there stays the layer
/// stack's to paint, alpha and all; an absent one paints nothing in the stack,
/// so its checkerboard is laid here, under the artwork.
class StagePlanesPainter extends CustomPainter with RepaintOnProps {
  const StagePlanesPainter({
    this.backdrop,
    this.pasteboard,
    required this.pasteboardReach,
    this.paperNone = false,
    required this.canvasSize,
    required this.viewport,
    required this.devicePixelRatio,
  });

  /// Null where the stage lies on a floor laid once under it: the film's
  /// covered cuts on the track stack's backdrop, which a fade reveals.
  final StagePlane? backdrop;

  /// Null on a canvas-base panel (`BrushCanvasPanel.canvasBase`): the
  /// backdrop alone.
  final StagePlane? pasteboard;

  /// How far [pasteboard] reaches past the paper (I-109).
  final PasteboardReach pasteboardReach;
  final bool paperNone;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap: the
  /// planes land on the device grid the stack over them snaps to.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final screen = canvas.getTransform();
    // 🚨 Clip to our own box, because the pasteboard below, laid through
    // the view, reaches as far as the pasteboard does — up
    // to three canvas widths and heights (its 3x size, I-109), 7020 x 4962
    // units at the default cut
    // size (it was five, 11700 x 8270, when the figures below were
    // measured — the showing margin F-114 retired). A `CustomPaint` clips nothing on its own, so the
    // display list's BOUNDS became that whole quad, and the engine sizes
    // a raster cache entry from the bounds times the transform:
    //
    //   369 MiB  x  zoom²  x  dpr²
    //
    // ⚠️ That constant is the CUT canvas (`defaultCutCanvasSize`, 2340 x
    // 1654) — this painter is handed `widget.canvasSize`, not the
    // camera's 1920 x 1080. Working it from the camera size gives 197.75
    // MiB, which is what the commit adding this clip said, and misses by
    // a factor of two. With dpr since measured at 1.0 the corrected
    // figure lands within 5% of both real-app readings: 90% zoom predicts
    // 313 MB against 296 measured, 131% predicts 664 against 634.
    //
    // Measured on the real app: the picture cache ran to ~1 GB on an
    // EMPTY project and tracked zoom² exactly, with a cliff where the
    // allocation finally failed. One draw.
    //
    // Everything past this box is composited away anyway, so the app was
    // paying hundreds of megabytes to rasterize pixels it then threw out.
    // And by default it was not even a visible colour: `backdrop` and
    // `pasteboard` are BOTH `0xFF141517`, so the money went on painting
    // #141517 over #141517.
    //
    // This is a return to the convention, not an invention — four of the
    // five canvas-space painters already clip (`canvas_layer_stack_view`,
    // `editor_canvas_area` twice, `camera_frame_overlay`, whose comment
    // says in as many words that CustomPaint does not clip). This one was
    // the exception.
    canvas.save();
    canvas.clipRect(box);
    if (backdrop case final backdrop?) {
      paintStagePlane(canvas, box, backdrop, screen: screen);
    }
    _layOnTheCanvas(canvas, screen);
    canvas.restore();
  }

  /// The planes that are PLACES ON THE CANVAS — the pasteboard, and the
  /// paper where it is absent — laid through the view.
  ///
  /// 🚨They go to the screen the one way every canvas-space painter takes
  /// the view (P8, [applyViewportTransform]) — its pan-phase snap with it,
  /// and they land on the pixels the stack over them lands on
  /// (stage-planes-are-not-pan-snapped: measured 10-23 at a pan of 10.3,
  /// an absent paper's edge was a blended column at 100% and at 150%
  /// where the paper's own was crisp). ↩️Their corners were carried
  /// through the exact view by hand, off the snap.
  void _layOnTheCanvas(Canvas canvas, Float64List screen) {
    canvas.save();
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    if (pasteboard case final pasteboard?) {
      paintStagePlane(
        canvas,
        canvasSize.pasteboardAt(pasteboardReach).rect,
        pasteboard,
        screen: screen,
      );
    }
    if (paperNone) {
      // Cut where the paper's own edge is cut (F-67-paper-edge,
      // [paintProjectPaper]), so turning the paper off and on moves no edge.
      final antiAlias = displayEdgeAntiAliased(viewport, devicePixelRatio);
      paintAbsentPlane(
        canvas,
        displayEdgeRect(
          canvas,
          canvasSize.canvasRect,
          antiAlias: antiAlias,
          pixelRatio: devicePixelRatio,
        ),
        screen: screen,
        antiAlias: antiAlias,
      );
    }
    canvas.restore();
  }

  @override
  Object get props => (
    backdrop,
    pasteboard,
    pasteboardReach,
    paperNone,
    canvasSize,
    viewport,
    // The pan-phase snap reads it — a monitor move must repaint.
    devicePixelRatio,
  );
}
