import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/one_pass_at_a_time.dart';
import '../../core/tree_nodes.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../models/cut_id.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardReach;
import '../../models/project_background.dart' show ProjectBackground;
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../native/app_kernels_ahead.dart' show appEngineGetsReady;
import '../../native/engine_frame_tools.dart';
import '../../native/screen_texture.dart' show ScreenTexture;
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/playback/frame_demand.dart';
import '../canvas/bitmap_surface_painter.dart' show BitmapSurfacePainter;
import '../canvas/canvas_layer_stack_view.dart'
    show
        CanvasActiveLayerRow,
        CanvasStackRow,
        EngineStackScreen,
        LiftedRowPainters,
        LiveRows,
        LiveSurfaceTokens,
        StackedFrame,
        waitsForItsPlugins;
import '../canvas/picture_up_view.dart';
import '../canvas/shown_cels.dart' show ShownCels;
import '../canvas/viewport_canvas_transform.dart' show renderSnappedViewport;
import '../effective_device_pixel_ratio.dart';
import '../engine_screen_texture.dart';
import 'camera_shot.dart' show canvasCutOnScreen;
import 'engine_frame_picture_store.dart';
import 'frame_pictures.dart';
import 'frame_wait_mark.dart';
import '../widgets/still_raster.dart';
import 'stacked_frame_picture.dart';

part 'live_cel_screen.dart';

/// What a screen showing frames takes from their maker: the signal that a
/// frame's picture landed, and the pictures the frames are kept in.
typedef StackRun = ({Listenable landings, FramePictures pictures});

/// 🚨★★★A FRAME ON SCREEN IS ITS ONE PICTURE (one-picture-per-frame ②-2 ·
/// ②-3, D7-2-Q3=a): the frame [nodes] stack for [picture], as its maker
/// made it ([FramePictures]) — drawn, never composited here. A frame two
/// screens show the same way is one picture: the canvas standing on a frame
/// and a run playing it show the same one, and pressing Play changes
/// nothing on the screen.
///
/// A frame not there yet is made by the run's maker as it walks ahead of
/// the playhead — or by this view at once ([laysWhatItMisses]); meanwhile
/// the last picture shown stands ([wholeFrames]; 유저 2026-10-08: 「재생바는
/// 지나가고있는데 그림이 없어서 비어있다던가」) or the frame is drawn as it
/// stands. A frame the maker gave up on is drawn from its cels as they
/// stand ([FramePictures.drawingNow]): nothing waits for it, and what it
/// shows is the frame without what would not come. So is a frame of no row
/// — its page alone, of which the store keeps no picture
/// ([FramePictures.drawsOnlyItsPage]).
///
/// 🚨A CANVAS THAT STANDS WRITES ITS LIVE ROWS INTO THE PICTURE ([live],
/// ②-4): each change of theirs is composed in where it lands, in the paint
/// that shows it ([StackedFrame.movedSince] →
/// [EngineFramePictureStore.patch]); a stroke that lands moves the picture
/// to the frame's next key ([EngineFramePictureStore.move]). ↩️Drawn as it
/// stood over the picture until then, a step and its picture were two
/// images of one frame, and their edges drew apart (F-465).
/// A float or a lift in hand is a change like any other, told where it
/// lands a step of the hand at a time (`LiveSurfaceTokens`). Where a change
/// cannot be told by where it lands — a pose that turns the row off the
/// canvas's axes, a posed row's own chain or blend, a cel a lift holds
/// that is not in hand — the frame is drawn as it stands, on a screen of
/// this view's that is no picture of the frame, until its key moves.
///
/// 🚨★★★SHOWN THROUGH A TEXTURE OF ITS OWN, PRESENTED IN ITS PAINT
/// ([_RenderFrameScreen]): a picture written into shows at the next paint.
/// ↩️A picture was a `ui.Image` over a `flutter_gpu` texture, a new image
/// after every write: the engine takes an image for a value, and on iPhone
/// and iPad (Impeller, Metal) a screen is drawn again only where its drawing
/// changed from the frame before, an image told apart by its identity alone
/// (`DlImage::Equals`) — so a stroke written into the very image the screen
/// drew went nowhere: invisible while drawn and after, until the frame was
/// left and come back to (F-509, 유저 2026-10-30 「홍보 한참인데 진짜
/// 비상사태」; 1079 from its second stroke, every stroke from 1080). A
/// texture's layer is marked dirty whatever it shows
/// (flow/layers/texture_layer.cc:22, `TextureLayer::Diff`).
///
/// ↩️Each screen stacked a frame from its ROWS' images
/// (`CanvasLayerStackView`), and composited them again into a buffer of its
/// own at the display's level.
class FramePictureView extends StatefulWidget {
  const FramePictureView({
    super.key,
    required this.run,
    required this.picture,
    required this.nodes,
    required this.viewport,
    this.live,
    this.laysWhatItMisses = false,
    this.wholeFrames = true,
    this.alreadyShown = false,
    this.drawnLive = const {},
    this.ground,
    this.cutAtCanvas,
    this.carriesTheOverlays = false,
  });

  final StackRun run;

  /// The frame this view shows, and whether its screen paints its paper.
  final DemandedPicture picture;

  /// The tree the screen stacks for [picture] — the key of its picture
  /// ([FramePictures.keyOfStack]).
  final List<CompositeNode<CanvasStackRow>> nodes;

  final CanvasViewport viewport;

  /// The rows a canvas that stands draws live ([LiveRows]) — what a stroke,
  /// a float or a lift moves with no new frame. Null for a screen that
  /// draws nothing live: a run, the track stack.
  final LiveRows? live;

  /// Whether a frame not there yet is made by this view — at once, at the
  /// front of the store's line ([FramePictures.makeShown]) — rather than
  /// left to the run's maker walking ahead of the playhead.
  final bool laysWhatItMisses;

  /// Whether a frame not there yet leaves the last one shown standing until
  /// it is, or is drawn as it stands meanwhile from the cels in hand
  /// ([FramePictures.frameAsItStands]) — a canvas that stands, where a row
  /// being drawn on may not wait for its neighbours: a frame of the cut it
  /// showed last. 🗣️A frame of a cut nothing of which was there — another
  /// than the one it showed, or any of a file just opened — stands bare
  /// till its picture comes (the-standing-canvas-composes-a-frame-twice-
  /// before-its-picture-Q5 · Q7 = blank, 유저 2026-11-18 「빈 종이로
  /// 기다린다」): a cut a command opened, or a file.
  ///
  /// ⛔Not one flag with [laysWhatItMisses]: who makes a frame and whether
  /// a frame waits to be whole are two questions, and a track stack's
  /// parked cut asks the first and waits. ↩️One flag, `run`, answered both
  /// on `CanvasLayerStackView` until the track stack drew its cuts there
  /// (2026-10-10) and asked the second without the first.
  final bool wholeFrames;

  /// Whether what this view shows is on screen already, painted by another
  /// route it takes over from — the conte's printed pictures, drawn live
  /// while its brush is on. Its first frame then reads every cel it draws
  /// on this thread, whatever it takes: a picture on screen may not go
  /// blank for the frames a read off it takes (F-215, 유저 2026-09-28:
  /// 「브러시 허용 on시 … 그림이 사라졌다가 다시 렌더되서 보이기시작. on하든off하든
  /// 바뀌는게 없어야」).
  ///
  /// ⛔False is every other view's first frame — a project opened, a cut
  /// switched to: nothing of it was on screen, and a whole cold stack read
  /// in one build is a stall nobody asked for.
  ///
  /// ↩️`CanvasLayerStackView.alreadyShown`, until the conte's live picture
  /// was the frame's one picture (one-picture-per-frame ②-3), which left it
  /// behind: the switch's frame drew the picture without its cut's rows.
  final bool alreadyShown;

  /// The cels the canvas under this view draws live — its active rows'
  /// (`CanvasActiveLayerRow.frameKey`). One of them this view is handed at
  /// the next build was on screen a frame ago, and is read on this thread:
  /// the cel you were just drawing, whole as a ghost on the first frame of
  /// the frame you stepped to (유저 2026-09-17: 「보이는 중이랑 결과랑 절대로
  /// 다르면 안 되」).
  ///
  /// ⛔Only those: any other cel this view is handed arrives as it is read
  /// off the UI thread — a whole cold stack read in one build is a stall.
  ///
  /// ↩️`CanvasLayerStackView.drawnLive`, until the ghosts were one picture
  /// too (one-picture-per-frame ②-5b-1).
  final Set<BrushFrameKey> drawnLive;

  /// The colour laid across the view under what it draws, where it draws
  /// anything — past [cut] too.
  ///
  /// 🗣️F-215 · I-132-Q34 a: none while it draws nothing — a frame that
  /// waits for its plugins, its picture not made yet — so what it took over
  /// from shows meanwhile: the conte's print, the last finished picture
  /// (「on하든off하든 바뀌는게 없어야」 · 「직전 완성 그림에 머문다」).
  final Color? ground;

  /// The canvas what the view draws is cut to ([canvasCutOnScreen]) — a
  /// conte picture's, in its camera frame — and not its [ground], which
  /// lies across the whole view as the print's does: cut to it too, the
  /// print a live picture takes over from showed past the canvas (🔬F-215's
  /// switch pin, 10-31). Null: nothing is cut.
  final CanvasSize? cutAtCanvas;

  /// Whether what is drawn over the canvas stands on this view's frame up
  /// ([PictureUpView]): the canvas's frame, seen through the panel's view.
  ///
  /// ⛔Not a picture seen through another view — a run seen through the
  /// camera — nor one of a texture beside the frame's — the ghosts over it,
  /// the track stack's cuts: one clock is one picture's, and whether
  /// pictures on textures of their own are put up together is asked
  /// (a-pan-moves-the-overlays-before-the-canvas, 11-16 (ㄱ)).
  final bool carriesTheOverlays;

  @override
  State<FramePictureView> createState() => _FramePictureViewState();
}

