import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show Listenable, ValueNotifier, visibleForTesting;

import '../../core/lru.dart';
import '../../core/once_a_microtask.dart';
import '../../core/tree_nodes.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/pasteboard_bounds.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../native/engine_chain_holds.dart';
import '../../native/engine_frame_tools.dart' show appEngineFrameToolsOpen;
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

/// How a frame's key reads a cel where it is not read now: the cel as it
/// was, or null for as it is now ([FramePictures.keyOfStack]).
typedef _CelReading = CelAsOf? Function(BrushFrameKey cel);

/// A frame's key as [FramePictures._standing] read it: of [cut] as it was,
/// on [page], from the tree [nodes] stacked then, with each cel that tree
/// stacks as it stood then and each plug-in's run it signs
/// ([pluginRunsOf]).
typedef _Stood = ({
  Cut cut,
  FramePage page,
  List<CompositeNode<CanvasStackRow>> nodes,
  FramePictureKey key,
  List<({BrushFrameKey cel, int revision, bool drawn})> cels,
  List<FxPluginRun> runs,
  _CelsStamp celsRead,
});

/// What a frame's key read of its cels moves with ([FramePictures._celsNow]):
/// any cel's revision, any crossing empty ↔ drawn, any cel noted as one
/// that will not read or holds pixels of another size, or let go as one.
///
/// ⚠️A device gone moves it as the cels' crossings it made are recorded
/// (`BrushFrameStore.recordWhatWentWithTheDevice`). ⛔Not by the engine
/// itself: a cel's drawn-ness flips as a tile it lost is read, which may be
/// after the engine moved (11-16, tried).
typedef _CelsStamp = (int, int, int, int);

