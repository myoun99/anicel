import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/movie_cel.dart';
import '../../models/transition_geometry.dart'
    show TransitionVeil, cutTransitionVeilsAt;
import '../../services/brush_frame_store.dart' show CelRead;
import '../../models/composite_tree.dart';
import '../../services/cut_frame_composite_plan.dart';
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
    show CameraView, cameraViewOver, pictureView;
import '../camera/camera_frame_render_service.dart';
import '../../services/composite_effect_paint.dart'
    show alphaOnly, resolveCompositeEffectPlan;
import '../canvas/subtree_image_composite.dart' show steppedForChain;
import '../editor_session_manager.dart';
import '../playback/playback_frame_painter.dart';
import '../playback/transition_veil_paint.dart';
import '../track_effect_paint_policy.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'export_cel_group_plan.dart';
import '../../models/playback_quality.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../../services/se_name_tag_plan.dart';
import '../timeline/memo_token.dart';
import 'export_plan.dart';
import 'held_pictures.dart';
import 'held_rows.dart';
import 'offscreen_raster.dart';

/// The ground a frame is rendered on unless a caller names another — what
/// the storyboard's and the conte's pictures stand on, and so what a conte
/// picture drawn live stands on too.
const ui.Color exportFrameGround = ui.Color(0xFFFFFFFF);

/// Where a cel stands in the project: its cut, its row, its drawing.
typedef _CelAt = (CutId, LayerId, FrameId);

/// Renders export output at full quality straight from the brush store, so
/// exports never depend on the playback quality setting or its caches.
///
/// It reads the store as a LOOK ([CelRead.look]) and holds only what the
/// frame it draws and the one before it read ([_startFrame]).
class ExportFrameRenderer {
  ExportFrameRenderer({
    required this.session,
    CameraFrameRenderService? renderService,
    this.applyLayerFx = true,
    ui.Color background = exportFrameGround,
  }) : renderService =
           renderService ?? CameraFrameRenderService(background: background);

  final EditorSessionManager session;
  final CameraFrameRenderService renderService;

  /// The export dialog's 'Apply layer FX' toggle: true (default) exports
  /// WYSIWYG with playback (per-layer fx switches respected); false
  /// bypasses EVERY layer's FX — raw cels at their static opacity, no
  /// transforms. The cut fade and the camera work are cut-level and stay.
  final bool applyLayerFx;

  /// The cels the frame being drawn has read, and the ones the frame before
  /// it read — all this renderer holds (card `render-reads-thaw-into-hot`).
  /// A LOOK is decoded for the render and never kept by the store, so what
  /// is held here is held outside every budget.
  ///
  /// ↩️It held its CUT's cels for the whole run (07-29, #780 — every cel was
  /// hot then, so a read held nothing new): on a long cut, every drawing at
  /// the canvas's size at once. Two frames are all the cache is for — a
  /// drawing held across a run of frames is read once for the run.
  var _thisFrame = <_CelAt, BitmapSurface?>{};
  var _frameBefore = <_CelAt, BitmapSurface?>{};

  /// The pictures the VIDEO frame being drawn is made of and the ones the
  /// frame before it was made of, each under what it was made of: a cut's
  /// whole picture in its own canvas space, and the finished frame. Held
  /// for one more frame like the cels above ([HeldPictures]), and GPU
  /// pictures, so let go by hand ([dispose]).
  ///
  /// 🚨A CUT'S PICTURE IS KEYED BY ITS SIGNATURE
  /// ([computeCutFrameCompositeSignature]) — the law the playback cache is
  /// addressed by. A drawing held across a run of frames is composited once
  /// for the run, however the camera moves over it.
  ///
  /// ↩️Every frame composited every row again, and read the result back
  /// (F-289, measured 2026-10-07 on the user's own film: of its 1,857
  /// frames 1,687 show the composite the frame before them showed, and
  /// 1,483 are that frame's picture, camera and all).
  late final HeldPictures _pictures = HeldPictures(onLetGo: _rows.letGoOf);

