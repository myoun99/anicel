import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/tree_nodes.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart'
    show
        CanvasActiveLayerRow,
        CanvasStackRow,
        LiftedRowPainters,
        LiveRows,
        LiveSurfaceTokens,
        StackedFrame,
        waitsForItsPlugins;
import '../canvas/display_resample.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import 'frame_picture_store.dart';
import 'frame_pictures.dart';
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
/// ②-4): each change of theirs is patched in where it lands
/// ([StackedFrame.movedSince] → [FramePictureStore.patch]) and shown once
/// its texels are in the picture; a stroke that lands moves the picture to
/// the frame's next key ([FramePictureStore.move]). ↩️Drawn as it stood
/// over the picture until then, a step and its picture were two images of
/// one frame, and their edges drew apart (F-465 — the store's write has
/// the measurement).
/// Where a change cannot be told by where it lands — a pose or a spreading
/// effect on the row, a float or a lift in hand, past the picture — the
/// frame is drawn as it stands until its key moves.
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

  /// The colour laid under what the view draws, where it draws anything.
  ///
  /// 🗣️F-215 · I-132-Q34 a: none while it draws nothing — a frame that
  /// waits for its plugins, its picture not made yet — so what it took over
  /// from shows meanwhile: the conte's print, the last finished picture
  /// (「on하든off하든 바뀌는게 없어야」 · 「직전 완성 그림에 머문다」).
  final Color? ground;

  @override
  State<FramePictureView> createState() => _FramePictureViewState();
}

