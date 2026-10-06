import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/convex_clip.dart' show convexContains, convexInset;
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/brush_edit_session_state.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/canvas_selection_paint_clip.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../../services/layer_pose_paint.dart'
    show
        LayerPlacement,
        canvasToArtwork,
        placementMatrix,
        placementViewportWrapMatrix;
import '../brush/brush_tool_state.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/bitmap_surface_painter.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet_painting.dart'
    show
        SheetDeviceGrid,
        SheetPictureOverInk,
        pictureCanvasViewport,
        pictureOutline,
        pictureShowsOnScreen;
import '../widgets/cursor_notice.dart' show cursorNotices;

/// A window the sheet's brush draws through: where it sits on the paper,
/// how the brush sees its surface, and which of that surface's pixels it
/// can show — for the sheet's own ink ([SheetInkWindow]) and for a picture
/// that draws into a cel ([SheetPictureWindow]) alike, so [SheetInkLayer]
/// asks nothing about which one it holds.
@immutable
sealed class SheetWindow {
  const SheetWindow({required this.id, required this.key, this.plane});

  /// WHICH of the panel's planes this window belongs to — the timesheet's
  /// page/strip, the conte's paper/cell/picture. ⛔This layer never reads
  /// it: it hands the window back to [SheetInkLayer.sessionStateFor] and
  /// [SheetInkLayer.onStrokeCommitted], and the panel that made the window
  /// is the only thing that knows what its planes mean. A sheet with one
  /// plane (the envelope) leaves it null.
  final Object? plane;

  /// Identifies the WINDOW, not the surface.
  ///
  /// The same strip band surface appears through TWO windows on a paged
  /// timesheet (the page's left and right halves), so the frame key cannot
  /// stand in for this.
  final String id;

  final BrushFrameKey key;

  /// The window's rect in the sheet's document space.
  Rect get documentRect;

  /// The viewport the interactive brush view needs so surface pixel (x, y)
  /// lands exactly where the sheet shows it.
  CanvasViewport inkViewport(CanvasViewport panelViewport);

  /// [paper], an outline in the sheet's document space, in this window's
  /// SURFACE pixels.
  CanvasSelectionShape surfaceShapeOf(List<Offset> paper);

  /// What of the paper this window takes — its rect, unless it shows less
  /// of it: a picture's slot, only where its canvas is. The windows
  /// under it keep the rest ([sheetInkRegions]), and a press there is its.
  List<Offset> get paperOutline => [
    documentRect.topLeft,
    documentRect.topRight,
    documentRect.bottomRight,
    documentRect.bottomLeft,
  ];

  /// Which of its surface's pixels this window shows at all, before the
  /// windows stacked above it take theirs ([sheetInkRegions]).
  CanvasSelectionRegion? get shows;

  /// Where on the screen this window shows its own surface, so that no
  /// window under it shows its there: its rect, or where a picture shows
  /// its cut's canvas ([SheetPictureWindow]) — on [grid], the one rounding
  /// every edge of the sheet goes through (F-216).
  Path takesOnScreen(SheetDeviceGrid grid, CanvasViewport panelViewport) =>
      Path()..addRect(shownOn(grid));

  /// The window's rect as the screen shows it: cut on [grid] — the one
  /// rounding every edge of the sheet goes through — so the live frame and
  /// the print clip the same whole pixels, whichever space they reach the
  /// rect from (F-215: a book's live layer reaches its pages' windows moved
  /// down the stack, each page's print reaches them where they lie, and
  /// the unrounded corner of one came out a level apart). Nearest lines: a
  /// pixel on the edge two windows share is exactly one of theirs.
  Rect shownOn(SheetDeviceGrid grid) => grid.snap(documentRect);

  /// How this window's view is LAID on the screen past what its viewport
  /// says ([inkViewport]) — null where the viewport says it all.
  ///
  /// A view draws through a pan, a zoom and a turn, and a viewport holds
  /// nothing else. What a window shows otherwise — the sheet's ink wider
  /// than its surface's own shape, a picture's cel where its row's placement
  /// puts it — is laid over the view, and a press reaches the view back
  /// through the same map, so the brush writes the pixel under the pen.
  /// ONE answer for the live views ([SheetInkLayer]) and for the print
  /// ([printSheetInkAsLive]).
  Matrix4? viewLaidBy(CanvasViewport panelViewport) => null;

  /// The live stroke's overlay when SOMEONE ELSE paints this window's
  /// surface, in its place in a composite — a picture's cel inside the
  /// cut's composite. Null when the window's own view paints it.
  ActiveStrokeOverlayModel? get overlay => null;

  /// Why this window takes no ink, said at the cursor when a press lands on
  /// it — the canvas's answer on an empty cell it may not fill. Null while
  /// it takes ink.
  ///
  /// A refusing window still covers what lies under it: nothing of a stroke
  /// is kept where it shows, by it or by the paper below.
  String? get refusal => null;