  /// The rows the cut pictures in [_pictures] are made of, each held while
  /// a picture made of it is — so the picture a frame changes on composes
  /// only the rows that changed (F-289-Q21). Their room is lent by
  /// playback's line of the memory allowance, whose caches give way to
  /// them while the run goes.
  late final HeldRows _rows = HeldRows(
    room: () => session.playbackRig.playbackCache.lendableBytes,
    onHeld: session.playbackRig.playbackCache.lend,
  );

  /// How many pictures this renderer has had to make (test hook) — a frame
  /// that is the picture before it makes none.
  @visibleForTesting
  int get debugPicturesMade => _pictures.made;

  /// How many row pictures this renderer has composed (test hook) — a row a
  /// held picture is made of composes once.
  @visibleForTesting
  int get debugRowsMade => _rows.made;

  /// Starts the next frame: what the frame before the last one read is let
  /// go, and what the last one read is kept for one more.
  ///
  /// ⚠️Once per frame a caller asked for — a transition's two cuts are one
  /// frame, and the composite inside a video frame starts none ([_composite]).
  void _startFrame() {
    _frameBefore = _thisFrame;
    _thisFrame = {};
    _pictures.nextFrame();
    _rows.fitRoom();
  }

  /// Lets go of the pictures a video run held — and with them the rows they
  /// were made of, which are held under nothing else. The run's to call
  /// when its last frame is out.
  void dispose() => _pictures.dispose();

  /// Keeps the cels [signature]'s picture is made of for one more frame.
  ///
  /// A held picture reads no cel, so the cels under it would be let go
  /// while it stands — and the frame ONE row changes on would read every
  /// row of the cut again.
  void _carryCelsOf(CutId cut, CutFrameCompositeSignature signature) {
    for (final layer in signature.layers) {
      final at = (cut, layer.layerId, layer.frameId);
      if (!_thisFrame.containsKey(at) && _frameBefore.containsKey(at)) {
        _thisFrame[at] = _frameBefore[at];
      }
    }
  }

  BitmapSurface? _surfaceFor(Cut cut, Layer layer, Frame frame) {
    // 🚨A MOVIE's pictures are read through, never held here: a movie is a
    // full-canvas picture per FRAME, and the store's budget decides how long
    // one lives; [_hydrate] puts back what a frame needs.
    if (movieCelOf(frame.id) != null) {
      return _readSurface(cut, layer, frame);
    }
    final at = (cut.id, layer.id, frame.id);
    return _thisFrame.putIfAbsent(
      at,
      () => _frameBefore.containsKey(at)
          ? _frameBefore[at]
          : _readSurface(cut, layer, frame),
    );
  }

  BitmapSurface? _readSurface(Cut cut, Layer layer, Frame frame) {
    _celReads += 1;
    final frameKey = session.brushFrameKeyForCut(cut, layer.id, frame.id);
    // R19 P3b: the baked raster is the truth — a READ-ONLY reference
    // (valid display cache first, else baked; the coordinator donates
    // on every commit, undo and redo); null = an empty cel.
    //
    // 🚨A LOOK: a cel that is cold or only in the file is decoded for this
    // render and nothing is kept. ↩️It thawed into the hot tier (the cold
    // tier, R20-A1, made a read do that) — measured 09-28, the storyboard's
    // pictures of a 13-cut film took the tier from 149 to 529MB and pushed
    // the cut being drawn toward cooling. A look still decodes at the
    // canvas's size, which is why those pictures render one at a time
    // ([StoryboardCutThumbnailStore]).
    return session.renderCaches.brushFrameStore.currentSurfaceWithoutReplay(
      frameKey,
      canvasSize: cut.canvasSize,
      read: CelRead.look,
    );
  }

  int _celReads = 0;

  /// How many cels this renderer has read from the store (test hook).
  @visibleForTesting
  int get debugCelReads => _celReads;

  /// How many surfaces the renderer holds right now (test hook) — a movie's
  /// pictures are never among them.
  @visibleForTesting
  int get debugHeldSurfaceCount => {
    for (final frame in [_thisFrame, _frameBefore])
      for (final MapEntry(:key, :value) in frame.entries)
        if (value != null) key,
  }.length;

