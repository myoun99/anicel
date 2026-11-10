import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/tree_nodes.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../services/playback/frame_demand.dart';
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
import '../effective_device_pixel_ratio.dart';
import '../engine_screen_texture.dart';
import 'camera_shot.dart' show outlineOnScreen, shotClipOnScreen;
import 'engine_frame_picture_store.dart';
import 'frame_pictures.dart';
import 'frame_wait_mark.dart';
import '../widgets/still_raster.dart';
import 'stacked_frame_picture.dart';

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
/// Where a change cannot be told by where it lands — a pose or a spreading
/// effect on the row, a float or a lift in hand — the frame is drawn as it
/// stands, on a screen of this view's that is no picture of the frame,
/// until its key moves.
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
  /// being drawn on may not wait for its neighbours.
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

  /// The canvas what the view draws is cut to ([clipToTheCanvas]) — a
  /// conte picture's, in its camera frame — and not its [ground], which
  /// lies across the whole view as the print's does: cut to it too, the
  /// print a live picture takes over from showed past the canvas (🔬F-215's
  /// switch pin, 10-31). Null: nothing is cut.
  final CanvasSize? cutAtCanvas;

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

class _FramePictureViewState extends State<FramePictureView> {
  /// The key of the frame shown — its picture, held for this view by the
  /// store; or the frame as it stands.
  FramePictureKey? _showing;

  /// The frame's picture shown, held by this view.
  EngineFramePicture? _shown;

  /// A frame of no row, or one the maker gave up on, drawn as its cels
  /// stand — by a view that draws nothing live ([_live] where it does).
  StackedFrame? _asItStands;

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
    // Opened by the first that asks. Why they would not open is said to
    // what asked the engine to open (`compileAppKernelsAhead`) and to every
    // lay asked of the store (`EngineFramePictureStore._noEngine`); a view
    // hears of it by [EngineFramePictureStore.waits], as it does of the
    // rest.
    _store.tools.ignore();
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
  /// still to be compiled ([FrameKernelsToCome]); or the frame's picture,
  /// nothing of the frame drawn meanwhile, in a line that stands behind
  /// such kernels ([EngineFramePictureStore.waitsForKernels]).
  ///
  /// ⛔Not a frame drawn as it stands while its picture is on its way: it
  /// is on the screen. Nor one that waits for its plugins alone (🗣️관제
  /// 2026-11-10 23:05: the answer is of the engine's getting ready).
  void _waitsAtPaint({required bool refused}) => _place?.says(
    this,
    waits:
        _store.toolsAreToCome ||
        refused ||
        (_making != null && !_standsMeanwhile && _store.waitsForKernels),
  );

  /// Whether a frame whose picture is not there yet is drawn as it stands
  /// until it is ([FramePictureView.wholeFrames], [_waits]).
  bool get _standsMeanwhile => !widget.wholeFrames && !_waits;

  /// The compile this view paints again after ([_paintOnceCompiled]).
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