/// Whether a frame is drawn as it stands where its picture is shown
/// ([whole]).
///
/// 🚨READ AT EACH PAINT, not handed to the painter at a build: a change of
/// the live rows moves it with no build — a change no patch can follow.
/// Handed at the build before, a frame gone to be drawn as it stands showed
/// the picture without the change until the next build.
final class _DrawnAsItStands {
  /// The live rows moved where no patch can follow: the frame is drawn as
  /// it stands until its key moves.
  bool whole = false;
}

/// How a frame screen's box lays its frame on its texture: the view through
/// `viewport` at `devicePixelRatio`, its corner on the texel `corner`.
typedef _OnTheTexture = ({
  CanvasViewport viewport,
  double devicePixelRatio,
  (int, int) corner,
});

/// What a frame screen's box ([_RenderFrameScreen]) asks, in its paint, of
/// what hands it its frames — a frame's picture view ([FramePictureView]),
/// or a cel's live screen ([LiveCelScreen]). The box is one: how a frame
/// goes up through its texture, stands where it was drawn for through a
/// pan, and waits for the engine is the same whoever feeds it.
abstract interface class _FrameFeed {
  /// Writes what moved since the paint before into what is shown, before
  /// it is shown: what this frame's paint moves is what this frame shows.
  void _catchUp();

  /// Whether there is a frame to show — a picture, or [asItStands] — and
  /// the engine's tools open to show it with.
  bool _hasAFrame(StackedFrame? asItStands);

  /// The frame as it is drawn now — [frame] where no picture is shown —
  /// onto [target] of [size] texels, laid [on] it.
  void _show(
    StackedFrame? frame,
    GpuTarget target,
    (int, int) size,
    _OnTheTexture on,
  );

  /// Tells the place the frame is shown in whether the engine keeps it
  /// from the screen at this paint — [refused] where the paint's lay met
  /// kernels still to be compiled ([FrameKernelsToCome]).
  void _waitsAtPaint({required bool refused});
}

/// Reports [thrown], the first throw a cel's reading gave while [doing]
/// — the cel noted and drawn without.
void _report((Object, StackTrace)? thrown, String doing) {
  if (thrown case (final error, final stack)) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'frame picture view',
        context: ErrorDescription(doing),
      ),
    );
  }
}