  /// Whether a stroke this window takes is kept only where the window
  /// shows it ([sheetInkRegions]) — the sheet's own ink is (유저
  /// 2026-09-30, H49: 「일반칸은 일반칸내에서만 지정된 범위 안에서만」); a
  /// picture keeps the whole stroke ([SheetPictureWindow]).
  bool get keepsOnlyWhatItShows => true;

  /// The same window on a page that lies [by] further on in a stack of
  /// pages (F-201): one layer hears the strokes of every page on screen, so
  /// its windows must stand in ONE space — two pages' first cells share a
  /// rect on their own pages, and would take each other's ink
  /// ([sheetInkRegions]). The surface under it does not move.
  SheetWindow shiftedBy(Offset by);

  /// The window's on-screen rect under the panel transform, unrounded —
  /// where its view lays its surface ([viewLaidBy]). What the screen
  /// shows of it is cut on the grid ([shownOn]).
  Rect screenRect(CanvasViewport panelViewport) => Rect.fromLTWH(
    panelViewport.panX + panelViewport.zoom * documentRect.left,
    panelViewport.panY + panelViewport.zoom * documentRect.top,
    panelViewport.zoom * documentRect.width,
    panelViewport.zoom * documentRect.height,
  );
}

/// 🚨★★★ONE ON-SHEET INK WINDOW, for every sheet that has them.
///
/// The timesheet, the conte and the cut envelope each had their own
/// `XInkWindow` + `XInkLayer` + a private `_WindowRectClipper`, and an
/// audit on 2026-08-28 (유저: 「사본은 특히 위험한대상이야」) found the
/// three [screenRect] bodies **byte-identical** and the three `build`
/// methods identical down to their comments. Only three things actually
/// differed: the widget-key prefix, whether the panel has a plane axis,
/// and where the ink scale came from.
///
/// ⛔THE THREE [inkViewport] FORMULAS WERE ALREADY ONE. The conte and the
/// envelope map surface pixel (0,0) to the window's top-left; the
/// timesheet maps [inkOffset] there instead. With `inkOffset` at the
/// origin the timesheet's expression IS the other two, term for term — so
/// this is one law with a default, not a law with an exception.
class SheetInkWindow extends SheetWindow {
  const SheetInkWindow({
    required super.id,
    required super.key,
    required this.placement,
    super.plane,
    this.refusal,
  });

  /// The window of an ink mark a sheet's walk yields — the walk the sheet's
  /// printers read too, so the brush writes where the paper shows.
  SheetInkWindow.of(
    SheetInk ink, {
    required String id,
    Object? plane,
    String? refusal,
  }) : this(
         id: id,
         key: ink.key,
         placement: ink.placement,
         plane: plane,
         refusal: refusal,
       );

  @override
  final String? refusal;

  /// Where this window shows its surface — the one mapping between ink
  /// pixels and the paper the printers lay the ink back by.
  final SheetInkPlacement placement;

  @override
  Rect get documentRect => placement.window;

  /// Ink-surface pixels per document unit.
  double get surfaceScale => placement.scale;

  /// Ink-surface pixel that maps to [documentRect]'s top-left.
  Offset get inkOffset => placement.origin;

  /// [SheetInkPlacement.stretch] times as wide from the window's left edge
  /// on screen — null where it is not stretched.
  @override
  Matrix4? viewLaidBy(CanvasViewport panelViewport) {
    final stretch = placement.stretch;
    if (stretch == 1) {
      return null;
    }
    final left = screenRect(panelViewport).left;
    return Matrix4.identity()
      ..translateByDouble(left, 0, 0, 1)
      ..scaleByDouble(stretch, 1, 1, 1)
      ..translateByDouble(-left, 0, 0, 1);
  }

  /// The panel transform composed with where surface pixel (0, 0) lies on
  /// the paper — the window at its surface's own shape
  /// ([SheetInkPlacement.unstretched]): a stretched window's view is laid
  /// wider by the layer ([SheetInkLayer]), which hands the brush the press
  /// where the view has it.
  @override
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    final origin = placement.unstretched.paperOf(Offset.zero);
    return CanvasViewport(
      zoom: panelViewport.zoom / placement.scale,
      panX: panelViewport.panX + panelViewport.zoom * origin.dx,
      panY: panelViewport.panY + panelViewport.zoom * origin.dy,
    );
  }

  /// The window's slice of its ink surface, in SURFACE pixels.
  Rect get surfaceRect => placement.surfaceRect;

  @override
  CanvasSelectionShape surfaceShapeOf(List<Offset> paper) =>
      _outlineShape([for (final point in paper) placement.pixelOf(point)]);

  @override
  CanvasSelectionRegion? get shows => refusal != null
      ? null
      : CanvasSelectionRegion.shape(_surfaceShape(surfaceRect));

  /// This window as the mark a printer lays its ink by.
  SheetInk get mark =>
      SheetInk(SheetPaintLayer.ink, key: key, placement: placement);

  @override
  SheetInkWindow shiftedBy(Offset by) => SheetInkWindow(
    id: id,
    key: key,
    placement: placement.shiftedBy(by),
    plane: plane,
    refusal: refusal,
  );
}