  @override
  void didUpdateWidget(FramePictureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run.landings, widget.run.landings)) {
      oldWidget.run.landings.removeListener(_landed);
      widget.run.landings.addListener(_landed);
    }
    if (!identical(oldWidget.run.pictures, widget.run.pictures)) {
      oldWidget.run.pictures.store.waits.removeListener(_paintAgain);
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
    final handedAnew =
        _stoodBy != _pictures.keyAsItStands(widget.nodes, widget.picture) ||
        !identical(oldWidget.run.pictures, widget.run.pictures) ||
        !_sameLive(oldWidget.live, widget.live) ||
        oldWidget.wholeFrames != widget.wholeFrames;
    if (handedAnew) {
      _standAnew(oldWidget.drawnLive);
    } else {
      _look();
    }
  }

  /// The frame stands as it was handed last, [drawnLive] as they were last
  /// drawn.
  void _standAnew(Set<BrushFrameKey> drawnLive) {
    final shown = _onScreen;
    _standLive(
      onScreen: (cel) => shown.contains(cel) || drawnLive.contains(cel),
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
    _store.waits.removeListener(_paintAgain);
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
  void _standLive({bool Function(BrushFrameKey cel)? onScreen}) {
    _stoodBy = _pictures.keyAsItStands(widget.nodes, widget.picture);
    _waits = waitsForItsPlugins(widget.nodes);
    _liveChanges?.removeListener(_liveMoved);
    _liveChanges = null;
    _live = null;
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

  void _liveMoved() => _standingMoved = true;

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
      _make(key);
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
  void _written() {
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

  /// Reports [thrown], the first throw a cel's reading gave while [doing]
  /// — the cel noted and drawn without.
  static void _report((Object, StackTrace)? thrown, String doing) {
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
    return live != null &&
        held != null &&
        live.steady &&
        live.movedSince(held).located;
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
    if (!live.steady || _showsUnstored(now)) {
      _standing.whole = true;
      return;
    }
    _held = now;
  }

  /// Whether the live rows, as [tokens] tell them, show what no cel stores
  /// — the overlay's tiles, a preview the painter floats.
  static bool _showsUnstored(LiveSurfaceTokens? tokens) =>
      tokens != null &&
      (tokens.overlay.isNotEmpty || tokens.previews.isNotEmpty);

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
  void _catchUp() {
    final live = _live;
    final key = _showing;
    if (live == null || _shown == null || key == null || _standing.whole) {
      return;
    }
    final held = _held;
    if (held == null) {
      // A live row whose change cannot be told by where it lands — none
      // where nothing is drawn live at all.
      _standing.whole =
          !live.steady || widget.live?.activeSurfacePainter != null;
      return;
    }
    if (!live.steady) {
      _standing.whole = true;
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
      _writeThrough(key, live, dirty);
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
  /// picture is shown — through [viewport] at [devicePixelRatio] onto
  /// [target] of [size] texels.
  void _show(
    StackedFrame? frame,
    GpuTarget target,
    (int, int) size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
  }) {
    final shown = _drawnPicture;
    if (shown != null) {
      shown.show(
        target,
        size,
        viewport: viewport,
        devicePixelRatio: devicePixelRatio,
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
    );
  }

  /// Where the live rows moved that is still to go through a frame's
  /// plugins ([_writeThrough]).
  Rect? _owed;

  /// Whether a write is on its way through them.
  bool _writingThrough = false;

  /// [_writeIn] of a frame that waits for its plugins: the screen stays on
  /// the picture as it is until they have run (🗣️I-132-Q34 a), one write at
  /// a time — the steps meanwhile go in together, in the next. A step whose
  /// frame stands no more by then does not go in.
  void _writeThrough(FramePictureKey key, StackedFrame live, Rect dirty) {
    final owed = _owed?.expandToInclude(dirty) ?? dirty;
    if (_writingThrough) {
      _owed = owed;
      return;
    }
    _owed = null;
    _writingThrough = true;
    final to = _keptUnder(key, _held);
    unawaited(
      _store
          .patchThrough(
            from: _keptAs!,
            to: to,
            rect: owed,
            frame: live,
            holds: _pictures.heldNodes,
            stands: () => mounted && identical(_live, live),
          )
          .then(
            (went) {
              _writingThrough = false;
              if (went && mounted) {
                _pictures.giveWayToSteps();
                _keepAs(to);
              }
              _writeWhatIsOwed();
            },
            onError: (Object error, StackTrace stack) {
              _writingThrough = false;
              _report((error, stack), 'writing a step through its plugins');
            },
          ),
    );
  }

  void _writeWhatIsOwed() {
    final (owed, live, key) = (_owed, _live, _showing);
    if (mounted && owed != null && live != null && key != null) {
      _writeThrough(key, live, owed);
    }
  }

  /// The picture to show, where the frame is not drawn as it stands: a
  /// frame that waits for its plugins keeps the picture shown whatever.
  EngineFramePicture? get _drawnPicture =>
      _standing.whole && !_waits ? null : _shown;

  /// [frame] composed on this view's own screen, where it or its live rows
  /// moved since it last was.
  EngineStackScreen _screenStoodOn(StackedFrame frame) {
    final (:composite, :letters) = _store.toolsOpen!;
    final screen = _standingOn ??= EngineStackScreen(composite, letters);
    if (!identical(_composedOn, frame) || _standingMoved) {
      screen.compose(
        frame,
        holds: widget.live == null ? null : _pictures.heldNodes,
      );
      _composedOn = frame;
      _standingMoved = false;
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
    // frame that waits for its plugins.
    asItStands: _waits ? _asItStands : _live ?? _asItStands,
    ground: widget.ground,
    cutAtCanvas: widget.cutAtCanvas,
    viewport: widget.viewport,
    devicePixelRatio: EffectiveDevicePixelRatio.of(context),
    repaint: Listenable.merge([_repaint, _liveChanges]),
  );
}

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
    required this.repaint,
  });

  final _FramePictureViewState view;
  final EngineFramePicture? shown;
  final StackedFrame? asItStands;
  final Color? ground;
  final CanvasSize? cutAtCanvas;
  final CanvasViewport viewport;
  final double devicePixelRatio;
  final Listenable repaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFrameScreen(view)..takeFrom(this);

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
class _RenderFrameScreen extends RenderBox {
  _RenderFrameScreen(this._view);

  final _FramePictureViewState _view;

  late final EngineScreenTexture _shownThrough = EngineScreenTexture(
    asks: () => attached,
    opened: (_) => markNeedsPaint(),
  );

  EngineFramePicture? _shown;
  StackedFrame? _asItStands;
  Color? _ground;
  CanvasSize? _cutAtCanvas;
  late CanvasViewport _viewport;
  double _devicePixelRatio = 1;
  Listenable? _repaint;

  void takeFrom(_FrameScreen screen) {
    if (!identical(screen.shown, _shown) ||
        !identical(screen.asItStands, _asItStands) ||
        screen.ground != _ground ||
        screen.cutAtCanvas != _cutAtCanvas ||
        screen.devicePixelRatio != _devicePixelRatio ||
        !identical(screen.viewport, _viewportOrNull)) {
      markNeedsPaint();
    }
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
    if (attached) {
      _repaint?.removeListener(markNeedsPaint);
      screen.repaint.addListener(markNeedsPaint);
    }
    _repaint = screen.repaint;
  }

  CanvasViewport? _viewportOrNull;

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
    _shownThrough.start();
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    _shownThrough.stop();
    super.detach();
  }

  @override
  void performResize() {
    super.performResize();
    _shownThrough.wanted = (
      (size.width * _devicePixelRatio).ceil(),
      (size.height * _devicePixelRatio).ceil(),
    );
    unawaited(_shownThrough.open());
  }

  bool get _drawsAnything =>
      (_view._drawnPicture ?? _asItStands) != null &&
      _shownThrough.texture != null &&
      _view._store.toolsOpen != null;

  /// The layer of this paint's frame, presented — or, where the frame waits
  /// for kernels still to be compiled ([FrameKernelsToCome]), of the frame
  /// the texture shows already, the box painted again once they are: the
  /// screen stays on the picture it showed, as it does for a plugin
  /// (🗣️I-132-Q34 a). Null where it has shown none; [refused] where the
  /// frame waits so.
  ({Layer? layer, bool refused}) _layerNow(Offset offset) {
    try {
      return (
        layer: _shownThrough.presented(
          (next, size) => _view._show(
            _asItStands,
            next,
            size,
            viewport: _viewport,
            devicePixelRatio: _devicePixelRatio,
          ),
          offset: offset,
          devicePixelRatio: _devicePixelRatio,
        ),
        refused: false,
      );
    } on FrameKernelsToCome catch (wait) {
      _view._paintOnceCompiled(wait.compiled);
      return (
        layer: _shownThrough.standing(
          offset: offset,
          devicePixelRatio: _devicePixelRatio,
        ),
        refused: true,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Written before it is shown: what this frame's paint moves is what
    // this frame shows.
    _view._catchUp();
    final (:layer, :refused) = _drawsAnything
        ? _layerNow(offset)
        : (layer: null, refused: false);
    _view._waitsAtPaint(refused: refused);
    if (layer == null) {
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
          context.addLayer(layer);
          return;
        }
        final cut = shotClipOnScreen(
          outlineOnScreen(canvasSize, _viewport, _devicePixelRatio),
          _devicePixelRatio,
        );
        context.pushClipPath(
          true,
          offset,
          Offset.zero & size,
          Path()..addPolygon(cut.corners, true),
          (context, _) => context.addLayer(layer),
          clipBehavior: cut.behavior,
        );
      });
    }, offset);
  }
}