class _FramePictureViewState extends State<FramePictureView>
    implements _FrameFeed {
  /// The key of the frame shown — its picture, held for this view by the
  /// store; or the frame as it stands.
  FramePictureKey? _showing;

  /// The frame's picture shown, held by this view.
  EngineFramePicture? _shown;

  /// A frame of no row, or one the maker gave up on, drawn as its cels
  /// stand — by a view that draws nothing live ([_live] where it does).
  StackedFrame? _asItStands;

  /// The cut of the frame this view put on its screen last — its picture,
  /// or the frame as it stands ([_show]); null till it puts one there. A
  /// frame of another cut stands bare against it ([_standsBare]).
  CutId? _cutOnScreen;

  /// The frame as it stands with its live rows ([LiveRows]) — drawn
  /// wherever its picture is not shown or [_standing], and the body every
  /// patch is drawn by. Null where this view draws nothing as it stands.
  StackedFrame? _live;

  /// What moves [_live]'s pixels ([StackedFrame.changes]).
  Listenable? _liveChanges;

  /// The cels this view had in hand when it last stood its frame — on
  /// screen, in its picture or as they stand. One an edit takes out of hand
  /// is read on this thread when the view is next handed its tree, at the
  /// next build of every screen that shows one: the frame after an edit
  /// shows the edit, not the drawing before it, nor a blank (H27, iPhone
  /// 2026-08-27: 「이전 변형하기 전 그림이 남아있었음」; 유저 2026-09-17:
  /// 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
  ///
  /// ↩️The editing stack composed on the spot a row it held an image of at
  /// an older revision (`CanvasLayerStackView._wasOnScreen`), until the
  /// ghosts were one picture too (one-picture-per-frame ②-5b-1).
  Set<BrushFrameKey> _onScreen = const {};

  /// The key the frame was last stood by ([FramePictures.keyAsItStands]):
  /// a tree handed under it is that frame handed again.
  FramePictureKey? _stoodBy;

  final LiftedRowPainters _painters = LiftedRowPainters();

  /// What of the live rows the picture shown holds, to measure their next
  /// change from — null while it cannot be told.
  ///
  /// 🚨NULL IS 「nothing held」, never an empty set of tokens: an EMPTY
  /// cel's tokens are empty too, and they are a base to measure from — a
  /// stamp's usual target is an empty cel. ↩️The display buffer marked
  /// 「nothing kept」 with a sentinel it compared by identity, after a check
  /// by emptiness refused the stamp's ghost its patch on every move there
  /// (F-130).
  LiveSurfaceTokens? _held;

  /// Whether the frame is drawn as it stands in place of the picture shown.
  final _DrawnAsItStands _standing = _DrawnAsItStands();

  /// Whether the frame is drawn as it stands, not shown from its picture.
  @visibleForTesting
  bool get drawnAsItStands => _standing.whole;

  /// Whether nothing more of the frame is on its way to its screen: the
  /// picture of the frame as it is stacked now taken, and no change of its
  /// live rows still going through its plugins ([_writeThrough]) — what a
  /// frame that waits for them ([_waits]) shows late. One that does not
  /// wait shows all of it at the paint — once its picture comes, where it
  /// stands bare till it does ([_standsBare]).
  @visibleForTesting
  bool get nothingOnItsWay =>
      (!_waits && !_standsBare) ||
      (_shown != null &&
          _showing == _pictures.keyOfStack(widget.nodes, widget.picture) &&
          !(_standing.whole && _movedSinceThrough) &&
          !_writesThrough.onItsWay &&
          _owed == null);

  /// 🗣️I-132-Q34 a (유저 2026-10-30): 「결과가 올 때까지 그 프레임의 직전
  /// 완성 그림에 머문다」 — whether the frame holds a plugin's step that only
  /// a picture made waiting for it draws ([waitsForItsPlugins]). Such a
  /// frame is never drawn as it stands: the picture shown stays until the
  /// next is there, and its live rows' changes go into it as every frame's
  /// do — a stroke shown late by its plugins' time.
  bool _waits = false;

  /// The cel the pen is on, as the key of the picture shown read it.
  CelAsOf? _drawnOn;

  /// The key the store keeps the picture shown under: the frame's own
  /// where it holds what the frame stores, and this view's
  /// ([FramePictureKey.standingOn]) where it holds what only the live rows
  /// show ([_keptUnder]).
  FramePictureKey? _keptAs;

  /// The key this view asked to be made ([FramePictureView.laysWhatItMisses]).
  FramePictureKey? _making;

  /// Ticks when what this view draws changes with no build.
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  FramePictures get _pictures => widget.run.pictures;

  EngineFramePictureStore<FramePictureKey> get _store => _pictures.store;

  /// The frame as it stands where no picture is shown, on the engine: a
  /// screen of this view's, no picture of the frame's — null while nothing
  /// stands on it.
  EngineStackScreen? _standingOn;

  /// The frame last composed on [_standingOn] ...
  StackedFrame? _composedOn;

  /// ... and whether its live rows moved since.
  bool _standingMoved = false;

  /// The compositions laid on [_standingOn], counted: the one that ends
  /// says by it whether it was the last ([_keepWhatStood]).
  int _stood = 0;

  /// The frame [_look] stands on, kept as its key's picture once the paint
  /// has laid it ([_keepWhatStood]) — the store not asked to lay it again.
  ({FramePictureKey key, StackedFrame frame})? _keeping;

  /// Whether the live rows moved since all of the frame last went through
  /// its plugins ([_throughWhole]).
  bool _movedSinceThrough = true;

  /// Whether this view is writing into the picture it shows: the paint that
  /// writes shows the write.
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    widget.run.landings.addListener(_landed);
    _standLive(onScreen: widget.alreadyShown ? (_) => true : null);
    _look();
    _hearItsStore();
  }

  /// Paints again at the store's news of what keeps a frame from the
  /// screen ([EngineFramePictureStore.waits], [_waitsAtPaint]): its tools
  /// opened — or found unable to open, nothing waits for them then — and
  /// its line come behind kernels still to be compiled, or through them.
  void _hearItsStore() {
    _store.waits.addListener(_paintAgain);
    _store.wentWithItsTools.addListener(_itsPicturesWent);
    _askForItsTools();
  }

  /// Opened by the first that asks. Why they would not open is said to
  /// what asked the engine to open (`compileAppKernelsAhead`) and to every
  /// lay asked of the store (`EngineFramePictureStore._noEngine`); a view
  /// hears of it by [EngineFramePictureStore.waits], as it does of the
  /// rest.
  void _askForItsTools() => _store.tools.ignore();

  /// Hears [store] no more ([_hearItsStore]).
  void _hearNoMore(EngineFramePictureStore<FramePictureKey> store) {
    store.waits.removeListener(_paintAgain);
    store.wentWithItsTools.removeListener(_itsPicturesWent);
  }

  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
  /// 않고 새 장치를 열어 사본으로 되살린다」 — the store's pictures went with
  /// the tools they were laid with
  /// ([EngineFramePictureStore.wentWithItsTools]): so do the one this view
  /// shows and the screen it stands a frame on, a screen of those tools,
  /// and its frame is asked for again — laid with the next, or made by
  /// this view as it was the first time ([_look]).
  ///
  /// ⚠️The next tools are asked for here as they were the first time: a
  /// frame that is drawn as it stands lays nothing, and no one else would.
  void _itsPicturesWent() {
    _letGo(_store);
    _standingOn?.free();
    _standingOn = null;
    _composedOn = null;
    _askForItsTools();
    if (mounted) {
      setState(_look);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _place = FrameWaitPlace.of(context);
  }

  void _paintAgain() {
    if (mounted) {
      _repaint.value += 1;
    }
  }

  /// The place this view's frame is shown in, where one marks its frames'
  /// waits ([FrameWaitPlace]).
  FramesWaiting? _place;

  /// 🗣️gpu-canonical-store-Q12 (유저 2026-11-10): 「캔버스 자리에 준비 중 표시를
  /// 둔다」 — tells this view's place whether the engine keeps its frame
  /// from the screen at this paint, ONE answer for every way it does: its
  /// tools still to be opened; [refused], the paint's own lay met kernels
  /// still to be compiled ([FrameKernelsToCome]); the frame's picture,
  /// nothing of the frame drawn meanwhile — a view of whole frames, or one
  /// that stands bare ([_standsBare]: a file just opened, a cut a command
  /// opened) — in a line that stands behind such kernels
  /// ([EngineFramePictureStore.waitsForKernels]).
  ///
  /// ⛔Not a frame drawn as it stands while its picture is on its way: it
  /// is on the screen. Nor one that waits for its plugins alone (🗣️관제
  /// 2026-11-10 23:05: the answer is of the engine's getting ready).
  @override
  void _waitsAtPaint({required bool refused}) => _place?.says(
    this,
    waits:
        _store.toolsAreToCome ||
        refused ||
        (_making != null &&
            (!_standsMeanwhile || _standsBare) &&
            _store.waitsForKernels),
  );

  @override
  bool _hasAFrame(StackedFrame? asItStands) =>
      (_drawnPicture ?? asItStands) != null && _store.toolsOpen != null;

  /// Whether a frame whose picture is not there yet is drawn as it stands
  /// until it is ([FramePictureView.wholeFrames], [_waits]).
  bool get _standsMeanwhile => !widget.wholeFrames && !_waits;

  @override
  void didUpdateWidget(FramePictureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run.landings, widget.run.landings)) {
      oldWidget.run.landings.removeListener(_landed);
      widget.run.landings.addListener(_landed);
    }
    if (!identical(oldWidget.run.pictures, widget.run.pictures)) {
      _hearNoMore(oldWidget.run.pictures.store);
      _hearItsStore();
      // What keeps its frame from the screen is this store's to say now.
      _paintAgain();
      _letGo(oldWidget.run.pictures.store);
    }
    // 🚨A TREE HANDED AGAIN IS NOT A FRAME HANDED ANEW (F-244): every
    // build of the canvas asks its tree afresh — a block's drag in the
    // timeline builds it at every step with every row as it was — and the
    // frame stood again at each repainted the whole canvas. ↩️Told by the
    // list's identity, which no build kept.
    final asItStands = _pictures.keyAsItStands(widget.nodes, widget.picture);
    final handedAnew =
        _stoodBy != asItStands ||
        !identical(oldWidget.run.pictures, widget.run.pictures) ||
        !_sameLive(oldWidget.live, widget.live) ||
        oldWidget.wholeFrames != widget.wholeFrames;
    if (handedAnew) {
      _standAnew(oldWidget.drawnLive, asItStands);
    } else {
      _look();
    }
  }

  /// The frame stands as it was handed last — [asItStands] its key — and
  /// [drawnLive] as they were last drawn.
  void _standAnew(Set<BrushFrameKey> drawnLive, FramePictureKey asItStands) {
    final shown = _onScreen;
    _standLive(
      onScreen: (cel) => shown.contains(cel) || drawnLive.contains(cel),
      asItStands: asItStands,
    );
    // 🚨THE FRAME FIRST, THEN WHAT ITS LIVE ROWS MOVED: rows handed with
    // another frame are that frame's. Measured against the picture of the
    // frame left, they were patched INTO it — and every screen showing that
    // frame drew the other one wherever the two differ (F-104 again: the
    // frame you left stayed where the frame you went to has nothing, once
    // you went back and forth).
    _look();
    if (widget.live != null) {
      _liveRowsHandedAnew();
    }
  }

  @override
  void dispose() {
    widget.run.landings.removeListener(_landed);
    _hearNoMore(_store);
    _place?.says(this, waits: false);
    _liveChanges?.removeListener(_liveMoved);
    _letGo(_store);
    _standingOn?.free();
    _repaint.dispose();
    super.dispose();
  }

  void _landed() => setState(_look);

  static bool _sameLive(LiveRows? a, LiveRows? b) =>
      identical(a?.activeSurfacePainter, b?.activeSurfacePainter) &&
      identical(a?.floatOverlay, b?.floatOverlay) &&
      identical(a?.liftedRows, b?.liftedRows);

  /// The frame as it stands, for a view that draws one ([_live]) — built
  /// again for each tree it is handed, from the cels in hand; the rest are
  /// read and it is built again once they are. The ones [onScreen] picks
  /// are on screen already and read on this thread first
  /// ([FramePictureView.alreadyShown], [FramePictureView.drawnLive],
  /// [_onScreen]).
  ///
  /// 🚨[asItStands] IS THE KEY THE HANDING WAS TOLD BY ([didUpdateWidget]),
  /// not signed again: ↩️each value of a box that draws on the frame (a cel
  /// number's) signed the 68 rows twice (🔬Surface Pro 11, S5_BA cut 352,
  /// F-620, 2026-11-19).
  void _standLive({
    bool Function(BrushFrameKey cel)? onScreen,
    FramePictureKey? asItStands,
  }) {
    _stoodBy =
        asItStands ?? _pictures.keyAsItStands(widget.nodes, widget.picture);
    _waits = waitsForItsPlugins(widget.nodes);
    _liveChanges?.removeListener(_liveMoved);
    _liveChanges = null;
    _live = null;
    _movedSinceThrough = true;
    _onScreen = const {};
    final live = widget.live;
    if (live == null && widget.wholeFrames) {
      _standing.whole = false;
      return;
    }
    if (onScreen != null) {
      _report(
        _pictures.readInStackNow(
          widget.nodes,
          widget.picture,
          onScreen: onScreen,
        ),
        'reading what is on screen already',
      );
    }
    final frame = _pictures.frameAsItStands(
      widget.nodes,
      widget.picture,
      live: live == null ? null : (rows: live, painters: _painters),
    );
    _live = frame;
    if (live != null) {
      _liveChanges = frame.changes..addListener(_liveMoved);
    }
    final nodes = widget.nodes;
    _onScreen = {
      for (final cel in stackedCelsOf(nodes))
        if (_pictures.inHand(cel, widget.picture)) cel,
    };
    if (!_pictures.allInHand(nodes, widget.picture)) {
      _readInThenStandAgain(frame);
    }
  }

  void _liveMoved() {
    _standingMoved = true;
    _movedSinceThrough = true;
  }

  /// Reads the cels [frame] stood without, and stands again where the read
  /// brought one into hand and [frame] is still the one standing.
  ///
  /// 🚨STOOD AGAIN ONLY FOR WHAT THE READ BROUGHT INTO HAND. A cel no read
  /// brings in — a movie's not decoded yet, its decode the hydrator's (and
  /// a decoded one, banked nowhere, until it was in hand: 2026-10-30,
  /// `LayerFrameImageCache.storedSurfaceIsInHand`) — or one whose bytes
  /// would not thaw answered the read at once, and the frame
  /// stood again and read again in the same microtask, for ever: from
  /// 2026-10-25 (one picture per frame) the app hung the moment a movie
  /// stood on the canvas (🐞10-30, the hands-on verify's 23.976 `.mov` —
  /// 21 million stands in two minutes). What changes a cel after moves its
  /// revision, and the frame is handed anew ([didUpdateWidget]).
  void _readInThenStandAgain(StackedFrame frame) {
    final nodes = widget.nodes;
    final picture = widget.picture;
    final inHand = _onScreen;
    unawaited(
      _pictures.readInStack(nodes, picture).then((_) {
        if (mounted &&
            identical(_live, frame) &&
            stackedCelsOf(nodes).any(
              (cel) => !inHand.contains(cel) && _pictures.inHand(cel, picture),
            )) {
          setState(_standLive);
        }
      }),
    );
  }

  /// Takes the frame asked for where it is there; leaves what stands where
  /// it is not yet.
  void _look() {
    final key = _pictures.keyOfStack(widget.nodes, widget.picture);
    if (key == _showing && _shown != null) {
      return;
    }
    // ⛔Not peeked under this view's own key ([_keptUnder]) where a landing
    // moved the picture there: it is the one shown already, and the view
    // goes on as the move's own until it is given back. Peeked there too,
    // no screen told the two apart (F-473's mutants, 2026-10-26).
    final there = _store.peek(key);
    if (there != null) {
      _take(key, there);
      return;
    }
    if (key == _showing) {
      return;
    }
    // 🚨A PAGE A PEN DRAWS ON IS A PICTURE TOO ([FramePictures.makeShown]):
    // drawn as it stood, each step of its first stroke composed the whole
    // view (🔬Surface Pro 11, step → ink p50 117–123 ms, 2026-10-28).
    if (_pictures.gaveUpAt(key) ||
        (_pictures.drawsOnlyItsPage(key) && widget.live == null)) {
      _standAsStored(key);
      return;
    }
    if (_moves(key)) {
      return;
    }
    if (widget.laysWhatItMisses) {
      _makeOrKeep(key);
    }
    if (_standsMeanwhile) {
      // Drawn as it stands until its picture is there.
      _letGo(_store);
      _showing = key;
    }
  }

  /// The picture shown was written into — by another view's stroke, or by
  /// a store that was not asked at a paint: shown again. A write made in a
  /// frame's own phases is another view's paint's, and this one's paint
  /// comes after that frame.
  ///
  /// A step that did not go in, the engine says once it is through
  /// ([EngineFramePicture.failed]): the frame is drawn as it stands from
  /// here on, never as the picture without it (F-509), as [_writeIn] does
  /// with a step refused where it is asked.
  void _written() {
    if (_shown?.failed case final failed? when !_standing.whole) {
      _standing.whole = true;
      _report(failed, 'writing a step into the picture shown');
    }
    if (_writing) {
      return;
    }
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => _paintAgain());
      return;
    }
    _paintAgain();
  }

  /// Shows [there], the picture of [key] — the one shown already where a
  /// stroke's landing moved it here, what it holds of the live rows kept.
  void _take(FramePictureKey key, EngineFramePicture there) {
    if (identical(there, _shown)) {
      // ⛔Not let go and taken again: what the picture holds of the live
      // rows it holds under this one, and the next stroke patches in from
      // there — let go, a stroke whose first step came before the last
      // one's landing would be drawn as it stands whole, a step at a time.
      _showing = key;
      _drawnOn = _celNow();
      return;
    }
    _letGo(_store);
    _store.retainPin(key);
    _keptAs = key;
    _shown = there.hold();
    there.addListener(_written);
    _showing = key;
    _drawnOn = _celNow();
    _standing.whole = false;
    _movedSinceThrough = true;
    _tell();
  }

  /// The cel the pen is on as the key of the picture shown reads it.
  CelAsOf? _celNow() {
    final cel = _celDrawnOn();
    return cel == null ? null : _pictures.celNow(cel);
  }

  /// A frame with nothing of it to wait for — its page alone where nothing
  /// is drawn live, or one whose making threw — drawn as it stands.
  void _standAsStored(FramePictureKey key) {
    _letGo(_store);
    final now = _pictures.drawingNow(widget.nodes, widget.picture);
    _asItStands = now.frame;
    _showing = key;
    _report(now.thrown, 'drawing a frame as its cels stand');
  }

  /// [_make]s [key]'s frame — or, where the frame drawn as it stands is the
  /// picture the store would lay of it ([_standsAsItsPicture]), keeps what
  /// the paint lays ([_keepWhatStood]): made once the frame is painted
  /// where no paint laid it.
  ///
  /// 🔬F-620 (S5_BA cut 352, 2026-11-19): ↩️a value dragged on the canvas
  /// — a cel number's box, a lane's colour wheel — was composed twice a
  /// value, the frame as it stands and again as its key's picture.
  void _makeOrKeep(FramePictureKey key) {
    final live = _live;
    if (live == null || !_standsAsItsPicture(live)) {
      _keeping = null;
      _make(key);
      return;
    }
    // The making of the key before, if any, is no one's now.
    _making = null;
    _keeping = (key: key, frame: live);
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => _madeUnlessLaid(key, live),
    );
  }

  /// Whether [live], drawn as it stands, is the picture the store would lay
  /// of its frame ([FramePictures.makeShown]): every cel it draws in hand
  /// ([FramePictures.frameAsItStands] leaves one out till it is read), its
  /// live rows showing nothing no cel stores ([_showsUnstored] — what keeps
  /// a picture under the frame's key, [_keptUnder]), its nodes held where
  /// a canvas's picture holds them ([_screenStoodOn]), and nothing it
  /// waits for ([_standsMeanwhile]).
  bool _standsAsItsPicture(StackedFrame live) =>
      widget.live != null &&
      _standsMeanwhile &&
      !_showsUnstored(live.tokens) &&
      _pictures.allInHand(widget.nodes, widget.picture);

  /// [key]'s frame made, where the paint laid nothing of [live] to keep —
  /// a view standing bare ([_standsBare]), or one not painted.
  void _madeUnlessLaid(FramePictureKey key, StackedFrame live) {
    final keeping = _keeping;
    if (!mounted ||
        keeping == null ||
        !identical(keeping.frame, live) ||
        identical(_composedOn, live)) {
      return;
    }
    _keeping = null;
    _make(key);
  }

  /// [frame], laid on [screen] by the composition counted [laidBy] (null
  /// where it threw), kept as the picture of the key [_look] stands on it
  /// for ([_keeping]) — or made by the store, where it was not the last
  /// laid there, its live rows moved since or show what no cel stores, or
  /// the store has the key laid or on its way.
  void _keepWhatStood(
    EngineStackScreen screen,
    StackedFrame frame, {
    required int? laidBy,
  }) {
    final keeping = _keeping;
    if (!mounted || keeping == null || !identical(keeping.frame, frame)) {
      return;
    }
    _keeping = null;
    final laidLast =
        identical(_standingOn, screen) &&
        laidBy == _stood &&
        !_standingMoved;
    final kept = laidLast && !_showsUnstored(frame.tokens)
        ? _store.keepLaid(keeping.key, screen)
        : null;
    if (kept == null) {
      _make(keeping.key);
      return;
    }
    // The store's now: freed once it lets it go and no one shows it.
    _standingOn = null;
    _composedOn = null;
    setState(_look);
  }

  /// Makes [key]'s frame now, as this view stacks it.
  void _make(FramePictureKey key) {
    if (_making == key) {
      return;
    }
    _making = key;
    unawaited(
      _pictures
          .makeShown(
            widget.nodes,
            widget.picture,
            shouldAbort: () => !mounted || _making != key,
            keepsNodes: widget.live != null,
          )
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              // 🚨NOTED, as the warmer notes a making of its own that threw
              // (`PlaybackPrerenderScheduler`): it is not asked for again at
              // this content, and the frame is drawn as its cels stand
              // ([_look]). ↩️Unnoted, a screen that draws nothing of its
              // frame till its picture is there asked for it again the
              // moment it had thrown, for as long as it threw, and came back
              // to no frame of the app's (🔬2026-11-11: its pin never
              // ended; 🗣️관제: 「끝나지 않는 재시도로 가지 않는지」).
              _pictures.noteFailureAt(key);
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stack,
                  library: 'frame picture view',
                  context: ErrorDescription('making the frame a screen shows'),
                ),
              );
            },
          )
          .whenComplete(() {
            if (!mounted || _making != key) {
              return;
            }
            _making = null;
            setState(_look);
          }),
    );
  }

  /// The cel of the row the pen is on, where a canvas that stands has one.
  BrushFrameKey? _celDrawnOn() {
    if (widget.live?.activeSurfacePainter == null) {
      return null;
    }
    for (final node in preorderNodes(widget.nodes)) {
      if (node case CompositeLeaf(
        payload: CanvasActiveLayerRow(frameKey: final cel?),
      )) {
        return cel;
      }
    }
    return null;
  }

  /// 🚨A STROKE THAT LANDS MOVES THE PICTURE IT WAS PATCHED INTO: [key] is
  /// the frame shown but for the cel the pen is on, and every change of
  /// the live rows is in its picture — the stroke's own steps — or goes in
  /// at the next patch, so its texels are [key]'s. ⛔Any other change of the
  /// frame — another row, the pen's own row's opacity, another frame — is a
  /// new picture.
  ///
  /// 🗣️F-525 (유저 2026-11-01): 「솔로할때만 안보임」 — ⛔SO IS A CHANGE THAT
  /// CANNOT GO IN ([_canCatchUp]). What lands on the cel but a stroke — a
  /// paste, a redo — has no step in the picture, all of it to go in at that
  /// patch; moved first and refused it, the picture stayed under the frame's
  /// key without it, and every screen that came back took it. A stack in
  /// solo draws no other row past the page, so a paste from one reached past
  /// its picture and not past the whole frame's.
  bool _moves(FramePictureKey key) {
    final from = _showing;
    final drawnOn = _drawnOn;
    final shown = _shown;
    if (shown == null || from == null || drawnOn == null) {
      return false;
    }
    if (_pictures.keyOfStack(widget.nodes, widget.picture, asOf: drawnOn) !=
        from) {
      return false;
    }
    if (!_canCatchUp) {
      return false;
    }
    // What is still out of it goes in under the key it moves to
    // ([_catchUp]) — where the build hands the live rows anew, and at the
    // paint after it. ↩️It was caught up here first, as the move's own,
    // until the change went in under the key a picture moves to: the same
    // texels.
    _repaint.value += 1;
    // The live rows as they are, not as [_held] last saw them: the stroke's
    // lift lets go of its overlay in the call that commits it, and what the
    // picture held of it is stored now — the frame's. (Kept under [_held],
    // the picture went this view's own until the lift's own patch gave it
    // back: no screen told the two apart, F-473's mutants 2026-10-26.)
    final to = _keptUnder(key, _live?.tokens);
    if (_standing.whole || !_store.move(from: _keptAs!, to: to)) {
      return false;
    }
    _keepAs(to);
    _showing = key;
    _drawnOn = _celNow();
    return true;
  }

  /// Whether what the live rows moved since the picture shown last held them
  /// can go into it: what [_catchUp] would draw the frame as it stands for.
  bool get _canCatchUp {
    final live = _live;
    final held = _held;
    return live != null && held != null && live.movedSince(held).located;
  }

  /// The live rows were handed anew — a lift taken up or put down, the
  /// pen's row's painter once its stroke landed: a change of the live rows
  /// like any other ([_catchUp]).
  ///
  /// ⛔Not left unasked: a box's lift would come with the picture standing,
  /// the float drawn nowhere until the box landed.
  ///
  /// 🚨A pen's row come to a picture that holds nothing of the live rows is
  /// told as its taking told them ([_tell]), with the cel the pen is on —
  /// untold, a blank page's first stroke was drawn as it stands, whole.
  ///
  /// 🚨ANOTHER CEL UNDER THE PEN IS NO CHANGE OF THE PICTURE (I-22): where
  /// the key stays, the picture holds that cel's stored pixels as it holds
  /// every row's, and it is told the same way. ↩️Measured from what the
  /// picture held of the cel left — another cel's tiles, every one of them
  /// 「moved」 — the frame was drawn as it stands until its key moved: on S5
  /// cut 352 5–9 ms a paint in debug, at each click on a row, and the first
  /// stroke on the row clicked composed the whole frame a step at a time.
  /// ⛔Asked of a picture only what no key answers, what it holds past the
  /// cels ([_showsUnstored]): what they store, its key holds it to. Asking
  /// what moved besides caught nothing (the mutants of 2026-11-01).
  void _liveRowsHandedAnew() {
    if (_shown != null) {
      final penMoved = _celDrawnOn() != _drawnOn?.cel;
      if (_held == null || (penMoved && !_showsUnstored(_held))) {
        _drawnOn = _celNow();
        _tell();
      }
      _catchUp();
    }
  }

  /// Tells what of the live rows the picture just taken holds: all of them
  /// where nothing is in hand — what is stored is what they show — and
  /// else what cannot be told, so the frame is drawn as it stands.
  void _tell() {
    final live = _live;
    if (widget.live == null || live == null) {
      return;
    }
    final now = live.tokens;
    if (_showsUnstored(now)) {
      _standing.whole = true;
      return;
    }
    _held = now;
  }

  /// Whether the live rows, as [tokens] tell them, show what no cel stores
  /// — the overlay's tiles, what floats over the live row, a row a lift
  /// holds.
  static bool _showsUnstored(LiveSurfaceTokens? tokens) =>
      tokens != null &&
      (tokens.overlay.isNotEmpty ||
          tokens.previews.isNotEmpty ||
          tokens.lifted.isNotEmpty);

  /// The key the picture of [key] is kept under once it holds the live
  /// rows as [tokens] tell them: [key] where they show nothing no cel
  /// stores, else this view's own ([FramePictureKey.standingOn]) — a
  /// picture under the frame's key is the frame, for every screen that
  /// asks for it.
  FramePictureKey _keptUnder(
    FramePictureKey key,
    LiveSurfaceTokens? tokens,
  ) => _showsUnstored(tokens) ? key.standingOn(this) : key;

  /// The picture shown is kept under [key] from here on — held there for
  /// this view: the one [key] answers with, another where the one shown
  /// stayed for another screen ([EngineFramePictureStore.patch]).
  void _keepAs(FramePictureKey key) {
    final kept = _keptAs!;
    if (key == kept) {
      return;
    }
    _store.retainPin(key);
    _store.releasePin(kept);
    _keptAs = key;
    final shown = _shown!;
    final there = _store.peek(key)!;
    if (!identical(there, shown)) {
      shown
        ..removeListener(_written)
        ..release();
      _shown = there.hold();
      there.addListener(_written);
    }
  }

  /// What the live rows moved since the picture shown last held them goes
  /// into it, patched in where it lands — or the frame is drawn as it stands
  /// from here on.
  ///
  /// 🚨ASKED AT EACH PAINT ([_catchUpAtPaint]) and where a build hands the
  /// live rows anew — not at each change of theirs, where a change
  /// and what goes with it come apart: a stroke that lands lets go of its
  /// overlay in the call that commits it, and the painter of the cel as
  /// committed comes with the next build. Measured at the change, the
  /// overlay letting go was patched in with the stroke gone — into the
  /// frame's one picture, which every screen showing that frame draws — and
  /// the build patched it back. ↩️The display buffer measured at its paint
  /// too (`_planMiss`).
  ///
  /// ↩️⛔NOT ONE STEP ON ITS WAY AT A TIME, HELD FOR ITS LANDING (F-512, 유저
  /// 2026-10-30 「선이 커서 뒤로 처진다」): a patch into a `flutter_gpu` picture
  /// took the store longer than a vsync, so each paint's request queued, and
  /// the line fell further behind the pen the longer it was (🔬Main PC, 144
  /// Hz, input to raster done p50 / p90, fitted 757 / 1346 ms → 49 / 60 ms).
  /// Composed here, in the paint that shows it, there is no line to grow.
  /// ⛔Nor ahead of the paint, or once the frame is out (F-533, undone
  /// 2026-11-03: the main PC gained 28 → 22 ms; on the Surface Pro 11 frames
  /// past 16.7 ms went 89 → 144 at 100%, the step's work landing in the next
  /// frame's way). 🚨The main PC does not speak for the Surface here.
  @override
  void _catchUp() {
    final live = _live;
    final key = _showing;
    if (live == null || _shown == null || key == null) {
      return;
    }
    if (!_standing.whole) {
      _patchIn(key, live);
    }
    if (_standing.whole && _waits) {
      _throughWhole(live);
    }
  }

  /// [_catchUp] where the frame is not drawn as it stands: what moved goes
  /// into the picture shown, or the frame is drawn as it stands from here.
  void _patchIn(FramePictureKey key, StackedFrame live) {
    final held = _held;
    if (held == null) {
      // Nothing drawn live: where rows are handed, [_tell] holds what the
      // picture holds of them, or draws the frame as it stands.
      // ↩️A live row handed and none held drew the frame as it stands,
      // until the live rows' tokens were never null — then no view reached
      // it (thrown there, the 295 files near it ran green, 2026-11-12).
      return;
    }
    final moved = live.movedSince(held);
    final dirty = moved.dirty;
    if (!moved.located) {
      _standing.whole = true;
      return;
    }
    _held = moved.now;
    if (dirty == null || dirty.isEmpty) {
      return;
    }
    _writeIn(key, live, dirty);
  }

  /// Writes the live rows' change at [dirty] into the picture of [key]
  /// shown — or draws the frame as it stands from here on, where it cannot
  /// be: a step that did not go in shows as the frame stands, never as the
  /// picture without it (F-509).
  void _writeIn(FramePictureKey key, StackedFrame live, Rect dirty) {
    if (_waits) {
      _writeThrough(dirty);
      return;
    }
    final to = _keptUnder(key, _held);
    _writing = true;
    try {
      if (!_store.patch(
        from: _keptAs!,
        to: to,
        rect: dirty,
        frame: live,
        holds: _pictures.heldNodes,
      )) {
        _standing.whole = true;
        return;
      }
    } on FrameKernelsToCome {
      // Drawn as it stands, which waits for them in this paint's show.
      _standing.whole = true;
      return;
    } on StateError catch (error, stack) {
      _standing.whole = true;
      _report((error, stack), 'writing a step into the picture shown');
      return;
    } finally {
      _writing = false;
    }
    _pictures.giveWayToSteps();
    _keepAs(to);
  }

  /// Lets go of what is shown, and of [store]'s hold on its picture.
  ///
  /// A picture kept as this view's own goes with it: what it holds past
  /// the frame's stored pixels is no picture of the frame's
  /// ([FramePictureKey.standingOn]).
  void _letGo(EngineFramePictureStore<FramePictureKey> store) {
    if (_shown case final picture?) {
      picture.removeListener(_written);
      final kept = _keptAs!;
      store.releasePin(kept);
      if (kept.standingFor != null) {
        store.letGo(kept);
      }
      picture.release();
    }
    _shown = null;
    _asItStands = null;
    _showing = null;
    _keptAs = null;
    _held = null;
  }

  /// What [_RenderFrameScreen] asks of this view in its paint.
  ///
  /// The frame as it is drawn now — what [frame] stands for where no
  /// picture is shown — onto [target] of [size] texels, laid [on] it.
  @override
  void _show(
    StackedFrame? frame,
    GpuTarget target,
    (int, int) size,
    _OnTheTexture on,
  ) {
    _cutOnScreen = _showing?.cutId ?? _cutOnScreen;
    _pictures.putOnScreen();
    final (:viewport, :devicePixelRatio, :corner) = on;
    final shown = _drawnPicture;
    if (shown != null) {
      shown.show(
        target,
        size,
        viewport: viewport,
        devicePixelRatio: devicePixelRatio,
        corner: corner,
      );
      _standingOn?.free();
      _standingOn = null;
      _composedOn = null;
      return;
    }
    final screen = _screenStoodOn(frame!);
    screen.show(
      target,
      size,
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
      corner: corner,
    );
  }

  /// Where the live rows moved that is still to go through a frame's
  /// plugins ([_writeThrough]).
  Rect? _owed;

  /// The writes through them, one at a time ([_writeThrough]).
  late final _writesThrough = OnePassAtATime(
    due: () => mounted && _owed != null && _live != null && _showing != null,
    pass: _writeWhatIsOwed,
  );

  /// 🗣️I-132-Q34 a with F-240 (유저 2026-09-29: 「변형중에도 필터 통일적용하도록」):
  /// a frame that waits for its plugins is never drawn as it stands
  /// ([_drawnPicture]) — where its live rows moved where no patch can
  /// follow ([StackedFrame.movedSince]), all of it goes through them at
  /// each change, on the picture shown meanwhile. ↩️A float and a lift were
  /// two of those, until they were told (a-float-in-hand-draws-the-frame-
  /// as-it-stands, 2026-11-12): through them whole at every step, a
  /// plug-in's row paid ~29 ms a step on the Surface Pro 11.
  ///
  /// ↩️It stayed on the picture shown until its key moved (ef44c1e56,
  /// 2026-10-30 — the choice of who built Q34 a, not the user's answer), and
  /// a float carried on such a row was drawn nowhere until it landed: met
  /// only past a chain's head until a plugin there was a step of the chain
  /// too (float-warp-resamples-in-the-c-engine (2), 2026-11-11), when
  /// F-240's six tests on a plugin's row read 16,048 pixels apart — the
  /// sheet where it was lifted from, all the drag.
  void _throughWhole(StackedFrame live) {
    if (!_movedSinceThrough) {
      return;
    }
    _movedSinceThrough = false;
    _writeThrough(live.extent);
  }

  /// [_writeIn] of a frame that waits for its plugins: the screen stays on
  /// the picture as it is until they have run (🗣️I-132-Q34 a), one write at
  /// a time — the steps meanwhile go in together, in the next. A step whose
  /// frame stands no more by then does not go in.
  void _writeThrough(Rect dirty) {
    _owed = _owed?.expandToInclude(dirty) ?? dirty;
    unawaited(_writesThrough.ask());
  }

  /// What is owed written through the plugins into the picture of the frame
  /// shown — false where they threw, said.
  Future<bool> _writeWhatIsOwed() async {
    final (owed, live, key) = (_owed!, _live!, _showing!);
    _owed = null;
    // Whole, it holds what no patch could tell — this view's own
    // ([FramePictureKey.standingOn]), as what no cel stores.
    final to = _standing.whole ? key.standingOn(this) : _keptUnder(key, _held);
    final bool went;
    try {
      went = await _store.patchThrough(
        from: _keptAs!,
        to: to,
        rect: owed,
        frame: live,
        holds: _pictures.heldNodes,
        stands: () => mounted && identical(_live, live),
      );
    } on Object catch (error, stack) {
      _report((error, stack), 'writing a step through its plugins');
      return false;
    }
    if (went && mounted) {
      _pictures.giveWayToSteps();
      _keepAs(to);
    }
    return true;
  }

  /// The picture to show, where the frame is not drawn as it stands: a
  /// frame that waits for its plugins keeps the picture shown whatever.
  EngineFramePicture? get _drawnPicture =>
      _standing.whole && !_waits ? null : _shown;

  /// Whether this view stands bare till the picture of its frame comes,
  /// where it would draw it as it stands: its picture still to come, of a
  /// cut nothing of which was there — another than the one it put on
  /// screen last (Q5 = blank), or, before it put one there, any of a
  /// project none of whose frames a view showed yet: a file just opened
  /// (🗣️Q7 = blank, 유저 2026-11-18 「빈 종이로 기다린다」,
  /// [FramePictures.anyOnScreen]). ⛔Not a page alone, nor a frame given up
  /// on: there is nothing of them to come, and a move lands on them at once
  /// ([FramePictures.toComeAt]).
  bool get _standsBare {
    final showing = _showing;
    if (!_standsMeanwhile || showing == null) {
      return false;
    }
    final onScreen = _cutOnScreen;
    final nothingThere = onScreen == null
        ? !_pictures.anyOnScreen
        : showing.cutId != onScreen;
    return nothingThere && _pictures.toComeAt(showing);
  }

  /// [frame] composed on this view's own screen, where it or its live rows
  /// moved since it last was.
  EngineStackScreen _screenStoodOn(StackedFrame frame) {
    final (:composite, :letters) = _store.toolsOpen!;
    final screen = _standingOn ??= EngineStackScreen(composite, letters);
    if (!identical(_composedOn, frame) || _standingMoved) {
      final composed = screen.compose(
        frame,
        holds: widget.live == null ? null : _pictures.heldNodes,
      );
      _composedOn = frame;
      _standingMoved = false;
      final stood = ++_stood;
      unawaited(
        composed.then<void>(
          (_) => _keepWhatStood(screen, frame, laidBy: stood),
          onError: (Object error, StackTrace stack) {
            // Composed again at the next paint, as one refused where it was
            // asked was: the screen keeps no canvas it failed on.
            if (identical(_composedOn, frame)) {
              _composedOn = null;
            }
            _report((error, stack), 'drawing a frame as it stands');
            _keepWhatStood(screen, frame, laidBy: null);
          },
        ),
      );
    }
    return screen;
  }

  /// 🚨PAINTED AGAIN ONLY FOR WHAT CHANGES IN IT — a layer of its own, as
  /// the brush's own canvas has (`brush_edit_canvas_view.dart`). In its
  /// screen's layer, a neighbour's repaint painted it too: the canvas's
  /// underlay is laid out again at each commit of the timeline (its tick
  /// layer's builder), and a layout marks its layer for paint — so a frame
  /// drawn as it stands, a page of nothing but paper, was composed whole at
  /// each block moved, though nothing in it had (F-244: 🔬1920×1080 a
  /// commit, +25ms in profile, Surface Pro 11, 저장 2026-10-27).
  @override
  Widget build(BuildContext context) => _FrameScreen(
    view: this,
    shown: _shown,
    // ⛔Not the stored cels where the view draws rows live: a frame of no
    // row is a page the pen may be drawing on — nor the live rows of a
    // frame that waits for its plugins, nor of one it stands bare for
    // ([_standsBare]).
    asItStands: _waits || _standsBare ? _asItStands : _live ?? _asItStands,
    ground: widget.ground,
    cutAtCanvas: widget.cutAtCanvas,
    viewport: widget.viewport,
    devicePixelRatio: EffectiveDevicePixelRatio.of(context),
    panel: null,
    repaint: Listenable.merge([_repaint, _liveChanges]),
    overlays: widget.carriesTheOverlays
        ? PictureUpViewScope.maybeOf(context)
        : null,
    together: PictureUpViewScope.togetherOf(context),
    // The canvas's own picture — on its paper: the editing canvas's frame,
    // the film's stage — is handed on where one screen takes another's
    // place; never the ghosts over it, nor a track over the stage
    // ([PicturesLeftUp], F-599).
    leftUp: widget.picture.paintPaper
        ? PictureUpViewScope.picturesLeftUpOf(context)
        : null,
  );
}

