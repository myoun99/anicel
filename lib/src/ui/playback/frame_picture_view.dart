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
        StackedFrame;
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
/// ([StackedFrame.movedSince] → [FramePictureStore.patch]), drawn as it
/// stands over the picture until its texels are in; a stroke that lands
/// moves the picture to the frame's next key ([FramePictureStore.move]).
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

  @override
  State<FramePictureView> createState() => _FramePictureViewState();
}

/// What the view draws: a frame's picture — the view's own handle on its
/// image, with what the store lays over it while patches land — or a frame
/// drawn as it stands.
typedef _Shown = ({FramePicture picture, ui.Image image})?;

/// A patch on its way into the picture shown: its rect drawn as it stands
/// until [landed].
typedef _Patching = ({ui.Rect rect, Future<void> landed});

/// What of a frame is drawn as it stands where its picture is shown: all of
/// it ([whole]), or the rects of the patches on their way into the picture
/// ([patching]).
///
/// 🚨READ AT EACH PAINT, not handed to the painter at a build: a change of
/// the live rows moves it with no build — a stroke's step patched in, a
/// change no patch can follow. Handed at the build before, the step did not
/// show until its texels were in the picture, and a frame gone to be drawn
/// as it stands showed the picture without the change until the next build.
final class _DrawnAsItStands {
  /// The live rows moved where no patch can follow: the frame is drawn as
  /// it stands until its key moves.
  bool whole = false;

  /// The patches on their way into the picture shown.
  final List<_Patching> patching = [];
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

  /// What of the frame is drawn as it stands over the picture shown.
  final _DrawnAsItStands _standing = _DrawnAsItStands();

  /// The cel the pen is on, as the key of the picture shown read it.
  CelAsOf? _drawnOn;

