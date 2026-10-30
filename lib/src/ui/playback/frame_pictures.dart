import 'dart:async';
import 'dart:ui' as ui;

import '../../core/lru.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/cel_content_notes.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../canvas/composite_tree_paint.dart' show BelowThePen;
import '../canvas/display_resample.dart' show rectOutwardOnGrid;
import '../canvas/subtree_image_composite.dart'
    show HeldSubtreeRasters, blurReductionCell;
import '../quiet_turns.dart';
import 'frame_picture_store.dart';
import 'layer_frame_image_cache.dart';
import 'playback_cache_budget.dart' show playbackCacheBudgetBytes;
import 'playback_pictures.dart';
import 'stacked_frame_picture.dart';

/// A frame as its cels stand now ([StackedFrame]), and the first throw a
/// cel's reading gave — the cel noted and drawn without.
typedef FrameDrawingNow = ({
  StackedFrame frame,
  (Object, StackTrace)? thrown,
});

/// A cel as a frame's key reads it at one moment
/// ([FramePictures.celNow]): whether the picture is made of it, and at
/// which revision.
typedef CelAsOf = ({BrushFrameKey cel, bool drawn, int revision});

/// The line the nodes of a frame a canvas stands on are held on
/// ([FramePictures.heldNodes]) — the playback line (`PlaybackCacheBudget`),
/// declared here as `PictureRoom` is: the line knows the pictures, they do
/// not know it.
abstract interface class HeldNodesLine {
  /// How much of the line the nodes held one by one may hold now.
  int get bytesForNodes;

  /// The frames' pictures give way to what the nodes hold now.
  void giveWayToNodes();
}

/// 🚨★★★A FRAME IS MADE ONCE, AS ONE PICTURE (one-picture-per-frame ②-2,
/// D7-2-Q3=a — 「쓸데없는 소재를 만들고 싶지 않은 것」): what the warmer makes
/// ahead of a screen is the frame the screen shows — the tree it stacks for
/// it ([stackOf]), drawn by the canvas's own body from each row's stored
/// pixels and kept in the frame picture store under the key that tree is
/// signed by ([FramePictureKey]). A screen shows that picture and makes
/// nothing; a frame two screens show the same way is one picture.
///
/// ↩️The warmer made each ROW's image (`CanvasPictures`), and every screen
/// composited a frame's rows again as it showed it.
class FramePictures implements PlaybackPictures {
  FramePictures({
    required this.store,
    required this.layerImages,
    required this.stackOf,
    required this.pageOf,
    this.line,
    QuietTurns? quietTurns,
  }) : quietTurns = quietTurns ?? QuietTurns.instance;

  final FramePictureStore<FramePictureKey> store;

  /// Where a row's cel is read from: thawed ahead off the UI thread
  /// ([LayerFrameImageCache.readIn]), its stored pixels
  /// ([LayerFrameImageCache.storedSurfaceOrNull]), and the record of the
  /// cels that could not be read.
  final LayerFrameImageCache layerImages;

  /// The tree a screen stacks for [Cut]'s frame — the canvas's own, no row
  /// live (`EditingCanvas.playedStackAt`), with its ghosts in place or
  /// without — or its ghosts' alone (`EditingCanvas.ghostsOverAt`).
  final List<CompositeNode<CanvasStackRow>> Function(
    DemandedPicture picture,
  )
  stackOf;

  /// The page [DemandedPicture]'s frame is drawn on — the cut's size, the
  /// project's pasteboard and paper, and whether its screen paints that
  /// paper ([DemandedPicture.paintPaper]).
  final FramePage Function(DemandedPicture picture) pageOf;

  /// Where a frame takes its turn to be rastered ([make]).
  final QuietTurns quietTurns;

  /// How long a frame has taken from its turn to its landing, at the most of
  /// late.
  final QuietSpan _frameSpan = QuietSpan();

  /// How long holding a frame's nodes has taken ([holdNodesOf]), likewise.
  final QuietSpan _holdSpan = QuietSpan();

