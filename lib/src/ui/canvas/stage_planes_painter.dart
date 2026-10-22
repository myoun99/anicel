import 'package:flutter/widgets.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../repaint_props.dart';
import 'canvas_viewport_offset.dart';
import 'paper_background.dart' show paintAlphaCheckerboard;

/// One plane of the stage (R3b): its colour and whether it is there at all
/// (F-114) — one value, so a colour never travels without its absence.
typedef StagePlane = ({Color color, bool none});

/// The stage's planes behind a cut seen through no camera (R3b): the
/// opaque BACKDROP over the box, the RGBA PASTEBOARD over the region it
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
/// for the three ([_paintPlane]). A paper that is there stays the layer
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

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    // 🚨 Clip to our own box, because the quad below is built in VIEWPORT
    // coordinates and therefore reaches as far as the pasteboard does — up
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
    // allocation finally failed. One `drawPath`.
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
      _paintPlane(canvas, box, null, backdrop);
    }
    if (pasteboard case final pasteboard?) {
      _paintPlane(
        canvas,
        box,
        _quad(canvasSize.pasteboardAt(pasteboardReach).rect),
        pasteboard,
      );
    }
    if (paperNone) {
      _paintPlane(
        canvas,
        box,
        _quad(canvasSize.canvasRect),
        (color: const Color(0x00000000), none: true),
      );
    }
    canvas.restore();
  }

  /// One plane over [region] — the whole [box] when null: the checkerboard
  /// when the plane is absent, otherwise its colour wherever that has any
  /// alpha. The plane rides as ONE value, its colour and whether it is there.
  ///
  /// ⚠️The box as a RECT, not a path: the backdrop is the box itself, and
  /// the clip test asks the first recorded path whether it escapes the box
  /// — the pasteboard's quad does, a box-shaped path cannot.
  static void _paintPlane(
    Canvas canvas,
    Rect box,
    Path? region,
    StagePlane plane,
  ) {
    final (:color, :none) = plane;
    if (none) {
      canvas.save();
      if (region != null) {
        canvas.clipPath(region);
      }
      paintAlphaCheckerboard(canvas, box);
      canvas.restore();
      return;
    }
    if (color.a <= 0) {
      return;
    }
    final paint = Paint()..color = color;
    if (region == null) {
      canvas.drawRect(box, paint);
    } else {
      canvas.drawPath(region, paint);
    }
  }

  /// [rect]'s four corners through the view transform, as a PATH: under
  /// rotation a plane is a quad, and a Rect would silently square it back up.
  Path _quad(Rect rect) {
    Offset at(double x, double y) =>
        viewport.canvasToViewportOffset(CanvasPoint(x: x, y: y));

    return Path()
      ..moveTo(at(rect.left, rect.top).dx, at(rect.left, rect.top).dy)
      ..lineTo(at(rect.right, rect.top).dx, at(rect.right, rect.top).dy)
      ..lineTo(at(rect.right, rect.bottom).dx, at(rect.right, rect.bottom).dy)
      ..lineTo(at(rect.left, rect.bottom).dx, at(rect.left, rect.bottom).dy)
      ..close();
  }

  @override
  Object get props => (
    backdrop,
    pasteboard,
    pasteboardReach,
    paperNone,
    canvasSize,
    viewport,
  );
}