/// Whether every frame's key kept is checked against its tree stacked anew
/// as it is handed out ([FramePictures.treeStamp]) — the test suite's
/// (`flutter_test_config.dart`): an input of the tree that moves past the
/// stamp throws there, in whichever test moves it.
@visibleForTesting
bool debugCheckFrameStanding = false;

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
    this.treeStamp,
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

  /// What every tree [stackOf] stacks reads past its cut, its page and its
  /// cels — the project, the cut the session stands in, all else a screen
  /// is told of — as one value, the same (`==`) while none of it moved: a
  /// frame's key is read once for as long as it stays ([_standing]). Null
  /// where the host cannot say so — then every reading stacks the frame
  /// anew.
  final Object Function()? treeStamp;

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

  /// 🚨★★★A FRAME MADE AHEAD LOOKS AT ITS CELS AND LETS GO (card
  /// `one-cut-of-fnk02-holds-nine-gigabytes`, Q1, 유저 2026-11-15: 「굽고
  /// 나면 놓는다 (같은 법을 재생 그림에도)」 — the render's law ([CelLooks],
  /// `gpu-canonical-store-Q10`) reaching the walk): what the walk reads to
  /// make a frame's picture ahead of a screen leaves the cel store as it
  /// stood, and is held here outside its budgets. The cels of the frame a
  /// canvas stands on are that canvas's, read as a use
  /// (`FramePictureView`).
  ///
  /// ↩️Read as a use ([LayerFrameImageCache.readIn]), every frame's cels
  /// stood hot once its picture was made, until the hot budget's ceiling —
  /// that tier's one way out. 🔬11-15, main PC, windowless, a 78-frame cut
  /// of 20 rows at the automatic allowance: 63 MB a frame, 4.80 GB at 72
  /// frames under a ceiling of 6.83 GB — its pictures 0.67 GB.
  ///
  /// 🔬After, the same harness (11-16): that cut's walk ran to its end at
  /// 2.4 GB, where it was cut off past 8.2; another cut, its band full,
  /// held 1303 MB where it held 1647 — its hot cels 211 MB, 813 before.
  /// ⚠️The price (the card's Q3): a ghost turned on is thawed from the file
  /// again and put on the engine again — that cut's band refilled in 5.0 s
  /// once every row's onion came on, 1.0 before; in 1.1 s for one row's,
  /// 0.15 before. ⏳The engine's tiles of a cel let go are kept for the
  /// next look by `let-go-cels-keep-their-gpu-tiles` (유저 2026-11-16
  /// 03:10: 「지금 착지하고, GPU 타일을 남기는 일을 바로 다음으로」).
  ///
  /// ⚖️As many frames' cels as the walk makes at a time — its own and the
  /// ones it asks for ahead (`PlaybackPrerenderScheduler`), those only
  /// while there is room ([roomToAskAhead]) — and the frame before them, so
  /// a drawing held over the next frame is read once; none once the walk
  /// rests ([rest]). Weighed with the drawings ([celsLookedAtAhead],
  /// `collectMemoryCensus`).
  late final CelLooks _aheadLooks = CelLooks(layerImages.frameStore);

  /// What the frames in the making read ahead of their drawing ([_make],
  /// [readIn]) — theirs until they are laid, whatever frames the looks have
  /// gone on to — each here from before its first cel is read.
  final Set<LooksAhead> _inTheMaking = Set.identity();

  /// The cels' pixels the frames made ahead hold now — the looks'
  /// ([_aheadLooks]) and what each frame in the making read
  /// ([_inTheMaking]) — for whoever weighs them; one may come more than
  /// once.
  Iterable<BitmapSurface> get celsLookedAtAhead => [
    ..._aheadLooks.surfaces,
    for (final ahead in _inTheMaking) ...ahead.surfaces,
  ];

  /// Frames whose making threw past their cels at the content they hold now
  /// — noted by the key of that content, so a walk does not make them
  /// again and a run is not held for a frame that will not come. A new
  /// content is a new key.
  final Lru<FramePictureKey, bool> _gaveNothing = Lru(entryCap: () => 256);

  /// 🚨★WHAT THE CHAINS OF A FRAME A CANVAS STANDS ON PUT
  /// ([EngineChainHolds]; card paint-walk-redoes-the-same-work-each-step,
  /// 실측 5): kept as the frame is laid for that canvas ([makeShown]) and as
  /// a stroke's steps are composed into it, so each folder a step or a value
  /// of a drag does not touch runs none of its chain again. What is recorded
  /// into these keeps its plug-ins' steps as well, and into no others
  /// ([EngineChainHolds.ofThePensFrame]).
  ///
  /// ⚖️As many as the playback [line] has room for — the frames' pictures
  /// made ahead give way to them (🗣️유저 2026-10-27, Q3 = c: 「위 폴더는
  /// 하나씩, 재생 메모리 몫 안에서 전부」). The screen is fed by the frame's
  /// picture, and these only make what comes before it cheaper. Past it they
  /// are let go of, and those run their chains as before.
  late final EngineChainHolds heldNodes = EngineChainHolds(
    room: () => line?.bytesForNodes ?? playbackCacheBudgetBytes,
    ofThePensFrame: true,
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
    ofThePensFrame: false,
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
    if (_gaveNothing.isNotEmpty) {
      _gaveNothing.clear();
      _gaveUpTold.ask();
    }
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
        (node) => switch (node) {
          CompositeLeafSignature(
            row: CompositeLayerSignature(:final sourceRevision),
          ) =>
            left.contains(sourceRevision),
          _ => false,
        },
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
  /// — each [readAs] answers for as it answers.
  List<CompositeNode<CanvasStackRow>> _drawnOf(
    List<CompositeNode<CanvasStackRow>> nodes, {
    _CelReading? readAs,
  }) => stackOfDrawnCels(
    nodes,
    drawn: (cel) => readAs?.call(cel)?.drawn ?? _drawn(cel),
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
  ///
  /// [nodes] the frame's key was read from and stand as read ([_standing])
  /// are signed by that key, not again.
  FramePictureKey keyOfStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    CelAsOf? asOf,
    FramePage? page,
  }) {
    final stamp = asOf == null && page == null ? treeStamp?.call() : null;
    final kept = stamp == null
        ? null
        : _keptStanding(picture, stamp, from: nodes);
    return kept?.key ??
        _keyOfStackRead(
          nodes,
          picture,
          page: page,
          readAs: asOf == null ? null : (cel) => cel == asOf.cel ? asOf : null,
        );
  }

  /// [keyOfStack] with each cel [readAs] answers for read as it answers —
  /// as it was then, or as it was read already — and every other as it is
  /// now.
  FramePictureKey _keyOfStackRead(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    FramePage? page,
    _CelReading? readAs,
  }) {
    _keysSigned += 1;
    return framePictureKeyOf(
      _drawnOf(nodes, readAs: readAs),
      cutId: picture.cut.id,
      page: page ?? pageOf(picture),
      revisionOf: (cel) => readAs?.call(cel)?.revision ?? _revisionOf(cel),
    );
  }

  /// How many frames' keys were signed from their trees ([keyOfStack]) — a
  /// test's word that a key read already was handed over, not signed again.
  @visibleForTesting
  int get keysSigned => _keysSigned;
  int _keysSigned = 0;

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
  ) {
    _standsSigned += 1;
    return framePictureKeyOf(
      nodes,
      cutId: picture.cut.id,
      page: pageOf(picture),
      revisionOf: _revisionOf,
    );
  }

  /// How many trees were signed as they stand ([keyAsItStands]) — a test's
  /// word that a frame handed anew is signed once.
  @visibleForTesting
  int get standsSigned => _standsSigned;
  int _standsSigned = 0;

  /// The key [picture]'s picture is kept under.
  FramePictureKey keyOf(DemandedPicture picture) => _standing(picture).key;

  /// The frames read under [_stoodUnder] ([_standing]).
  final Map<
    ({CutId cut, int frame, bool paper, FrameGhosts ghosts}),
    _Stood
  >
  _stood = {};

  /// The [treeStamp] [_stood] was read under.
  Object? _stoodUnder;

  /// [picture]'s key and the cels its tree stacks, read once while what the
  /// tree reads stays ([treeStamp]): kept where [picture]'s cut is the one
  /// it was read of, on the same page, each cel at the revision and the
  /// drawn-ness it stood at, and each plug-in's run still the one its
  /// binding would make ([FxPluginRun.standsAsBound]); stacked and signed
  /// anew where any moved.
  ///
  /// 🚨A PLUG-IN'S FRAME IS KEPT AS EVERY OTHER IS (H57): its key signs each
  /// run — its runner, the moment as the runner reads it, the rows it
  /// reads — which no stamp follows, so the run itself says whether it
  /// stands. ↩️Such a frame was not kept: stacked anew at every asking,
  /// it was what the bar and the walk spent their time on while a band
  /// with a plug-in filled — 🔬main PC, S5_BA cut 352 with an invert on a
  /// row, 176 frames made anew: the ruler's bar read its window again at
  /// each landing, 1.1–1.3 s of the UI thread a band, nearly all of it
  /// these frames stacked and signed (11-17,
  /// a-plugin-step-is-keyed-by-a-moment-it-may-not-read).
  ///
  /// 🔬The walk, the ruler's bar and the weighing ask it of every frame
  /// (11-14, S5_BA cut 352 · 68 rows, its frames refilled after a stroke,
  /// windowless): the tree stacked and signed anew at every asking was 42%
  /// of the UI thread's samples, the engine's verbs 6%.
  ///
  /// 🚨THE FRAME THE WALK MAKES IS THE TREE ITS KEY WAS READ FROM ([nodes]
  /// of it): weighed ([bytesToMake]), read in ([readIn]), drawn and keyed
  /// ([make]) from that one stacking. ↩️Each stacked the frame again, and
  /// the making signed it again once drawn — five stackings and two
  /// signings a frame. 🔬Main PC, S5_BA cut 352 copy · 37 rows, a band
  /// filled (profile, 11-19, baking-ahead-allocates-the-ui-isolate-into-gc):
  /// the trees stacked 34–36 ms and the keys signed and compared 40–55 ms
  /// of the UI thread's 505–567, and the GC they fed 221–227 ms of it.
  _Stood _standing(DemandedPicture picture) {
    final stamp = treeStamp?.call();
    if (stamp == null) {
      return _stoodNow(picture);
    }
    // A run that cannot say whether it stands ([FxPluginRun.standsAsBound])
    // is kept too, and stacked anew at the next asking all the same.
    return _keptStanding(picture, stamp) ??
        (_stood[_askOf(picture)] = _stoodNow(picture));
  }

  /// What [picture] is kept under in [_stood].
  static ({CutId cut, int frame, bool paper, FrameGhosts ghosts}) _askOf(
    DemandedPicture picture,
  ) => (
    cut: picture.cut.id,
    frame: picture.frameIndex,
    paper: picture.paintPaper,
    ghosts: picture.ghosts,
  );

  /// [picture]'s reading kept under [stamp] where it stands ([_standing]) —
  /// null where none is kept, or what it read moved. [from] asks for the
  /// reading of that tree alone: null where the one kept was stacked
  /// otherwise.
  _Stood? _keptStanding(
    DemandedPicture picture,
    Object stamp, {
    List<CompositeNode<CanvasStackRow>>? from,
  }) {
    if (_stoodUnder != stamp) {
      _stood.clear();
      _stoodUnder = stamp;
    }
    final ask = _askOf(picture);
    final kept = _stood[ask];
    if (kept == null ||
        (from != null && !identical(kept.nodes, from)) ||
        !identical(kept.cut, picture.cut) ||
        kept.page != pageOf(picture) ||
        !kept.runs.every((run) => run.standsAsBound)) {
      return null;
    }
    final cels = _celsNow();
    if (kept.celsRead != cels && !_celsStand(kept)) {
      return null;
    }
    assert(!debugCheckFrameStanding || _standsAsRead(kept, picture));
    if (kept.celsRead != cels) {
      _stood[ask] = (
        cut: kept.cut,
        page: kept.page,
        nodes: kept.nodes,
        key: kept.key,
        cels: kept.cels,
        runs: kept.runs,
        celsRead: cels,
      );
    }
    return kept;
  }

  /// Whether each cel [kept]'s tree stacks stands at the revision and the
  /// drawn-ness it was read at — asked where something a cel's reading
  /// moves with moved since ([_CelsStamp]), and only there: 🔬asked at every
  /// asking, it was 8,179 readings of every row of the frame, 77 µs each,
  /// while S5_BA cut 352's band filled (11-15, main PC, debug).
  bool _celsStand(_Stood kept) {
    _celsReadAgain += 1;
    return kept.cels.every(
      (at) => at.revision == _revisionOf(at.cel) && at.drawn == _drawn(at.cel),
    );
  }

  /// How many times a kept key's cels were read again ([_celsStand]) — a
  /// test's word that nothing they move with moved.
  @visibleForTesting
  int get celsReadAgain => _celsReadAgain;
  int _celsReadAgain = 0;

  /// What a key's cels are read under now ([_CelsStamp]): what [_revisionOf]
  /// and [_drawn] read moves one of these.
  _CelsStamp _celsNow() {
    final cels = layerImages.frameStore;
    return (
      cels.revisionsMoved,
      cels.celContentRevision.value,
      layerImages.unreadable.revision.value,
      _drawnNothing.revision.value,
    );
  }

  /// [picture]'s key as its tree stacks now ([_standing]): each cel it
  /// stacks read once, for the key and for what is kept of it.
  ///
  /// 🔬Read twice, each cel's drawn-ness and revision were asked of the
  /// store again for every frame a ruler's bar keys after an edit — the
  /// two askings 168 and 55 of the bar's 966 sampled ms (card
  /// an-eye-toggle-holds-the-ui-thread, 11-18, S5_BA cut 352 · 68 rows, 40
  /// eye toggles).
  _Stood _stoodNow(DemandedPicture picture) {
    final celsRead = _celsNow();
    final nodes = stackOf(picture);
    final page = pageOf(picture);
    final cels = [for (final cel in stackedCelsOf(nodes)) celNow(cel)];
    // By the cel's own object: the key reads the same rows' cels.
    final read = Map<BrushFrameKey, CelAsOf>.identity();
    for (final at in cels) {
      read[at.cel] = at;
    }
    return (
      cut: picture.cut,
      page: page,
      nodes: nodes,
      key: _keyOfStackRead(
        nodes,
        picture,
        page: page,
        readAs: (cel) => read[cel],
      ),
      cels: cels,
      runs: pluginRunsOf(nodes),
      celsRead: celsRead,
    );
  }

  /// Whether [kept] is what [picture]'s tree stacks now — a test's word
  /// that no input of the tree moved past [treeStamp]
  /// ([debugCheckFrameStanding]).
  bool _standsAsRead(_Stood kept, DemandedPicture picture) {
    final now = _stoodNow(picture);
    if (now.key != kept.key) {
      throw StateError(
        'frame ${picture.frameIndex} of ${picture.cut.id} was kept under '
        '${kept.key}, and stacks ${now.key} now — an input of its tree '
        'moved past the stamp',
      );
    }
    return true;
  }

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

  /// Whether [key]'s frame's picture is still to come — not there, nor
  /// given up on: what a move waits for (`StandsWithItsPicture`), and a
  /// canvas stands bare for in another cut (`FramePictureView`).
  bool toComeAt(FramePictureKey key) => _stateAt(key) == PictureState.toCome;

  /// Whether a view of these pictures has put a frame on its screen yet.
  /// Till one has, nothing of the project was there to stand on — a file
  /// just opened (🗣️the-standing-canvas-composes-a-frame-twice-before-its-
  /// picture-Q7 = blank, 유저 2026-11-18 「빈 종이로 기다린다」) — and a view
  /// stands bare till its first frame's picture comes (`FramePictureView`).
  /// ⛔Not each view's own: a view made again over a screen that showed —
  /// another engine's, a switch of what it draws — stands as it stood.
  bool get anyOnScreen => _anyOnScreen;
  bool _anyOnScreen = false;

  /// A view put a frame on its screen ([anyOnScreen]).
  void putOnScreen() => _anyOnScreen = true;

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
    final stood = _standing(picture);
    return (
      state: _stateAt(stood.key),
      cannotRead: stood.cels.any((at) => layerImages.unreadable.has(at.cel)),
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
      _gaveUpTold.ask();
    }
  }

  /// Tells that what [standingOf] answers of a frame may have moved: a
  /// picture laid or let go of ([EngineFramePictureStore.laidOrLetGo]), a
  /// making given up on ([noteFailureAt]) or let be again
  /// ([letGoWithTheirEngine]), a cel found unreadable, a cel's pixels
  /// edited — what a bar that counts the frames ready hears (the green
  /// band).
  ///
  /// 🗣️the-screen-shows-a-frame-the-green-band-leaves-empty (유저
  /// 2026-11-15): a frame a canvas made was on the screen, and the band
  /// filled there only once the walk moved on. ↩️The band heard the walk's
  /// progress — the pictures the walk laid and no other: a canvas's and a
  /// move's ([makeShown]) went into the store unheard.
  late final Listenable standingMoved = Listenable.merge([
    store.laidOrLetGo,
    _gaveUp,
    layerImages.unreadable.revision,
    layerImages.frameStore.celPixelRevision,
  ]);

  /// Bumped once a making given up on is noted, or they are all let be
  /// again with their engine ([standingMoved]).
  final ValueNotifier<int> _gaveUp = ValueNotifier<int>(0);
  late final _gaveUpTold = OnceAMicrotask(() => _gaveUp.value += 1);

  /// What the picture will weigh: the tiles the engine makes of it laid
  /// afresh ([EngineStackScreen.bytesToMake]) — none for a tile its
  /// pictures keep one of the same input for —, where every cel it draws
  /// is in hand ([readIn]) — and else of the page's ([EngineStackScreen.
  /// bytesOver]). ⛔Reads nothing: a walk weighs the frames it asks for
  /// ahead before it reads them.
  ///
  /// ⚠️Where the engine cannot plan it yet — its tools still opening, its
  /// chains' kernels still to compile ([FrameKernelsToCome]) — every tile
  /// its world meets: more than it will weigh, never less. ⏳And a tile an
  /// effect chain's picture is laid on is weighed as made, whoever keeps
  /// one: weighed ahead, a frame's chains are held under no number
  /// ([EngineChainHolds]) — holding one is running it.
  @override
  Future<int> bytesToMake(DemandedPicture picture) async {
    final nodes = _standing(picture).nodes;
    final canvasSize = pageOf(picture).canvasSize;
    final inHand = stackedCelsOf(
      _drawnOf(nodes),
    ).every((cel) => _aheadLooks.holds(cel, canvasSize: canvasSize));
    if (!inHand) {
      return EngineStackScreen.bytesOver(canvasSize.canvasRect);
    }
    final frame = drawingNow(nodes, picture, looks: _aheadLooks).frame;
    final tools = appEngineFrameToolsOpen;
    if (tools != null) {
      try {
        return await EngineStackScreen.bytesToMake(
          frame,
          tools.composite,
          tools.letters,
        );
      } on FrameKernelsToCome {
        // Weighed as the world it holds, below.
      }
    }
    return EngineStackScreen.bytesOver(frame.extent);
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

  /// Reads every cel [picture] draws ahead of its making, at once, off the
  /// UI thread — as the looks of a frame made ahead ([_aheadLooks]): none
  /// another frame holds is read again.
  @override
  Future<void> readIn(DemandedPicture picture) async {
    final ahead = LooksAhead();
    _inTheMaking.add(ahead);
    try {
      await readInStack(
        _standing(picture).nodes,
        picture,
        looks: _aheadLooks,
        into: ahead,
      );
    } finally {
      _inTheMaking.remove(ahead);
    }
  }

  /// The walk rests: what it read for a picture it then did not make, and
  /// the last frames' cels, are let go.
  @override
  void rest() => _aheadLooks.letGo();

  /// 🚨WHAT THE FRAMES MADE AHEAD HOLD STANDS IN THE HOT CELS' ROOM (저장
  /// 2026-11-15 20:12, reading this law's first cut: 「묶음이 프레임 수이고
  /// 바이트가 아니다」). The looks hold their cels outside the store's
  /// budgets, a frame's worth for each frame in the making and for the two
  /// the looks keep: where every row draws a canvas-wide cel anew each
  /// frame, five frames' cels stood beside a store whose hot budget had
  /// stood over every one of them. So a frame past the walk's own is asked
  /// for only while the hot cels and what the looks hold beside them weigh
  /// under that budget — the one allowance for thawed cels, no number of
  /// its own. The walk's own frame is made whatever they weigh: a frame is
  /// drawn of all its cels at once.
  @override
  bool get roomToAskAhead {
    final store = layerImages.frameStore;
    final held =
        store.hotBakedBytes + _aheadLooks.bytesBesideTheStore(_inTheMaking);
    return held < store.hotCelByteBudget;
  }

  /// Reads the cels [nodes] — a screen's own stack, or a frame's as it is
  /// made — draw, at once, off the UI thread, on [picture]'s page or [page]
  /// ([keyOfStack]): thawed hot where a screen stands on them, each not in
  /// hand already ([LayerFrameImageCache.readIn]) — or through [looks],
  /// where a render or the walk makes the picture ([CelLooks.ahead]), and
  /// what was read handed back for the drawing ([drawingNow]) — read
  /// [into] the hold its frame counts already, where it has one
  /// ([_inTheMaking]).
  Future<LooksAhead?> readInStack(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    FramePage? page,
    CelLooks? looks,
    LooksAhead? into,
  }) async {
    final canvasSize = (page ?? pageOf(picture)).canvasSize;
    final cels = stackedCelsOf(_drawnOf(nodes));
    if (looks != null) {
      return looks.ahead(cels, canvasSize: canvasSize, into: into);
    }
    await Future.wait([
      for (final cel in cels)
        if (!inHand(cel, picture, page: page))
          layerImages.readIn(cel, canvasSize: canvasSize),
    ]);
    return null;
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
    () => _standing(picture).nodes,
    picture,
    shouldAbort: shouldAbort,
    due: due,
    shownNow: false,
    keepsNodes: false,
    looks: _aheadLooks,
  ).whenComplete(_aheadLooks.nextFrame);

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
  /// they last did, once what the steps kept is weighed
  /// ([EngineChainHolds.onceWeighed]).
  void giveWayToSteps() => heldNodes.onceWeighed(_giveWayToSteps);

  void _giveWayToSteps() {
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
  /// [looks] says ([drawingNow]) — ahead of the drawing ([readInStack]),
  /// and weighed while the frame is in the making ([celsLookedAtAhead]).
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
    // In the count before its first cel is read ([LooksAhead.new]).
    final ahead = looks == null ? null : LooksAhead();
    if (ahead != null) {
      _inTheMaking.add(ahead);
    }
    try {
      await readInStack(
        nodesOf(),
        picture,
        page: page,
        looks: looks,
        into: ahead,
      );
      return await _drawAndLay(
        nodesOf,
        picture,
        shouldAbort: shouldAbort,
        due: due,
        shownNow: shownNow,
        keepsNodes: keepsNodes,
        page: page,
        looks: looks,
        ahead: ahead,
      );
    } finally {
      _inTheMaking.remove(ahead);
    }
  }

  /// [_make] once the frame's cels are read: drawn as they stand now and
  /// laid in its turn.
  Future<bool> _drawAndLay(
    List<CompositeNode<CanvasStackRow>> Function() nodesOf,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    required bool Function() due,
    required bool shownNow,
    required bool keepsNodes,
    required FramePage? page,
    required CelLooks? looks,
    required LooksAhead? ahead,
  }) async {
    if (shouldAbort()) {
      return false;
    }
    final nodes = nodesOf();
    final film = picture.ghosts == FrameGhosts.inPlace
        ? keyOfStack(stackWithoutGhosts(nodes), picture, page: page)
        : null;
    final made = drawingNow(
      nodes,
      picture,
      page: page,
      looks: looks,
      ahead: ahead,
    );
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
  /// — and one the walk makes ahead of a screen ([_aheadLooks]) — reads
  /// each cel through its [looks] ([CelLooks]), what its frame read [ahead]
  /// in hand — the store left as it stood — and a screen that stands on the
  /// frame reads them as a use, in hand from then on
  /// ([LayerFrameImageCache.storedSurfaceOrNull]).
  ///
  /// On [picture]'s page, or [page] ([keyOfStack]).
  FrameDrawingNow drawingNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    FramePage? page,
    CelLooks? looks,
    LooksAhead? ahead,
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
              ahead: ahead,
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
  /// [looks] where a render reads them ([drawingNow]), what its frame read
  /// [ahead] read by no one again — or null, the cel noted, where they are
  /// held at another canvas size or [thrown] says why they cannot be read.
  BitmapSurface? _readNow(
    BrushFrameKey cel,
    FramePage page,
    void Function(Object error, StackTrace stack) thrown, {
    CelLooks? looks,
    LooksAhead? ahead,
  }) {
    final canvasSize = page.canvasSize;
    final BitmapSurface? stored;
    try {
      stored = looks == null
          ? layerImages.storedSurfaceOrNull(cel, canvasSize: canvasSize)
          : layerImages.unreadable.notingNow(
              cel,
              () => looks.surfaceOf(
                cel,
                canvasSize: canvasSize,
                ahead: ahead,
              ),
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