/// A PICTURE the brush draws into: a cel a sheet shows in a slot, seen
/// through the camera and the layer's placement — the conte's picture,
/// whose part of a stroke goes to its block's cel (유저 2026-09-25,
/// conte-drawing-target: 「그림 칸 안의 부분은 그 블록의 콘티 레이어
/// 그림으로」).
///
/// ⛔ONE map, the printer's: [canvasToPaper] is the camera
/// (`cameraProjectionMatrix`) and the slot's contain (`containRect`), and
/// [placement] the layer's (`layerPlacementAt`) — the ones the picture is
/// painted with, so the pen lands where the picture shows the stroke.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)」. The camera and the slot are each a zoom, a turn and a move, so
/// the canvas they show is one brush viewport ([inkViewport]). A row's
/// placement no longer is one, so it is not in that viewport: the view
/// sees the cut's CANVAS and is laid through the placement ([viewLaidBy]) —
/// the main canvas's own draw-through wrap (`placementViewportWrapMatrix`).
/// ↩️The whole chain, placement and all, was read back as one viewport
/// (`viewportOfSimilarity(…)!`). A row stretched along one axis, or
/// flipped, has none to read, and the unwrap threw.
class SheetPictureWindow extends SheetWindow {
  const SheetPictureWindow({
    required super.id,
    required super.key,
    super.plane,
    required this.picture,
    required this.placement,
    required this.overlay,
    this.refusal,
  });

  /// The picture as the sheet prints it, where its cut's canvas lies on
  /// the paper and the map that lays it there — THE shape the pen takes
  /// ([paperOutline]), the one the paper's ink yields to on screen
  /// ([takesOnScreen]) and the map the print is laid by (F-215).
  final SheetPictureOverInk picture;

  /// Where the picture sits on the paper.
  Rect get slot => picture.picture.slot;

  /// What the picture shows of its slot — the outline the sheet clips it
  /// to, as its corners on the paper: in the slot's rounded corners, and
  /// only where its canvas is, since a picture is cropped at the canvas
  /// after the placement (「페이스트보드는 포함 안 시킴」). The rest of the
  /// slot is the windows' under it: a stroke there shows, so it is kept.
  @override
  List<Offset> get paperOutline => pictureOutline(picture);

  /// Where its live composite shows the cut's canvas on [grid] — cut
  /// INSIDE (F-197), the same call the composite is clipped by, and the one
  /// the print's ink yields to (F-215).
  @override
  Path takesOnScreen(SheetDeviceGrid grid, CanvasViewport panelViewport) =>
      pictureShowsOnScreen(grid, picture);

  @override
  final String? refusal;

  /// A stroke that leaves the picture goes on into its cut's canvas, past
  /// the camera (유저 2026-09-30, H49: 「밖으로 나가면 해당 캔버스의 카메라
  /// 밖 영역에 그리긴 하게. 픽쳐칸만 칸 외부공간이 있으니」) — drawn as the
  /// canvas draws it.
  @override
  bool get keepsOnlyWhatItShows => false;

  /// The picture is painted live in the cut's composite while the brush is
  /// on, its stroke in the cel's place there (유저 답 conte-picture-display-Q1
  /// 「실시간 합성 (정확)」) — so its view hands the painter this and paints
  /// nothing itself.
  @override
  final ActiveStrokeOverlayModel overlay;

  /// The cut's canvas → the paper.
  Matrix4 get canvasToPaper => picture.canvasToPaper;

  /// Where the cel's own pixels lie on the cut's canvas — null for a row
  /// that lies as it is drawn.
  final LayerPlacement? placement;

  @override
  Rect get documentRect => slot;

  Matrix4 get _artworkToPaper => switch (placement) {
    null => canvasToPaper,
    final placement => canvasToPaper.multiplied(placementMatrix(placement)),
  };

  /// The view the cut's CANVAS is seen through — the one its live composite
  /// is drawn through ([pictureCanvasViewport]). The cel's own pixels are
  /// laid on that canvas by [viewLaidBy].
  @override
  CanvasViewport inkViewport(CanvasViewport panelViewport) =>
      pictureCanvasViewport(panelViewport, canvasToPaper);