/// How much of a screen is to spare on every side of its box, in device
/// pixels, for the frame drawn last to serve a view panned since
/// ([_RenderFrameScreen._servedByTheFrameDrawnLast]): nearer its edge the
/// next is asked for, and this is how far the view may pan on before that
/// one is up — a frame of the app's or more ([ScreenTexture.present]) —
/// with the box still held whole by the frame that is, moved with it
/// ([_RenderFrameScreen._standingFrom]). Past it, the edge the pan
/// uncovers is bare of any picture till the next comes up.
const int _screenMargin = 128;

/// How far past its box a view's screen holds, in device pixels, along an
/// axis — half to either side ([EngineScreenTexture.windowOf]): the margin
/// on each side, and half as much again that a pan crosses with nothing
/// drawn. ⚠️The least it holds: a texture's sides are rounded up a step
/// ([EngineScreenTexture]), and what that spares is room too.
const int _screenRoom = 3 * _screenMargin;

/// The step a cel's window's screen is rounded up to, in device pixels
/// ([_holdsOver]): a box a few pixels across is not held in a texture a
/// canvas's step on a side. One a zoom grows past its texture stands on
/// what it outgrew till the next shows ([EngineScreenTexture.replaced]).
const int _windowSideStep = 64;

/// What of a box its screen holds, in the box's device pixels: the [rect]
/// a frame is laid around ([EngineScreenTexture.windowOf]), the [margin]
/// past it the frame drawn last spares to serve a view panned since
/// ([_RenderFrameScreen._servedByTheFrameDrawnLast]), and the sides its
/// texture is opened at ([wanted]).
typedef _ScreenHolds = ({Rect rect, int margin, (int, int) wanted});