  /// Cels with pixels recorded at ANOTHER canvas size: the picture is made
  /// without them. Noted as well at the store's whole-content generation,
  /// as a resize heals such a cel with no revision of its own — a picture
  /// made of the blank stand-in, or kept under a key a heal does not move,
  /// would show it blank for ever after.
  late final CelContentNotes _drawnNothing = CelContentNotes.orTheStoresContent(
    layerImages.frameStore,
  );

  /// Frames whose making threw past their cels at the content they hold now
  /// — noted by the key of that content, so a walk does not make them
  /// again and a run is not held for a frame that will not come. A new
  /// content is a new key.
  final Lru<FramePictureKey, bool> _gaveNothing = Lru(entryCap: () => 256);

  /// 🚨★THE PICTURES THE NODES OF A FRAME A CANVAS STANDS ON WERE DRAWN INTO
  /// ([HeldNodePictures]; card paint-walk-redoes-the-same-work-each-step,
  /// 실측 5): kept as the frame is laid for that canvas ([makeShown]), or
  /// once a canvas stands on one laid ahead ([holdNodesOf]), and found as a
  /// stroke's steps are patched into it ([frameAsItStands]) — what lies
  /// below the row a pen draws on, as one picture or in the cells a step
  /// landed in ([BelowThePen]), and each folder over it drawn whole are not
  /// drawn again for each step that does not touch them.
  ///
  /// ⚖️Below the pen, two pages at the most — the page of the frame last
  /// drawn with them ([estimatedImageBytes]): the frame's own list and the
  /// folder the pen is in — the option 유저 picked 2026-10-27 (Q2 = c):
  /// 「폴더가 몇 개든 2~3장」. Over it, each node a page at the most, and as
  /// many as the playback [line] has room for — the frames' pictures made
  /// ahead give way to them (🗣️유저 2026-10-27, Q3 = c: 「위 폴더는 하나씩,
  /// 재생 메모리 몫 안에서 전부」). The screen is fed by the frame's picture,
  /// and these only make its patches cheaper. Past it they are let go of,
  /// and a patch draws them as it did before; and they are only ever the
  /// nodes of the frame last drawn to hold them
  /// ([HeldSubtreeRasters.holdOnly]).
  ///
  /// ↩️One page held the nodes over the pen together until Q3: 🔬nine
  /// folders at 50% over the row drawn on, one of them fitted and a step
  /// drew the rest — a step on the screen p50 14.8–27.5ms against
  /// 6.5–12.6ms at 100% (10-27, the whole app, Windows, profile).
  late final HeldSubtreeRasters heldNodes = HeldSubtreeRasters(
    bytes: () => line?.bytesForNodes ?? playbackCacheBudgetBytes,
    eachAtMost: () => _heldPageBytes,
    bytesBelow: () => 2 * _heldPageBytes,
  );
  int _heldPageBytes = 0;

  /// The line [heldNodes] stand on — null where none is told: the line's
  /// own size, which nothing else holds then.
  final HeldNodesLine? line;

  /// Where a frame drawn on [page] finds its nodes' pictures ([heldNodes]),
  /// its rows signed as its key signs them — and keeps the ones it draws
  /// whole where it [keeps], what lies below its pen drawn as [below] says.
  ({HeldNodePictures pictures, int Function(BrushFrameKey cel) revisionOf})
  _holding(
    FramePage page, {
    required bool keeps,
    required BelowThePen below,
  }) {
    _heldPageBytes = estimatedImageBytes(
      page.canvasSize.width,
      page.canvasSize.height,
    );
    return (
      pictures: (rasters: heldNodes, keeps: keeps, below: below),
      revisionOf: _revisionOf,
    );
  }

  /// Lets go of the pictures the frames' nodes are held in ([heldNodes]).
  void dispose() => heldNodes.clear();

  /// Whether the frame's picture is made of [cel]: one with something to
  /// draw — a cel with nothing in it draws nothing, and N frames of blank
  /// cels on one paper are one picture — that it can be made of. Not one
  /// that could not be read at the content it holds now
  /// ([LayerFrameImageCache.unreadable]), nor one holding pixels recorded
  /// at another canvas size ([_drawnNothing]).
  bool _drawn(BrushFrameKey cel) =>
      layerImages.frameStore.celHasRenderableContent(cel) &&
      !layerImages.unreadable.has(cel) &&
      !_drawnNothing.has(cel);

