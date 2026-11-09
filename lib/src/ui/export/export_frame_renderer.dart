import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;

import '../../models/camera_path_settings.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cel_number_letters.dart' show celNumberText;
import '../../models/cut.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../../models/cut_id.dart';
import '../../models/drawing_guide.dart' show DrawingGuide;
import '../../models/export_format_selection.dart';
import '../../models/export_spec.dart' show ExportLayerFx;
import '../../models/frame.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/import/import_warning.dart'
    show ImportWarning, layerEffectsNotApplied, unsupportedLayerKind;
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/onion_skin_settings.dart' show OnionSkinPlacement;
import '../../models/transition_geometry.dart'
    show TransitionVeil, cutTransitionVeilsAt;
import '../../models/composite_tree.dart';
import '../../services/cel_numbered_row.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../../services/layer_as_output.dart';
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../text/se_name_tag_paint.dart';
import '../../services/playback/playback_frame_mapping.dart'
    show
        TrackStackContribution,
        TransitionContribution,
        resolveTrackStackContributions,
        resolveTransitionContributions,
        sourceOverWeights,
        trackGroupSourceOverWeights;
import '../../services/camera_frame_corners.dart'
    show
        CameraView,
        cameraFrameCornersInCanvas,
        cameraViewOver;
import '../../models/sheet_marks.dart' show SheetMark;
import '../../models/sheet_paint_layer.dart';
import '../../services/camera_path.dart';
import '../camera/camera_frame_overlay.dart' show paintCameraDim;
import '../camera/camera_path_overlay.dart';
import '../canvas/canvas_layer_stack_view.dart'
    show
        CanvasActiveLayerRow,
        CanvasLayerImageRequest,
        CanvasStackRow,
        FramePage;
import '../canvas/guide_overlay.dart' show paintGuideLines;
import '../conte/conte_fonts.dart' show conteTextStyle;
import '../sheet_painting.dart';
import '../../services/composite_effect_paint.dart' show alphaOnly;
import '../editor_session_manager.dart';
import '../frame_shots.dart';
import '../playback/stacked_frame_picture.dart' show stackOfDrawnCels;
import '../../services/playback/frame_demand.dart';
import '../playback/playback_frame_painter.dart';
import '../playback/transition_veil_paint.dart';
import '../track_effect_paint_policy.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'export_cel_group_plan.dart';
import '../../services/se_name_tag_plan.dart';
import '../timeline/memo_token.dart';
import 'export_plan.dart';
import 'held_pictures.dart';
import 'offscreen_raster.dart';
import 'still_image_encoders.dart'
    show ExportLayerFolder, ExportLayerNode, ExportLayerRow;
import '../text/app_strings.dart';

/// The ground a frame is rendered on unless a caller names another — what
/// the storyboard's and the conte's pictures stand on, and so what a conte
/// picture drawn live stands on too.
const ui.Color exportFrameGround = ui.Color(0xFFFFFFFF);

/// A row of a label-group cel ([ExportFrameRenderer.renderCelGroup]): the
/// row and the cut it is a row of, its drawing there, the effects it
/// wears, and where its file's picture stands on the paper — its reference
/// fx alone, null for every other row.
///
/// 🗣️I-65-Q7 (유저 2026-10-25): 「참조 fx 만 따른다」 — 「트랜스폼은 기본만켬에서
/// 빠진다고 몇번이나 말했잖아」: a cel goes out on its paper, so the row's
/// transform never moves it; the reference fx says where a file's picture
/// stands on that paper, so it is the paper's, and the tab's 레이어 FX keeps
/// it as every tab's does ([layerAsOutput] — 켬 · 기본만 켬 keep it, 끔
/// lays the picture where its pixels are). ↩️A cel left it out under all
/// three.
typedef _CelRow = ({
  Cut cut,
  Layer layer,
  Frame frame,
  List<ResolvedLayerEffect> effects,
  LayerPlacement? placement,
});

/// A [row] of a cel and how the cel lays it — [paint]
/// ([ExportFrameRenderer._laidInTheCel]).
typedef _CelLaid = ({_CelRow row, RowPaint paint});

/// A label-group cel's rows, bottom-up, the view they are seen through,
/// and the guides and the camera's work laid over them — null where the
/// hand laid none.
typedef _CelGroup = ({
  List<_CelRow> rows,
  CameraView view,
  CameraOverlayPass? guides,
  CameraOverlayPass? camera,
});

/// Renders export output on the engine: each cut's picture is the frame's
/// one picture, shot through its view as a panel's is ([frameShot]) — so a
/// film, a still and a panel of one frame through one view on one paper
/// are one picture.
///
/// ↩️It rendered straight from the brush store, every cel read as a LOOK
/// (`CelRead.look`) and composited again on Flutter through the camera
/// (`CameraFrameRenderService`), its rows held between the frames of a
/// run (`HeldRows`) — until exports went on the engine (7′).
class ExportFrameRenderer {
  ExportFrameRenderer({
    required this.session,
    this.layerFx,
    this.keepsRowsApart = false,
    this.ground = exportFrameGround,
  });

  /// A renderer for a run written in [format], on the ground its files are
  /// made on: none where the file keeps its alpha — a still asked for RGBA,
  /// a video with an alpha channel ([alphaVideo]) — the format's colour
  /// under any other still, and white under a video. A PSD keeps the rows
  /// apart ([keepsRowsApart]).
  ///
  /// ↩️The export window spelled this for itself; it lives here since
  /// 「다른 이름으로 저장」 writes the image tab's picture (backlog-21-Q7).
  ExportFrameRenderer.forFormat({
    required EditorSessionManager session,
    required ExportFormatSelection format,
    required ExportLayerFx layerFx,
    bool alphaVideo = false,
  }) : this(
         session: session,
         layerFx: layerFx,
         keepsRowsApart: format.keepsRowsApart,
         ground: groundFor(format, alphaVideo: alphaVideo),
       );

  /// The ground [ExportFrameRenderer.forFormat] makes a run written in
  /// [format] on — read by a preview of that run as well, so the two lay
  /// the one ground (export-film-preview-is-not-the-film).
  static ui.Color groundFor(
    ExportFormatSelection format, {
    bool alphaVideo = false,
  }) => (alphaVideo || (format.isStill && format.wantsAlpha))
      ? const ui.Color(0x00000000)
      : format.isStill
      ? ui.Color(format.backgroundArgb)
      : const ui.Color(0xFFFFFFFF);

  final EditorSessionManager session;

  /// What a picture of this renderer's fills its whole output with, beyond
  /// the canvas's edges too — and lays its rows on where no paper is laid
  /// with them ([_pageOf]). Opaque or nothing: the export's grounds are
  /// white, black or none.
  final ui.Color ground;

  /// What the export window's 레이어 FX keeps of the rows
  /// ([layerAsOutput]) — or null for a picture of the SCREEN, which no
  /// window asks about (the storyboard's panels, the conte's cells): every
  /// row's own switches read as they stand, the camera row's and the V
  /// row's too (🗣️I-65-Q9, 유저 2026-10-25: 「화면 그대로(지금)」). The
  /// cut's fade is cut-level and stays either way; an output keeps the
  /// camera work and the V row's chain as their switches show them under 켬
  /// and 기본만 켬, and neither under 끔 (I-65-Q11, [layerAsOutput] ·
  /// [_trackFxLaid]).
  final ExportLayerFx? layerFx;

  /// Whether the frames drawn here go into a file that keeps the cut's rows
  /// apart — a PSD ([frameRows]). Its picture is then the one those rows
  /// lay up: what no row of the file can hold is left out of it as well —
  /// a folder's effects, an adjustment row's filter ([leftOutOfRows]).
  ///
  /// 🗣️I-117-Q2 (유저 2026-10-22): 「층을 지키고 그 효과는 뺀다」 — and the
  /// cost it was chosen at: the file's picture differs from the app's by
  /// those effects.
  final bool keepsRowsApart;

  /// The pictures the frame a run draws is made of and the ones the
  /// frame before it was made of, each under what it was made of: a cut's
  /// shot, and the finished frame. Held for one more frame ([HeldPictures]),
  /// and GPU pictures, so let go by hand ([dispose]).
  ///
  /// 🚨A CUT'S SHOT IS KEYED BY ITS PICTURE'S KEY
  /// ([FramePictures.keyOfStack]) — the law the engine keeps a frame's
  /// picture by — and by the view and what is drawn over it. A drawing held
  /// across a run of frames is shot once for the run while the camera
  /// stands; the engine composes it once however the camera moves.
  ///
  /// ↩️Every frame composited every row again, and read the result back
  /// (F-289, measured 2026-10-07 on the user's own film: of its 1,857
  /// frames 1,687 show the composite the frame before them showed, and
  /// 1,483 are that frame's picture, camera and all).
  final HeldPictures _pictures = HeldPictures();

  /// How many pictures this renderer has had to make (test hook) — a frame
  /// that is the picture before it makes none.
  @visibleForTesting
  int get debugPicturesMade => _pictures.made;

  /// Starts the next frame: what the frame before the last one held is let
  /// go, and what the last one held is kept for one more.
  ///
  /// ⚠️Once per frame a caller asked for — a transition's two cuts are one
  /// frame, and the cut picture inside a video frame starts none
  /// ([_cutPicture]).
  void _startFrame() => _pictures.nextFrame();

  /// Lets go of the pictures a run held. The run's to call when its last
  /// frame is out.
  void dispose() => _pictures.dispose();

  /// What runs the plugins [cut]'s chains run in this render: the device's,
  /// as the canvas runs them (`EditorSessionManager.fxPluginsIn`).
  FxPluginBinding _pluginsOf(Cut cut) => session.fxPluginsIn(cut);

  /// Decodes the movie pictures [cut] shows at [frameIndex] before its
  /// composite is planned: export walks frames nobody is looking at, so
  /// nothing else will have (the playback warmer awaits the same call).
  Future<void> _hydrate(Cut cut, int frameIndex) =>
      session.movieCels.hydrate(cut, frameIndex);

  /// Cuts whose FX-stripped view has already been built (memoized: the
  /// stream renders the same cut for many frames) — keyed by the cut
  /// ITSELF: the film can change under the window a renderer lives in
  /// (I-127 — its undo), and a cut changed is another cut. ↩️Keyed by its
  /// id, a preview drew the cut as it was when first drawn.
  final Expando<Cut> _fxStrippedByCut = Expando<Cut>('fx-stripped cut');