/// What the view draws: a frame's picture — the view's own handle on its
/// image — or a frame drawn as it stands.
typedef _Shown = ({FramePicture picture, ui.Image image})?;

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

  _Shown _shown;

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

  /// Whether a step is on its way into the picture shown ([_writeIn]) — what
  /// the change behind it waits for ([_catchUp]).
  bool _stepOnItsWay = false;

  /// Whether the frame is drawn as it stands in place of the picture shown.
  final _DrawnAsItStands _standing = _DrawnAsItStands();

  /// 🗣️I-132-Q34 a (유저 2026-10-30): 「결과가 올 때까지 그 프레임의 직전
  /// 완성 그림에 머문다」 — whether the frame holds a plugin's step that only
  /// a picture made waiting for it draws ([waitsForItsPlugins]). Such a
  /// frame is never drawn as it stands: the picture shown stays until the
  /// next is there, and its live rows' changes go into it one patch at a
  /// time ([_writingThrough]) — a stroke shown late by its plugins' time.
  bool _waits = false;

  /// Whether a patch of a frame that [_waits] is on its way into the
  /// picture shown: the changes after it wait to go in together, behind it
  /// — one a step, each waiting for the plugins, would fall ever further
  /// behind the pen.
  bool _writingThrough = false;

  /// The cel the pen is on, as the key of the picture shown read it.
  CelAsOf? _drawnOn;

  /// The key a stroke's landing is moving the picture shown to.
  FramePictureKey? _moving;

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

  FramePictureStore<FramePictureKey> get _store => _pictures.store;

  @override
  void initState() {
    super.initState();
    widget.run.landings.addListener(_landed);
    _standLive(onScreen: widget.alreadyShown ? (_) => true : null);
    _look();
  }

  @override
  void didUpdateWidget(FramePictureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run.landings, widget.run.landings)) {
      oldWidget.run.landings.removeListener(_landed);
      widget.run.landings.addListener(_landed);
    }
    if (!identical(oldWidget.run.pictures, widget.run.pictures)) {
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
      final shown = _onScreen;
      final drawnLive = oldWidget.drawnLive;
      _standLive(
        onScreen: (cel) => shown.contains(cel) || drawnLive.contains(cel),
      );
    }
    // 🚨THE FRAME FIRST, THEN WHAT ITS LIVE ROWS MOVED: rows handed with
    // another frame are that frame's. Measured against the picture of the
    // frame left, they were patched INTO it — and every screen showing that
    // frame drew the other one wherever the two differ (F-104 again: the
    // frame you left stayed where the frame you went to has nothing, once
    // you went back and forth).
    _look();
    if (handedAnew && widget.live != null) {
      _liveRowsHandedAnew();
    }
  }

  @override
  void dispose() {
    widget.run.landings.removeListener(_landed);
    _letGo(_store);
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
      _liveChanges = frame.changes;
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
    // goes on as the move's own until it is given back — then taken under
    // [key]. Peeked there too, no screen told the two apart (F-473's
    // mutants, 2026-10-26).
    final there = _store.peek(key);
    if (there != null) {
      _take(key, there);
      return;
    }
    if (key == _showing || key == _moving) {
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
    if (!widget.wholeFrames && !_waits) {
      // Drawn as it stands until its picture is there.
      _letGo(_store);
      _showing = key;
    }
  }

  /// The picture shown was written into — by this view's stroke or
  /// another's: drawn from here on by the image it is now
  /// ([FramePicture.image]: a picture written into is a new image, or the
  /// screen of an iPhone or iPad is not drawn again where it changed,
  /// F-509).
  void _written() {
    final (:picture, :image) = _shown!;
    setState(() {
      image.dispose();
      _shown = (picture: picture, image: picture.image.clone());
    });
  }

  /// Shows [there], the picture of [key] — the one shown already where a
  /// stroke's landing moved it here, what it holds of the live rows kept.
  void _take(FramePictureKey key, FramePicture there) {
    if (identical(there, _shown?.picture)) {
      // ⛔Not let go and taken again: what the picture holds of the live
      // rows it holds under this one, and the next stroke patches in from
      // there — let go, a stroke whose first step came before the last
      // one's landing would be drawn as it stands whole, a step at a time.
      _showing = key;
      _moving = null;
      _drawnOn = _celNow();
      return;
    }
    final image = there.image.clone();
    _letGo(_store);
    _store.retainPin(key);
    _keptAs = key;
    _shown = (picture: there, image: image);
    there.addListener(_written);
    _showing = key;
    _drawnOn = _celNow();
    _standing.whole = false;
    _tell();
    if (widget.live != null) {
      _holdNodes();
    }
  }

  /// Holds the nodes of the frame this canvas stands on for the steps its
  /// strokes patch in ([FramePictures.holdNodesOf]).
  void _holdNodes() {
    unawaited(
      _pictures
          .holdNodesOf(widget.nodes, widget.picture, shouldAbort: () => !mounted)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) => _report(
              (error, stack),
              'holding the nodes of the frame a canvas stands on',
            ),
          ),
    );
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
  /// the live rows is in its picture — the stroke's own steps — so its
  /// texels are [key]'s. ⛔Any other change of the frame — another row, the
  /// pen's own row's opacity, another frame — is a new picture.
  bool _moves(FramePictureKey key) {
    final from = _showing;
    final drawnOn = _drawnOn;
    if (_shown == null || from == null || drawnOn == null) {
      return false;
    }
    if (_pictures.keyOfStack(widget.nodes, widget.picture, asOf: drawnOn) !=
        from) {
      return false;
    }
    // What is still out of it goes in under the key it moves to
    // ([_catchUp]) — where the build hands the live rows anew, and at the
    // paint after it, painted whatever its painter compares. ↩️It was caught
    // up here first, as the move's own, until the change went in under the
    // key a picture moves to: the same texels.
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
    _moving = key;
    unawaited(
      _store.landingOf(to)!.then((_) {
        if (mounted && _moving == key) {
          setState(_look);
        }
      }),
    );
    return true;
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
  void _liveRowsHandedAnew() {
    if (_shown != null) {
      if (_held == null) {
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
  /// this view.
  void _keepAs(FramePictureKey key) {
    final kept = _keptAs!;
    if (key == kept) {
      return;
    }
    _store.retainPin(key);
    _store.releasePin(kept);
    _keptAs = key;
  }

  /// What the live rows moved since the picture shown last held them goes
  /// into it, patched in where it lands — or the frame is drawn as it stands
  /// from here on.
  ///
  /// 🚨ASKED AT EACH PAINT ([_FramePicturePainter.paint]) and where a build
  /// hands the live rows anew — not at each change of theirs, where a change
  /// and what goes with it come apart: a stroke that lands lets go of its
  /// overlay in the call that commits it, and the painter of the cel as
  /// committed comes with the next build. Measured at the change, the
  /// overlay letting go was patched in with the stroke gone — into the
  /// frame's one picture, which every screen showing that frame draws — and
  /// the build patched it back. ↩️The display buffer measured at its paint
  /// too (`_planMiss`).
  ///
  /// 🚨★★★ONE STEP ON ITS WAY AT A TIME ([_stepOnItsWay]): what moves while
  /// one goes in stays out of [_held], and goes in as one patch the paint
  /// after it lands. ↩️Each paint asked for its own, and a patch takes the
  /// store longer than a vsync, so the queue grew for as long as the pen
  /// moved and the line fell further behind it the longer it was (F-512, 유저
  /// 2026-10-30 「선이 커서 뒤로 처진다」). 🔬Main PC, 144 Hz, 2544×1361, a
  /// new project, input to raster done, p50 / p90: fitted 757 / 1346 ms →
  /// 49 / 60 ms, at 100% 2111 / 3168 ms → 41 / 54 ms, a frame every vsync
  /// again (it was every other one). ⛔Not until the step is rendered
  /// rather than in: 61 / 77 ms fitted, its batches behind it instead.
  ///
  /// ⛔NOT WHILE A STROKE'S LANDING MOVES THE PICTURE ([_moving]): the last
  /// of the stroke goes in now, under the key it moves to ([_moves]) — left
  /// to wait, another frame stood on in that time would leave the frame's
  /// own key with a picture short of it for good.
  void _catchUp() {
    final live = _live;
    final shown = _shown;
    // A picture a stroke's landing is moving takes the change under the key
    // it is moving to ([_moves]) — the store patches a picture a move is
    // still moving. ⛔Not left out until the move lands: the next stroke's
    // first steps were drawn nowhere.
    final key = _moving ?? _showing;
    if (live == null ||
        shown == null ||
        key == null ||
        _standing.whole ||
        _writingThrough) {
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
    if (_stepOnItsWay && _moving == null) {
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
    _writeIn(key, shown.picture, live, dirty);
  }

  /// Writes the live rows' change at [dirty] into [picture], the picture of
  /// [key] shown — or draws the frame as it stands from here on, where it
  /// cannot be.
  void _writeIn(
    FramePictureKey key,
    FramePicture picture,
    StackedFrame live,
    Rect dirty,
  ) {
    // ⛔A picture does not grow: a frame that now draws past it is drawn as
    // it stands, and its next picture is laid wide enough. Inside it, the
    // change is cut to it — past it the frame draws nothing, and the pixel
    // the change is widened by ([StackedFrame.movedSince]) has no texel
    // there. ⛔Not by the change alone: every stroke on the page's first
    // row or column of tiles would be drawn as it stands.
    final extent = picture.extent;
    final drawing = live.drawing;
    if (drawing.extent.intersect(extent) != drawing.extent) {
      _standing.whole = true;
      return;
    }
    final rect = dirty.intersect(extent);
    if (rect.isEmpty) {
      return;
    }
    final to = _keptUnder(key, _held);
    if (!_store.patch(
      from: _keptAs!,
      to: to,
      rect: rect,
      draw: drawing.draw,
      // Drawn again once its plugins have run, by the frame still standing.
      gone: () => !mounted || !identical(_live, live),
    )) {
      _standing.whole = true;
      return;
    }
    _pictures.giveWayToSteps();
    _keepAs(to);
    _writingThrough = _waits;
    // Shown once its texels are in the picture, at every level — or, where
    // they never went in, the frame as it stands from the paint after: the
    // picture let go on the way (a write the GPU threw on, F-509). ⛔Not
    // the picture until the next change: a step that did not go in showed
    // only once another came after it.
    _stepOnItsWay = true;
    unawaited(
      _store.landingOf(to)!.then((landed) {
        _stepOnItsWay = false;
        if (!mounted) {
          return;
        }
        if (!landed && identical(_shown?.picture, picture)) {
          _standing.whole = true;
        }
        _writingThrough = false;
        _repaint.value += 1;
      }),
    );
  }

  /// Lets go of what is shown, and of [store]'s hold on its picture.
  ///
  /// A picture kept as this view's own goes with it: what it holds past
  /// the frame's stored pixels is no picture of the frame's
  /// ([FramePictureKey.standingOn]).
  void _letGo(FramePictureStore<FramePictureKey> store) {
    if (_shown case (:final image, :final picture)) {
      picture.removeListener(_written);
      image.dispose();
      final kept = _keptAs!;
      store.releasePin(kept);
      if (kept.standingFor != null) {
        store.letGo(kept);
      }
    }
    _shown = null;
    _asItStands = null;
    _showing = null;
    _moving = null;
    _keptAs = null;
    _held = null;
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
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FramePicturePainter(
          shown: _shown,
          // ⛔Not the stored cels where the view draws rows live: a frame of
          // no row is a page the pen may be drawing on — nor the live rows
          // of a frame that waits for its plugins.
          asItStands: _waits ? _asItStands : _live ?? _asItStands,
          standing: _standing,
          waits: _waits,
          ground: widget.ground,
          catchUp: _catchUp,
          viewport: widget.viewport,
          devicePixelRatio: EffectiveDevicePixelRatio.of(context),
          repaint: Listenable.merge([_repaint, _liveChanges]),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FramePicturePainter extends CustomPainter {
  _FramePicturePainter({
    required this.shown,
    required this.asItStands,
    required this.standing,
    required this.waits,
    required this.ground,
    required this.catchUp,
    required this.viewport,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Shown shown;

  /// The frame as it stands, drawn where [shown] is not
  /// ([StackedFrame.paintOnScreen]).
  final StackedFrame? asItStands;

  /// Whether the frame is drawn as it stands in place of [shown].
  final _DrawnAsItStands standing;

  /// Whether the frame waits for its plugins: [shown] stays, whatever
  /// [standing] says ([_FramePictureViewState._waits]).
  final bool waits;

  /// Laid under what is drawn, where anything is ([FramePictureView.ground]).
  final Color? ground;

  /// Puts what the live rows moved into [standing] or the picture shown
  /// before it is read ([_FramePictureViewState._catchUp]).
  final VoidCallback catchUp;
  final CanvasViewport viewport;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    catchUp();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final shown = standing.whole && !waits ? null : this.shown;
    final ground = this.ground;
    if (ground != null && (shown != null || asItStands != null)) {
      canvas.drawColor(ground, BlendMode.srcOver);
    }
    if (shown case (:final picture, :final image)) {
      applyViewportTransform(
        canvas,
        viewport,
        devicePixelRatio: devicePixelRatio,
      );
      _paintPicture(canvas, picture, image);
    } else if (asItStands case final frame?) {
      frame.paintOnScreen(
        canvas,
        size,
        viewport: viewport,
        devicePixelRatio: devicePixelRatio,
      );
    }
    canvas.restore();
  }

  /// The picture as its store says it is drawn ([FramePicture]): its image
  /// where its extent lies, and the world outside it its colour.
  void _paintPicture(Canvas canvas, FramePicture picture, ui.Image image) {
    final extent = picture.extent;
    if (picture.outside.a != 0) {
      canvas.save();
      canvas.clipRect(extent, clipOp: ui.ClipOp.difference);
      canvas.drawPaint(Paint()..color = picture.outside);
      canvas.restore();
    }
    drawOnTheDisplay(
      canvas,
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      extent,
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  bool shouldRepaint(_FramePicturePainter oldDelegate) =>
      !identical(oldDelegate.shown?.image, shown?.image) ||
      !identical(oldDelegate.asItStands, asItStands) ||
      oldDelegate.waits != waits ||
      oldDelegate.ground != ground ||
      oldDelegate.viewport != viewport ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
