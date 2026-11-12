import 'dart:async';
import 'dart:ui' as ui;

import '../../core/lru.dart';
import '../../core/tree_nodes.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/pasteboard_bounds.dart';
import '../../native/engine_chain_holds.dart';
import '../../services/cel_content_notes.dart';
import '../../services/cel_looks.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../quiet_turns.dart';
import 'engine_frame_picture_store.dart';
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

  /// How much of the line nothing holds now.
  int get bytesLeftFree;

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

  final EngineFramePictureStore<FramePictureKey> store;

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

  /// 🚨★WHAT THE CHAINS OF A FRAME A CANVAS STANDS ON PUT
  /// ([EngineChainHolds]; card paint-walk-redoes-the-same-work-each-step,
  /// 실측 5): kept as the frame is laid for that canvas ([makeShown]) and as
  /// a stroke's steps are composed into it, so each folder a step or a value
  /// of a drag does not touch runs none of its chain again.
  ///
  /// ⚖️As many as the playback [line] has room for — the frames' pictures
  /// made ahead give way to them (🗣️유저 2026-10-27, Q3 = c: 「위 폴더는
  /// 하나씩, 재생 메모리 몫 안에서 전부」). The screen is fed by the frame's
  /// picture, and these only make what comes before it cheaper. Past it they
  /// are let go of, and those run their chains as before.
  late final EngineChainHolds heldNodes = EngineChainHolds(
    room: () => line?.bytesForNodes ?? playbackCacheBudgetBytes,
  );

  /// 🚨★WHAT THE CHAINS OF THE FRAMES MADE AHEAD PUT (🗣️유저 2026-11-01,
  /// F-529-Q1: 「거기서 굽는시간 최대한 단축하고싶음」): what the next frame
  /// made ahead finds, so a folder that draws the same on both does not run
  /// its chain again — [heldNodes] are what a canvas stands on, these what a
  /// walk goes through.
  ///
  /// ⚖️In what the [line] has free ([HeldNodesLine.bytesLeftFree]) — the
  /// frames' pictures feed the screen and these only make them cheaper, so
  /// no picture gives way to them, nor does a walk end a picture short.
  ///
  /// 🔬Surface Pro 11, profile, S5_BA cut 353 (38 rows, one folder under a
  /// camera lens blur at 2720 x 1696 whose rows change at 2 of 47 frames),
  /// the bar's 114 frames from nothing, in turn, on the walk: 29.9–30.8 s →
  /// 8.0–8.5 s with the folder's picture held.
  late final EngineChainHolds aheadNodes = EngineChainHolds(
    room: () => line?.bytesLeftFree ?? playbackCacheBudgetBytes,
  );

  /// The line [heldNodes] stand on — null where none is told: the line's
  /// own size, which nothing else holds then.
  final HeldNodesLine? line;

  /// What the chains held weigh, on the [line] beside the frames' pictures
  /// ([heldNodes], [aheadNodes]).
  int get heldBytes => heldNodes.heldBytes + aheadNodes.heldBytes;

  /// The chains held past what the [line] has room for are let go of.
  void fitNodes() {
    heldNodes.fit();
    aheadNodes.fit();
  }

  /// Lets go of every chain held.
  void letGoOfNodes() {
    heldNodes.clear();
    aheadNodes.clear();
  }

  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
  /// 않고 새 장치를 열어 사본으로 되살린다」 — what the frames stand on went
  /// with the engine that made it: the chains held, every frame's picture
  /// ([EngineFramePictureStore.letGoWithItsTools]), and the word that a
  /// frame's making threw ([gaveUpAt]) — a device going refuses what the
  /// next one makes, and a frame is asked of the next as if for the first
  /// time.
  ///
  /// ⚠️The pictures last: who shows one asks for its frame again as it
  /// hears ([EngineFramePictureStore.wentWithItsTools]), and finds none of
  /// the rest.
  void letGoWithTheirEngine() {
    letGoOfNodes();
    _gaveNothing.clear();
    store.letGoWithItsTools();
  }

  /// Lets go of every frame's picture made of a revision the cels' store
  /// last left for good ([BrushFrameStore.revisionsLastLeft]) — asked for
  /// by no key again — but the ones a screen holds ([FramePictureStore
  /// .letGoUnpinnedWhere]). Told at every pixel edit
  /// ([BrushFrameStore.celPixelRevision]).
  ///
  /// 🔬F-569 (2026-11-06, S5_BA cut 352, Windows, profile): 30 fills on a
  /// cel two frames show left 30 pictures of the other frame, 21 MB each —
  /// the store grew 2757 → 3390 MB and let none go at rest, under a budget
  /// of 6 GB.
  void letGoOfLeftRevisions() {
    final left = layerImages.frameStore.revisionsLastLeft;
    if (left.isEmpty) {
      return;
    }
    store.letGoUnpinnedWhere(
      (key) => preorderNodes(key.signature.nodes).any(
        (node) =>
            node is CompositeLeafSignature &&
            left.contains(node.layer.sourceRevision),
      ),
    );
  }

  void dispose() {
    heldNodes.free();
    aheadNodes.free();
  }

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
  ///
  /// [page] is the page the picture is drawn on where it is not the one
  /// [picture] is ([pageOf]) — a file's rows on the ground it is made on
  /// (`frameOnTheEngine`).
  FramePictureKey keyOfStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    CelAsOf? asOf,
    FramePage? page,
  }) => framePictureKeyOf(
    _drawnOf(nodes, asOf: asOf),
    cutId: picture.cut.id,
    page: page ?? pageOf(picture),
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
  void noteFailure(DemandedPicture picture) => noteFailureAt(keyOf(picture));

  /// [noteFailure] of the frame under [key]: as a screen stacks it
  /// ([makeShown]), which is not always as the warmer does.
  void noteFailureAt(FramePictureKey key) {
    if (!_isThere(key)) {
      _gaveNothing.keep(key, true);
    }
  }

  /// What the picture will weigh: the tiles the engine keeps of its
  /// world ([EngineStackScreen.bytesOver]), where every cel it draws is in
  /// hand ([readIn]) — and else of the page's. ⛔Reads nothing: a walk
  /// weighs the frames it asks for ahead before it reads them.
  @override
  int bytesToMake(DemandedPicture picture) {
    final nodes = stackOf(picture);
    return EngineStackScreen.bytesOver(
      allInHand(nodes, picture)
          ? drawingNow(nodes, picture).frame.extent
          : pageOf(picture).canvasSize.canvasRect,
    );
  }

  /// Whether every cel [nodes] draw for [picture] is in hand — its stored
  /// pixels read and laid out already ([readInStack] reads the rest).
  bool allInHand(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) => stackedCelsOf(_drawnOf(nodes)).every((cel) => inHand(cel, picture));

  /// Whether [cel]'s stored pixels on [picture]'s page — or [page] — are
  /// read and laid out already — drawn without a reading
  /// ([frameAsItStands]).
  bool inHand(BrushFrameKey cel, DemandedPicture picture, {FramePage? page}) =>
      layerImages.storedSurfaceIsInHand(
        cel,
        canvasSize: (page ?? pageOf(picture)).canvasSize,
      );

  /// Thaws every cel [picture] draws that is not in hand already, at once,
  /// off the UI thread ([LayerFrameImageCache.readIn]) — none another frame
  /// has read.
  @override
  Future<void> readIn(DemandedPicture picture) =>
      readInStack(stackOf(picture), picture);

  /// [readIn] for the cels [nodes] — a screen's own stack — draw, on
  /// [picture]'s page or [page] ([keyOfStack]).
  ///
  /// A render's [looks] read nothing ahead: a look thaws nothing, and its
  /// cels are read as the frame is drawn ([drawingNow]).
  Future<void> readInStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    FramePage? page,
    CelLooks? looks,
  }) {
    if (looks != null) {
      return Future<void>.value();
    }
    final canvasSize = (page ?? pageOf(picture)).canvasSize;
    return Future.wait([
      for (final cel in stackedCelsOf(_drawnOf(nodes)))
        if (!inHand(cel, picture, page: page))
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

  /// 🚨THE PICTURE A PANEL IS CUT FROM (F-533-Q8, 유저 2026-11-05: 「프레임
  /// 그림에서 잘라 쓴다」 · 「최대한 하나로 통합」): the frame [nodes] stack for
  /// [picture], under its key ([keyOfStack]) — the canvas's and the warmer's
  /// own wherever they stack the frame alike — and made in the store's line
  /// as one made ahead is ([make]) where none is there. Null where there is
  /// none to cut from: the frame draws its page alone ([drawsOnlyItsPage]),
  /// a canvas holds it as its own over what no cel stores ([_isThere] — a
  /// panel is of what the cels store), or the making was given up.
  ///
  /// ↩️A panel composed the frame again for itself, every row at the
  /// canvas's size (`ExportFrameRenderer.renderPicture`) — 🔬S5_BA cut 352,
  /// 68 rows: about 180 Mpx a picture, seconds of a Surface Pro 11's GPU
  /// each time the pen came up.
  ///
  /// On [picture]'s page, or [page] ([keyOfStack]); its cels read as
  /// [looks] says where a render makes it ([drawingNow]).
  ///
  /// 🚨HELD FOR THE ONE IT IS HANDED TO, WHO RELEASES IT
  /// ([EngineFramePicture.hold] — the store's law 「HELD BY WHOEVER SHOWS
  /// IT」; 관제 11-10 08:48): the store may let it go while the asker is
  /// still on its way to showing it. ↩️It was handed unheld, and a shot
  /// (`frameOnTheEngine`) waits for the engine's tools between this and its
  /// show — a picture the budget let go in that wait was freed, and its
  /// show threw.
  Future<EngineFramePicture?> pictureOf(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    FramePage? page,
    CelLooks? looks,
  }) async {
    var key = keyOfStack(nodes, picture, page: page);
    if (!store.holds(key)) {
      if (_isThere(key) ||
          !await _make(
            () => nodes,
            picture,
            shouldAbort: shouldAbort,
            due: notDue,
            shownNow: false,
            keepsNodes: false,
            page: page,
            looks: looks,
          )) {
        return null;
      }
      // Asked once it is made: a cel it was made without is noted then.
      key = keyOfStack(nodes, picture, page: page);
    }
    return store.peek(key)?.hold();
  }

  /// What [heldNodes] weighed when the frames' pictures last gave way to
  /// them on the [line].
  int _gaveWayTo = 0;

  /// The frames' pictures give way on the [line] to what a stroke's steps
  /// kept of their chains ([heldNodes]) — where they hold more than when
  /// they last did.
  void giveWayToSteps() {
    if (heldNodes.heldBytes > _gaveWayTo) {
      line?.giveWayToNodes();
      _gaveWayTo = heldNodes.heldBytes;
    }
  }

  /// 🚨A FRAME WITH ITS GHOSTS IN PLACE IS LAID OVER ITS FILM
  /// (onion-ghosts-in-place ②, 유저 2026-10-26 「보통 합성이 아닌 경우라도
  /// 최대한 극한으로 개선해보자」): the same tree without its ghosts, on the
  /// same page, held when its turn comes — composited where the ghosts show
  /// ([StackedFrame.whereTheGhostsShow]) alone, the film's elsewhere as it is
  /// ([EngineFramePictureStore.lay]), so any blend, adjustment, folder or
  /// clip over the ghosts alike. Laid whole where the film is gone by then,
  /// or the ghosts cannot be told.
  ///
  /// 🔬Laid whole, S5_BA cut 352 (67 rows, 2436×1524, 10-28, Windows,
  /// profile): the standing order warmed in 444–523 ms against 132–166 ms
  /// with the ghosts on top — on the Surface Pro 11 3,635–3,759 ms against
  /// 691–816 ms.
  ///
  /// On [picture]'s page, or [page] ([keyOfStack]); its cels read as
  /// [looks] says ([drawingNow]).
  Future<bool> _make(
    List<CompositeNode<CanvasStackRow>> Function() nodesOf,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    required bool Function() due,
    required bool shownNow,
    required bool keepsNodes,
    FramePage? page,
    CelLooks? looks,
  }) async {
    if (shouldAbort()) {
      return false;
    }
    await readInStack(nodesOf(), picture, page: page, looks: looks);
    if (shouldAbort()) {
      return false;
    }
    final nodes = nodesOf();
    final film = picture.ghosts == FrameGhosts.inPlace
        ? keyOfStack(stackWithoutGhosts(nodes), picture, page: page)
        : null;
    final made = drawingNow(nodes, picture, page: page, looks: looks);
    // Asked once the drawing is: a cel it was made without is noted now.
    final key = keyOfStack(nodes, picture, page: page);
    final ghosts = film != null && store.holds(film)
        ? made.frame.whereTheGhostsShow
        : null;
    if ((keepsNodes || !drawsOnlyItsPage(key)) &&
        !await _lay(
          key,
          made.frame,
          shouldAbort,
          due,
          over: ghosts == null ? null : (film: film!, fresh: ghosts),
          holds: shownNow && keepsNodes ? heldNodes : aheadNodes,
          shownNow: shownNow,
        )) {
      return false;
    }
    // What the picture laid took of the line.
    aheadNodes.fit();
    if (made.thrown case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    return true;
  }

  /// Lays [key]'s picture of [frame] in its turn ([make]), over the film
  /// [over] says, its chains held in [holds]; false where the turn did not
  /// come, or [shouldAbort] left the store's line before its lay was made.
  Future<bool> _lay(
    FramePictureKey key,
    StackedFrame frame,
    bool Function() shouldAbort,
    bool Function() due, {
    required ({FramePictureKey film, ui.Rect fresh})? over,
    required EngineChainHolds holds,
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
    final EngineFramePicture? laid;
    try {
      // ⛔Not `shownNow: due()`: [due] says the run's next frame is missing,
      // not that this is it — every picture a walk asks for ahead while it
      // waits is due, and laid at the front each went before the one the
      // run waits for (the asks came back last first). The walk asks in the
      // order it wants them; the store lays them so — and a screen standing
      // on a frame that is not there asks for it to go first ([makeShown]).
      laid = await store.lay(
        key,
        frame,
        shownNow: shownNow,
        gone: shouldAbort,
        over: over,
        holds: holds,
      );
    } on Object {
      unawaited(turn.gaveUp());
      rethrow;
    }
    if (laid == null) {
      unawaited(turn.gaveUp());
      return !shouldAbort();
    }
    await turn.landed();
    return true;
  }

  /// The picture [nodes] — a stack of [picture]'s frame — draw as their
  /// cels stand now: each cel the picture is made of ([_drawn]) from its
  /// stored pixels, and none of any other — a row a cel number is written
  /// on stands bare ([stackedFrameOf]). A cel found here unreadable, or
  /// held at another canvas size, is noted and drawn without — so the key
  /// asked after this ([keyOfStack]) is of the picture it gave.
  ///
  /// ⚠️Reads a cel not in hand on this thread ([readIn] first).
  ///
  /// 🚨★★★A RENDER'S CELS ARE LOOKS (`gpu-canonical-store-Q10`, 유저
  /// 2026-11-10 「추천대로 법 지키도록」): a picture made for a file or a panel
  /// reads each cel through its [looks] ([CelLooks]) — the store left as it
  /// stood — and the app's own screens read them as a use, in hand from
  /// then on ([LayerFrameImageCache.storedSurfaceOrNull]).
  ///
  /// On [picture]'s page, or [page] ([keyOfStack]).
  FrameDrawingNow drawingNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    FramePage? page,
    CelLooks? looks,
  }) {
    final on = page ?? pageOf(picture);
    (Object, StackTrace)? thrown;
    final frame = stackedFrameOf(
      nodes,
      page: on,
      surfaceOf: (cel) => _drawn(cel)
          ? _readNow(
              cel,
              on,
              (error, stack) => thrown ??= (error, stack),
              looks: looks,
            )
          : null,
      revisionOf: _revisionOf,
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

  /// [cel]'s stored pixels on [page], read on this thread — through
  /// [looks] where a render reads them ([drawingNow]) — or null, the cel
  /// noted, where they are held at another canvas size or [thrown] says why
  /// they cannot be read.
  BitmapSurface? _readNow(
    BrushFrameKey cel,
    FramePage page,
    void Function(Object error, StackTrace stack) thrown, {
    CelLooks? looks,
  }) {
    final canvasSize = page.canvasSize;
    final BitmapSurface? stored;
    try {
      stored = looks == null
          ? layerImages.storedSurfaceOrNull(cel, canvasSize: canvasSize)
          : layerImages.unreadable.notingNow(
              cel,
              () => looks.surfaceOf(cel, canvasSize: canvasSize),
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
  /// ([makeShown]), and the body its strokes are composed in by.
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
      revisionOf: _revisionOf,
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