  /// The cuts [_onPaper] has laid out, each by the cut it lays.
  final Expando<Cut> _onPaperByCut = Expando<Cut>('cut on paper');

  /// The cut as this RENDER should see it: every row as the window's
  /// 레이어 FX keeps it ([layerAsOutput] — the choice expressed as DATA,
  /// cheaper to reason about than an override threaded through the plan,
  /// and impossible for another route to forget: the plan renders exactly
  /// the cut it is given), or the cut itself for a picture of the screen
  /// ([layerFx] null).
  ///
  /// For a file that keeps the rows apart ([keepsRowsApart]), the effects
  /// of every row that paints nothing of its own — a folder, an adjustment
  /// row — read off as well: the file has no row to hold them.
  Cut _cutForRender(Cut cut) {
    if (layerFx == null && !keepsRowsApart) {
      return cut;
    }
    return _fxStrippedByCut[cut] ??= cut.copyWith(
      layers: [for (final layer in cut.layers) _layerForRender(layer)],
    );
  }

  /// [layer] as [_cutForRender] hands it to the plan.
  Layer _layerForRender(Layer layer) {
    final output = _asOutput(layer);
    return keepsRowsApart && !output.kind.paintsArtwork
        ? output.copyWith(effects: _switchedOff(output.effects))
        : output;
  }

  /// [layer] as the window's 레이어 FX keeps it — itself for a picture of
  /// the screen.
  Layer _asOutput(Layer layer) => switch (layerFx) {
    final fx? => layerAsOutput(layer, fx),
    null => layer,
  };

  /// Whether this render lays [cutId]'s V row chain: where the screen shows
  /// it — the row's switch on — and, in an output, where the window's 레이어
  /// FX is not 끔 (I-65-Q11 「켬 · 기본만 켬이면 화면 스위치대로, 끔이면
  /// 빠짐」, as the camera row's work is — [layerAsOutput]). ↩️I-65-Q8 laid
  /// it in every output whatever the switch said; the switch alone gated
  /// the output since R8 before that.
  bool _trackFxLaid(CutId cutId) =>
      layerFx != ExportLayerFx.off &&
      session.effectsAndFx.isCutFxEnabled(cutId);

  /// [cut]'s V row chain at [globalFrame] — the frame's place on the track's
  /// own axis (R4) — laid as [_trackFxLaid] says: what every route that
  /// draws a cut lays under its picture. Its plugins run as the cut's rows'
  /// do (🗣️I-132-Q34 a), reading [cut]'s rows at its own [frameIndex].
  List<ResolvedLayerEffect> _trackChainAt(
    Cut cut,
    int globalFrame, {
    required int frameIndex,
  }) => _pluginsOf(cut)(
    trackEffectsAt(
      session.effectsAndFx.trackEffectsForCut(cut.id),
      globalFrame,
      enabled: _trackFxLaid(cut.id),
      track: session.trackOwningCut(cut.id)?.id,
    ),
    cut: cut,
    frameIndex: frameIndex,
  );

  /// [task]'s cut's V row chain at the task's place on the track
  /// ([_trackChainAt]).
  List<ResolvedLayerEffect> _trackChainOf(ExportFrameTask task) =>
      _trackChainAt(
        task.cut,
        session.rowSpans.trackGlobalFrameOf(task.cut.id, task.frameIndex),
        frameIndex: task.frameIndex,
      );

  /// The V row chain under a STILL of [task] — as a video's frame lays it
  /// ([_trackChainOf]; I-65-Q10 a: 「이미지 탭에도 V 행 fx 를 깐다」) — none in
  /// a file that keeps the rows apart, which no row of the file can hold
  /// ([leftOutOfRows] says so). ↩️A still laid none, whatever the switch.
  List<ResolvedLayerEffect> _stillChainOf(ExportFrameTask task) =>
      keepsRowsApart ? const [] : _trackChainOf(task);

  static List<LayerEffect> _switchedOff(List<LayerEffect> effects) => [
    for (final effect in effects) effect.copyWith(enabled: false),
  ];

  /// Each contribution's UNIT ALPHA: its own share of the frame. (↩️Times
  /// its track's static opacity, until the V row lost it — I-73,
  /// 2026-10-08.)
  ///
  /// ⚠️Both bakes below need exactly this before they can weigh anything,
  /// and they weigh it differently afterwards ([sourceOverWeights] within
  /// one canvas, [trackGroupSourceOverWeights] across tracks). The half
  /// they share is here; the half they don't stays at the call site.
  List<double> _unitAlphas(List<({Cut cut, double opacity})> contributions) {
    return [for (final contribution in contributions) contribution.opacity];
  }

  /// The ground of the pictures that stand on nothing: TRANSPARENT. A track
  /// of the stack's, so an upper track's picture never blanks the tracks
  /// below — the paper belongs to the bottom covered track, and its unit
  /// lays it ([_stackUnit]); and a row of a layered file's, which the file
  /// lays over the rows under it ([frameRows], [celGroupRows]).
  static const ui.Color _clear = ui.Color(0x00000000);

  /// The page [cut]'s rows are laid on here: [paper] with them where the
  /// route lays one — a stage's, a canvas-size film's, the picture 「다른
  /// 이름으로 저장」 writes — and else the [ground] the picture is made on,
  /// as the rows' paper; nothing under them on a clear one.
  ///
  /// ⚖️THE GROUND IS THE PAPER OF A PICTURE THAT LAYS NONE — what a blend
  /// over its backdrop and an adjustment read below the rows, as on the
  /// canvas they read its paper (↩️the old composite laid the ground as its
  /// tree's bottom row, `onUnderlay`). So a still and a panel of one frame
  /// through one view on one paper are one picture
  /// (`a_film_frame_is_the_frame_playback_shows_test`). My call, not the
  /// user's.
  ///
  /// A page with no paper reads as the screen's does ([PlaybackRig
  /// .framePictures]): a track over the stage, on the project's paper
  /// unpainted, is the picture playback made of it.
  FramePage _pageOf(Cut cut, ui.Color ground, ProjectBackground? paper) {
    final under =
        paper ??
        (ground.a > 0 ? ProjectBackground.color(ground.toARGB32()) : null);
    return (
      canvasSize: cut.canvasSize,
      pasteboardReach: session.repository.requireProject().pasteboardReach,
      paintPaper: under != null,
      paperBackground: under ?? session.projectSettings.projectBackground,
    );
  }

  /// [cut]'s frame [frameIndex] on [page], with the onion's [ghosts] in it
  /// as they lie: what the engine keeps its picture under ([frameShot]).
  static DemandedPicture _frameOn(
    Cut cut,
    int frameIndex,
    FramePage page, {
    FrameGhosts ghosts = FrameGhosts.none,
  }) => (
    cut: cut,
    frameIndex: frameIndex,
    paintPaper: page.paintPaper,
    ghosts: ghosts,
  );

  /// [nodes] — a tree of [cut]'s frame [frameIndex] — shot through [view]
  /// ([frameShot]) at [outputSize], on [ground] — this renderer's own unless
  /// another is named ([_clear]) — with [paper] laid with the rows
  /// ([_pageOf]), cut at the canvas's edge where [cutsToTheCanvas] says,
  /// and [over] laid over the picture.
  Future<ui.Image> _shot(
    Cut cut,
    int frameIndex,
    List<CompositeNode<CanvasStackRow>> nodes, {
    required CameraView view,
    CanvasSize? outputSize,
    ui.Color? ground,
    ProjectBackground? paper,
    FrameGhosts ghosts = FrameGhosts.none,
    bool cutsToTheCanvas = true,
    CameraOverlayPass? over,
  }) {
    final on = ground ?? this.ground;
    final page = _pageOf(cut, on, paper);
    return frameShot(
      session,
      pictures: session.playbackRig.framePictures,
      nodes: nodes,
      frame: _frameOn(cut, frameIndex, page, ghosts: ghosts),
      page: page,
      view: view,
      output: outputSize ?? view.frameSize,
      ground: on,
      cutsToTheCanvas: cutsToTheCanvas,
      over: over,
    );
  }

  /// [task]'s tree as the canvas stacks it ([EditingCanvas.stackAt]) — of
  /// the cut as this render sees it ([_cutForRender]), no row live — with
  /// each onion row's [ghosts] directly under its drawing where some are
  /// given.
  List<CompositeNode<CanvasStackRow>> _nodesFor(
    ExportFrameTask task, {
    Map<LayerId, List<CutFrameCompositeGhost>>? ghosts,
  }) => session.editingCanvas
      .stackAt(
        cut: task.cut,
        stackCut: _cutForRender(task.cut),
        frameIndex: task.frameIndex,
        drawingLayerId: null,
        ghosts: ghosts,
      )
      .nodes;

  /// [rows] — a tree of the cut [task]'s frame is made of, as this render
  /// sees it ([_cutForRender]) — as the canvas stacks them
  /// ([EditingCanvas.stackOfRows]).
  List<CompositeNode<CanvasStackRow>> _stackOf(
    ExportFrameTask task,
    List<CompositeNode<CutFrameCompositeRow>> rows,
  ) => session.editingCanvas.stackOfRows(
    task.cut,
    task.frameIndex,
    rows,
    stackCut: _cutForRender(task.cut),
  );

  /// Whether [cut]'s cel of [layer] at [frame] shows anything — the
  /// store's own word for it ([BrushFrameStore.celHasRenderableContent]).
  bool _hasArtwork(Cut cut, Layer layer, Frame frame) =>
      session.renderCaches.brushFrameStore.celHasRenderableContent(
        session.brushFrameKeyForCut(cut, layer.id, frame.id),
      );

  /// The multi-track layout, built once per export run (the project is
  /// frozen while a run streams).
  List<StoryboardTimelineLayoutEntry>? _stackLayout;

  List<StoryboardTimelineLayoutEntry> get _layout =>
      _stackLayout ??= buildStoryboardTimelineLayout(
        session.repository.requireProject(),
      );

  /// [task]'s cut in [_layout] — its place on its own TRACK axis, which a
  /// transition, its screen and the stack are all read against. Null for a
  /// cut the layout does not hold.
  StoryboardTimelineLayoutEntry? _entryOf(ExportFrameTask task) =>
      _layout.where((entry) => entry.cutId == task.cut.id).firstOrNull;