  /// [nodes] as the picture draws them: the rows of cels it is [_drawn] of
  /// — [asOf]'s cel as it was then.
  List<CompositeNode<CanvasStackRow>> _drawnOf(
    List<CompositeNode<CanvasStackRow>> nodes, {
    CelAsOf? asOf,
  }) => stackOfDrawnCels(
    nodes,
    drawn: (cel) => cel == asOf?.cel ? asOf!.drawn : _drawn(cel),
  );

  /// The key of the picture a screen shows where it stacks [nodes] for
  /// [picture] — the warmer's own key for it ([keyOf]) wherever it stacks
  /// the tree [stackOf] answers. Signed by the rows the picture draws: a
  /// cel it is made without is no part of it ([_drawn]), and one that
  /// comes in is a new picture.
  ///
  /// [asOf] asks the key the stack had with one cel as it was then
  /// ([celNow]): a frame whose key that is changed in that cel alone — what
  /// a stroke's landing moves (`FramePictureView`).
  FramePictureKey keyOfStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    CelAsOf? asOf,
  }) => framePictureKeyOf(
    _drawnOf(nodes, asOf: asOf),
    cutId: picture.cut.id,
    page: pageOf(picture),
    revisionOf: (cel) => cel == asOf?.cel ? asOf!.revision : _revisionOf(cel),
  );

  /// The key of the frame [nodes] stack for [picture] AS IT STANDS — signed
  /// by every row of it, a cel drawn or not ([framePictureKeyOf]): a tree
  /// that stands under the key a frame was stood by is that frame handed
  /// again (`FramePictureView`).
  ///
  /// ⛔Not [keyOfStack]: a cel with nothing in it is no part of the
  /// picture, but the row a pen is on draws its stroke as it stands by that
  /// row's opacity, blend and pose.
  FramePictureKey keyAsItStands(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) => framePictureKeyOf(
    nodes,
    cutId: picture.cut.id,
    page: pageOf(picture),
    revisionOf: _revisionOf,
  );

  /// The key [picture]'s picture is kept under.
  FramePictureKey keyOf(DemandedPicture picture) =>
      keyOfStack(stackOf(picture), picture);

  /// [cel] as a frame's key reads it now ([keyOfStack]).
  CelAsOf celNow(BrushFrameKey cel) =>
      (cel: cel, drawn: _drawn(cel), revision: _revisionOf(cel));

  int _revisionOf(BrushFrameKey cel) =>
      layerImages.frameStore.sourceRevisionOf(cel);

  /// Whether the frame [key] is of draws no row — its page alone, the paper
  /// or nothing — which the store keeps no picture of: there by definition,
  /// drawn as it stands ([drawingNow]), as the ruler's bar has always
  /// counted a frame that composes to nothing (유저 2026-08-16: 「왜
  /// 콘텐츠끝너머가 초록이되면 안되는거지? 재생가능한거잖아」).
  ///
  /// ⛔Not a picture of the paper: one for every hole and runway of a cut
  /// was work and room spent on a fill a screen draws for nothing, and a
  /// run and its bar waited for it where nothing was still to come.
  bool drawsOnlyItsPage(FramePictureKey key) => key.signature.nodes.isEmpty;

  /// Whether the making of [key]'s frame threw, and nothing more of it is
  /// to come.
  bool gaveUpAt(FramePictureKey key) => _stateAt(key) == PictureState.gaveUp;

  PictureState _stateAt(FramePictureKey key) => _isThere(key)
      ? PictureState.there
      : _gaveNothing.containsKey(key)
      ? PictureState.gaveUp
      : PictureState.toCome;

  /// 🚨A FRAME WHOSE PICTURE A CANVAS HOLDS AS ITS OWN IS THERE — lent while
  /// the canvas shows what no cel stores over it ([FramePictureKey
  /// .standingOn]), and given back under the frame's key once it does not.
  /// ⛔Not missing meanwhile: a walk would lay the frame on screen again,
  /// and the picture given back would take a key another holds (F-473).
  bool _isThere(FramePictureKey key) =>
      store.holds(key) ||
      store.holdsWhere(
        (held) => held.standingFor != null && held.ofTheFrame == key,
      ) ||
      drawsOnlyItsPage(key);

  @override
  bool has(DemandedPicture picture) => _isThere(keyOf(picture));

  /// The frame itself: one picture, made once however many frames show it.
  @override
  Set<Object> partsToMake(DemandedPicture picture) {
    final key = keyOf(picture);
    return _stateAt(key) == PictureState.toCome ? {key} : {};
  }

  /// Its red: a cel it shows that [LayerFrameImageCache.unreadable] holds.
  @override
  PictureStanding standingOf(DemandedPicture picture) {
    final nodes = stackOf(picture);
    return (
      state: _stateAt(keyOfStack(nodes, picture)),
      cannotRead: stackedCelsOf(nodes).any(layerImages.unreadable.has),
    );
  }

  /// ⚠️Not where the frame is there: a cel's throw is handed on once the
  /// frame is laid without it ([make]), and the picture laid is no failure.
  @override
  void noteFailure(DemandedPicture picture) {
    final key = keyOf(picture);
    if (!_isThere(key)) {
      _gaveNothing.keep(key, true);
    }
  }

  /// What the picture will weigh: the picture the store lays of its
  /// drawing's extent ([pictureExtentOf]), where every cel it draws is in
  /// hand ([readIn]) — and else of the page's. ⛔Reads nothing: a walk
  /// weighs the frames it asks for ahead before it reads them.
  @override
  int bytesToMake(DemandedPicture picture) {
    final nodes = stackOf(picture);
    final extent = pictureExtentOf(
      allInHand(nodes, picture)
          ? drawingNow(nodes, picture).frame.drawing.extent
          : pageOf(picture).canvasSize.canvasRect,
    );
    return estimatedImageBytes(extent.width.round(), extent.height.round());
  }

  /// Whether every cel [nodes] draw for [picture] is in hand — its stored
  /// pixels read and laid out already ([readInStack] reads the rest).
  bool allInHand(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) => stackedCelsOf(_drawnOf(nodes)).every((cel) => inHand(cel, picture));

  /// Whether [cel]'s stored pixels on [picture]'s page are read and laid
  /// out already — drawn without a reading ([frameAsItStands]).
  bool inHand(BrushFrameKey cel, DemandedPicture picture) => layerImages
      .storedSurfaceIsInHand(cel, canvasSize: pageOf(picture).canvasSize);

  /// Thaws every cel [picture] draws that is not in hand already, at once,
  /// off the UI thread ([LayerFrameImageCache.readIn]) — none another frame
  /// has read.
  @override
  Future<void> readIn(DemandedPicture picture) =>
      readInStack(stackOf(picture), picture);

  /// [readIn] for the cels [nodes] — a screen's own stack — draw.
  Future<void> readInStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) {
    final canvasSize = pageOf(picture).canvasSize;
    return Future.wait([
      for (final cel in stackedCelsOf(_drawnOf(nodes)))
        if (!inHand(cel, picture))
          layerImages.readIn(cel, canvasSize: canvasSize),
    ]);
  }

  /// A frame's picture is one part however many frames show it.
  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) {
    final key = keyOf(picture);
    final bytes = store.bytesOf(key);
    return bytes != null && seen.add(key) ? bytes : 0;
  }

  /// 🚨THE FRAME TAKES ITS TURN IN THE QUIET BETWEEN A RUN'S HELD FRAMES
  /// ([QuietTurns]) once its cels are read and its drawing is — the CPU's
  /// — before it is rastered: one frame at a time, as one row at a time
  /// was. A frame found then to draw its page alone takes none: it is there
  /// by definition ([drawsOnlyItsPage]), as a row with nothing stored to
  /// show took no turn.
  ///
  /// 🚨ONE CEL'S FAILURE IS ONE CEL'S: a cel that cannot be read is noted
  /// and the frame laid without it, and the throw handed on once it is —
  /// the frame's other rows are no reason for the cel to be read again, nor
  /// its failure a reason for them to be missing.
  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  }) => _make(
    () => stackOf(picture),
    picture,
    shouldAbort: shouldAbort,
    due: due,
    shownNow: false,
    keepsNodes: false,
  );

  /// Makes the frame a screen stands on — stacked as that screen stacks it
  /// ([nodes]: a drag in flight, the row a pen is on) — at once, at the
  /// front of the store's line: the frame on screen before any made ahead
  /// of it ([make] has the rest). Where it [keepsNodes] — a canvas that
  /// stands on it to draw — the pictures its nodes are drawn into are what
  /// is held ([heldNodes]), and a frame of its page alone is laid too
  /// ([drawsOnlyItsPage]): the pen's steps patch into it.
  ///
  /// ⛔Not every screen's: a screen that draws nothing live patches no step
  /// in, and a frame it laid let go of the nodes of the frame a pen is on
  /// (🗣️Q3 = c: 「편집 중인 프레임의 위 폴더만」).
  Future<bool> makeShown(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    required bool keepsNodes,
  }) => _make(
    () => nodes,
    picture,
    shouldAbort: shouldAbort,
    due: () => true,
    shownNow: true,
    keepsNodes: keepsNodes,
  );

  /// 🚨Holds the nodes of the frame [nodes] stack for [picture] — one a
  /// screen stands on to draw on, its picture laid ahead of it ([make]),
  /// which keeps none ([heldNodes]): the frame drawn as it is laid, in its
  /// turn ([QuietTurns]), into nothing but them. A node held already is cut
  /// from and costs no raster; one over the pen that is not is drawn whole
  /// once, as the lay would have drawn it.
  ///
  /// 🚨★★★NOT WHAT LIES BELOW THE PEN ([BelowThePen.asHeld]): what is held
  /// of it stays, and a step draws the cells of it it lands in
  /// ([frameAsItStands]) — ↩️it was drawn whole here, a picture the
  /// frame's size at each frame a canvas came to, until 2026-10-28 (card
  /// a-scrub-prepares-every-frame-it-crosses, 유저 「최대한 근본적인
  /// 해결쪽으로」 — 🔬Surface Pro 11, S5_BA cut 352: a ruler scrub's step on
  /// the screen p50 200–267 ms with it, 49–50 ms without).
  ///
  /// ⛔Not on a step's way: a stroke begun before its turn draws each node
  /// as it did before, until the turn comes. And not the frame's picture
  /// again — that is there, and stays as it is.
  ///
  /// The frame laid for the screen keeps them as it is laid ([makeShown]);
  /// one laid ahead keeps none — the warmer lays every frame but the one a
  /// cut opens on, and asks for the one a screen stands on as the screen
  /// does, so either may lay it.
  ///
  /// Held, the frames' pictures made ahead give way to them on the [line]
  /// — here, where the screen holds the frame's own picture already: a
  /// picture laid for it and not yet held would be let go of first.
  Future<void> holdNodesOf(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
  }) async {
    await readInStack(nodes, picture);
    // 🔬Drawn again where the canvas's own lay held them ([makeShown]), it
    // was a third composite of the frame after one show-all on S5_BA cut
    // 352 — 65–114ms of the raster thread (공통, 10-28, Windows, profile).
    if (heldNodes.holdsAllOf(keyOfStack(nodes, picture))) {
      _giveWayToNodes();
      return;
    }
    final turn = await quietTurns.inAQuiet(_holdSpan, gone: shouldAbort);
    if (turn == null) {
      return;
    }
    // A cel that cannot be read is noted and drawn without, as the frame's
    // own making noted it and handed its throw on ([make]).
    final recorder = ui.PictureRecorder();
    drawingNow(
      nodes,
      picture,
      keepsNodes: true,
      below: BelowThePen.asHeld,
    ).frame.drawing.draw(ui.Canvas(recorder));
    recorder.endRecording().dispose();
    heldNodes.heldAllOf(keyOfStack(nodes, picture));
    _giveWayToNodes();
    await turn.landed();
  }

  /// What [heldNodes] weighed when the frames' pictures last gave way to
  /// them on the [line].
  int _gaveWayTo = 0;

  /// The frames' pictures give way on the [line] to what [heldNodes] hold.
  void _giveWayToNodes() {
    line?.giveWayToNodes();
    _gaveWayTo = heldNodes.heldBytes;
  }

  /// The frames' pictures give way on the [line] to the cells of what lies
  /// below a pen that a stroke's steps kept ([frameAsItStands]) — where
  /// they hold more than when they last did.
  void giveWayToSteps() {
    if (heldNodes.heldBytes > _gaveWayTo) {
      _giveWayToNodes();
    }
  }

  Future<bool> _make(
    List<CompositeNode<CanvasStackRow>> Function() nodesOf,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    required bool Function() due,
    required bool shownNow,
    required bool keepsNodes,
  }) async {
    if (shouldAbort()) {
      return false;
    }
    await readInStack(nodesOf(), picture);
    if (shouldAbort()) {
      return false;
    }
    final nodes = nodesOf();
    // Laid over its film — the same tree without its ghosts, on the same
    // page — a frame draws its nodes only where they show, and keeps none:
    // a canvas that shows it holds them then ([holdNodesOf]).
    final film = picture.ghosts == FrameGhosts.inPlace
        ? keyOfStack(stackWithoutGhosts(nodes), picture)
        : null;
    final heldFilm = film != null && store.holds(film) ? film : null;
    final keeps = keepsNodes && heldFilm == null;
    final made = drawingNow(nodes, picture, keepsNodes: keeps);
    // Asked once the drawing is: a cel it was made without is noted now.
    final key = keyOfStack(nodes, picture);
    final drawing = heldFilm == null
        ? made.frame.drawing
        : _overTheFilm(made.frame, () => store.peek(heldFilm));
    // ↩️F-509 A/B: no picture of a page alone, as in build 1079 — the view
    // draws it as it stands ([FramePictureView]).
    if (!drawsOnlyItsPage(key) &&
        !await _lay(
          key,
          keeps ? _thenHeldAllOf(heldNodes, key, drawing) : drawing,
          shouldAbort,
          due,
          shownNow: shownNow,
        )) {
      return false;
    }
    if (made.thrown case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    return true;
  }

  /// Lays [key]'s picture of [drawing] in its turn ([make]); false where
  /// the turn did not come.
  Future<bool> _lay(
    FramePictureKey key,
    FrameDrawing drawing,
    bool Function() shouldAbort,
    bool Function() due, {
    required bool shownNow,
  }) async {
    final turn = await quietTurns.inAQuiet(
      _frameSpan,
      gone: shouldAbort,
      due: due,
    );
    if (turn == null) {
      return false;
    }
    final FramePicture? laid;
    try {
      // ⛔Not `shownNow: due()`: [due] says the run's next frame is missing,
      // not that this is it — every picture a walk asks for ahead while it
      // waits is due, and laid at the front each went before the one the
      // run waits for (the asks came back last first). The walk asks in the
      // order it wants them; the store lays them so — and a screen standing
      // on a frame that is not there asks for it to go first ([makeShown]).
      laid = await store.lay(key, drawing, shownNow: shownNow);
    } on Object {
      unawaited(turn.gaveUp());
      rethrow;
    }
    if (laid == null) {
      unawaited(turn.gaveUp());
    } else {
      await turn.landed();
    }
    return true;
  }

  /// The picture [nodes] — a stack of [picture]'s frame — draw as their
  /// cels stand now: each cel the picture is made of ([_drawn]) from its
  /// stored pixels, and none of any other — a row a cel number is written
  /// on stands bare ([stackedFrameOf]). A cel found here unreadable, or
  /// held at another canvas size, is noted and drawn without — so the key
  /// asked after this ([keyOfStack]) is of the picture it gave.
  ///
  /// Where it [keepsNodes], the pictures its nodes are drawn into whole are
  /// kept ([heldNodes]); what lies below its pen is drawn as [below] says.
  ///
  /// ⚠️Reads a cel not in hand on this thread ([readIn] first).
  FrameDrawingNow drawingNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    bool keepsNodes = false,
    BelowThePen below = BelowThePen.whole,
  }) {
    final page = pageOf(picture);
    (Object, StackTrace)? thrown;
    final frame = stackedFrameOf(
      nodes,
      page: page,
      surfaceOf: (cel) => _drawn(cel)
          ? _readNow(cel, page, (error, stack) => thrown ??= (error, stack))
          : null,
      held: _holding(page, keeps: keepsNodes, below: below),
    );
    return (frame: frame, thrown: thrown);
  }

  /// [readInStack] on this thread for the cels [onScreen] says are on screen
  /// already — a screen whose first frame may not go without them
  /// (`FramePictureView.alreadyShown`), a cel the canvas drew live that is
  /// a ghost now (`FramePictureView.drawnLive`), one the screen drew a
  /// frame ago that an edit took out of hand — each read as [drawingNow]
  /// reads it, and the first throw a reading gave.
  (Object, StackTrace)? readInStackNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    required bool Function(BrushFrameKey cel) onScreen,
  }) {
    final page = pageOf(picture);
    (Object, StackTrace)? thrown;
    for (final cel in stackedCelsOf(_drawnOf(nodes)).where(onScreen)) {
      if (!inHand(cel, picture)) {
        _readNow(cel, page, (error, stack) => thrown ??= (error, stack));
      }
    }
    return thrown;
  }

  /// [cel]'s stored pixels on [page], read on this thread — or null, the
  /// cel noted, where they are held at another canvas size or [thrown]
  /// says why they cannot be read.
  BitmapSurface? _readNow(
    BrushFrameKey cel,
    FramePage page,
    void Function(Object error, StackTrace stack) thrown,
  ) {
    final BitmapSurface? stored;
    try {
      stored = layerImages.storedSurfaceOrNull(
        cel,
        canvasSize: page.canvasSize,
      );
    } on Object catch (error, stack) {
      thrown(error, stack);
      return null;
    }
    if (stored == null) {
      _drawnNothing.note(cel);
    }
    return stored;
  }

  /// [nodes] for [picture] as they stand, drawn from the cels in hand
  /// alone — none is read here, and one not in hand is left out until it
  /// is — and, under [live], the rows a canvas that stands holds live: the
  /// frame a still screen shows while its picture is not there
  /// ([makeShown]), and the body its strokes are patched in by.
  ///
  /// ⛔Not [_drawnOf]: the row a pen is on draws what it holds live, a cel
  /// with nothing stored in it included — the first stroke on it.
  StackedFrame frameAsItStands(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    ({LiveRows rows, LiftedRowPainters painters})? live,
  }) {
    final page = pageOf(picture);
    return stackedFrameOf(
      nodes,
      page: page,
      surfaceOf: (cel) => inHand(cel, picture)
          ? layerImages.storedSurfaceOrNull(cel, canvasSize: page.canvasSize)
          : null,
      live: live,
      held: _holding(page, keeps: false, below: BelowThePen.inCells),
    );
  }

  /// How many steps on each frame's picture is next shown under [demand] —
  /// what the budget lets go of LATEST first. Walked once, the first time
  /// it is asked: a budget with room asks nothing.
  int? Function(FramePictureKey key) wantedAt(FrameDemand? demand) {
    Map<FramePictureKey, int>? soonest;
    return (key) {
      if (demand == null) {
        return null;
      }
      soonest ??= _soonestSteps(demand);
      return soonest![key];
    };
  }

  Map<FramePictureKey, int> _soonestSteps(FrameDemand demand) {
    final soonest = <FramePictureKey, int>{};
    for (var step = 0; step < demand.length; step += 1) {
      for (final picture
          in demand.picturesAt(step) ?? const <DemandedPicture>[]) {
        soonest.putIfAbsent(keyOf(picture), () => step);
      }
    }
    return soonest;
  }
}