  /// The row's placement, as the main canvas lays its own over its view:
  /// the wrap shows the cel placed, and a press comes back through it into
  /// the cel's own pixels.
  ///
  /// ⛔ALWAYS a matrix — the identity for a row that lies as it is drawn. A
  /// view that changes parent is a view mounted again (the main canvas's
  /// lesson, F-195), and a row's placement comes and goes with a key on a
  /// lane.
  @override
  Matrix4 viewLaidBy(CanvasViewport panelViewport) => switch (placement) {
    null => Matrix4.identity(),
    final placement => placementViewportWrapMatrix(
      placement,
      inkViewport(panelViewport),
    ),
  };

  @override
  CanvasSelectionShape surfaceShapeOf(List<Offset> paper) {
    final toArtwork = Matrix4.inverted(_artworkToPaper);
    return _outlineShape([
      for (final point in paper) MatrixUtils.transformPoint(toArtwork, point),
    ]);
  }

  /// Its [paperOutline], and nothing where that is no outline at all — a
  /// camera framing none of the canvas — or where the row's placement has
  /// collapsed it: a cel that shows nothing has no pixel under the pen
  /// ([canvasToArtwork]).
  @override
  CanvasSelectionRegion? get shows =>
      refusal != null || paperOutline.length < 3 || _collapsed
      ? null
      : CanvasSelectionRegion.shape(surfaceShapeOf(paperOutline));

  bool get _collapsed => switch (placement) {
    null => false,
    final placement => canvasToArtwork(placement) == null,
  };

  @override
  SheetPictureWindow shiftedBy(Offset by) {
    return SheetPictureWindow(
      id: id,
      key: key,
      plane: plane,
      picture: (
        picture: picture.picture.shiftedBy(by),
        canvas: [for (final point in picture.canvas) point + by],
        canvasToPaper: Matrix4.translationValues(
          by.dx,
          by.dy,
          0,
        ).multiplied(canvasToPaper),
      ),
      placement: placement,
      overlay: overlay,
      refusal: refusal,
    );
  }
}

/// [points] as the outline they make.
CanvasSelectionShape _outlineShape(List<Offset> points) =>
    CanvasSelectionShape([
      for (final point in points) CanvasPoint(x: point.dx, y: point.dy),
    ]);

/// Something over a window that takes the screen from it where it shows
/// its own: its [rect] on the paper, and the shape it [takes] on a grid.
typedef SheetInkAbove = ({Rect rect, Path Function(SheetDeviceGrid grid) takes});

/// [window] as one standing over another ([SheetWindow.takesOnScreen]).
SheetInkAbove sheetInkAbove(SheetWindow window, CanvasViewport viewport) => (
  rect: window.documentRect,
  takes: (grid) => window.takesOnScreen(grid, viewport),
);

/// [over] as a picture standing over the paper's ink
/// ([pictureShowsOnScreen]) — the print's stand-in for its window, which
/// only the brush mounts.
SheetInkAbove sheetInkAbovePicture(SheetPictureOverInk over) => (
  rect: over.picture.slot,
  takes: (grid) => pictureShowsOnScreen(grid, over),
);

/// Where a [window] shows its own surface on screen: its rect on the grid
/// ([SheetWindow.shownOn]), less what it [yieldsTo] there.
typedef SheetInkShown = ({SheetWindow window, Rect shows, List<Path> yieldsTo});

/// Where each of [windows] shows its own surface on screen, in their order:
/// each yields to every window after it and to [above] where they overlap
/// it (F-216). ONE answer for the live frames ([SheetInkLayer]) and for the
/// print ([printSheetInkAsLive]) — the brush switch must not move a pixel
/// of the ink (F-215, 유저 2026-10-01: 「허용 on하면 칸 잉크는 선명해지고
/// 살짝오른쪽이동 … 대체 왜?」).
List<SheetInkShown> sheetInkWindowsShown(
  List<SheetWindow> windows,
  List<SheetInkAbove> above,
  SheetDeviceGrid grid,
  CanvasViewport viewport,
) => [
  for (var index = 0; index < windows.length; index += 1)
    (
      window: windows[index],
      shows: windows[index].shownOn(grid),
      yieldsTo: [
        for (final upper in [
          for (final later in windows.skip(index + 1))
            sheetInkAbove(later, viewport),
          ...above,
        ])
          if (upper.rect.overlaps(windows[index].documentRect))
            upper.takes(grid),
      ],
    ),
];

/// [shows] less each of [yieldsTo] — null when it yields nothing, and a
/// plain rect, hard-edged, clips it.
Path? sheetInkShownCut(Rect shows, List<Path> yieldsTo) {
  if (yieldsTo.isEmpty) {
    return null;
  }
  var shown = Path()..addRect(shows);
  for (final upper in yieldsTo) {
    shown = Path.combine(PathOperation.difference, shown, upper);
  }
  return shown;
}