  /// The key a stroke's landing is moving the picture shown to.
  FramePictureKey? _moving;

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
    _standLive();
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
    final handedAnew =
        !identical(oldWidget.nodes, widget.nodes) ||
        !_sameLive(oldWidget.live, widget.live) ||
        oldWidget.wholeFrames != widget.wholeFrames;
    if (handedAnew) {
      _standLive();
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
  /// read and it is built again once they are.
  void _standLive() {
    _liveChanges = null;
    _live = null;
    final live = widget.live;
    if (live == null && widget.wholeFrames) {
      _standing.whole = false;
      return;
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
    if (!_pictures.allInHand(nodes, widget.picture)) {
      unawaited(
        _pictures.readInStack(nodes, widget.picture).then((_) {
          if (mounted && identical(widget.nodes, nodes)) {
            setState(_standLive);
          }
        }),
      );
    }
  }

  /// Takes the frame asked for where it is there; leaves what stands where
  /// it is not yet.
  void _look() {
    final key = _pictures.keyOfStack(widget.nodes, widget.picture);
    if (key == _showing && _shown != null) {
      return;
    }
    final there = _store.peek(key);
    if (there != null) {
      _take(key, there);
      return;
    }
    if (key == _showing || key == _moving) {
      return;
    }
    if (_pictures.drawsOnlyItsPage(key) || _pictures.gaveUpAt(key)) {
      _standAsStored(key);
      return;
    }
    if (_moves(key)) {
      return;
    }
    if (widget.laysWhatItMisses) {
      _make(key);
    }
    if (!widget.wholeFrames) {
      // Drawn as it stands until its picture is there.
      _letGo(_store);
      _showing = key;
    }
  }

  /// Shows [there], the picture of [key] — the one shown already where a
  /// stroke's landing moved it here, what it holds of the live rows kept.
  void _take(FramePictureKey key, FramePicture there) {
    final moved = identical(there, _shown?.picture);
    final held = _held;
    final patching = [..._standing.patching];
    final image = there.image.clone();
    _letGo(_store);
    _store.retainPin(key);
    _shown = (picture: there, image: image);
    _showing = key;
    final cel = _celDrawnOn();
    _drawnOn = cel == null ? null : _pictures.celNow(cel);
    if (moved) {
      // ⛔Not let go with the key it left: what the picture holds of the
      // live rows it holds under this one, and the next stroke patches in
      // from there — let go, every stroke after the first would be drawn
      // as it stands whole, a step at a time. Nor the patches the next
      // stroke sent after it while it moved: their rects are drawn as
      // they stand until their texels are in.
      _held = held;
      _standing.patching.addAll(patching);
      return;
    }
    _standing.whole = false;
    _tell();
  }

  /// A frame with nothing of it to wait for — its page alone, or one whose
  /// making threw — drawn as it stands.
  void _standAsStored(FramePictureKey key) {
    _letGo(_store);
    final now = _pictures.drawingNow(widget.nodes, widget.picture);
    _asItStands = now.frame;
    _showing = key;
    if (now.thrown case (final error, final stack)) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'frame picture view',
          context: ErrorDescription('drawing a frame as its cels stand'),
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
    if (_standing.whole || !_store.move(from: from, to: key)) {
      return false;
    }
    _moving = key;
    unawaited(
      _store.landingOf(key)!.then((_) {
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
  void _liveRowsHandedAnew() {
    if (_shown != null) {
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
    if (!live.steady ||
        (now != null && (now.overlay.isNotEmpty || now.previews.isNotEmpty))) {
      _standing.whole = true;
      return;
    }
    _held = now;
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
  void _catchUp() {
    final live = _live;
    final shown = _shown;
    // A picture a stroke's landing is moving takes the change under the key
    // it is moving to ([_moves]) — the store patches a picture a move is
    // still moving. ⛔Not left out until the move lands: the next stroke's
    // first steps were drawn nowhere.
    final key = _moving ?? _showing;
    if (live == null || shown == null || key == null || _standing.whole) {
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
    if (!_store.patch(from: key, to: key, rect: rect, draw: drawing.draw)) {
      _standing.whole = true;
      return;
    }
    final landed = _store.landingOf(key)!;
    final patching = (rect: rect, landed: landed);
    _standing.patching.add(patching);
    unawaited(
      landed.then((_) {
        if (_standing.patching.remove(patching) && mounted) {
          _repaint.value += 1;
        }
      }),
    );
  }

  /// Lets go of what is shown, and of [store]'s hold on its picture.
  void _letGo(FramePictureStore<FramePictureKey> store) {
    if (_shown case (:final image, picture: _)) {
      image.dispose();
      store.releasePin(_showing!);
    }
    _shown = null;
    _asItStands = null;
    _showing = null;
    _moving = null;
    _held = null;
    _standing.patching.clear();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePicturePainter(
        shown: _shown,
        // ⛔Not the stored cels where the view draws rows live: a frame of
        // no row is a page the pen may be drawing on.
        asItStands: _live ?? _asItStands,
        standing: _standing,
        catchUp: _catchUp,
        patchedBy: _live,
        viewport: widget.viewport,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
        repaint: Listenable.merge([_repaint, _liveChanges]),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _FramePicturePainter extends CustomPainter {
  _FramePicturePainter({
    required this.shown,
    required this.asItStands,
    required this.standing,
    required this.catchUp,
    required this.patchedBy,
    required this.viewport,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Shown shown;

  /// The frame as it stands, drawn where [shown] is not
  /// ([StackedFrame.paintOnScreen]).
  final StackedFrame? asItStands;

  /// What of the frame is drawn as it stands over [shown] — whole, or where
  /// patches are on their way into it, by [patchedBy] until their texels
  /// are in.
  final _DrawnAsItStands standing;

  /// Puts what the live rows moved into [standing] before it is read
  /// ([_FramePictureViewState._catchUp]).
  final VoidCallback catchUp;
  final StackedFrame? patchedBy;
  final CanvasViewport viewport;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    catchUp();
    final screen = Offset.zero & size;
    canvas.save();
    canvas.clipRect(screen);
    final shown = standing.whole ? null : this.shown;
    if (shown case (:final picture, :final image)) {
      final landing = patchedBy == null
          ? null
          : _onScreen([
              for (final patching in standing.patching) patching.rect,
            ]);
      // 🚨A patch still landing is drawn by the walk ALONE: the picture
      // under it holds what the rows were, and translucent ink laid over
      // that again — no paper under it — is the ink twice. Both sides are
      // cut on one edge, unsmoothed, so no pixel is drawn twice or not at
      // all.
      if (landing != null) {
        canvas.clipPath(
          ui.Path.combine(
            ui.PathOperation.difference,
            ui.Path()..addRect(screen),
            landing,
          ),
          doAntiAlias: false,
        );
      }
      canvas.save();
      applyViewportTransform(
        canvas,
        viewport,
        devicePixelRatio: devicePixelRatio,
      );
      _paintPicture(canvas, picture, image);
      canvas.restore();
      if (landing != null) {
        canvas.restore();
        canvas.save();
        canvas.clipRect(screen);
        canvas.clipPath(landing, doAntiAlias: false);
        _standOnScreen(canvas, size, patchedBy!);
      }
    } else if (asItStands case final frame?) {
      _standOnScreen(canvas, size, frame);
    }
    canvas.restore();
  }

  /// [rects], world rects, where the screen shows them — on the grid
  /// [applyViewportTransform] lays the picture on — or null where there are
  /// none.
  ui.Path? _onScreen(List<ui.Rect> rects) {
    if (rects.isEmpty) {
      return null;
    }
    final world = ui.Path();
    for (final rect in rects) {
      world.addRect(rect);
    }
    return world.transform(
      viewportTransformMatrix(
        renderSnappedViewport(viewport, devicePixelRatio),
      ).storage,
    );
  }

  void _standOnScreen(Canvas canvas, Size size, StackedFrame frame) =>
      frame.paintOnScreen(
        canvas,
        size,
        viewport: viewport,
        devicePixelRatio: devicePixelRatio,
      );

  /// The picture as its store says it is drawn ([FramePicture]): its image
  /// where its extent lies, the world outside it its colour, and every
  /// patch still landing over it with `BlendMode.src` — the image and its
  /// patches in a layer of their own, so a patch's clear texels cut
  /// through the picture alone.
  void _paintPicture(Canvas canvas, FramePicture picture, ui.Image image) {
    _paintOutside(canvas, picture.extent, picture.outside);
    final landing = picture.landing;
    if (landing.isNotEmpty) {
      canvas.saveLayer(picture.extent, Paint());
    }
    _lay(canvas, image, picture.extent);
    for (final patch in landing) {
      _lay(canvas, patch.image, patch.rect, blendMode: BlendMode.src);
    }
    if (landing.isNotEmpty) {
      canvas.restore();
    }
  }

  void _lay(
    Canvas canvas,
    ui.Image image,
    Rect at, {
    BlendMode blendMode = BlendMode.srcOver,
  }) => drawOnTheDisplay(
    canvas,
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    at,
    viewport: viewport,
    devicePixelRatio: devicePixelRatio,
    blendMode: blendMode,
  );

  void _paintOutside(Canvas canvas, Rect extent, Color outside) {
    if (outside.a == 0) {
      return;
    }
    canvas.save();
    canvas.clipRect(extent, clipOp: ui.ClipOp.difference);
    canvas.drawPaint(Paint()..color = outside);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FramePicturePainter oldDelegate) =>
      !identical(oldDelegate.shown?.image, shown?.image) ||
      !identical(oldDelegate.asItStands, asItStands) ||
      !identical(oldDelegate.patchedBy, patchedBy) ||
      oldDelegate.viewport != viewport ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