/// 🚨A FRAME WITH ITS GHOSTS IN PLACE IS LAID OVER ITS FILM
/// (onion-ghosts-in-place ②, 유저 2026-10-26 「보통 합성이 아닌 경우라도
/// 최대한 극한으로 개선해보자」): [frame]'s picture made of the picture of
/// its [film] — the frame as a run plays it (`FramePictures._make`), held
/// when its turn comes — those texels as they are, and where the ghosts
/// show ([StackedFrame.whereTheGhostsShow]) a picture of that place alone,
/// drawn on nothing by the frame's own body, in their stead: what a
/// stroke's step writes into the picture it patches
/// ([FramePictureStore.patch]). So any blend, adjustment, folder or clip
/// over the ghosts alike — nothing is laid over a texel. Drawn whole where
/// the film is gone by then, or the ghosts cannot be told.
///
/// Past the film's picture the frame holds nothing but its ghosts: a frame
/// covers its page and every row's buffer, spread and all
/// (`_LayerStackPaintPass._compositeExtent`), and the ghosts' place covers
/// theirs.
///
/// 🔬Laid whole, S5_BA cut 352 (67 rows, 2436×1524, 10-28, Windows,
/// profile): the standing order warmed in 444–523 ms against 132–166 ms
/// with the ghosts on top — on the Surface Pro 11 3,635–3,759 ms against
/// 691–816 ms.
FrameDrawing _overTheFilm(StackedFrame frame, FramePicture? Function() film) {
  final whole = frame.drawing;
  return (
    extent: whole.extent,
    outside: whole.outside,
    draw: (canvas) {
      final under = film();
      final ghosts = frame.whereTheGhostsShow;
      if (under == null || ghosts == null) {
        whole.draw(canvas);
        return;
      }
      _inStead(canvas, under.image, under.extent.topLeft);
      final place = _onTheCells(ghosts, pictureExtentOf(whole.extent));
      if (place.isEmpty) {
        return;
      }
      final alone = recordedOver(place, whole.draw);
      final image = alone.toImageSync(
        place.width.toInt(),
        place.height.toInt(),
      );
      alone.dispose();
      _inStead(canvas, image, place.topLeft);
      image.dispose();
    },
  );
}