  /// Decodes the movie pictures [cut] shows at [frameIndex] before its
  /// composite is planned: export walks frames nobody is looking at, so
  /// nothing else will have (the playback warmer awaits the same call).
  Future<void> _hydrate(Cut cut, int frameIndex) =>
      session.movieCels.hydrate(cut, frameIndex);

  /// Cuts whose FX-stripped view has already been built (memoized: the
  /// stream renders the same cut for many frames).
  final Map<CutId, Cut> _fxStrippedByCut = {};

  /// The cut as this RENDER should see it. With [applyLayerFx] on — the
  /// default, and what the video/PNG paths use — that is the cut itself, so
  /// the render is WYSIWYG with playback down to the rows' own fx switches.
  ///
  /// With it OFF (the cel exports: "cels stay raw artwork") every row's
  /// transform switch and every effect's switch read false, which is the
  /// master toggle expressed as DATA. Cheaper to reason about than an
  /// override threaded through the plan, and impossible for another route
  /// to forget: the plan renders exactly the cut it is given.
  Cut _cutForRender(Cut cut) {
    if (applyLayerFx) {
      return cut;
    }
    return _fxStrippedByCut.putIfAbsent(
      cut.id,
      () => cut.copyWith(
        layers: [
          for (final layer in cut.layers)
            layer.copyWith(
              transformEnabled: false,
              effects: [
                for (final effect in layer.effects) effect.copyWith(enabled: false),
              ],
            ),
        ],
      ),
    );
  }

  /// Each contribution's UNIT ALPHA: its own share of the frame times its
  /// track's static opacity and fade.
  ///
  /// ⚠️Both bakes below need exactly this before they can weigh anything,
  /// and they weigh it differently afterwards ([sourceOverWeights] within
  /// one canvas, [trackGroupSourceOverWeights] across tracks). The half
  /// they share is here; the half they don't stays at the call site.
  List<double> _unitAlphas(List<({Cut cut, double opacity})> contributions) {
    return [
      for (final contribution in contributions)
        contribution.opacity *
            session.opacityVerbs.trackStaticOpacityForCut(contribution.cut.id),
    ];
  }