  /// One composited frame. [ExportSizeMode.canvas] renders the identity
  /// camera over the cut's own canvas size (centered, zoom 1, no rotation),
  /// which is exactly the raw canvas at 1:1 pixels on the white paper.
  /// [outputSize] scales the same view down (storyboard thumbnails); null
  /// exports at full size.
  ///
  /// No SE name tags (R5b): a compositing source stays clean, as a PNG
  /// sequence stays unposed and unfaded, and a thumbnail has no room for
  /// them. A film burns them in ([renderVideoFrame]). ↩️A flag drew them
  /// here for the export window's preview of a film, which draws the film's
  /// own frame now (export-film-preview-is-not-the-film).
  Future<ui.Image> renderComposite(
    ExportFrameTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
  }) async {
    _startFrame();
    return _shot(
      task.cut,
      task.frameIndex,
      await _cutNodes(task, _stillChainOf(task)),
      view: _viewFor(task.cut, task.frameIndex, mode),
      outputSize: outputSize,
    );
  }

  /// [task]'s frame as the canvas shows it, in [mode]'s view of it — the
  /// picture a person asks for by hand (「다른 이름으로 저장」, the export
  /// window's image tab), where [renderComposite] is a film's: the rows with
  /// their onion ghosts ([_nodesAsShown]), and over them what the canvas
  /// draws on the picture's own pixels ([_shownOver]). [paper] is laid under
  /// the rows as the canvas lays it, and a guide that names no colour of its
  /// own is drawn in [guideInk].
  ///
  /// 🗣️F-547 (유저 2026-11-03): 「다른이름저장은 진짜 보이는대로 출력이니까
  /// 가이드던 어니언스킨이던 뭐던 화면 보이는 그대로 캔버스사이즈로 크롭해서
  /// 출력하도록 … 심플하게 구현하기만 하면됨」 · 「출력탭 이미지저장도 마찬가지」.
  ///
  /// ⛔Not a capture of the screen, though that reads simpler: the screen is
  /// the view's — cut at the panel's edges and at its zoom. It is what the
  /// canvas draws from, drawn by what draws it, at the file's pixels; what
  /// the canvas has hidden is in no picture of it.
  Future<ui.Image> renderAsShown(
    ExportFrameTask task,
    ExportSizeMode mode, {
    required ui.Color guideInk,
    CanvasSize? outputSize,
    ProjectBackground? paper,
  }) async {
    _startFrame();
    final cut = task.cut;
    final view = _viewFor(cut, task.frameIndex, mode);
    await _hydrate(cut, task.frameIndex);
    return _shot(
      cut,
      task.frameIndex,
      _nodesAsShown(task),
      view: view,
      outputSize: outputSize,
      paper: paper,
      ghosts: _ghostsInPlace ? FrameGhosts.inPlace : FrameGhosts.none,
      over: _shownOver(task, view, guideInk),
    );
  }

  /// Whether the canvas lays the onion's ghosts each directly under its
  /// row's drawing ([OnionSkinPlacement.inPlace]) — else over the frame's
  /// every row.
  bool get _ghostsInPlace =>
      session.onionSkin.settings.value.placement == OnionSkinPlacement.inPlace;

  /// [task]'s tree under the V row's chain, as [renderComposite] lays it,
  /// with its onion ghosts where the canvas lays them
  /// ([OnionSkinPlacement]): each directly under its row's drawing, or over
  /// the frame's every row.
  List<CompositeNode<CanvasStackRow>> _nodesAsShown(ExportFrameTask task) {
    final inPlace = _ghostsInPlace;
    return [
      ...underTheCutsFx(
        _nodesFor(task, ghosts: inPlace ? _ghostsOf(task) : null),
        _stillChainOf(task),
      ),
      if (!inPlace) ..._ghostsAlone(task),
    ];
  }

  /// The onion ghosts of [task]'s frame, each onion row's under its id — of
  /// the cut as this render sees it, so a chain the render leaves off
  /// ([_cutForRender]) is off them too.
  Map<LayerId, List<CutFrameCompositeGhost>> _ghostsOf(ExportFrameTask task) =>
      session.onionSkin.ghostsAt(
        _cutForRender(task.cut),
        task.frameIndex,
        null,
      );

  /// [task]'s onion ghosts by themselves ([ghostsAlone]).
  List<CompositeNode<CanvasStackRow>> _ghostsAlone(ExportFrameTask task) =>
      _stackOf(
        task,
        ghostsAlone(
          cut: _cutForRender(task.cut),
          frameIndex: task.frameIndex,
          ghosts: _ghostsOf(task).values.expand((ghosts) => ghosts),
        ),
      );

  /// What the canvas draws over [task]'s picture on the picture's own
  /// pixels, through [view], in the order it stacks them (`_overlayStack`):
  /// the guides, the SE rows' name tags, the screens one-sided transitions
  /// lay, the camera's path and the dim of its view. Null where it shows none
  /// of them.
  ///
  /// ⛔Not what it draws at the screen's size whatever the zoom — a guide's
  /// handles and names, a row's path, the crosses in time, a box, the camera
  /// frame's hairline and cross: 🗣️F-547
  /// 「카메라에 서있을때 조작 나오는거라던가도 출력되버리면 상관없고 딱히 결과적으로
  /// 그런 픽셀사이즈가 아닌건 출력안된다해도 상관없음」.
  ///
  /// ⚠️Nor an O.L's other cut, or the thinning that makes room for it (the
  /// canvas's fade wash): a picture of two cuts is the film's, and this is
  /// the one cut as it stands — my call, not the user's, for 「심플하게」.
  CameraOverlayPass? _shownOver(
    ExportFrameTask task,
    CameraView view,
    ui.Color guideInk,
  ) {
    final cut = task.cut;
    final veils = _veilsOf(task);
    return _laidOver([
      _guideLinesOver(
        cut,
        [
          for (final guide in cut.guides.guides)
            if (guide.visible) guide,
        ],
        view,
        guideInk,
      ),
      _nameTagsOver(
        cut,
        session.seEntries.seNameTagsForCutFrame(cut, task.frameIndex),
      ),
      if (veils.isNotEmpty)
        (canvas, _) => paintTransitionVeils(
          canvas,
          session.pasteboardOf(cut.canvasSize).rect,
          veils,
        ),
      _cameraPathShown(task),
      _cameraDimShown(task),
    ]);
  }

  /// [task]'s camera path as the canvas draws it off the camera's row
  /// ([CameraPathOverlay.standing]): as the canvas's camera path settings
  /// say, around [task]'s frame where they keep to it, as large as the
  /// canvas prints it there ([CameraPathOverlay.printedAt]) — the overlay's
  /// own marks, on a view that is the canvas. Null where it draws none.
  CameraOverlayPass? _cameraPathShown(ExportFrameTask task) {
    final settings = CameraPathSettings.settings.value;
    final path = settings.show == CameraPathShow.off
        ? null
        : CameraPath.of(task.cut, session.camera.cameraFrameSize);
    if (path == null) {
      return null;
    }
    return _marksOver(
      task.cut,
      CameraPathOverlay(
        path: path,
        playhead: task.frameIndex,
        settings: settings,
        viewport: CanvasViewport(),
        standing: false,
        printedAt: _poseAt(task),
      ).marks,
    );
  }

  /// The camera view's dim over [task]'s picture, round the frame the camera
  /// stands in there, where the view is on. The eye is the switch: closed,
  /// the picture has none. Null where there is none.
  CameraOverlayPass? _cameraDimShown(ExportFrameTask task) {
    final view = session.cameraViewMode;
    final dim = view.dim.value;
    if (!view.enabled.value || dim <= 0) {
      return null;
    }
    final frame = ui.Path()
      ..addPolygon(
        cameraFrameCornersInCanvas(
          pose: _poseAt(task),
          cameraFrameSize: session.camera.cameraFrameSize,
        ),
        true,
      );
    final stage = task.cut.canvasSize.canvasRect.size;
    return (canvas, _) => paintCameraDim(canvas, stage, frame, dim);
  }

  /// The camera's pose at [task]'s frame, as this render sees the camera
  /// ([_viewFor]).
  CameraPose _poseAt(ExportFrameTask task) => session.camera.cameraPoseForCut(
    _cutForRender(task.cut),
    task.frameIndex,
  );

  /// What [renderAsShown] lays over [task]'s rows, as a row of its own over
  /// a file that keeps them apart ([frameRows]) — the ghosts with the rest,
  /// wherever they lie in the picture, as no row of the file holds one; so
  /// a person who wants the rows alone hides one row. Null where the canvas
  /// shows nothing over them.
  ExportLayerRow? rowShownOver(
    ExportFrameTask task,
    ExportSizeMode mode, {
    required ui.Color guideInk,
  }) {
    final cut = task.cut;
    final view = _viewFor(cut, task.frameIndex, mode);
    final over = _shownOver(task, view, guideInk);
    final ghosts = _ghostsAlone(task);
    final store = session.renderCaches.brushFrameStore;
    if (over == null &&
        stackOfDrawnCels(
          ghosts,
          drawn: store.celHasRenderableContent,
        ).isEmpty) {
      return null;
    }
    return ExportLayerRow(
      name: AppText.notation.exOnScreen,
      draw: () async {
        await _hydrate(cut, task.frameIndex);
        return _shot(
          cut,
          task.frameIndex,
          _ghostsAlone(task),
          view: view,
          ground: _clear,
          over: over,
        );
      },
    );
  }

  /// [task]'s frame as the rows a layered file keeps apart, bottom-up — the
  /// cut's own rows, as its layer list holds them (I-117-Q2, 유저
  /// 2026-10-22: 「층을 지키고 그 효과는 뺀다」): a folder, a folder of the
  /// file with what is in it, 통과 kept 통과; a row that paints, its picture
  /// here — its pose and its effects on it, drawn by itself on nothing
  /// through the view [renderComposite] looks through, whole and in no
  /// blend — laid by its own strength and blend; an adjustment row, a row of
  /// no picture under its name ([leftOutOfRows]). Each keeps its eye: a
  /// hidden row is in the file, hidden. Under them all, the ground
  /// [renderComposite] lays them on and [paper] with it, where there is
  /// either.
  ///
  /// ⚠️It starts no frame: drawn after [renderComposite]'s picture of the
  /// same frame, as [celGroupRows] is after its cel's.
  List<ExportLayerNode> frameRows(
    ExportFrameTask task,
    ExportSizeMode mode, {
    ProjectBackground? paper,
  }) {
    final frameIndex = task.frameIndex;
    final view = _viewFor(task.cut, frameIndex, mode);
    // A picture of the file: what [laid] hands over, by itself on [ground],
    // through the view and cut at the canvas's edge as the frame is
    // ([_shot]).
    Future<ui.Image> drawn(
      ui.Color ground, {
      List<CompositeNode<CanvasStackRow>> Function()? laid,
      ProjectBackground? paper,
    }) async {
      await _hydrate(task.cut, frameIndex);
      return _shot(
        task.cut,
        frameIndex,
        laid?.call() ?? const [],
        view: view,
        ground: ground,
        paper: paper,
      );
    }

    final cut = _cutForRender(task.cut);
    final childrenOf = <LayerId?, List<ExportLayerNode>>{};
    for (final layer in cut.layers) {
      final ExportLayerNode? node;
      if (layer.kind.groupsLayers) {
        node = ExportLayerFolder(
          name: layer.name,
          opacity: resolveFolderOpacityAt(
            folder: layer,
            frameIndex: frameIndex,
          ),
          blendMode: layer.blendMode,
          visible: layer.isVisible,
          // Photoshop clips as the row does (I-92).
          clipped: clipsToLayerBelow(layer),
          children: childrenOf.remove(layer.id) ?? const [],
        );
      } else if (layer.kind.filtersBelow) {
        node = ExportLayerRow(
          name: layer.name,
          opacity: resolveLayerEffectiveOpacityAt(
            layer: layer,
            frameIndex: frameIndex,
          ),
          blendMode: layer.blendMode,
          visible: layer.isVisible,
          draw: () => drawn(_clear),
        );
      } else {
        node = switch (layerDrawingAt(
          cut: cut,
          layer: layer,
          frameIndex: frameIndex,
        )) {
          null => null,
          final drawing => ExportLayerRow(
            name: layer.name,
            opacity: drawing.render.opacity,
            blendMode: drawing.render.blendMode,
            visible: layer.isVisible,
            clipped: clipsToLayerBelow(layer),
            draw: () => drawn(
              _clear,
              laid: () => _laidAlone(task, layer, drawing),
            ),
          ),
        };
      }
      if (node != null) {
        (childrenOf[layer.folderId] ??= []).add(node);
      }
    }
    return [
      if (ground.a > 0 || paper != null)
        ExportLayerRow(
          name: AppText.notation.exBackground,
          draw: () => drawn(ground, paper: paper),
        ),
      ...?childrenOf[null],
    ];
  }

  /// [layer]'s [drawing] in [task]'s frame by itself — whole, in no blend,
  /// its pose and its effects on it, reading the rows they name as the
  /// film reads them ([readingTheirRows]), its cel number with them
  /// ([celNumberedRow]): the picture a layered file lays by the row's own
  /// strength and blend ([frameRows]). Nothing where it exposes no cel
  /// here, or one with nothing on it.
  List<CompositeNode<CanvasStackRow>> _laidAlone(
    ExportFrameTask task,
    Layer layer,
    ({Frame? frame, ResolvedRowRender render}) drawing,
  ) {
    final cut = task.cut;
    final frame = drawing.frame;
    if (frame == null || !_hasArtwork(cut, layer, frame)) {
      return const [];
    }
    return _stackOf(
      task,
      readingTheirRows(
        celNumberedRow(
          paint: _alone(drawing.render.effects),
          rowOf: (paint) => CutFrameCompositeEntry(
            layer: layer,
            frame: frame,
            opacity: paint.opacity,
            blendMode: paint.blendMode,
            placement: drawing.render.placement,
            effects: paint.effects,
          ),
          text: celNumberText(
            rowName: layer.name,
            drawingName: frame.name,
            kind: layer.kind,
          ),
          paper: cut.canvasSize,
          // By itself in its picture: the file clips the picture, not a
          // node.
          asOnePicture: false,
        ),
        // Read off the cut as the file lays it ([_cutForRender]): a
        // folder's chain no row of the file holds is out of a map as it is
        // out of the file — I-117-Q2 「층을 지키고 그 효과는 뺀다」.
        cut: _cutForRender(cut),
        frameIndex: task.frameIndex,
        liveLayerId: null,
      ),
    );
  }

  /// What a file that keeps [task]'s rows apart leaves out of them
  /// ([keepsRowsApart]) — every adjustment row, whose filter no row of the
  /// file holds, every folder whose effects are on here, and the V row
  /// whose chain a picture of the frame would lay ([_trackChainOf]) — each
  /// said as a PSD's reader says what it could not bring in. None where the
  /// file is the picture alone.
  ///
  /// 🗣️I-117-Q2 (유저 2026-10-22): 「내보내기가 끝나면 무엇이 빠졌는지
  /// 알린다(PSD 를 읽을 때 못 담은 것을 알리듯이)」.
  List<ImportWarning> leftOutOfRows(ExportFrameTask task) => [
    if (keepsRowsApart) ...[
      for (final layer in task.cut.layers)
        if (layer.kind.filtersBelow)
          unsupportedLayerKind(layer.name)
        else if (layer.kind.groupsLayers &&
            resolveFolderEffectsAt(
              folder: _asOutput(layer),
              frameIndex: task.frameIndex,
            ).isNotEmpty)
          layerEffectsNotApplied(layer.name),
      // The V row's chain lies over the whole picture, as a folder's does
      // over what it holds ([_stillChainOf]).
      if (session.trackOwningCut(task.cut.id) case final track?
          when _trackChainOf(task).isNotEmpty)
        layerEffectsNotApplied(track.name),
    ],
  ];

  /// [cut]'s rows at [frameIndex] over the canvas [region], a pixel a
  /// pixel — a camera standing square over it ([cameraViewOver]), and the
  /// pasteboard it takes in kept: what a merge lays as the one cel its rows
  /// become (`merge_layer_rows`).
  ///
  /// ↩️It was a panel's picture too — at a panel's width, through the
  /// camera where no region was given — until a panel was cut from the
  /// frame's one picture (F-533-Q8, `PanelPictures`).
  Future<ui.Image> renderOver(Cut cut, int frameIndex, ui.Rect region) async {
    final view = cameraViewOver(region);
    _startFrame();
    await _hydrate(cut, frameIndex);
    return _shot(
      cut,
      frameIndex,
      _nodesFor(ExportFrameTask(cut: cut, frameIndex: frameIndex)),
      view: view,
      cutsToTheCanvas: false,
    );
  }

  /// What a render of [cut] at [frameIndex] looks through in [mode]: its
  /// camera there, or the whole canvas — a camera standing square over all
  /// of it, at its own size.
  ///
  /// The camera is the RENDER's ([_cutForRender]): the camera row's switch
  /// as the screen shows it, and off under an output's 끔 ([layerAsOutput],
  /// I-65-Q11).
  CameraView _viewFor(Cut cut, int frameIndex, ExportSizeMode mode) =>
      switch (mode) {
        ExportSizeMode.camera => (
          pose: session.camera.cameraPoseForCut(
            _cutForRender(cut),
            frameIndex,
          ),
          frameSize: session.camera.cameraFrameSize,
        ),
        ExportSizeMode.canvas => cameraViewOver(cut.canvasSize.canvasRect),
      };

  /// [task]'s tree ([_nodesFor]) under the V row's [trackEffects]
  /// ([underTheCutsFx]) — asked once the movie pictures it shows are in
  /// ([_hydrate]): where a movie's picture was laid is where its row lies.
  Future<List<CompositeNode<CanvasStackRow>>> _cutNodes(
    ExportFrameTask task,
    List<ResolvedLayerEffect> trackEffects,
  ) async {
    await _hydrate(task.cut, task.frameIndex);
    return underTheCutsFx(_nodesFor(task), trackEffects);
  }

  /// [nameTags] over [cut]'s picture. Null for none.
  CameraOverlayPass? _nameTagsOver(
    Cut cut,
    List<ResolvedSeNameTag> nameTags,
  ) => nameTags.isEmpty
      ? null
      : (canvas, rasterScale) => paintSeNameTags(
          canvas,
          tags: nameTags,
          canvasSize: cut.canvasSize,
          rasterScale: rasterScale,
        );

  /// The BACKDROP ground (R3b) under a video frame — null when nothing is
  /// laid down at all, which is what [preserveAlpha] asks for.
  ///
  /// ⛔THE GROUND IS THE VIDEO'S FLOOR AND THE GUARD IS THE MASTER'S. An
  /// opaque codec bakes the stage's floor everywhere the picture leaves
  /// uncovered — gap frames, a posed stage sliding off, a fade thinning
  /// the stack away — while an alpha master must stay transparent. Four
  /// renders wrote the pair out, and one that forgot the guard bakes an
  /// opaque floor into a master somebody asked to keep clear.
  ///
  /// A VALUE, read once into what the frame is made of ([_frameOf]).
  ui.Color? _backdropGround({required bool preserveAlpha}) {
    final project = session.repository.requireProject();
    // A backdrop that is NONE (F-114) prints nothing, the way an alpha
    // master leaves it out: the plane is not there.
    if (preserveAlpha || project.backdropNone) {
      return null;
    }
    return ui.Color(project.backdropArgb);
  }

  /// A video FRAME that is made of [made] and of nothing else: the one held
  /// under it, as a picture of the caller's own to dispose.
  ///
  /// 🚨A FRAME MADE OF WHAT THE FRAME BEFORE IT WAS MADE OF IS THAT FRAME'S
  /// PICTURE — not one like it: the same image, handed again
  /// (`ui.Image.isCloneOf`). So whoever takes the frames can tell without
  /// looking at a pixel that it has these already, and a hold costs what
  /// the encoder charges to see a frame twice.
  ///
  /// ⚠️[paint] is handed [made] AND NO MORE — a function of this library's
  /// top level, with no renderer to read from — so what a frame is keyed by
  /// is all it can be drawn from. A value that reached the paint and not
  /// the key would be a held frame shown where the picture moved.
  Future<ui.Image> _frameOf<T extends Object>(
    T made, {
    required int width,
    required int height,
    required void Function(ui.Canvas canvas, T made) paint,
  }) async => (await _pictures.of(
    (T, made),
    () => rasterizeOffscreen(
      width: width,
      height: height,
      paint: (canvas) => paint(canvas, made),
    ),
  )).clone();

  /// [task]'s cut's picture through [view] at [outputSize] — under the V
  /// row's [trackEffects], with [nameTags] drawn over it, on [ground] with
  /// [paper] laid with its rows ([_shot]) — held ([_pictures]) under the key
  /// the engine keeps its picture by ([FramePictures.keyOfStack]), the
  /// ground, and [route]: whatever of the shot that key does not say —
  /// which of the renders it is, the view it is drawn through, its size and
  /// what is drawn over it. The renderer's own: nobody it is handed to
  /// disposes it.
  ///
  /// Cut at its canvas's edge: a film shows no pasteboard, and a picture of
  /// a sequence is one of its frames.
  Future<ui.Image> _cutPicture(
    ExportFrameTask task,
    CameraView view, {
    required Object route,
    CanvasSize? outputSize,
    List<ResolvedLayerEffect> trackEffects = const [],
    List<ResolvedSeNameTag> nameTags = const [],
    ui.Color? ground,
    ProjectBackground? paper,
  }) async {
    final cut = task.cut;
    final nodes = await _cutNodes(task, trackEffects);
    final on = ground ?? this.ground;
    final page = _pageOf(cut, on, paper);
    final key = session.playbackRig.framePictures.keyOfStack(
      nodes,
      _frameOn(cut, task.frameIndex, page),
      page: page,
    );
    return _pictures.of(
      (route, key, on),
      () => _shot(
        cut,
        task.frameIndex,
        nodes,
        view: view,
        outputSize: outputSize,
        ground: on,
        paper: paper,
        over: _nameTagsOver(cut, nameTags),
      ),
    );
  }

  /// [cut]'s picture at [frameIndex] over its whole canvas, its paper laid
  /// with its rows on this renderer's ground, under the V row's
  /// [trackEffects] and the SE rows' name tags — a canvas-size video
  /// frame's picture, at [outputSize] where one is asked. The presentation
  /// render: the アフレコ name tags belong in the video (their row's eye is
  /// the switch).
  ///
  /// 🗣️export-film-preview-is-not-the-film-Q1 (유저 2026-11-04: 「깐다 —
  /// 카메라 크기와 같게」): the paper is laid here as the stage's is in a
  /// camera-size frame ([_stackUnit]). ↩️A canvas-size film stood on the
  /// ground alone — white, or nothing in an alpha master — whatever the
  /// paper was.
  Future<ui.Image> _canvasPicture(
    Cut cut,
    int frameIndex,
    List<ResolvedLayerEffect> trackEffects, {
    CanvasSize? outputSize,
  }) {
    final nameTags = session.seEntries.seNameTagsForCutFrame(cut, frameIndex);
    final view = _viewFor(cut, frameIndex, ExportSizeMode.canvas);
    return _cutPicture(
      ExportFrameTask(cut: cut, frameIndex: frameIndex),
      view,
      route: ('canvas', seNameTagSignature(nameTags), view, outputSize),
      outputSize: outputSize,
      trackEffects: trackEffects,
      nameTags: nameTags,
      paper: session.projectSettings.projectBackground,
    );
  }

  /// A video run of [plan] in [mode] — its frames, drawn in order
  /// ([ExportRun.frame]), each made of the cuts the frame shows
  /// ([renderVideoFrame]), each drawn through its view ([_viewFor]).
  ExportRun videoRun(
    List<ExportFrameTask> plan,
    ExportSizeMode mode, {
    bool preserveAlpha = false,
  }) => ExportRun._(
    plan: plan,
    draw: (task) => renderVideoFrame(task, mode, preserveAlpha: preserveAlpha),
  );

  /// A run of STILLS of [plan] in [mode] — a picture sequence's frames,
  /// each the picture [renderComposite] makes of its task, held as a video
  /// run holds its own: a frame made of what the frame before it was made
  /// of is that frame's picture, handed again ([_stillFrame]).
  ExportRun stillRun(List<ExportFrameTask> plan, ExportSizeMode mode) =>
      ExportRun._(plan: plan, draw: (task) => _stillFrame(task, mode));

  /// The picture [renderComposite] makes of [task] in [mode] — at its full
  /// size, without the names — held as a cut's picture is ([_cutPicture]),
  /// under the view it is drawn through: a picture of the caller's own to
  /// dispose.
  Future<ui.Image> _stillFrame(
    ExportFrameTask task,
    ExportSizeMode mode,
  ) async {
    _startFrame();
    final view = _viewFor(task.cut, task.frameIndex, mode);
    final picture = await _cutPicture(
      task,
      view,
      route: ('still', view),
      trackEffects: _stillChainOf(task),
    );
    return picture.clone();
  }

  /// What a CANVAS-size video frame is made of: no cut in a gap; the cuts a
  /// transition reaching across this frame's boundary mixes, where they
  /// share its space ([shared]); else its own cut — each at its own frame.
  ///
  /// A transition puts a SECOND cut here, and canvas space is shared
  /// whenever the two agree on their canvas size — which two cuts of one
  /// track normally do. Only differing sizes keep the single-cut bake,
  /// because then there is no shared space to mix in (the camera frame is
  /// that space, and that is the track stack's).
  ({List<(Cut, int)> cuts, _SharedTransitionSpace? shared}) _canvasFrameOf(
    ExportFrameTask task,
  ) {
    if (task.isGap) {
      return (cuts: const [], shared: null);
    }
    final shared = _sharedTransitionSpace(task);
    if (shared != null) {
      return (
        cuts: [
          for (final contribution in shared.contributions)
            (contribution.cut, contribution.localFrameIndex),
        ],
        shared: shared,
      );
    }
    return (cuts: [(task.cut, task.frameIndex)], shared: null);
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
  /// Transform, AE precomp semantics), thinned by the fade (R3b:
  /// transparency over the backdrop) and covered by a one-sided
  /// transition's own black or white screen (F-192). PNG sequences
  /// deliberately stay unposed and unfaded (they are compositing
  /// sources).
  ///
  /// [preserveAlpha] (ProRes 4444 α): gap frames and the uncovered ground
  /// stay TRANSPARENT instead of baking an opaque backing — the fade
  /// still paints toward its target color (a fade IS opaque paint).
  ///
  /// A frame that is the picture the frame before it was comes back as
  /// that picture ([_frameOf]).
  ///
  /// [outputSize] draws the same frame at another size — a preview's
  /// (export-film-preview-is-not-the-film). ↩️The window's preview of a film
  /// drew [renderComposite]'s still instead: no stage, no other track, no
  /// pose, no fade, and a checkerboard where the film lays its paper.
  Future<ui.Image> renderVideoFrame(
    ExportFrameTask task,
    ExportSizeMode mode, {
    required bool preserveAlpha,
    CanvasSize? outputSize,
  }) {
    _startFrame();
    return switch (mode) {
      ExportSizeMode.camera => _renderTrackStackForVideo(
        task,
        preserveAlpha: preserveAlpha,
        outputSize: outputSize,
      ),
      ExportSizeMode.canvas => _canvasVideoFrame(
        task,
        preserveAlpha: preserveAlpha,
        outputSize: outputSize,
      ),
    };
  }

  /// The CANVAS-size video frame of [task] ([renderVideoFrame]): the
  /// backdrop in a gap, a transition's cuts mixed in their shared space, or
  /// the cut's own picture under its one-sided screens.
  Future<ui.Image> _canvasVideoFrame(
    ExportFrameTask task, {
    required bool preserveAlpha,
    CanvasSize? outputSize,
  }) async {
    final ground = _backdropGround(preserveAlpha: preserveAlpha);
    final (:cuts, :shared) = _canvasFrameOf(task);
    if (cuts.isEmpty) {
      // A leading-gap frame: nothing plays — the BACKDROP (R3b), exactly
      // what playback shows in the gap. Opaque codecs bake the floor; an
      // alpha master keeps the gap transparent.
      final size = outputSize ?? task.cut.canvasSize;
      return _frameOf<_GapFrame>(
        (size: size, ground: ground),
        width: size.width,
        height: size.height,
        paint: _paintGapFrame,
      );
    }
    if (shared != null) {
      return _canvasSpaceTransitionFrame(
        shared,
        ground: ground,
        outputSize: outputSize,
      );
    }
    final cut = task.cut;
    // The V effects are TRACK data on the global axis (R4). No track fade:
    // the transition row's ramp lands in [_canvasSpaceTransitionFrame]
    // above, on the frames it actually covers, and the track's static
    // opacity went with the V row's bar (I-73).
    final trackEffects = _trackChainOf(task);
    final image = await _canvasPicture(
      cut,
      task.frameIndex,
      trackEffects,
      outputSize: outputSize,
    );
    // F-192: a lone F.I/F.O/W.I/W.O is ONE contribution, so it never reached
    // the transition mix above — ↩️its fade was simply missing from a
    // canvas-size export. Its screen lands here, on this one frame.
    final veils = _veilsOf(task);
    if (veils.isEmpty) {
      return image.clone();
    }
    return _frameOf<_BakedFrame>(
      (
        ground: ground,
        cut: (picture: ByIdentity(image), weight: 1, veils: ByList(veils)),
      ),
      width: image.width,
      height: image.height,
      paint: _paintBakedFrame,
    );
  }

  /// The screens one-sided transitions lay over [task]'s cut at its frame
  /// ([cutTransitionVeilsAt]) — the frame's place on the cut's own TRACK
  /// axis ([_entryOf]).
  List<TransitionVeil> _veilsOf(ExportFrameTask task) {
    final own = _entryOf(task);
    if (own == null) {
      return const [];
    }
    return cutTransitionVeilsAt(
      cutStart: own.startFrame,
      cutEnd: own.endFrame,
      spans: session.transitions.transitionSpansOfTrack(own.trackId),
      globalFrame: own.startFrame + task.frameIndex,
    );
  }

  /// The cuts this frame is mixed from and the space they share — null when
  /// only one cut contributes (the ordinary bake) or when the contributors
  /// disagree on their canvas size, which leaves no shared space to mix in.
  ///
  /// The weights come out already source-over composed.
  _SharedTransitionSpace? _sharedTransitionSpace(ExportFrameTask task) {
    final own = _entryOf(task);
    if (own == null) {
      return null;
    }
    // This cut's own TRACK axis: a transition is a track's, so the partner can
    // only come from here.
    final entries = [
      for (final entry in _layout)
        if (entry.trackId == own.trackId) entry,
    ];
    final globalFrame = own.startFrame + task.frameIndex;
    final contributions = resolveTransitionContributions(
      playlist: entries,
      spans: session.transitions.transitionSpansOfTrack(own.trackId),
      globalFrameIndex: globalFrame,
    );
    if (contributions.length < 2) {
      return null;
    }
    final size = contributions.first.cut.canvasSize;
    for (final contribution in contributions) {
      if (contribution.cut.canvasSize != size) {
        return null;
      }
    }
    final unitAlphas = _unitAlphas([
      for (final contribution in contributions)
        (cut: contribution.cut, opacity: contribution.opacity),
    ]);
    return (
      contributions: contributions,
      size: size,
      weights: sourceOverWeights(unitAlphas),
      globalFrame: globalFrame,
    );
  }

  /// A CANVAS-size video frame that two cuts share, because a transition
  /// reaches across the boundary here ([shared]).
  ///
  /// Each cut is drawn with its own chain and unit weight, in the order the
  /// resolver returns them (leaving cut first) — the camera path's rules,
  /// in canvas space instead of the camera frame.
  Future<ui.Image> _canvasSpaceTransitionFrame(
    _SharedTransitionSpace shared, {
    required ui.Color? ground,
    CanvasSize? outputSize,
  }) async {
    final size = outputSize ?? shared.size;
    return _frameOf<_MixedFrame>(
      (
        size: size,
        ground: ground,
        cuts: ByList([
          for (final (i, contribution) in shared.contributions.indexed)
            (
              picture: ByIdentity(
                await _canvasPicture(
                  contribution.cut,
                  contribution.localFrameIndex,
                  // The V row's chain on this contribution, keys included —
                  // the dissolve weights what the chain made, not what it
                  // started from.
                  _trackChainAt(
                    contribution.cut,
                    shared.globalFrame,
                    frameIndex: contribution.localFrameIndex,
                  ),
                  outputSize: outputSize,
                ),
              ),
              weight: shared.weights[i].clamp(0.0, 1.0),
              // F-192: a one-sided transition's own screen, inside this
              // contribution's weight — the painter's unit, in canvas
              // space.
              veils: ByList(contribution.veils),
            ),
        ]),
      ),
      width: size.width,
      height: size.height,
      paint: _paintMixedFrame,
    );
  }

  /// The track stack at [task]'s frame, bottom up — read once for its
  /// render and for the run that counts what it shows ([videoRun]).
  List<TrackStackContribution> _stackPositionsOf(ExportFrameTask task) =>
      resolveTrackStackContributions(
        layout: _layout,
        spansOf: session.transitions.transitionSpansOfTrack,
        globalFrameIndex: (_entryOf(task)?.startFrame ?? 0) + task.frameIndex,
      );

  /// The camera-frame video frame as the display's track stack (R3a).
  ///
  /// The task's cut names the frame's GLOBAL index (its layout start plus
  /// the local index — negative for a leading-gap task, which lands inside
  /// the gap exactly); every track covering that index lays its cut's unit
  /// as playback lays it ([_stackUnit]) — the stage on the bottom covered
  /// track only, thinned there as a whole, upper tracks thinning their own
  /// contribution.
  ///
  /// The frame is made of its units, and two stacks of units are one
  /// picture by the painters' own word ([_StackUnits]).
  Future<ui.Image> _renderTrackStackForVideo(
    ExportFrameTask task, {
    required bool preserveAlpha,
    CanvasSize? outputSize,
  }) async {
    final positions = _stackPositionsOf(task);
    // The unit alphas, and then the source-over weights that make the stack
    // read as that mix (see [sourceOverWeights]) — grouped by track here,
    // because an upper track thins only its own contribution.
    final unitAlphas = _unitAlphas([
      for (final position in positions)
        (cut: position.cut, opacity: position.opacity),
    ]);
    final weights = trackGroupSourceOverWeights(positions, unitAlphas);

    final size = outputSize ?? session.camera.cameraFrameSize;
    return _frameOf<_StackFrame>(
      (
        size: size,
        // The BACKDROP (R3b), everywhere the stack leaves uncovered: gap
        // frames, a posed stage sliding off, a fade thinning the stack
        // away.
        ground: _backdropGround(preserveAlpha: preserveAlpha),
        stack: _StackUnits([
          for (final (i, position) in positions.indexed)
            await _stackUnit(
              position,
              weights[i],
              preserveAlpha: preserveAlpha,
              outputSize: outputSize,
            ),
        ]),
      ),
      width: size.width,
      height: size.height,
      paint: _paintStackFrame,
    );
  }

  /// One position of the track stack as playback lays it
  /// (`CanvasTrackStackView._unit`): the stage's apron under its cut where
  /// it is the stage, the cut's picture through its camera — its paper laid
  /// with its rows there, held ([_cutPicture]), under the V row's chain —
  /// and its names and veils over that, at [weight].
  ///
  /// ↩️The picture was the cut's canvas-space composite at full size, which
  /// the painter projected through the camera in one bilinear draw — where
  /// the canvas reduces by halvings, so that at the user's camera zoom of
  /// 0.42–0.52 a line a pixel wide came and went (card
  /// video-export-speed-Q2, 유저 2026-10-13: 「캔버스 규칙으로」).
  Future<_StackUnit> _stackUnit(
    TrackStackContribution position,
    double weight, {
    required bool preserveAlpha,
    CanvasSize? outputSize,
  }) async {
    final cut = position.cut;
    final frameIndex = position.localFrameIndex;
    final view = _viewFor(cut, frameIndex, ExportSizeMode.camera);
    // Track effects at the frame's GLOBAL position (R4) — the stack's
    // own axis.
    final trackEffects = _trackChainAt(
      cut,
      position.globalFrameIndex,
      frameIndex: frameIndex,
    );
    // The stage belongs to the bottom covered TRACK, and to every
    // contribution of it: an O.L is a 場面転換, so the arriving cut brings
    // its own paper and the weights cross-fade the whole screen. Keyed to
    // the bottom CONTRIBUTION this baked a superimpose.
    final isStage = position.isBottomTrack;
    // The stage's paper is laid with its rows, in its picture, as playback
    // lays it (`FramePage.paintPaper`).
    final paper = isStage ? session.projectSettings.projectBackground : null;
    final picture = await _cutPicture(
      ExportFrameTask(cut: cut, frameIndex: frameIndex),
      view,
      route: ('stack', view, outputSize),
      outputSize: outputSize,
      trackEffects: trackEffects,
      ground: _clear,
      paper: paper,
    );
    final project = session.repository.requireProject();
    // A preview's size of the frame is the view playback shows a frame at
    // ([PlaybackFramePainter.viewport]): what the painters raster, the names
    // above all, rasters at the scale it is shown at.
    final shownAt = outputSize == null
        ? null
        : CanvasViewport(zoom: outputSize.width / view.frameSize.width);
    PlaybackFramePainter painter({required bool under}) => PlaybackFramePainter(
      canvasSize: cut.canvasSize,
      pasteboardReach: project.pasteboardReach,
      viewport: shownAt,
      cameraPose: view.pose,
      cameraFrameSize: view.frameSize,
      // The paper is the picture's; an absent one prints nothing.
      paintPaper: false,
      // The alpha matrix (user 2026-07-29): alpha masters exclude the
      // backdrop AND the pasteboard — they are compositing sources,
      // and the paper carries its own alpha. A pasteboard that is NONE
      // (F-114) prints nothing either: the plane is not there.
      pasteboardColor:
          under && isStage && !preserveAlpha && !project.pasteboardNone
          ? ui.Color(project.pasteboardArgb)
          : null,
      // The output IS the camera frame — there is no outside to
      // letterbox, and an alpha master needs the ground transparent.
      paintLetterbox: false,
      seNameTags: under
          ? const []
          : session.seEntries.seNameTagsForCutFrame(cut, frameIndex),
      // An upper track thins its names and veils with its picture.
      imageOpacity: isStage ? 1 : weight,
      veils: under ? const [] : position.veils,
    );
    return _StackUnit(
      under: painter(under: true),
      picture: picture,
      pictureOpacity: isStage ? 1 : weight,
      over: painter(under: false),
      fade: isStage ? weight : 1,
    );
  }

  /// One LABEL-GROUP cel (EX5): the gated members' frames composited
  /// bottom-up at their static opacities — a delivery cel is the stack
  /// (기준+어태치), not the pieces. Null when NO member has artwork.
  /// The renderer's background carries the channel choice (transparent
  /// for RGBA, the picked backing for RGB); [ExportSizeMode.camera]
  /// crops through the camera at the base cel's FIRST exposure (a cel
  /// has no time of its own — where it first shows is the honest frame).
  /// The guides laid over it are drawn in [guideColor], the colour the
  /// canvas draws them in (`guideColorOf`).
  Future<ui.Image?> renderCelGroup(
    ExportCelGroupTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
    required ui.Color guideColor,
  }) async {
    _startFrame();
    final cel = _celGroupOf(task, mode, guideColor);
    if (cel == null) {
      return null;
    }
    // The members clip as their cut clips them (I-92) — to a row of the
    // cel's. ⚠️My call: one that clips to a row the cel does not hold
    // shows nowhere, as over a base with no drawing here.
    final clips = ClipPlacing<_CelLaid>(
      blendOf: (laid) => laid.paint.blendMode,
      asClipBase: (laid) => (
        base: (row: laid.row, paint: _alone(laid.paint.effects)),
        opacity: laid.paint.opacity,
        blendMode: laid.paint.blendMode,
      ),
    );
    final stack = <CompositeNode<_CelLaid>>[];
    for (final row in cel.rows) {
      // R26 #30: the delivery cel is the stack as composited — the
      // members' strengths and blends apply.
      final [standing, ...over] = _celNumbered(
        row,
        (
          opacity: row.layer.opacity,
          blendMode: row.layer.blendMode,
          effects: row.effects,
        ),
        asOnePicture: meetsAClip(row.cut, row.layer),
      );
      clips.place(row.cut, row.layer, standing, into: stack);
      // The letters over a row that neither clips nor is clipped to — so
      // [clips] laid it last in [stack].
      stack.addAll(over);
    }
    final frameIndex = celGroupFirstExposure(task);
    return _shot(
      task.cut,
      frameIndex,
      _celStack(
        composeOverTheirBackdrops(
          stack,
          blendOf: (laid) => laid.paint.blendMode,
          paintedNormal: (laid) => (
            row: laid.row,
            paint: (
              opacity: laid.paint.opacity,
              blendMode: LayerBlendMode.normal,
              effects: laid.paint.effects,
            ),
          ),
        ),
        frameIndex: frameIndex,
      ),
      view: cel.view,
      outputSize: outputSize,
      cutsToTheCanvas: false,
      over: _laidOver([cel.guides, cel.camera]),
    );
  }

  /// [task]'s cel as the rows a layered file keeps apart, bottom-up — the
  /// ones [renderCelGroup] lays into one picture: the ground it lays them
  /// on, where it has one; each member, then each direction laid over
  /// them; then the guides and the camera's work, where they are laid.
  /// Each is drawn through the view [renderCelGroup] looks through, by
  /// itself on nothing — whole, in no blend — and carries its strength and
  /// blend for the file to lay it by. None where [renderCelGroup] draws
  /// nothing.
  ///
  /// 🗣️I-117 (유저 2026-10-21): 「셀은 출력될 셀 등 소재 하나당 해당
  /// 어태치레이어 구조 그대로 지켜서 출력」.
  ///
  /// ⚠️It starts no frame: drawn after [renderCelGroup]'s picture of the
  /// same cel, its rows read no cel that picture did not.
  List<ExportLayerRow> celGroupRows(
    ExportCelGroupTask task,
    ExportSizeMode mode, {
    required ui.Color guideColor,
  }) {
    final cel = _celGroupOf(task, mode, guideColor);
    if (cel == null) {
      return const [];
    }
    final frameIndex = celGroupFirstExposure(task);
    Future<ui.Image> drawn(
      ui.Color ground, {
      List<CompositeNode<CanvasStackRow>> nodes = const [],
      CameraOverlayPass? over,
    }) => _shot(
      task.cut,
      frameIndex,
      nodes,
      view: cel.view,
      ground: ground,
      cutsToTheCanvas: false,
      over: over,
    );
    ExportLayerRow laidOver(String name, CameraOverlayPass pass) =>
        ExportLayerRow(name: name, draw: () => drawn(_clear, over: pass));
    final strings = AppText.notation;
    return [
      if (ground.a > 0)
        ExportLayerRow(name: strings.exBackground, draw: () => drawn(ground)),
      for (final row in cel.rows)
        ExportLayerRow(
          name: row.layer.name,
          opacity: row.layer.opacity,
          blendMode: row.layer.blendMode,
          // Photoshop clips as the row does (I-92) — the switch as the row
          // holds it, as [frameRows] carries it.
          clipped: clipsToLayerBelow(row.layer),
          draw: () => drawn(
            _clear,
            nodes: _celStack(
              _celNumbered(row, _alone(row.effects), asOnePicture: false),
              frameIndex: frameIndex,
            ),
          ),
        ),
      if (cel.guides case final guides?) laidOver(strings.exLayGuides, guides),
      if (cel.camera case final camera?) laidOver(strings.tlKindCamera, camera),
    ];
  }

  /// What [renderCelGroup] lays and [celGroupRows] keeps apart: [task]'s
  /// rows bottom-up — the members, then the directions laid over them —
  /// the view they are seen through, and what the hand laid over all of
  /// it. Null when no member has artwork: over a cel with none there is
  /// nothing to lay anything on.
  _CelGroup? _celGroupOf(
    ExportCelGroupTask task,
    ExportSizeMode mode,
    ui.Color guideColor,
  ) {
    // A cel has no time of its own, so the group's FX sample at the base
    // cel's FIRST exposure — the same honest frame the camera pose uses,
    // in the cut that shows the cel ([ExportCelGroupTask.cut], F-300).
    final firstExposure = celGroupFirstExposure(task);
    final rows = <_CelRow>[];
    // One picture of the stack: [layer]'s [frame] as [cut] holds it.
    void lay(Cut cut, Layer layer, Frame? frame) {
      if (frame == null) {
        return;
      }
      if (!_hasArtwork(cut, layer, frame)) {
        return;
      }
      rows.add((
        cut: cut,
        layer: layer,
        frame: frame,
        // R6: the members' EFFECTS are the chain each row wears in its cut
        // ([chainWornBy] — an attached row its base's, short of the cel
        // number), as the tab's 레이어 FX keeps it ([chainAsOutput]) — the
        // one answer every tab reads.
        //
        // The cel tab's FX used to be a hardcoded false ("cels stay raw
        // artwork"); 유저 2026-08-27 made it the tab's own choice,
        // defaulting ON — see [CelsExportSpec.layerFx]. Blend and static
        // opacity are display properties and stay whatever it is.
        effects: resolveLayerEffectsAt(
          effects: _outputChainOf(chainWornBy(cut, layer)),
          frameIndex: firstExposure,
          blocks: chainBlocksOf(cut, layer),
          worn: chainWornAs(cut, layer),
        ),
        placement: referenceMoveAt(_asOutput(layer), firstExposure),
      ));
    }

    for (var i = 0; i < task.members.length; i += 1) {
      lay(task.cut, task.members[i], task.memberFrames[i]);
    }
    if (rows.isEmpty) {
      return null;
    }
    // What is laid over the cel goes on top of all of it — and over a cel
    // with no artwork there is nothing to lay it on (the null above).
    for (final over in task.overlays) {
      lay(over.cut, over.layer, over.frame);
    }
    final view = _viewFor(task.cut, firstExposure, mode);
    return (
      rows: rows,
      view: view,
      guides: _guidesOver(task, view, guideColor),
      camera: _cameraWorkOver(task, view),
    );
  }

  /// [chain] as the window's 레이어 FX keeps it — itself for a picture of
  /// the screen ([_asOutput]).
  List<LayerEffect> _outputChainOf(List<LayerEffect> chain) =>
      switch (layerFx) {
        final fx? => chainAsOutput(chain, fx),
        null => chain,
      };

  /// [row] — a row of its cel — as the tree of a cel lays it with [paint]:
  /// its leaf, with the letters its cel number writes over it, or the
  /// group the two make ([celNumberedRow], [asOnePicture]).
  List<CompositeNode<_CelLaid>> _celNumbered(
    _CelRow row,
    RowPaint paint, {
    required bool asOnePicture,
  }) => celNumberedRow(
    paint: paint,
    rowOf: (paint) => (row: row, paint: paint),
    text: celNumberText(
      rowName: row.layer.name,
      drawingName: row.frame.name,
      kind: row.layer.kind,
    ),
    paper: row.cut.canvasSize,
    asOnePicture: asOnePicture,
  );

  /// [effects] whole and in no blend: the picture a layered file keeps and
  /// lays by the row's own strength and blend ([celGroupRows]), or a clip's
  /// base, whose strength and blend are its group's.
  static RowPaint _alone(List<ResolvedLayerEffect> effects) =>
      (opacity: 1, blendMode: LayerBlendMode.normal, effects: effects);

  /// [stack] — a cel's rows, each as the cel lays it by its paint — as the
  /// canvas stacks rows: each row's cel by its key, its chain run as the
  /// device runs it ([_pluginsOf]) at the frame the cel is sampled at
  /// ([frameIndex], [celGroupFirstExposure]), and each whose chain reads
  /// rows of its cut reading them ([withTheRowsTheyRead]) as the cel lays
  /// its own: on paper ([_onPaper]).
  ///
  /// 🗣️I-132-Q26 a (유저 2026-10-29): 「셀처럼 종이 그대로 읽는다」 — the cel
  /// the map's row exposes there, where it is drawn on its paper, at its
  /// own strength (Q24 b); a folder as what it holds (Q25 a).
  List<CompositeNode<CanvasStackRow>> _celStack(
    List<CompositeNode<_CelLaid>> stack, {
    required int frameIndex,
  }) {
    final cutOf = Map<CanvasStackRow, Cut>.identity();
    CanvasStackRow laidInTheCel(_CelLaid laid) {
      final row = laid.row;
      final request = CanvasLayerImageRequest(
        frameKey: session.brushFrameKeyForCut(
          row.cut,
          row.layer.id,
          row.frame.id,
        ),
        opacity: laid.paint.opacity,
        blendMode: laid.paint.blendMode,
        placement: row.placement,
        effects: _pluginsOf(
          row.cut,
        )(laid.paint.effects, cut: row.cut, frameIndex: frameIndex),
      );
      cutOf[request] = row.cut;
      return request;
    }

    return withTheRowsTheyRead(
      mapCompositeLeaves<_CelLaid, CanvasStackRow>(stack, laidInTheCel),
      effectsOf: _effectsOf,
      drawnOf: (row, by) => switch (cutOf[by]) {
        final cut? => switch (rowAsRead(
          cut: _onPaper(cut),
          row: row,
          frameIndex: frameIndex,
        )) {
          final read? => session.editingCanvas.stackOfRows(
            cut,
            frameIndex,
            read,
            stackCut: _onPaper(cut),
          ),
          null => null,
        },
        null => null,
      },
    );
  }

  /// [row]'s chain, whole.
  static List<ResolvedLayerEffect> _effectsOf(CanvasStackRow row) =>
      switch (row) {
        CanvasLayerImageRequest(:final effects) => effects,
        CanvasActiveLayerRow(:final effects) => effects,
      };

  /// [cut] as a cel lays its rows: as the window's 레이어 FX keeps each
  /// ([_asOutput]), on its paper — no row's transform moving it, only a
  /// reference's fx ([referenceMoveAt]) — at its static strength, as
  /// [_celGroupOf] lays a member.
  Cut _onPaper(Cut cut) => _onPaperByCut[cut] ??= cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        _asOutput(layer).copyWith(transformEnabled: false),
    ],
  );

  /// What the hand laid over a cel, one pass over another in [passes]'
  /// order — the guides under the camera's work. Null where nothing is.
  ///
  /// ⚠️The order is my call, not the user's (I-105): the camera's marks are
  /// what is said of the drawing, the guides what it was drawn over.
  CameraOverlayPass? _laidOver(
    List<CameraOverlayPass?> passes,
  ) {
    final laid = passes.nonNulls.toList();
    if (laid.isEmpty) {
      return null;
    }
    return (canvas, rasterScale) {
      for (final pass in laid) {
        pass(canvas, rasterScale);
      }
    };
  }

  /// The cut's guides laid over [task]'s cel (I-105) — those of the cut the
  /// hand laid them in ([ExportCelGroupTask.listedCut]) that a cel wears
  /// ([exportLaidGuidesOf]), in [color]: the picture 래스터라이즈 bakes,
  /// the faint line the canvas draws at rest on the paper alone
  /// ([paintGuideLines]), at the camera's work's sizes — a pixel of the
  /// file for each pixel of the screen (I-89-Q20). Null where none is laid.
  ///
  /// 🗣️I-105-Q2 (유저 2026-10-16): 「래스터라이즈와 같은 … 모습」 — and
  /// 「애초에 래스터라이즈도 캔버스에 보이는 옅은선 그대로 래스터라이즈하도록
  /// 법 통일」: one picture, drawn by one function.
  CameraOverlayPass? _guidesOver(
    ExportCelGroupTask task,
    CameraView view,
    ui.Color color,
  ) => _guideLinesOver(
    task.listedCut,
    task.guidesLaid ? exportLaidGuidesOf(task.listedCut) : const [],
    view,
    color,
  );

  /// [guides] of [cut] as the canvas draws them at rest ([paintGuideLines]),
  /// through [view]. Null for none.
  CameraOverlayPass? _guideLinesOver(
    Cut cut,
    List<DrawingGuide> guides,
    CameraView view,
    ui.Color color,
  ) {
    if (guides.isEmpty) {
      return null;
    }
    return (canvas, _) => paintGuideLines(
      canvas,
      guides,
      canvasSize: cut.canvasSize,
      color: color,
      // As for the camera's work: a canvas pixel is [CameraPose.zoom] of
      // the file's.
      scale: view.pose.zoom,
    );
  }

  /// The camera's work laid over [task]'s cel (CAM, I-89-Q18) — the camera
  /// of the cut the hand laid it in ([ExportCelGroupTask.listedCut]): its
  /// path as the canvas writes it off the camera's row
  /// ([CameraPathOverlay.standing]), at its sizes ([CameraPathOverlay.sizes])
  /// in the file's pixels — as large on the picture as the canvas draws
  /// them ([CameraPathOverlay.printedAt], F-421) — on the canvas [view]
  /// looks at, over everything laid before it. Null where none is laid, or
  /// the camera moves nothing ([CameraPath.of]).
  ///
  /// 🗣️I-89-Q20 (유저 2026-10-12): 「캔버스와 같은 픽셀 수」 — ⛔not grown with
  /// the camera's frame as the conte sheet's are, though a large frame
  /// prints them small.
  CameraOverlayPass? _cameraWorkOver(
    ExportCelGroupTask task,
    CameraView view,
  ) => task.cameraLaid ? _cameraPathOver(task.listedCut, view) : null;

  /// [cut]'s camera path alone, on nothing, over its whole canvas — what a
  /// cel of it in the canvas's size lays with the camera's work
  /// ([_cameraWorkOver]); null where the camera moves nothing. The AE
  /// Script tab's guide over the canvas comp (ae-script-export-Q3).
  Future<ui.Image>? cameraPathOf(Cut cut) {
    final view = cameraViewOver(cut.canvasSize.canvasRect);
    final pass = _cameraPathOver(cut, view);
    if (pass == null) {
      return null;
    }
    return _shot(
      cut,
      0,
      const [],
      view: view,
      ground: _clear,
      cutsToTheCanvas: false,
      over: pass,
    );
  }

  /// [cut]'s camera path as [_cameraWorkOver] lays it through [view] — null
  /// where the camera moves nothing ([CameraPath.of]).
  CameraOverlayPass? _cameraPathOver(Cut cut, CameraView view) {
    final path = CameraPath.of(cut, session.camera.cameraFrameSize);
    if (path == null) {
      return null;
    }
    return _marksOver(
      cut,
      cameraPathMarks(
        path,
        place: (point) => point,
        // The file is the view's frame at full size.
        sizes: CameraPathOverlay.sizesOnTheCanvas(view.pose),
        layer: SheetPaintLayer.picture,
      ).toList(),
    );
  }

  /// [marks], placed on [cut]'s canvas, as the sheets print theirs.
  CameraOverlayPass _marksOver(Cut cut, List<SheetMark> marks) {
    final paper = cut.canvasSize.canvasRect.size;
    return (canvas, _) => const SheetCanvasPrinter(style: conteTextStyle).paint(
      canvas,
      paper,
      (viewport: null, devicePixelRatio: 1, paper: paper),
      marks,
    );
  }

}

