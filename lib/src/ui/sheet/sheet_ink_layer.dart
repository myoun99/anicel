import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/brush_edit_canvas_input_settings.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
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
import '../../services/viewport_transform_matrix.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';

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

  /// [paper], a rect in the sheet's document space, in this window's
  /// SURFACE pixels.
  CanvasSelectionShape surfaceShapeOf(Rect paper);

  /// Which of its surface's pixels this window shows at all, before the
  /// windows stacked above it take theirs ([sheetInkRegions]).
  CanvasSelectionRegion? get shows;

  /// The live stroke's overlay when SOMEONE ELSE paints this window's
  /// surface, in its place in a composite — a picture's cel inside the
  /// cut's composite. Null when the window's own view paints it.
  ActiveStrokeOverlayModel? get overlay => null;

  /// The window's on-screen rect under the panel transform — what its view
  /// is clipped to on screen.
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
  });

  /// The window of an ink mark a sheet's walk yields — the walk the sheet's
  /// printers read too, so the brush writes where the paper shows.
  SheetInkWindow.of(SheetInk ink, {required String id, Object? plane})
    : this(id: id, key: ink.key, placement: ink.placement, plane: plane);

  /// Where this window shows its surface — the one mapping between ink
  /// pixels and the paper the printers lay the ink back by.
  final SheetInkPlacement placement;

  @override
  Rect get documentRect => placement.window;

  /// Ink-surface pixels per document unit.
  double get surfaceScale => placement.scale;

  /// Ink-surface pixel that maps to [documentRect]'s top-left.
  Offset get inkOffset => placement.origin;

  /// The panel transform composed with where surface pixel (0, 0) lies on
  /// the paper.
  @override
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    final origin = placement.paperOf(Offset.zero);
    return CanvasViewport(
      zoom: panelViewport.zoom / placement.scale,
      panX: panelViewport.panX + panelViewport.zoom * origin.dx,
      panY: panelViewport.panY + panelViewport.zoom * origin.dy,
    );
  }

  /// The window's slice of its ink surface, in SURFACE pixels.
  Rect get surfaceRect => placement.surfaceRect;

  @override
  CanvasSelectionShape surfaceShapeOf(Rect paper) => _surfaceShape(
    Rect.fromPoints(
      placement.pixelOf(paper.topLeft),
      placement.pixelOf(paper.bottomRight),
    ),
  );

  @override
  CanvasSelectionRegion get shows =>
      CanvasSelectionRegion.shape(_surfaceShape(surfaceRect));

  /// This window as the mark a printer lays its ink by.
  SheetInk get mark =>
      SheetInk(SheetPaintLayer.ink, key: key, placement: placement);
}

/// A PICTURE the brush draws into: a cel a sheet shows in a slot, seen
/// through the camera and the layer's placement — the conte's picture,
/// whose part of a stroke goes to its block's cel (유저 2026-09-25,
/// conte-drawing-target: 「그림 칸 안의 부분은 그 블록의 콘티 레이어
/// 그림으로」).
///
/// ⛔ONE map, the printer's: [canvasToPaper] is the camera
/// (`cameraProjectionMatrix`) and the slot's contain (`containRect`), and
/// [artworkToCanvas] the layer's placement (`layerPlacementAt`) — the ones
/// the picture is painted with, so the pen lands where the picture shows
/// the stroke. Every step is a zoom, a turn or a move, so the whole chain
/// is one brush viewport.
class SheetPictureWindow extends SheetWindow {
  const SheetPictureWindow({
    required super.id,
    required super.key,
    super.plane,
    required this.slot,
    required this.canvasToPaper,
    required this.artworkToCanvas,
    required this.canvasSize,
    required this.overlay,
  });

  /// Where the picture sits on the paper.
  final Rect slot;

  /// The picture is painted live in the cut's composite while the brush is
  /// on, its stroke in the cel's place there (유저 답 conte-picture-display-Q1
  /// 「실시간 합성 (정확)」) — so its view hands the painter this and paints
  /// nothing itself.
  @override
  final ActiveStrokeOverlayModel overlay;

  /// The cut's canvas → the paper.
  final Matrix4 canvasToPaper;

  /// The cel's own pixels → the cut's canvas.
  final Matrix4 artworkToCanvas;

  /// The canvas the camera crops the picture at.
  final CanvasSize canvasSize;

  @override
  Rect get documentRect => slot;

  Matrix4 get _artworkToPaper => canvasToPaper.multiplied(artworkToCanvas);

  @override
  CanvasViewport inkViewport(CanvasViewport panelViewport) =>
      viewportOfSimilarity(
        viewportTransformMatrix(panelViewport).multiplied(_artworkToPaper),
      )!;

  @override
  CanvasSelectionShape surfaceShapeOf(Rect paper) =>
      _mappedRect(Matrix4.inverted(_artworkToPaper), paper);

  /// The slot, and only where the canvas is: a picture is cropped at the
  /// canvas after the placement, so artwork the pose carries past the edge
  /// is not in it (「페이스트보드는 포함 안 시킴」).
  @override
  CanvasSelectionRegion? get shows =>
      CanvasSelectionRegion.shape(surfaceShapeOf(slot)).combinedWith(
        _mappedRect(
          Matrix4.inverted(artworkToCanvas),
          Rect.fromLTWH(
            0,
            0,
            canvasSize.width.toDouble(),
            canvasSize.height.toDouble(),
          ),
        ),
        SelectionCombineMode.intersect,
      );
}