/// A box of [sides] that is the panel's: held whole, a pan uncovering its
/// edge.
_ScreenHolds _holdsWhole((int, int) sides) {
  final (width, height) = sides;
  return (
    rect: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    margin: _screenMargin,
    wanted: (width + _screenRoom, height + _screenRoom),
  );
}

/// A cel's window of [sides] with the [panel] lying over it where it does
/// ([LiveCelScreen]): along an axis the panel and [_screenMargin] past its
/// edges take in, the box held whole — a pan moves it with the paper and
/// asks for nothing — and along a longer one, what lies within them, its
/// texture no wider.
///
/// ↩️Held as the panel's box is, every window's screen was a texture the
/// panel's size, a step and the room to pan round it — for a band of the
/// conte's a few rows high, or a box of the envelope's among dozens
/// (board the-screen-premultiplies-ram-tiles-to-show-them).
_ScreenHolds _holdsOver((int, int) sides, Rect panel) {
  final around = panel.inflate(_screenMargin.toDouble());
  (double, double) along(int side, double from, double to) {
    if (side <= to - from) {
      return (0, side.toDouble());
    }
    final start = from.clamp(0, side).toDouble();
    return (start, to.clamp(start, side).toDouble());
  }

  final (width, height) = sides;
  final (left, right) = along(width, around.left, around.right);
  final (top, bottom) = along(height, around.top, around.bottom);
  return (
    rect: Rect.fromLTRB(left, top, right, bottom),
    margin: 0,
    wanted: (
      math.min(width, around.width.ceil()),
      math.min(height, around.height.ceil()),
    ),
  );
}