/// What the print of a sheet's ink is laid through: the panel's
/// [viewport] at [devicePixelRatio] over a box of [size], and what stands
/// over all its windows ([above]).
typedef SheetInkPrintView = ({
  CanvasViewport viewport,
  double devicePixelRatio,
  Size size,
  List<SheetInkAbove> above,
});

/// Prints [ink] on screen as the layer's live views paint it (F-215): each
/// window's surface ([surfaceFor] — null for a window a live view is
/// showing, or with no ink) clipped where its frame clips the view
/// ([sheetInkWindowsShown]), laid as wide as the layer lays it, and drawn
/// by the brush view's own painter at the window's ink viewport — its
/// snap, its levels, its sampling. The brush switch only mounts the views;
/// it does not change a pixel. ↩️It drew the surface's whole raster in
/// paper space, `medium`-filtered and snapped with the PAGE's view: the
/// ink went soft and slid by up to a pixel as the switch was flipped.
///
/// It IS the surface the moment it is the surface — a pen-up, an undo, a
/// redo (유저 절대규칙 2026-09-17 「보이는 중이랑 결과랑 절대로 다르면 안
/// 되」): the painter draws its tiles' pictures, made where they are
/// missing through the one synchronous door, with nothing to wait for.
void printSheetInkAsLive(
  Canvas canvas,
  List<SheetInk> ink,
  BitmapSurface? Function(BrushFrameKey key) surfaceFor,
  SheetInkPrintView view,
) {
  final windows = [
    for (final mark in ink) SheetInkWindow.of(mark, id: 'print-${mark.key}'),
  ];
  final grid = SheetDeviceGrid.through(view.viewport, view.devicePixelRatio);
  for (final shown in sheetInkWindowsShown(
    windows,
    view.above,
    grid,
    view.viewport,
  )) {
    final surface = surfaceFor(shown.window.key);
    if (surface == null) {
      continue;
    }
    final window = shown.window;
    canvas.save();
    final cut = sheetInkShownCut(shown.shows, shown.yieldsTo);
    if (cut == null) {
      canvas.clipRect(shown.shows, doAntiAlias: false);
    } else {
      canvas.clipPath(cut);
    }
    if (window.viewLaidBy(view.viewport) case final laid?) {
      canvas.transform(laid.storage);
    }
    BitmapSurfacePainter(
      surface: surface,
      viewport: window.inkViewport(view.viewport),
      showTransparentBackground: false,
      lineage: (window.key.layerId, window.key.frameId),
      devicePixelRatio: view.devicePixelRatio,
    ).paint(canvas, view.size);
    canvas.restore();
  }
}

/// How a sheet's painter prints its ink on screen — a [viewport] and the
/// ink's surfaces ([inkSurfaceFor]) — as the live windows draw it
/// ([printSheetInkAsLive]), ONE way for the conte's, the envelope's and the
/// timesheet's painters (F-215). An export hands in rasters and no
/// surfaces, and the painter lays those in paper space itself.
mixin SheetInkOnScreen {
  CanvasViewport? get viewport;
  double get effectiveRatio;
  BitmapSurface? Function(BrushFrameKey key)? get inkSurfaceFor;

  /// Keys a live window is showing: not printed again, so translucent ink
  /// never composites twice.
  Set<BrushFrameKey> get liveInkKeys;

  /// Prints [ink] as the live windows draw it, the pictures [above] taking
  /// their place over it — nothing without a view and surfaces (an
  /// export).
  void printInkAsLive(
    Canvas canvas,
    Size size,
    List<SheetInk> ink, {
    List<SheetInkAbove> above = const [],
  }) {
    final view = viewport;
    final surfaceFor = inkSurfaceFor;
    if (view == null || surfaceFor == null) {
      return;
    }
    printSheetInkAsLive(
      canvas,
      ink,
      (key) => liveInkKeys.contains(key) ? null : surfaceFor(key),
      (
        viewport: view,
        devicePixelRatio: effectiveRatio,
        size: size,
        above: above,
      ),
    );
  }
}

