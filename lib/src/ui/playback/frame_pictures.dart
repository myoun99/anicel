import 'dart:async';

import '../../core/lru.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/cel_content_notes.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../quiet_turns.dart';
import 'frame_picture_store.dart';
import 'layer_frame_image_cache.dart';
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
    QuietTurns? quietTurns,
  }) : quietTurns = quietTurns ?? QuietTurns.instance;

  final FramePictureStore<FramePictureKey> store;

  /// Where a row's cel is read from: thawed ahead off the UI thread
  /// ([LayerFrameImageCache.readIn]), its stored pixels
  /// ([LayerFrameImageCache.storedSurfaceOrNull]), and the record of the
  /// cels that could not be read.
  final LayerFrameImageCache layerImages;

  /// The tree a screen stacks for [Cut]'s frame while a run shows it — the
  /// canvas's own with no row standing live (`EditingCanvas.playedStackAt`).
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

  /// The key [picture]'s picture is kept under.
  FramePictureKey keyOf(DemandedPicture picture) =>
      keyOfStack(stackOf(picture), picture);

  /// [cel] as a frame's key reads it now ([keyOfStack]).
  CelAsOf celNow(BrushFrameKey cel) =>
      (cel: cel, drawn: _drawn(cel), revision: _revisionOf(cel));

  int _revisionOf(BrushFrameKey cel) =>
      layerImages.frameStore.frameOrNull(cel)?.sourceRevision ?? 0;

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
  /// to come ([failed]).
  bool gaveUpAt(FramePictureKey key) =>
      !_isThere(key) && _gaveNothing.containsKey(key);

  bool _isThere(FramePictureKey key) =>
      store.holds(key) || drawsOnlyItsPage(key);

  @override
  bool has(DemandedPicture picture) => _isThere(keyOf(picture));

  /// The frame itself: one picture, made once however many frames show it.
  @override
  Set<Object> partsToMake(DemandedPicture picture) {
    final key = keyOf(picture);
    return _isThere(key) || _gaveNothing.containsKey(key) ? {} : {key};
  }

  @override
  bool failed(DemandedPicture picture) => gaveUpAt(keyOf(picture));

  /// ⚠️Not where the frame is there: a cel's throw is handed on once the
  /// frame is laid without it ([make]), and the picture laid is no failure.
  @override
  void noteFailure(DemandedPicture picture) {
    final key = keyOf(picture);
    if (!_isThere(key)) {
      _gaveNothing.keep(key, true);
    }
  }

  /// Whether a cel [picture] shows could not be read at the content it has
  /// now ([LayerFrameImageCache.unreadable]) — the ruler's bar paints the
  /// frame red, as it plays without that cel.
  bool cannotRead(DemandedPicture picture) =>
      stackedCelsOf(stackOf(picture)).any(layerImages.unreadable.has);

  /// What the picture will weigh: its drawing's extent, where every cel it
  /// draws is in hand ([readIn]) — and else the page's. ⛔Reads nothing:
  /// a walk weighs the frames it asks for ahead before it reads them.
  @override
  int bytesToMake(DemandedPicture picture) {
    final nodes = stackOf(picture);
    final canvasSize = pageOf(picture).canvasSize;
    final extent = allInHand(nodes, picture)
        ? drawingNow(nodes, picture).frame.drawing.extent
        : null;
    return extent == null
        ? estimatedImageBytes(canvasSize.width, canvasSize.height)
        : estimatedImageBytes(extent.width.ceil(), extent.height.ceil());
  }

  /// Whether every cel [nodes] draw for [picture] is in hand — its stored
  /// pixels read and laid out already ([readInStack] reads the rest).
  bool allInHand(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) {
    final canvasSize = pageOf(picture).canvasSize;
    return stackedCelsOf(_drawnOf(nodes)).every(
      (cel) => layerImages.storedSurfaceIsInHand(cel, canvasSize: canvasSize),
    );
  }

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
        if (!layerImages.storedSurfaceIsInHand(cel, canvasSize: canvasSize))
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
  );

  /// Makes the frame a screen stands on — stacked as that screen stacks it
  /// ([nodes]: a drag in flight, the row a pen is on) — at once, at the
  /// front of the store's line: the frame on screen before any made ahead
  /// of it ([make] has the rest).
  Future<bool> makeShown(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
  }) => _make(
    () => nodes,
    picture,
    shouldAbort: shouldAbort,
    due: () => true,
    shownNow: true,
  );

  Future<bool> _make(
    List<CompositeNode<CanvasStackRow>> Function() nodesOf,
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    required bool Function() due,
    required bool shownNow,
  }) async {
    if (shouldAbort()) {
      return false;
    }
    await readInStack(nodesOf(), picture);
    if (shouldAbort()) {
      return false;
    }
    final nodes = nodesOf();
    final made = drawingNow(nodes, picture);
    // Asked once the drawing is: a cel it was made without is noted now.
    final key = keyOfStack(nodes, picture);
    if (!drawsOnlyItsPage(key) &&
        !await _lay(
          key,
          made.frame.drawing,
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
  /// stored pixels. A cel found here unreadable, or held at another canvas
  /// size, is noted and drawn without — so the key asked after this
  /// ([keyOfStack]) is of the picture it gave.
  ///
  /// ⚠️Reads a cel not in hand on this thread ([readIn] first).
  FrameDrawingNow drawingNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) {
    final page = pageOf(picture);
    (Object, StackTrace)? thrown;
    final frame = stackedFrameOf(
      _drawnOf(nodes),
      page: page,
      surfaceOf: (cel) =>
          _readNow(cel, page, (error, stack) => thrown ??= (error, stack)),
    );
    return (frame: frame, thrown: thrown);
  }

  /// [readInStack] on this thread, for a screen whose first frame may not
  /// go without them (`FramePictureView.alreadyShown`) — each cel read as
  /// [drawingNow] reads it, and the first throw a reading gave.
  (Object, StackTrace)? readInStackNow(
    List<CompositeNode<CanvasStackRow>> nodes,
    DemandedPicture picture,
  ) {
    final page = pageOf(picture);
    (Object, StackTrace)? thrown;
    for (final cel in stackedCelsOf(_drawnOf(nodes))) {
      if (!layerImages.storedSurfaceIsInHand(
        cel,
        canvasSize: page.canvasSize,
      )) {
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
      surfaceOf: (cel) =>
          layerImages.storedSurfaceIsInHand(cel, canvasSize: page.canvasSize)
          ? layerImages.storedSurfaceOrNull(cel, canvasSize: page.canvasSize)
          : null,
      live: live,
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