/// The frames of a run — a video's ([ExportFrameRenderer.videoRun]) or a
/// picture sequence's ([ExportFrameRenderer.stillRun]).
final class ExportRun {
  ExportRun._({
    required List<ExportFrameTask> plan,
    required Future<ui.Image> Function(ExportFrameTask task) draw,
  }) : _plan = plan,
       _draw = draw;

  final List<ExportFrameTask> _plan;
  final Future<ui.Image> Function(ExportFrameTask task) _draw;

  /// Frame [index] of the run, a picture of the caller's own to dispose.
  ///
  /// ⚠️One at a time, in order: a frame holds what the frame after it may
  /// show again for one more frame ([HeldPictures]), and lets go of what
  /// the frame before it held.
  Future<ui.Image> frame(int index) => _draw(_plan[index]);
}

/// The cuts a canvas-size video frame mixes, when a transition puts two in
/// one space ([ExportFrameRenderer._sharedTransitionSpace]).
typedef _SharedTransitionSpace = ({
  List<TransitionContribution> contributions,
  CanvasSize size,
  List<double> weights,
  int globalFrame,
});

// --- what a video frame is made of ------------------------------------------
//
// Each is a VALUE that says when two frames are one picture, and the one
// thing its paint is handed (`ExportFrameRenderer._frameOf`). The paints are
// down here, out of the renderer, so that they have nothing else to read.