/// Where each of [windows] keeps ink, in its OWN surface's pixels: what it
/// [SheetWindow.shows], less every window stacked above it — and a ring of
/// [sheetInkApron] past the edge of a window above it, which the screen
/// never shows it in ([SheetWindow.takesOnScreen]). Null for a window the
/// ones above cover whole — it keeps nothing, so it is not mounted.
///
/// 🚨★★★A STROKE IS THE WINDOW'S IT STARTS IN (유저 2026-09-30, H49: 「그냥
/// 선 시작한곳에따라 칸 나누자 … 일반칸은 일반칸내에서만 지정된 범위
/// 안에서만 그려지도록」): the window on top where the pen lands takes the
/// whole stroke ([sheetInkOwnerAt]), and a window of the sheet's own ink
/// keeps of it only this — what it shows. A picture keeps all of it: a
/// stroke that leaves the picture goes on into its cut's canvas, past the
/// camera (「밖으로 나가면 해당 캔버스의 카메라 밖 영역에 그리긴 하게」).
///
/// ↩️Twice over. A stroke first belonged to the window it started in and
/// ran on over its neighbours unclipped — into the paper's ink across a
/// strip or a box, off the bottom of a paged timesheet's left half into
/// the top of the right one, the same band surface. Then every window took
/// the piece of every stroke drawn over it (유저 2026-09-25,
/// conte-drawing-target: 「진짜 하나의 용지처럼」), until the user split
/// the strokes by where they start again.
List<CanvasSelectionRegion?> sheetInkRegions(List<SheetWindow> windows) => [
  for (var index = 0; index < windows.length; index += 1)
    _inkRegionOf(windows[index], windows.skip(index + 1)),
];

CanvasSelectionRegion? _inkRegionOf(
  SheetWindow window,
  Iterable<SheetWindow> above,
) {
  var region = window.shows;
  for (final upper in above) {
    if (region == null) {
      break;
    }
    final taken = convexInset(upper.paperOutline, sheetInkApron);
    if (taken.length < 3 || !upper.documentRect.overlaps(window.documentRect)) {
      continue;
    }
    region = region.combinedWith(
      window.surfaceShapeOf(taken),
      SelectionCombineMode.subtract,
    );
  }
  return region;
}

/// The window a stroke that lands at paper point [paper] belongs to: the
/// topmost of [windows] whose outline holds it — a refusing one too, which
/// keeps the stroke from the windows under it — or null off every window.
SheetWindow? sheetInkOwnerAt(List<SheetWindow> windows, Offset paper) {
  for (final window in windows.reversed) {
    if (convexContains(window.paperOutline, paper)) {
      return window;
    }
  }
  return null;
}

/// How far, in paper units, a window keeps a stroke on past the edge of a
/// window stacked above it (F-216, 유저 2026-09-28: 「칸 사이에 흰 빈공간이
/// 존재. 줌 배율에 따라 사라지거나 생기거나 함 … 근본/구조적으로 해결」).
///
/// The screen shows each window up to an edge cut on the device grid —
/// never where the edge lies on the paper — and a surface keeps its pixels
/// on its own grid: the conte's paper ink a point a pixel. A stroke stopped
/// exactly at the edge left a sliver of the pixel the edge falls in that
/// nothing held: measured one to three device pixels, white where the
/// print under the picture showed, black where the silhouette did. Three
/// points hold a device pixel at 50% on a 1× screen and the pixel the edge
/// falls in.
const double sheetInkApron = 3;

CanvasSelectionShape _surfaceShape(Rect rect) => CanvasSelectionShape.rect(
  left: rect.left,
  top: rect.top,
  right: rect.right,
  bottom: rect.bottom,
);

/// The live ink input windows for ONE sheet panel, bottom-of-stack first.
///
/// The caller keeps its own controller and its own plane axis: it answers
/// [sessionStateFor] and [onStrokeCommitted] for a window and this widget
/// asks nothing about what a plane is. That is what let three panels with
/// three different controller shapes mount ink through one widget.
///
/// The window on top where the pen lands hears the stroke, the whole of it
/// ([sheetInkOwnerAt]; [sheetInkRegions] says what it keeps), and the
/// layer takes the press once for them all: with the brush on, what lies
/// under it — the header's editors, the cells' taps — is not reachable
/// (the switch doubles as the edit-mode switch).
class SheetInkLayer extends StatefulWidget {
  const SheetInkLayer({
    super.key,
    required this.windows,
    required this.keyPrefix,
    required this.viewport,
    required this.brushToolState,
    required this.strokeActive,
    required this.history,
    required this.sessionStateFor,
    required this.onStrokeCommitted,
  });

  final List<SheetWindow> windows;

  /// Widget-key prefix — `timesheet`, `conte`, `envelope`. Each window's
  /// key is `<prefix>-ink-<window id>`, which is what the panels spelled
  /// by hand.
  final String keyPrefix;

  /// The live panel viewport — the same transform the sheet painter takes.
  final CanvasViewport viewport;

  /// The brush in hand — heard, not handed over (H40 ②, 2026-09-24): the
  /// windows read it when a stroke starts, so a brush change rebuilds no
  /// window. The hosts used to rebuild this whole layer on every one.
  final ValueListenable<BrushToolState> brushToolState;

  /// Raised while the pen is down on the sheet, once for the stroke — so
  /// the panel's gesture layer holds navigation exactly as it does for
  /// canvas strokes.
  final ValueNotifier<bool> strokeActive;