/// What a frame of a view's screen was drawn for: the view it was drawn
/// through, as every painter under it snaps it ([renderSnappedViewport]),
/// and the texel of the screen the view's corner stood on.
typedef _DrawnFor = ({CanvasViewport viewport, (int, int) corner});

/// The box a [FramePictureView] shows its frame in.
class _FrameScreen extends LeafRenderObjectWidget {
  const _FrameScreen({
    required this.view,
    required this.shown,
    required this.asItStands,
    required this.ground,
    required this.cutAtCanvas,
    required this.viewport,
    required this.devicePixelRatio,
    required this.panel,
    required this.repaint,
    required this.overlays,
    required this.together,
    required this.leftUp,
  });

  final _FrameFeed view;
  final EngineFramePicture? shown;
  final StackedFrame? asItStands;
  final Color? ground;
  final CanvasSize? cutAtCanvas;
  final CanvasViewport viewport;
  final double devicePixelRatio;
  final Listenable repaint;

  /// Where the panel lies over this box, in the box's own space, where the
  /// box is a cel's window on the panel's paper ([LiveCelScreen]) — what of
  /// it a frame holds ([_holdsOver]); null where the box is the panel's.
  final Rect? panel;

  /// The clock of what is drawn over the canvas, where this box carries it
  /// ([FramePictureView.carriesTheOverlays]).
  final PictureUpView? overlays;

  /// What its frames go up together with: the canvas's other pictures.
  final PicturesUpTogether? together;

  /// Where the canvas's picture is left up for the screen that takes its
  /// place, and taken by one that has put none up — named where this
  /// screen's picture is the canvas's own, on its paper ([PicturesLeftUp]).
  final PicturesLeftUp? leftUp;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFrameScreen(view, windowed: panel != null)..takeFrom(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderFrameScreen).takeFrom(this);
}