/// A frame nothing plays in: the ground alone.
typedef _GapFrame = ({CanvasSize size, ui.Color? ground});

/// One cut's finished [picture] as a canvas-size frame takes it: thinned to
/// [weight], under its own [veils].
///
/// ↩️It carried the V row's chain as well, filtering the finished picture —
/// the names drawn over it included — until the chain went into the cut's
/// tree, as every route lays it ([underTheCutsFx]).
typedef _CutInFrame = ({
  ByIdentity<ui.Image> picture,
  double weight,
  ByList<TransitionVeil> veils,
});

/// A canvas-size frame of one cut, baked over the ground.
typedef _BakedFrame = ({ui.Color? ground, _CutInFrame cut});

/// A canvas-size frame a transition mixes from two cuts, leaving cut first.
typedef _MixedFrame = ({
  CanvasSize size,
  ui.Color? ground,
  ByList<_CutInFrame> cuts,
});

/// The camera frame as its track stack.
typedef _StackFrame = ({CanvasSize size, ui.Color? ground, _StackUnits stack});

/// One covered cut's share of a camera frame, as playback lays it
/// (`CanvasTrackStackView._unit`): the stage [under] its [picture], the
/// picture at [pictureOpacity], its names and veils [over] it — the whole
/// thinned to [fade] as one layer.
final class _StackUnit {
  _StackUnit({
    required this.under,
    required this.picture,
    required this.pictureOpacity,
    required this.over,
    required this.fade,
  });