  /// Where a stroke's landing becomes ONE step with what was made for it
  /// to land in (the conte's block, its cut — [onStrokeCommitted]'s
  /// caller): the pen-up folds them — the rail swipe's
  /// many-landings-one-undo, said of a stroke.
  final HistoryGestures history;

  final BrushEditSessionState Function(SheetWindow window) sessionStateFor;

  final void Function(SheetWindow window, BrushStrokeCommitData strokeData)
  onStrokeCommitted;

  @override
  State<SheetInkLayer> createState() => _SheetInkLayerState();
}

class _SheetInkLayerState extends State<SheetInkLayer> {
  /// The windows whose view has the stroke in flight.
  final Set<String> _stroking = <String>{};

  /// The history as it stood before the stroke's first landing.
  HistoryMark? _strokeStart;

  void _windowStroking(String id, {required bool active}) {
    final wasDown = _stroking.isNotEmpty;
    if (active) {
      _stroking.add(id);
    } else {
      _stroking.remove(id);
    }
    final down = _stroking.isNotEmpty;
    if (down && !wasDown) {
      _strokeStart = widget.history.mark;
    }
    if (!down && wasDown) {
      final start = _strokeStart;
      _strokeStart = null;
      if (start != null) {
        widget.history.foldSince(start, BrushStrokeHistoryCommand.label);
      }
    }
    widget.strokeActive.value = down;
  }

  /// The stroke [window] took, confined to [keeps] of its surface as it
  /// stands NOW — the canvas selection's funnel — or whole where the window
  /// keeps it all.
  void _land(
    SheetWindow window,
    CanvasSelectionRegion? keeps,
    BrushStrokeCommitData strokeData,
  ) {
    final landed = keeps == null
        ? strokeData
        : clipStrokeCommitToSelection(
            strokeData,
            region: keeps,
            surface: widget.sessionStateFor(window).canvasState.currentSurface,
          );
    if (landed != null) {
      widget.onStrokeCommitted(window, landed);
    }
  }

  /// [position], a point of this layer, on the paper.
  Offset _paperOf(Offset position) {
    final viewport = widget.viewport;
    return (position - Offset(viewport.panX, viewport.panY)) / viewport.zoom;
  }

  /// The refusal of the window a press at [position] lands on, at the
  /// cursor — the canvas's notice for a press on an empty cell it may not
  /// fill.
  void _refuseAt(Offset position) {
    if (sheetInkOwnerAt(widget.windows, _paperOf(position))?.refusal
        case final refusal?) {
      cursorNotices.show(refusal);
    }
  }