/// [rect]'s corners through [map], as the outline they make.
CanvasSelectionShape _mappedRect(Matrix4 map, Rect rect) {
  CanvasPoint corner(Offset paper) {
    final point = MatrixUtils.transformPoint(map, paper);
    return CanvasPoint(x: point.dx, y: point.dy);
  }

  return CanvasSelectionShape([
    corner(rect.topLeft),
    corner(rect.topRight),
    corner(rect.bottomRight),
    corner(rect.bottomLeft),
  ]);
}

/// Where each of [windows] keeps ink, in its OWN surface's pixels: what it
/// [SheetWindow.shows], less every window stacked above it. Null for a
/// window the ones above cover whole — it keeps nothing, so it is not
/// mounted.
///
/// 🚨★★★ONE PAPER (유저 2026-09-25, conte-drawing-target: 「진짜 하나의
/// 용지처럼. 데이터는 나누더라도」 · 「보이는 거 = 결과」). A stroke is
/// every window's at once, and the paper decides which surface keeps each
/// piece of it: the window that SHOWS that spot — the topmost one there.
/// The pieces meet at the window edges, so the line reads as one while
/// every surface keeps only its own.
///
/// ↩️A stroke used to belong to the window it STARTED in (pointer capture)
/// and ran on over its neighbours: into the paper's ink across a strip or
/// a box, and on a paged timesheet off the bottom of the left half into
/// the top of the right one — the same band surface, which that window
/// shows.
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
    if (!upper.documentRect.overlaps(window.documentRect)) {
      continue;
    }
    region = region.combinedWith(
      window.surfaceShapeOf(upper.documentRect),
      SelectionCombineMode.subtract,
    );
  }
  return region;
}

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
/// Every window HEARS every press ([sheetInkRegions] says what each keeps
/// of it), and the layer takes the press once for them all: with the brush
/// on, what lies under it — the header's editors, the cells' taps — is not
/// reachable (the switch doubles as the edit-mode switch).
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

  /// Raised while the pen is down on the sheet — once for the stroke,
  /// however many windows it crosses — so the panel's gesture layer holds
  /// navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  /// Where one stroke's landings become ONE step: every window lands its
  /// own piece on its own surface, and the pen-up folds them — the rail
  /// swipe's many-landings-one-undo, said of a stroke.
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

  /// A window's piece of the stroke, confined to its slice on the surface
  /// as it stands NOW — the canvas selection's funnel. A band surface two
  /// windows share has taken the other half's piece by the time the
  /// second one lands.
  void _land(
    SheetWindow window,
    CanvasSelectionRegion region,
    BrushStrokeCommitData strokeData,
  ) {
    final landed = clipStrokeCommitToSelection(
      strokeData,
      region: region,
      surface: widget.sessionStateFor(window).canvasState.currentSurface,
    );
    if (landed != null) {
      widget.onStrokeCommitted(window, landed);
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
    BrushEditCanvasInputSettings inputSettings() =>
        widget.brushToolState.value.toInputSettings();
    final regions = sheetInkRegions(widget.windows);
    final keeping = [
      for (var index = 0; index < widget.windows.length; index += 1)
        if (regions[index] case final region?)
          (window: widget.windows[index], region: region),
    ];
    _releaseWindowsGone({for (final entry in keeping) entry.window.id});
    // No callbacks: it only claims the press, after every window has
    // heard it.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          for (final (:window, :region) in keeping)
            Positioned.fill(
              child: _InkWindowFrame(
                shows: window.screenRect(widget.viewport),
                child: RepaintBoundary(
                  child: InteractiveBrushEditCanvasView(
                    key: ValueKey<String>(
                      '${widget.keyPrefix}-ink-${window.id}',
                    ),
                    sessionState: widget.sessionStateFor(window),
                    layerId: window.key.layerId,
                    frameId: window.key.frameId,
                    inputSettings: inputSettings,
                    viewport: window.inkViewport(widget.viewport),
                    selectionRegion: region,
                    // The sheet paper is painted below this stack; an
                    // opaque background here would cover it.
                    showTransparentBackground: false,
                    // The canvas's MERGED pairing: a surface painted in its
                    // place in a composite leaves its view input only.
                    overlayModel: window.overlay,
                    paintsContent: window.overlay == null,
                    onActiveStrokeChanged: (active) =>
                        _windowStroking(window.id, active: active),
                    onSourceStrokeCommitted: (strokeData) =>
                        _land(window, region, strokeData),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A window SHOWS its own rect and HEARS the whole layer.
///
/// It hit-tests its view and never claims the hit, so the Stack offers the
/// press to every window under it too; and it clips what the view PAINTS,
/// not what it hears.
///
/// ↩️It was a `ClipRect` with a rect clipper — the one `CustomClipper` the
/// 08-28 audit left of three byte-identical copies — which clips both: a
/// press outside the window fell through to the one below, and the stroke
/// stayed with the window it started in.
class _InkWindowFrame extends SingleChildRenderObjectWidget {
  const _InkWindowFrame({required this.shows, required super.child});

  final Rect shows;

  @override
  _RenderInkWindowFrame createRenderObject(BuildContext context) =>
      _RenderInkWindowFrame(shows);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInkWindowFrame renderObject,
  ) {
    renderObject.shows = shows;
  }
}

class _RenderInkWindowFrame extends RenderProxyBox {
  _RenderInkWindowFrame(this._shows);

  Rect _shows;

  Rect get shows => _shows;

  set shows(Rect value) {
    if (value == _shows) {
      return;
    }
    _shows = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    super.hitTest(result, position: position);
    return false;
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => _shows;

  @override
  void paint(PaintingContext context, Offset offset) {
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      _shows,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