/// A frame shown through a texture of the engine's, one texel a device
/// pixel, presented in this box's paint and laid as its layer — so what a
/// frame's paint writes into the picture is what that frame shows.
///
/// [_FrameScreen.ground] lies under it across the box; the texture is cut
/// to the box, and to [_FrameScreen.cutAtCanvas] where one is named, and
/// not the ground.
///
/// 🚨★★★THE FRAME UP STANDS WHERE IT WAS DRAWN FOR, AND A PAN MOVES IT WITH
/// THE VIEW ([_standingFrom]) — the frame grid's law on the canvas
/// (`timeline_grid_screen.dart`: a screen wider than what the view shows,
/// laid where it was drawn for, a scroll moving it layer and all; 관제
/// 2026-11-09 08:07 F).
///
/// 🗣️유저 2026-11-15, 최신 빌드 실기: 「캔버스 화면 팬으로 움직일때 카메라
/// 오버레이? 위젯이랑 캔버스랑 어긋나거든? … 더 빠릿하게 따라오고 캔버스는 …
/// 더 늦게 따라오는느낌. 이런 캔버스에 보이는건 동일하게 했으면좋겟는데. 거기서
/// 더 가볍게하는식으로」 — what is seen on the canvas moves as one body: the
/// picture, and what Flutter draws over it for the view as it stands (the
/// camera's frame, the guides, the SE tags, the fade).
/// ↩️The frame up was laid at the box's corner whatever view it was drawn
/// through: a frame is up once the GPU has finished it
/// ([ScreenTexture.present]) — a frame of the app's or more after it was
/// asked for — so through a pan the picture stood a step or more behind
/// everything drawn over it, further the busier the engine.
///
/// ⚠️Not what a-float-in-hand-draws-the-frame-as-it-stands-Q2 let be
/// (「어긋나는거 ok」): that is a picture made again under a box that
/// follows the hand. A pan makes nothing again — the same picture, seen
/// from another place (관제 2026-11-15).
class _RenderFrameScreen extends RenderBox implements StandingPicture {
  _RenderFrameScreen(this._view, {required bool windowed})
    : _windowed = windowed;

  final _FrameFeed _view;

  /// Whether this box is a cel's window's ([_FrameScreen.panel]).
  final bool _windowed;

  late final EngineScreenTexture _shownThrough = EngineScreenTexture(
    asks: () => attached,
    opened: (_) {
      markNeedsPaint();
      _tellTheOverlays();
    },
    letGo: () {
      _letGoOfTheStandIn();
      markNeedsPaint();
      _tellTheOverlays();
    },
    putUp: ({required behind}) {
      behind ? markNeedsPaint() : _showWhatIsUp();
      _tellTheOverlays();
    },
    sideStep: _windowed ? _windowSideStep : null,
    replaced: _standOn,
  );

  /// [outgrown] — the texture this box's picture was seen through, which
  /// it has grown past — stands in till the one opened in its place shows
  /// a frame ([_standIn]): that one shows nothing till then.
  void _standOn(ScreenTexture outgrown) {
    final standIn = _standIn;
    _standIn = outgrown;
    unawaited(standIn?.free());
  }

  /// The clock of what is drawn over the canvas, where this box carries it.
  PictureUpView? _overlays;

  /// The view of the frame up the clock was last told of.
  CanvasViewport? _toldUp;

  /// What its frames go up together with: the canvas's other pictures.
  PicturesUpTogether? _together;

  /// Where the canvas's picture is left up and taken — this box's where its
  /// picture is the canvas's own, on its paper ([PicturesLeftUp]).
  PicturesLeftUp? _leftUp;

  /// What is stood on till this box has put a picture up: the canvas's
  /// that another screen left up ([PicturesLeftUp]), or the texture this
  /// box grew past ([_standOn]).
  ScreenTexture? _standIn;

  /// Whether this box's own texture shows a frame.
  bool get _ownUp => _shownThrough.texture?.showsAFrame ?? false;

  /// The texture this box's picture is seen through now: its own once it
  /// has put one up, else the picture it stands in on.
  ScreenTexture? get _seenThrough =>
      _ownUp ? _shownThrough.texture : _standIn ?? _shownThrough.texture;

  /// The picture left up for this box, laid where it was drawn for — while
  /// this box has put none up of its own, its picture made or not yet: a
  /// cut coming in that makes its own has none at its first paint.
  Layer? _standingIn(Offset offset) {
    var standIn = _standIn;
    if (standIn == null) {
      standIn = _standIn = _leftUp?.take();
      if (standIn == null) {
        return null;
      }
      _tellTheOverlays();
    }
    return EngineScreenTexture.layerOf(standIn, _placeAt(offset));
  }

  void _letGoOfTheStandIn() {
    final standIn = _standIn;
    if (standIn == null) {
      return;
    }
    _standIn = null;
    unawaited(standIn.free());
    _tellTheOverlays();
  }

  /// Lets go of the screen — what it shows left up for the screen that
  /// takes its place, where its picture is the canvas's own
  /// ([PicturesLeftUp]).
  void _leaveWhatIsUp() {
    final leftUp = _leftUp;
    final standIn = _standIn;
    _standIn = null;
    if (leftUp == null) {
      _shownThrough.stop();
      unawaited(standIn?.free());
      return;
    }
    final own = _shownThrough.stopLeavingItsFrame();
    if (own != null) {
      unawaited(standIn?.free());
    }
    final left = own ?? standIn;
    if (left != null) {
      leftUp.left(left);
    }
  }

  /// The frame up is drawn through another view: what is drawn over the
  /// canvas is told — between the app's frames, as a frame goes up
  /// ([ScreenTexture.putUp]), so the frame that shows it draws them with
  /// it. ⛔Not at each frame up: a stroke puts one up a frame, all of one
  /// view, and its overlays would be built again with nothing moved.
  void _tellTheOverlays() {
    final up = _shownFor()?.viewport;
    if (up == _toldUp) {
      return;
    }
    _toldUp = up;
    _overlays?.moved();
  }

  /// What the frame up was drawn for — null where none is up.
  _DrawnFor? _shownFor() {
    final texture = _seenThrough;
    final shownFor = texture?.shownFor;
    return texture != null && texture.showsAFrame && shownFor is _DrawnFor
        ? shownFor
        : null;
  }

  /// The view the frame up stands at, the view being [now] — the view it
  /// was drawn through, moved by the pan it stands at ([_panStood]) — or
  /// the view as it is where this box shows none.
  @override
  CanvasViewport standingFor(CanvasViewport now) {
    final shownFor = _drawsAnything || _standIn != null ? _shownFor() : null;
    if (shownFor == null) {
      return now;
    }
    return viewMovedBy(
      shownFor.viewport,
      _panStood(shownFor, now),
      _devicePixelRatio,
    );
  }

  /// The frame up and the pan it stood at last ([_panStood]).
  ({_DrawnFor frame, (double, double) pan})? _stoodLast;

  /// The whole device pixels the frame up, drawn for [shownFor], stands
  /// moved by, the view being [now]: the pan since it was drawn
  /// ([panSince]) — and through a zoom, a turn or a flip since, the pan it
  /// stood at last, till the next is up.
  ///
  /// 🗣️F-601 (유저 2026-11-16: 「팬으로 한번 이동한 다음 확대/축소시 캔버스
  /// 화면이 1프레임 다른곳으로 이동했다가 돌아옴」). ↩️Through a zoom it
  /// stood where it was drawn: a pan the frame drawn last served draws
  /// nothing ([_servedByTheFrameDrawnLast]), so the frame up after a pan
  /// was drawn before it, and the zoom's first frame showed the picture —
  /// and everything drawn over it — back where the pan began.
  (double, double) _panStood(_DrawnFor shownFor, CanvasViewport now) {
    final pan = panSince(shownFor.viewport, now, _devicePixelRatio);
    if (pan != null) {
      _stoodLast = (frame: shownFor, pan: pan);
      return pan;
    }
    final last = _stoodLast;
    return last != null && last.frame == shownFor ? last.pan : (0.0, 0.0);
  }

  /// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
  /// 띄운다 — 그때까지 고리」 — whether this box's frame is kept from the
  /// screen till the app has what a hand needs of its engine
  /// ([appEngineGetsReady]): the frame coming to the screen is the word
  /// that it can be worked on. Its picture is made meanwhile all the same,
  /// and shown by the paint that follows the app's being let go.
  ///
  /// ⛔Not a wait its place marks ([_FrameFeed._waitsAtPaint]): the app
  /// stands behind its one wait window for it
  /// (`HomePage._waitForTheEngineBehindTheWindow`).
  bool get _heldForTheEngine => appEngineGetsReady.value;

  /// The compile this box paints again after ([_paintOnceCompiled]).
  Future<void>? _compiling;

  /// Paints again once [compiled] is done: a frame the paint could not lay
  /// yet ([FrameKernelsToCome]) is laid by that one. Once a compile, however
  /// many paints meet it.
  void _paintOnceCompiled(Future<void> compiled) {
    if (identical(_compiling, compiled)) {
      return;
    }
    _compiling = compiled;
    unawaited(
      compiled.then(
        (_) => _paintAgain(),
        onError: (Object error, StackTrace stack) {
          _report((error, stack), 'compiling the kernels a frame is laid on');
          // Laid by the paint all the same: its run says why it cannot be.
          _paintAgain();
        },
      ),
    );
  }

  void _paintAgain() {
    if (attached) {
      markNeedsPaint();
    }
  }

  /// Whether this box was asked to paint for anything but a frame put up:
  /// a paint for that alone shows it and draws nothing — or every frame
  /// the GPU finished would draw the next, for ever.
  bool _drawAsked = true;

  @override
  void markNeedsPaint() {
    _drawAsked = true;
    super.markNeedsPaint();
  }

  /// A frame the GPU finished is up on the texture: painted again to show
  /// it ([EngineScreenTexture.standing]).
  void _showWhatIsUp() {
    if (attached) {
      super.markNeedsPaint();
    }
  }

  EngineFramePicture? _shown;
  StackedFrame? _asItStands;
  Color? _ground;
  CanvasSize? _cutAtCanvas;
  late CanvasViewport _viewport;
  double _devicePixelRatio = 1;
  Listenable? _repaint;