  final PlaybackFramePainter under;
  final ui.Image picture;
  final double pictureOpacity;
  final PlaybackFramePainter over;
  final double fade;

  /// Every input its pixels depend on — the painters' by their own word
  /// ([RepaintOnProps.props]: the law the screen repaints by).
  Object get props =>
      (under.props, ByIdentity(picture), pictureOpacity, over.props, fade);
}

/// The units of one camera frame's track stack, bottom up.
///
/// Two stacks are ONE picture when each unit lays what its fellow laid
/// ([_StackUnit.props]).
final class _StackUnits {
  _StackUnits(this.all);

  final List<_StackUnit> all;

  late final List<Object> _props = [for (final unit in all) unit.props];

  @override
  bool operator ==(Object other) =>
      other is _StackUnits && listEquals(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

void _paintGround(ui.Canvas canvas, ui.Rect bounds, ui.Color? ground) {
  if (ground != null) {
    canvas.drawRect(bounds, ui.Paint()..color = ground);
  }
}

void _paintGapFrame(ui.Canvas canvas, _GapFrame made) =>
    _paintGround(canvas, made.size.canvasRect, made.ground);

void _paintBakedFrame(ui.Canvas canvas, _BakedFrame made) {
  final picture = made.cut.picture.value;
  final bounds = ui.Rect.fromLTWH(
    0,
    0,
    picture.width.toDouble(),
    picture.height.toDouble(),
  );
  // The BACKDROP ground (R3b): a fade thins the frame down to it. An alpha
  // master leaves it transparent instead.
  _paintGround(canvas, bounds, made.ground);
  _paintCutInFrame(canvas, bounds, made.cut);
}

void _paintMixedFrame(ui.Canvas canvas, _MixedFrame made) {
  final bounds = made.size.canvasRect;
  _paintGround(canvas, bounds, made.ground);
  for (final cut in made.cuts.value) {
    _paintCutInFrame(canvas, bounds, cut);
  }
}

void _paintStackFrame(ui.Canvas canvas, _StackFrame made) {
  final bounds = made.size.canvasRect;
  _paintGround(canvas, bounds, made.ground);
  for (final unit in made.stack.all) {
    // The FADE is transparency (R3b): the stage's whole contribution —
    // apron, paper, picture, names, veils — thins as one layer, revealing
    // whatever lies behind (the tracks below, then the backdrop).
    final fading = unit.fade < 1;
    if (fading) {
      canvas.saveLayer(bounds, ui.Paint()..color = alphaOnly(unit.fade));
    }
    unit.under.paint(canvas, bounds.size);
    canvas.drawImage(
      unit.picture,
      ui.Offset.zero,
      ui.Paint()..color = alphaOnly(unit.pictureOpacity),
    );
    unit.over.paint(canvas, bounds.size);
    if (fading) {
      canvas.restore();
    }
  }
}

/// ONE cut laid into a canvas-size frame — the baked frame's only cut, and
/// each cut of a mixed one.
///
/// ↩️The two routes each wrote this out, a fade's weight in one and a
/// dissolve's in the other.
void _paintCutInFrame(ui.Canvas canvas, ui.Rect bounds, _CutInFrame cut) {
  // The fade is transparency (R3b): the frame thins as one layer over the
  // ground; no target-color wash.
  if (cut.weight < 1) {
    canvas.saveLayer(bounds, ui.Paint()..color = alphaOnly(cut.weight));
  }
  canvas.drawImage(cut.picture.value, ui.Offset.zero, ui.Paint());
  paintTransitionVeils(canvas, bounds, cut.veils.value);
  if (cut.weight < 1) {
    canvas.restore();
  }
}