  /// A window taken away mid-stroke never reports the stroke's end, and
  /// the pen would stay down for good. After the frame: this runs during
  /// build, and the flag's listeners rebuild widgets.
  void _releaseWindowsGone(Set<String> mountedIds) {
    final gone = [
      for (final id in _stroking)
        if (!mountedIds.contains(id)) id,
    ];
    if (gone.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final id in gone) {
        if (_stroking.contains(id)) {
          _windowStroking(id, active: false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final windows = widget.windows;
    final regions = sheetInkRegions(windows);
    final keeping = [
      for (var index = 0; index < windows.length; index += 1)
        if (regions[index] case final region?)
          (index: index, window: windows[index], region: region),
    ];
    _releaseWindowsGone({for (final entry in keeping) entry.window.id});
    // Where each shows its own (F-216) — what it keeps past the edges of
    // the windows above it is never on screen — the print's answer too
    // (F-215).
    final shown = sheetInkWindowsShown(
      windows,
      const [],
      SheetDeviceGrid.through(
        widget.viewport,
        EffectiveDevicePixelRatio.of(context),
      ),
      widget.viewport,
    );
    // It claims the press, after the window it lands on has heard it — and
    // where that window refuses the pen, says why, as the canvas does.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _refuseAt(event.localPosition),
      child: Stack(
        children: [
          for (final (:index, :window, :region) in keeping)
            Positioned.fill(
              child: _InkWindowFrame(
                shows: shown[index].shows,
                // The press is its own where it is the window on top, and
                // the stroke with it wherever the pen goes after (H49).
                owns: (position) => identical(
                  sheetInkOwnerAt(windows, _paperOf(position)),
                  window,
                ),
                yieldsTo: shown[index].yieldsTo,
                child: RepaintBoundary(
                  child: _laid(window, _view(window, region)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [window]'s brush view: a stroke it takes kept to [region] of its
  /// surface, or whole where the window keeps it all
  /// ([SheetWindow.keepsOnlyWhatItShows]).
  ///
  /// The brush is read as it is, a pixel of its size a pixel of the
  /// surface — the canvas's own reading (유저 2026-09-30, H50: 「원본
  /// 1:1그대로 공용로직 그대로 적용해서 원복하자」). ↩️The conte's paper
  /// read it at the pictures' scale (F-217) while a stroke crossed from a
  /// picture onto the paper; a stroke stays in its window now (H49), and so
  /// scaled a brush drew too thin to hold together.
  Widget _view(SheetWindow window, CanvasSelectionRegion region) {
    final keeps = window.keepsOnlyWhatItShows ? region : null;
    return InteractiveBrushEditCanvasView(
      key: ValueKey<String>('${widget.keyPrefix}-ink-${window.id}'),
      celNow: () => widget.sessionStateFor(window).canvasState.currentSurface,
      layerId: window.key.layerId,
      frameId: window.key.frameId,
      inputSettings: () => widget.brushToolState.value.toInputSettings(),
      viewport: window.inkViewport(widget.viewport),
      selectionRegion: keeps,
      // The sheet paper is painted below this stack; an opaque
      // background here would cover it.
      showTransparentBackground: false,
      // The canvas's MERGED pairing: a surface painted in its place in a
      // composite leaves its view input only.
      overlayModel: window.overlay,
      paintsContent: window.overlay == null,
      onActiveStrokeChanged: (active) =>
          _windowStroking(window.id, active: active),
      onSourceStrokeCommitted: (strokeData) =>
          _land(window, keeps, strokeData),
    );
  }

  /// [view] — a window's — laid as the window says
  /// ([SheetWindow.viewLaidBy]): the sheet's ink wider than its surface's own
  /// shape, a picture's cel where its row's placement puts it. The view
  /// draws through its own viewport ([SheetWindow.inkViewport]) and a press
  /// reaches it back through the same map, so the brush writes the pixel
  /// under the pen.
  Widget _laid(SheetWindow window, Widget view) =>
      switch (window.viewLaidBy(widget.viewport)) {
        final laid? => Transform(transform: laid, child: view),
        null => view,
      };
}

/// A window SHOWS its own rect and HEARS the presses it [owns] — the ones
/// it is the window on top at ([sheetInkOwnerAt]) — and every move of the
/// stroke after, wherever the pen goes: the pointer is its view's. It
/// clips what the view PAINTS, not what it hears.
///
/// ↩️It was a `ClipRect` with a rect clipper — the one `CustomClipper` the
/// 08-28 audit left of three byte-identical copies — which clipped the
/// press by the window's rect; then it heard every press (09-25, one
/// paper), until strokes were split by where they start again (H49).
class _InkWindowFrame extends SingleChildRenderObjectWidget {
  const _InkWindowFrame({
    required this.shows,
    required this.owns,
    required this.yieldsTo,
    required super.child,
  });

  final Rect shows;

  /// Whether a press at a point of the layer is this window's.
  final bool Function(Offset position) owns;

  /// Where windows above this one show theirs — cut out of [shows].
  final List<Path> yieldsTo;

  @override
  _RenderInkWindowFrame createRenderObject(BuildContext context) =>
      _RenderInkWindowFrame(shows, owns, yieldsTo);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInkWindowFrame renderObject,
  ) {
    renderObject
      ..shows = shows
      ..owns = owns
      ..yieldsTo = yieldsTo;
  }
}

class _RenderInkWindowFrame extends RenderProxyBox {
  _RenderInkWindowFrame(this._shows, this.owns, this._yieldsTo);

  /// A hit test's question alone — nothing is painted by it.
  bool Function(Offset position) owns;

  Rect _shows;

  Rect get shows => _shows;

  set shows(Rect value) {
    if (value == _shows) {
      return;
    }
    _shows = value;
    markNeedsPaint();
  }

  List<Path> _yieldsTo;

  List<Path> get yieldsTo => _yieldsTo;

  /// A path has no value equality: any shape to yield to repaints the
  /// frame's clip — never the view under it, which is its own boundary.
  set yieldsTo(List<Path> value) {
    if (value.isEmpty && _yieldsTo.isEmpty) {
      return;
    }
    _yieldsTo = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<ClipPathLayer> _cutClip = LayerHandle<ClipPathLayer>();

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      owns(position) && super.hitTest(result, position: position);

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => _shows;

  @override
  void paint(PaintingContext context, Offset offset) {
    // The print clips by the same cut (printSheetInkAsLive, F-215).
    final cut = sheetInkShownCut(_shows, _yieldsTo);
    if (cut == null) {
      _cutClip.layer = null;
      _clip.layer = context.pushClipRect(
        needsCompositing,
        offset,
        _shows,
        super.paint,
        oldLayer: _clip.layer,
      );
      return;
    }
    _clip.layer = null;
    _cutClip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      _shows,
      cut,
      super.paint,
      oldLayer: _cutClip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _cutClip.layer = null;
    super.dispose();
  }
}