  /// Canvas-space composites for the stack bake: TRANSPARENT backing, so
  /// an upper track's frame never blanks the tracks below — the paper
  /// belongs to the bottom covered track and the assembler paints it.
  static const CameraFrameRenderService _stackRenderService =
      CameraFrameRenderService(background: ui.Color(0x00000000));

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
  /// [withNameTags] draws the SE rows' on-canvas name tags over the
  /// picture (R5b) — ON for presentation renders (the アフレコ video),
  /// OFF for compositing sources: PNG sequences already stay unposed and
  /// unfaded for the same reason, and a thumbnail has no room for them.
  Future<ui.Image> renderComposite(
    ExportFrameTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
    bool withNameTags = false,
  }) {
    _startFrame();
    return _composite(
      task,
      _viewFor(task.cut, task.frameIndex, mode),
      outputSize: outputSize,
      nameTags: withNameTags
          ? session.seEntries.seNameTagsForCutFrame(task.cut, task.frameIndex)
          : const [],
    );
  }

  /// A panel's picture — the storyboard's, the conte's: [cut] at
  /// [frameIndex] through its camera, or over the canvas [region] a conte
  /// cell's moving camera sweeps ([pictureView]) — [width] pixels wide, in
  /// the shape of what it shows, reduced as the canvas's display reduces
  /// ([CameraFrameRenderService.renderThroughCamera]'s `displayLevels`).
  Future<ui.Image> renderPicture(
    Cut cut,
    int frameIndex, {
    required int width,
    ui.Rect? region,
  }) async {
    final view = pictureView(
      _viewFor(cut, frameIndex, ExportSizeMode.camera),
      region,
    );
    _startFrame();
    await _hydrate(cut, frameIndex);
    return renderService.renderThroughCamera(
      nodes: _nodesFor(ExportFrameTask(cut: cut, frameIndex: frameIndex)),
      pose: view.pose,
      cameraFrameSize: view.frameSize,
      outputSize: view.frameSize.scaledToWidth(width),
      displayLevels: true,
    );
  }

  /// What a render of [cut] at [frameIndex] looks through in [mode]: its
  /// camera there, or the whole canvas — a camera standing square over all
  /// of it, at its own size.
  CameraView _viewFor(Cut cut, int frameIndex, ExportSizeMode mode) =>
      switch (mode) {
        ExportSizeMode.camera => (
          pose: session.camera.cameraPoseForCut(cut, frameIndex),
          frameSize: session.camera.cameraFrameSize,
        ),
        ExportSizeMode.canvas => cameraViewOver(cut.canvasSize.canvasRect),
      };

  /// [renderComposite] inside a frame that has already started, through
  /// [view], with [nameTags] drawn over the picture — handed in resolved,
  /// so a caller that keys the picture ([_canvasPicture]) keys it by the
  /// very tags that are drawn — and its rows from [rows] when a held
  /// picture keeps them ([_cutPicture]).
  Future<ui.Image> _composite(
    ExportFrameTask task,
    CameraView view, {
    CanvasSize? outputSize,
    List<ResolvedSeNameTag> nameTags = const [],
    RowPictures? rows,
  }) async {
    final cut = task.cut;
    await _hydrate(cut, task.frameIndex);
    return renderService.renderThroughCamera(
      nodes: _nodesFor(task),
      pose: view.pose,
      cameraFrameSize: view.frameSize,
      outputSize: outputSize,
      rows: rows,
      overlayPass: nameTags.isEmpty
          ? null
          : (canvas) => paintSeNameTags(
              canvas,
              tags: nameTags,
              canvasSize: cut.canvasSize,
            ),
    );
  }

  /// [task]'s composite tree. The rows' own fx switches apply here too (AE
  /// semantics: the layer fx switch affects the render) — WYSIWYG with
  /// playback. They live on the layers now (R8), so the dialog's 'Apply
  /// layer FX' master toggle is expressed by rendering an FX-STRIPPED VIEW
  /// of the cut rather than by threading an override through the plan.
  List<CompositeNode<CutFrameCompositeLayer>> _nodesFor(
    ExportFrameTask task,
  ) => planCutFrameCompositeTree(
    cut: _cutForRender(task.cut),
    frameIndex: task.frameIndex,
    surfaceResolver: (layer, frame) => _surfaceFor(task.cut, layer, frame),
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

  /// What [cut]'s picture at [frameIndex] is made of — the playback cache's
  /// own identity of it, of the cut as this render sees it
  /// ([_cutForRender]).
  CutFrameCompositeSignature _signatureOf(Cut cut, int frameIndex) =>
      computeCutFrameCompositeSignature(
        cut: _cutForRender(cut),
        frameIndex: frameIndex,
        // What an export draws: every cel at its own pixels.
        quality: PlaybackQuality.full,
        revisionOf: (layerId, frameId) =>
            session.renderCaches.brushFrameStore
                .frameOrNull(session.brushFrameKeyForCut(cut, layerId, frameId))
                ?.sourceRevision ??
            0,
      );

  /// [cut]'s whole picture at [frameIndex] as [route] draws it, held
  /// ([_pictures]) under the signature of what it is made of — and the
  /// cels it is made of kept with it ([_carryCelsOf]), and the row
  /// pictures [render] made it of ([_rows]). The renderer's own: nobody it
  /// is handed to disposes it.
  ///
  /// [route] is whatever of [render] the signature does not say: which of
  /// the two canvas-space renders it is, and what is drawn over it.
  Future<ui.Image> _cutPicture(
    Cut cut,
    int frameIndex, {
    required Object route,
    required Future<ui.Image> Function(RowPictures rows) render,
  }) {
    final signature = _signatureOf(cut, frameIndex);
    _carryCelsOf(cut.id, signature);
    final key = (route, signature);
    return _pictures.of(key, () => _rows.during(key, render));
  }

  /// [cut]'s picture at [frameIndex] over its whole canvas, on this
  /// renderer's ground, under [nameTags] — a canvas-size video frame's
  /// picture.
  Future<ui.Image> _canvasPicture(
    Cut cut,
    int frameIndex,
    List<ResolvedSeNameTag> nameTags,
  ) => _cutPicture(
    cut,
    frameIndex,
    route: ('canvas', seNameTagSignature(nameTags)),
    render: (rows) => _composite(
      ExportFrameTask(cut: cut, frameIndex: frameIndex),
      _viewFor(cut, frameIndex, ExportSizeMode.canvas),
      nameTags: nameTags,
      rows: rows,
    ),
  );

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
  Future<ui.Image> renderCompositeForVideo(
    ExportFrameTask task,
    ExportSizeMode mode, {
    bool preserveAlpha = false,
  }) async {
    _startFrame();
    if (mode == ExportSizeMode.camera) {
      return _renderTrackStackForVideo(task, preserveAlpha: preserveAlpha);
    }
    final ground = _backdropGround(preserveAlpha: preserveAlpha);
    if (task.isGap) {
      // A leading-gap frame: nothing plays — the BACKDROP (R3b), exactly
      // what playback shows in the gap. Opaque codecs bake the floor; an
      // alpha master keeps the gap transparent.
      final size = task.cut.canvasSize;
      return _frameOf<_GapFrame>(
        (size: size, ground: ground),
        width: size.width,
        height: size.height,
        paint: _paintGapFrame,
      );
    }
    // A transition reaching across this frame's boundary puts a SECOND cut
    // here, and canvas space is shared whenever the two agree on their canvas
    // size — which two cuts of one track normally do. Only differing sizes
    // keep the single-cut bake, because then there is no shared space to mix
    // in (the camera frame is that space, and that is the camera path above).
    final overlap = await _canvasSpaceTransitionFrame(task, ground: ground);
    if (overlap != null) {
      return overlap;
    }
    // The presentation render: the アフレコ name tags belong in the video
    // (their row's eye is the switch).
    final cut = task.cut;
    final image = await _canvasPicture(
      cut,
      task.frameIndex,
      session.seEntries.seNameTagsForCutFrame(cut, task.frameIndex),
    );
    // The V effects are TRACK data on the global axis (R4).
    final trackFrame = session.rowSpans.trackGlobalFrameOf(
      cut.id,
      task.frameIndex,
    );
    // The V row's fx MASTER reaches the OUTPUT, like every fx switch since
    // R8 ("a bypass that vanished on reload while a per-effect bypass
    // survived" is exactly what R8 refused). It gates the effect chain —
    // never the STATIC opacity, which is a compositing property and not an fx
    // (R9 #21).
    final trackFxEnabled = session.effectsAndFx.isCutFxEnabled(cut.id);
    // No animated track fade any more; the transition row's ramp lands in
    // [_canvasSpaceTransitionFrame] above, on the frames it actually covers.
    final fade = session.opacityVerbs.trackStaticOpacityForCut(cut.id);
    final trackEffects = trackEffectsAt(
      session.effectsAndFx.trackEffectsForCut(cut.id),
      trackFrame,
      enabled: trackFxEnabled,
    );
    // F-192: a lone F.I/F.O/W.I/W.O is ONE contribution, so it never reached
    // the transition mix above — ↩️its fade was simply missing from a
    // canvas-size export. Its screen lands here, on this one frame.
    final veils = _veilsOf(task);
    if (fade >= 1 && trackEffects.isEmpty && veils.isEmpty) {
      return image.clone();
    }
    return _frameOf<_BakedFrame>(
      (
        ground: ground,
        cut: (
          picture: ByIdentity(image),
          weight: fade,
          chain: ByList(trackEffects),
          veils: ByList(veils),
          canvasExtent: cut.canvasSize.width.toDouble(),
        ),
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
  ({
    List<TransitionContribution> contributions,
    CanvasSize size,
    List<double> weights,
    int globalFrame,
  })?
  _sharedTransitionSpace(ExportFrameTask task) {
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
  /// reaches across the boundary here — null when this frame has only one
  /// contribution (the ordinary bake) or when the contributing cuts disagree
  /// on their canvas size (no shared space to mix in).
  ///
  /// Each cut is drawn with its own track pose, chain and unit weight, in the
  /// order the resolver returns them (leaving cut first) — the camera path's
  /// rules, in canvas space instead of the camera frame.
  Future<ui.Image?> _canvasSpaceTransitionFrame(
    ExportFrameTask task, {
    required ui.Color? ground,
  }) async {
    final shared = _sharedTransitionSpace(task);
    if (shared == null) {
      return null;
    }
    final size = shared.size;
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
                  session.seEntries.seNameTagsForCutFrame(
                    contribution.cut,
                    contribution.localFrameIndex,
                  ),
                ),
              ),
              weight: shared.weights[i].clamp(0.0, 1.0),
              // The V row's chain on this contribution, keys included — the
              // dissolve weights what the chain made, not what it started
              // from.
              chain: ByList(
                trackEffectsAt(
                  session.effectsAndFx.trackEffectsForCut(contribution.cut.id),
                  shared.globalFrame,
                  enabled: session.effectsAndFx.isCutFxEnabled(
                    contribution.cut.id,
                  ),
                ),
              ),
              // F-192: a one-sided transition's own screen, inside this
              // contribution's weight — the painter's unit, in canvas
              // space.
              veils: ByList(contribution.veils),
              canvasExtent: contribution.cut.canvasSize.width.toDouble(),
            ),
        ]),
      ),
      width: size.width,
      height: size.height,
      paint: _paintMixedFrame,
    );
  }

  /// The camera-frame video frame as the display's track stack (R3a).
  ///
  /// The task's cut names the frame's GLOBAL index (its layout start plus
  /// the local index — negative for a leading-gap task, which lands inside
  /// the gap exactly); every track covering that index renders its cut's
  /// CANVAS-SPACE composite (transparent backing) and hands it to
  /// [PlaybackFramePainter] with the stack's own rules — paper on the
  /// bottom covered track only, full-frame fade wash there, upper tracks
  /// thinning their own contribution. One painter for screen and bake.
  ///
  /// The frame is made of its painters, and two stacks of painters are one
  /// picture by the painters' own word ([_StackPainters]).
  Future<ui.Image> _renderTrackStackForVideo(
    ExportFrameTask task, {
    required bool preserveAlpha,
  }) async {
    final globalFrame = (_entryOf(task)?.startFrame ?? 0) + task.frameIndex;
    final positions = resolveTrackStackContributions(
      layout: _layout,
      spansOf: session.transitions.transitionSpansOfTrack,
      globalFrameIndex: globalFrame,
    );
    // The unit alphas, and then the source-over weights that make the stack
    // read as that mix (see [sourceOverWeights]) — grouped by track here,
    // because an upper track thins only its own contribution.
    final unitAlphas = _unitAlphas([
      for (final position in positions)
        (cut: position.cut, opacity: position.opacity),
    ]);
    final weights = trackGroupSourceOverWeights(positions, unitAlphas);

    final size = session.camera.cameraFrameSize;
    return _frameOf<_StackFrame>(
      (
        size: size,
        // The BACKDROP (R3b), everywhere the stack leaves uncovered: gap
        // frames, a posed stage sliding off, a fade thinning the stack
        // away.
        ground: _backdropGround(preserveAlpha: preserveAlpha),
        stack: _StackPainters([
          for (final (i, position) in positions.indexed)
            await _stackPainter(
              position,
              weights[i],
              size: size,
              preserveAlpha: preserveAlpha,
            ),
        ]),
      ),
      width: size.width,
      height: size.height,
      paint: _paintStackFrame,
    );
  }

  /// The painter of one position of the track stack: its cut's picture,
  /// held ([_cutPicture]), under everything the stack lays on it at
  /// [weight].
  Future<PlaybackFramePainter> _stackPainter(
    TrackStackContribution position,
    double weight, {
    required CanvasSize size,
    required bool preserveAlpha,
  }) async {
    final cut = position.cut;
    final image = await _cutPicture(
      cut,
      position.localFrameIndex,
      route: 'stack',
      render: (rows) async {
        await _hydrate(cut, position.localFrameIndex);
        return _stackRenderService.renderThroughCamera(
          rows: rows,
          nodes: planCutFrameCompositeTree(
            cut: _cutForRender(cut),
            frameIndex: position.localFrameIndex,
            surfaceResolver: (layer, frame) => _surfaceFor(cut, layer, frame),
          ),
          // The IDENTITY camera: a canvas-space composite, exactly what
          // the playback cache holds — the painter below projects it
          // through the cut's real camera, so the camera is never baked
          // into the composite itself (playback's own rule).
          pose: CameraPose(
            center: CanvasPoint(
              x: cut.canvasSize.width / 2,
              y: cut.canvasSize.height / 2,
            ),
          ),
          cameraFrameSize: cut.canvasSize,
        );
      },
    );
    // Track effects at the frame's GLOBAL position (R4) — the stack's
    // own axis — with the row's fx master gating them (R8's rule; the
    // static opacity is not an fx and stays).
    final trackFxEnabled = session.effectsAndFx.isCutFxEnabled(cut.id);
    // The stage belongs to the bottom covered TRACK, and to every
    // contribution of it: an O.L is a 場面転換, so the arriving cut brings
    // its own paper and the weights cross-fade the whole screen. Keyed to
    // the bottom CONTRIBUTION this baked a superimpose.
    final isStage = position.isBottomTrack;
    return PlaybackFramePainter(
      image: image,
      canvasSize: cut.canvasSize,
      // The multitrack video path projects here, so the tags ride
      // this painter instead of the identity-camera composite above —
      // one draw, in the same canvas space as every other surface.
      seNameTags: session.seEntries.seNameTagsForCutFrame(
        cut,
        position.localFrameIndex,
      ),
      cameraPose: session.camera.cameraPoseForCut(
        cut,
        position.localFrameIndex,
      ),
      cameraFrameSize: size,
      // No cutPose/cutAnchorPoint: the V row has no transform.
      cutEffects: trackEffectsAt(
        session.effectsAndFx.trackEffectsForCut(cut.id),
        position.globalFrameIndex,
        enabled: trackFxEnabled,
      ),
      paperBackground: session.projectSettings.projectBackground,
      paintPaper: isStage,
      // The alpha matrix (user 2026-07-29): alpha masters exclude the
      // backdrop AND the pasteboard — they are compositing sources,
      // and the paper carries its own alpha. A pasteboard that is NONE
      // (F-114) prints nothing either: the plane is not there.
      pasteboardColor:
          isStage &&
              !preserveAlpha &&
              !session.repository.requireProject().pasteboardNone
          ? ui.Color(session.repository.requireProject().pasteboardArgb)
          : null,
      // The output IS the camera frame — there is no outside to
      // letterbox, and an alpha master needs the ground transparent.
      paintLetterbox: false,
      fadeOpacity: isStage ? weight : 1,
      imageOpacity: isStage ? 1 : weight,
      veils: position.veils,
    );
  }

  /// One LABEL-GROUP cel (EX5): the gated members' frames composited
  /// bottom-up at their static opacities — a delivery cel is the stack
  /// (기준+어태치), not the pieces. Null when NO member has artwork.
  /// The renderer's background carries the channel choice (transparent
  /// for RGBA, the picked backing for RGB); [ExportSizeMode.camera]
  /// crops through the camera at the base cel's FIRST exposure (a cel
  /// has no time of its own — where it first shows is the honest frame).
  Future<ui.Image?> renderCelGroup(
    ExportCelGroupTask task,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
  }) async {
    _startFrame();
    // A cel has no time of its own, so the group's FX sample at the base
    // cel's FIRST exposure — the same honest frame the camera pose uses,
    // in the cut that shows the cel ([ExportCelGroupTask.cut], F-300).
    final firstExposure = celGroupFirstExposure(task);
    final layers = <CutFrameCompositeLayer>[];
    // One picture of the stack: [layer]'s [frame] as [cut] holds it.
    void lay(Cut cut, Layer layer, Frame? frame) {
      final surface = frame == null ? null : _surfaceFor(cut, layer, frame);
      if (surface == null) {
        return;
      }
      layers.add(
        CutFrameCompositeLayer(
          surface: surface,
          opacity: layer.opacity,
          // R26 #30: the delivery cel is the stack as composited — the
          // members' blends apply. R6: their EFFECTS ride the same fx
          // gates every other route uses — the dialog's master toggle and
          // the row's own fx switch.
          //
          // The cel tab's master toggle used to be a hardcoded false ("cels
          // stay raw artwork"); 유저 2026-08-27 made it the tab's own switch,
          // defaulting ON — see [CelsExportSpec.applyLayerFx]. An artist who
          // wants raw line art back turns it off, which is what the other
          // tabs always allowed. Blend and static opacity are display
          // properties and stay either way.
          blendMode: layer.blendMode,
          effects: applyLayerFx
              ? resolveLayerEffectsAt(
                  // Each effect's own switch (R8) gates it from here.
                  effects: layer.effects,
                  frameIndex: firstExposure,
                )
              : const [],
        ),
      );
    }

    for (var i = 0; i < task.members.length; i += 1) {
      lay(task.cut, task.members[i], task.memberFrames[i]);
    }
    if (layers.isEmpty) {
      return null;
    }
    // What is laid over the cel goes on top of all of it — and over a cel
    // with no artwork there is nothing to lay it on (the null above).
    for (final over in task.overlays) {
      lay(over.cut, over.layer, over.frame);
    }
    final view = _viewFor(task.cut, firstExposure, mode);
    return renderService.renderThroughCamera(
      layers: layers,
      pose: view.pose,
      cameraFrameSize: view.frameSize,
      outputSize: outputSize,
    );
  }

}