  void takeFrom(_FrameScreen screen) {
    final changed =
        !identical(screen.shown, _shown) ||
        !identical(screen.asItStands, _asItStands) ||
        screen.ground != _ground ||
        screen.cutAtCanvas != _cutAtCanvas ||
        screen.devicePixelRatio != _devicePixelRatio;
    final moved = !identical(screen.viewport, _viewportOrNull);
    final shifted = screen.panel != _panel;
    if (screen.devicePixelRatio != _devicePixelRatio) {
      markNeedsLayout();
    }
    _shown = screen.shown;
    _asItStands = screen.asItStands;
    _ground = screen.ground;
    _cutAtCanvas = screen.cutAtCanvas;
    _viewportOrNull = screen.viewport;
    _viewport = screen.viewport;
    _devicePixelRatio = screen.devicePixelRatio;
    _panel = screen.panel;
    if (!identical(screen.overlays, _overlays)) {
      if (attached) {
        _overlays?.letGoOf(this);
        screen.overlays?.carriedBy(this);
      }
      _overlays = screen.overlays;
    }
    _together = screen.together;
    _leftUp = screen.leftUp;
    // Where the panel lies over a window moves what it holds, not what is
    // drawn on it: a texture to hold that, and a frame where the one drawn
    // last does not.
    if (shifted && hasSize) {
      _wantAsHeld();
    }
    if (changed || ((moved || shifted) && !_servedByTheFrameDrawnLast)) {
      markNeedsPaint();
    } else if (moved) {
      // The view alone, and the frame drawn last serves it yet: painted to
      // move what is up with it, nothing drawn.
      super.markNeedsPaint();
    }
    if (attached) {
      _repaint?.removeListener(markNeedsPaint);
      screen.repaint.addListener(markNeedsPaint);
    }
    _repaint = screen.repaint;
  }

  CanvasViewport? _viewportOrNull;

  /// Where the panel lies over this box, where it is a cel's window's
  /// ([_FrameScreen.panel]).
  Rect? _panel;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
    appEngineGetsReady.addListener(markNeedsPaint);
    _overlays?.carriedBy(this);
    _shownThrough.start();
    // A box put back — moved under another parent, laid out with the
    // constraints it had — is not resized, and asks for its texture here
    // (frame-timing-overlay-hides-the-canvas): the grid's slots' law
    // (`_RenderGridScreenSlot.attach`). A box come anew has nothing wanted
    // yet, and asks as it is sized ([performResize]).
    unawaited(_shownThrough.open());
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    appEngineGetsReady.removeListener(markNeedsPaint);
    _overlays?.letGoOf(this);
    _leaveWhatIsUp();
    super.detach();
  }

  @override
  void performResize() {
    super.performResize();
    _wantAsHeld();
  }

  /// Asks for a texture as big as what the box holds wants
  /// ([_ScreenHolds.wanted]).
  void _wantAsHeld() {
    _shownThrough.wanted = _holds.wanted;
    unawaited(_shownThrough.open());
  }

  /// What of this box its frames hold: the box whole where it is the
  /// panel's ([_holdsWhole]), and where it is a cel's window, what the
  /// panel over it takes in ([_holdsOver]).
  _ScreenHolds get _holds {
    final sides = _sidesInDevicePixels;
    final panel = _panel;
    if (panel == null) {
      return _holdsWhole(sides);
    }
    final ratio = _devicePixelRatio;
    return _holdsOver(
      sides,
      Rect.fromLTRB(
        panel.left * ratio,
        panel.top * ratio,
        panel.right * ratio,
        panel.bottom * ratio,
      ),
    );
  }

  /// This box's sides, in whole device pixels.
  (int, int) get _sidesInDevicePixels => (
    (size.width * _devicePixelRatio).ceil(),
    (size.height * _devicePixelRatio).ceil(),
  );

  /// The texel of [texture] this box's corner stands on: what the texture
  /// spares of what the box holds ([_holds]), half to either side
  /// ([EngineScreenTexture.windowOf]).
  (int, int) _cornerOn(ScreenTexture texture) {
    final window = EngineScreenTexture.windowOf(texture, _holds.rect);
    return (-window.left.toInt(), -window.top.toInt());
  }

  /// 🚨A PAN THE FRAME DRAWN LAST STILL SERVES DRAWS NOTHING: the frame up
  /// is moved with the view ([_standingFrom]) and the engine is asked for
  /// no other — 「거기서 더 가볍게」 (유저 2026-11-15), the frame grid's law
  /// (관제 2026-11-09 08:07 F: 「픽셀 스크롤은 레이어째 따라가니 다시 깔지
  /// 않고」). Whether the frame drawn last — up, or still on the GPU
  /// ([ScreenTexture.drawnLastFor]) — serves the view as it stands: drawn
  /// through this view a whole number of device pixels of pan away, and
  /// what the box holds still within it ([_holds]), its margin to spare
  /// on every side.
  /// ↩️Every step of a pan asked the engine for a frame, a body on its
  /// thread behind whatever else it had been handed.
  ///
  /// ⚠️A view turned pans by parts of a pixel
  /// ([renderSnappedViewport] snaps none of it): moved by the whole pixels
  /// nearest, the frame up would stand that part off what is drawn over it
  /// for as long as nothing else drew it — so it is drawn at every step,
  /// as it was.
  bool get _servedByTheFrameDrawnLast {
    final texture = _shownThrough.texture;
    final drawnFor = texture?.drawnLastFor;
    if (texture == null || drawnFor is! _DrawnFor) {
      return false;
    }
    final (:viewport, corner: (cornerX, cornerY)) = drawnFor;
    final ratio = _devicePixelRatio;
    final now = renderSnappedViewport(_viewport, ratio);
    if (viewport.copyWith(panX: now.panX, panY: now.panY) != now) {
      return false;
    }
    final (pannedX, pannedY) = (
      (now.panX - viewport.panX) * ratio,
      (now.panY - viewport.panY) * ratio,
    );
    final (movedX, movedY) = (pannedX.roundToDouble(), pannedY.roundToDouble());
    // A float's worth off a whole pixel is the snap's own arithmetic.
    if ((pannedX - movedX).abs() > 1e-6 || (pannedY - movedY).abs() > 1e-6) {
      return false;
    }
    final (:rect, :margin, wanted: _) = _holds;
    final (left, top) = (movedX - cornerX, movedY - cornerY);
    return left <= rect.left - margin &&
        top <= rect.top - margin &&
        left + texture.width >= rect.right + margin &&
        top + texture.height >= rect.bottom + margin;
  }

  /// What a frame drawn now, the view's corner on the texel [corner], is
  /// drawn for.
  _DrawnFor _drawnFor((int, int) corner) => (
    viewport: renderSnappedViewport(_viewport, _devicePixelRatio),
    corner: corner,
  );

  /// Where the frame up on the screen stands, this box painting from
  /// [offset]: where it was drawn for ([_DrawnFor]) — its view's corner on
  /// the box's, and the pan it stands at away from there ([_panStood]).
  ///
  /// ⚠️A zoom, a turn or a flip since it was drawn moves it no further: it
  /// stands where it stood till the next is up. Moved with the view there,
  /// it would be shown stretched or turned by Flutter meanwhile.
  Offset _standingFrom(Offset offset, Object? shownFor) {
    if (shownFor is! _DrawnFor) {
      return offset;
    }
    final (cornerX, cornerY) = shownFor.corner;
    final (movedX, movedY) = _panStood(shownFor, _viewport);
    return offset +
        Offset(movedX - cornerX, movedY - cornerY) / _devicePixelRatio;
  }

  bool get _drawsAnything =>
      !_heldForTheEngine &&
      _view._hasAFrame(_asItStands) &&
      _shownThrough.texture != null;

  /// The layer of this paint's frame, presented — or, where the frame waits
  /// for kernels still to be compiled ([FrameKernelsToCome]), of the frame
  /// the texture shows already, the box painted again once they are: the
  /// screen stays on the picture it showed, as it does for a plugin
  /// (🗣️I-132-Q34 a). Null where it has shown none; [refused] where the
  /// frame waits so.
  ({Layer? layer, bool refused}) _layerNow(Offset offset) {
    final corner = _cornerOn(_shownThrough.texture!);
    try {
      final layer = _shownThrough.presented(
        (next, size) => _view._show(_asItStands, next, size, (
          viewport: _viewport,
          devicePixelRatio: _devicePixelRatio,
          corner: corner,
        )),
        drawnFor: _drawnFor(corner),
        place: _placeAt(offset),
        upTogether: _together?.joined,
      );
      // Up already, on a screen that shows a frame as soon as it is drawn.
      _tellTheOverlays();
      return (layer: layer, refused: false);
    } on FrameKernelsToCome catch (wait) {
      _paintOnceCompiled(wait.compiled);
      return (layer: _shownThrough.standing(_placeAt(offset)), refused: true);
    }
  }

  /// Where this box, painted at [offset], lays the frame up on its texture.
  FramePlace _placeAt(Offset offset) => (
    from: (shownFor) => _standingFrom(offset, shownFor),
    devicePixelRatio: _devicePixelRatio,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    // Written before it is shown: what this frame's paint moves is what
    // this frame shows.
    _view._catchUp();
    final drawAsked = _drawAsked;
    _drawAsked = false;
    final (:layer, :refused) = !_drawsAnything
        ? (layer: null, refused: false)
        : drawAsked
        ? _layerNow(offset)
        : (layer: _shownThrough.standing(_placeAt(offset)), refused: false);
    _view._waitsAtPaint(refused: refused);
    if (_ownUp) {
      _letGoOfTheStandIn();
    }
    final shown = _ownUp ? layer : _standingIn(offset) ?? layer;
    if (shown == null) {
      return;
    }
    if (_ground case final ground?) {
      context.canvas.drawRect(offset & size, Paint()..color = ground);
    }
    // Live between what a still region holds: no image can vouch for a
    // texture, and the conte's picture stands in a dock.
    context.pushLayer(TickSceneLayer(alwaysLive: true)..size = size, (
      context,
      offset,
    ) {
      context.pushClipRect(true, offset, Offset.zero & size, (context, offset) {
        final canvasSize = _cutAtCanvas;
        if (canvasSize == null) {
          context.addLayer(shown);
          return;
        }
        // Where the picture stands: through a zoom, as it was drawn.
        final cut = canvasCutOnScreen(
          canvasSize,
          standingFor(_viewport),
          _devicePixelRatio,
        );
        context.pushClipPath(
          true,
          offset,
          Offset.zero & size,
          Path()..addPolygon(cut.corners, true),
          (context, _) => context.addLayer(shown),
          clipBehavior: cut.behavior,
        );
      });
    }, offset);
  }
}