/// [image]'s texels laid at [at] as they are, one to a pixel, in place of
/// what [canvas] holds there — as a patch's take the place of the
/// picture's ([_overTheFilm]).
void _inStead(ui.Canvas canvas, ui.Image image, ui.Offset at) =>
    canvas.drawImage(
      image,
      at,
      ui.Paint()
        ..blendMode = ui.BlendMode.src
        ..filterQuality = ui.FilterQuality.none,
    );

/// [place] out to the cells a blur reduces what it reads by
/// ([blurReductionCell]), counted from [extent]'s corner — so a chain that
/// spreads reads the place's raster as it reads the picture laid whole —
/// inside [extent]; empty where nothing of it is.
///
/// 🔬On whole pixels alone, a blurred folder over the ghosts came out 1/255
/// apart from the frame laid whole at 17 pixels (Impeller tester, 10-28).
ui.Rect _onTheCells(ui.Rect place, ui.Rect extent) {
  if (place.intersect(extent).isEmpty) {
    return ui.Rect.zero;
  }
  return rectOutwardOnGrid(
    place,
    1 / blurReductionCell,
    origin: extent.topLeft,
  ).intersect(extent);
}

/// [drawing], noting once it is drawn that [key]'s nodes are held
/// ([HeldSubtreeRasters.heldAllOf]) — where its lay draws it, not where the
/// store hands back a picture there already.
FrameDrawing _thenHeldAllOf(
  HeldSubtreeRasters held,
  FramePictureKey key,
  FrameDrawing drawing,
) => (
  extent: drawing.extent,
  outside: drawing.outside,
  draw: (canvas) {
    drawing.draw(canvas);
    held.heldAllOf(key);
  },
);