// --- what a video frame is made of ------------------------------------------
//
// Each is a VALUE that says when two frames are one picture, and the one
// thing its paint is handed (`ExportFrameRenderer._frameOf`). The paints are
// down here, out of the renderer, so that they have nothing else to read.

/// A frame nothing plays in: the ground alone.
typedef _GapFrame = ({CanvasSize size, ui.Color? ground});

/// One cut's finished [picture] as a canvas-size frame takes it: thinned to
/// [weight], through the V row's [chain], under its own [veils].
typedef _CutInFrame = ({
  ByIdentity<ui.Image> picture,
  double weight,
  ByList<ResolvedLayerEffect> chain,
  ByList<TransitionVeil> veils,
  double canvasExtent,
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
typedef _StackFrame = ({
  CanvasSize size,
  ui.Color? ground,
  _StackPainters stack,
});

/// The painters of one camera frame's track stack, bottom up.
///
/// Two stacks are ONE picture when each painter paints what its fellow
/// painted — by the painter's own word for it ([RepaintOnProps.props]:
/// every input its pixels depend on, the law the screen repaints by).
final class _StackPainters {
  _StackPainters(this.all);

  final List<PlaybackFramePainter> all;

  late final List<Object> _props = [for (final painter in all) painter.props];

  @override
  bool operator ==(Object other) =>
      other is _StackPainters && listEquals(other._props, _props);

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
  _paintGround(canvas, made.size.canvasRect, made.ground);
  final extent = ui.Size(
    made.size.width.toDouble(),
    made.size.height.toDouble(),
  );
  for (final painter in made.stack.all) {
    painter.paint(canvas, extent);
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
  final framePaint = ui.Paint();
  // The chain filters the cut's finished picture, under the fade — the same
  // order the screen draws it in.
  //
  // 🚨AND A KEY IN IT NEEDS ITS OWN RASTER. The picture is the cut's
  // finished one at its own size and the export draws it 1:1, so the steps
  // run at scale 1 — the one route where the ratio is not a question.
  final picture = cut.picture.value;
  final plan = resolveCompositeEffectPlan(cut.chain.value);
  plan.finalPaint.applyTo(framePaint);
  final stepped = steppedForChain(
    image: picture,
    plan: plan,
    canvasExtent: cut.canvasExtent,
  );
  canvas.drawImage(stepped, ui.Offset.zero, framePaint);
  if (!identical(stepped, picture)) {
    stepped.dispose();
  }
  paintTransitionVeils(canvas, bounds, cut.veils.value);
  if (cut.weight < 1) {
    canvas.restore();
  }
}
