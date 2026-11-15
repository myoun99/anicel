import '../core/in_flight.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import 'brush_frame_store.dart';

/// The cels a render looks at ([CelRead.look]) — a film's frames, a
/// still, a panel's picture — each held for ONE frame after the last frame
/// that looked at it, under what was looked at: the cel, the revision it
/// stood at and the canvas size it was read at.
///
/// 🚨★★★A RENDER LOOKS AND LETS GO (card `render-reads-thaw-into-hot`;
/// `gpu-canonical-store-Q10`, 유저 2026-11-10 「추천대로 법 지키도록」): a
/// picture made for a file or a panel reads the cels nobody is drawing on
/// and leaves the store as it found them — no hot tier, no place in line,
/// no display cache. What a look decodes is held here, outside every
/// budget, so only what the frame being drawn and the one before it looked
/// at: a cel drawn by frames in a row is read once for the row.
///
/// ↩️On the engine (7′), until that answer, a render read its cels as
/// playback reads them — thawed hot ([BrushFrameStore.thawAhead]), the
/// display cache seeded — which is what took a 13-cut film's storyboard
/// from 149 to 529MB of the hot tier on 09-28.
///
/// ⚠️The second hold by two frames: the export's pictures are held so too
/// (`HeldPictures`). Apart while they are two — a picture is made in turns
/// and let go by hand, a cel's pixels are read at once and left to the
/// collector. A third is where they share a law.
///
/// 🚨WHAT A FRAME READS AHEAD IS ITS OWN UNTIL IT IS DRAWN ([ahead]): a
/// kept cel is thawed off the UI thread ([BrushFrameStore.lookAhead]) before
/// the frame draws, and frames are made several at a time — a walk asks for
/// the next ones before it waits — so the looks have gone on a frame or two
/// by the time the last cel of one is in. ⛔Not held by the looks alone: a
/// cel read for the third frame of three is let go by the first two as
/// they are drawn, and its frame would read it again as it draws, on the UI
/// thread. So each frame holds what it read ([LooksAhead]), and the looks
/// hold it beside that for the frame after.
class CelLooks {
  CelLooks(this.store);

  /// The store looked at.
  final BrushFrameStore store;

  var _thisFrame = <_Looked, BitmapSurface?>{};
  var _frameBefore = <_Looked, BitmapSurface?>{};

  /// What [ahead] is reading now: a frame that looks at a cel another frame
  /// is reading waits for that reading.
  final InFlight<_Looked, BitmapSurface?> _reading = InFlight();

  /// How many cels have been read from [store] (test hook) — a cel held
  /// from the frame before reads none.
  int get reads => _reads;
  int _reads = 0;

  /// How many cels are held right now (test hook): what this frame and the
  /// frame before it looked at, and found something in.
  int get held => [
    ..._thisFrame.values,
    ..._frameBefore.values,
  ].nonNulls.length;

  /// Every surface held now — this frame's and the frame before's — for
  /// whoever weighs what a look keeps outside the store's budgets
  /// (`collectMemoryCensus`); what a frame read ahead and still holds is
  /// that frame's to tell ([LooksAhead.surfaces]).
  Iterable<BitmapSurface> get surfaces => [
    ..._thisFrame.values.nonNulls,
    ..._frameBefore.values.nonNulls,
  ];

  /// [cel]'s pixels at [canvasSize] as a look reads them
  /// ([BrushFrameStore.currentSurfaceWithoutReplay]) — this frame's, or the
  /// frame before's, or what its frame read [ahead], else read now — or
  /// null where the store keeps none at that size.
  ///
  /// A movie's picture is read and never held: the movie tier keeps it,
  /// and its budget says for how long.
  BitmapSurface? surfaceOf(
    BrushFrameKey cel, {
    required CanvasSize canvasSize,
    LooksAhead? ahead,
  }) {
    if (store.hasMovieCel(cel, canvasSize)) {
      return _read(cel, canvasSize);
    }
    final looked = _lookedAt(cel, canvasSize);
    if (!_takes(looked)) {
      final read = ahead?._read;
      _thisFrame[looked] = read != null && read.containsKey(looked)
          ? read[looked]
          : _read(cel, canvasSize);
    }
    return _thisFrame[looked];
  }

  /// Whether [cel] at [canvasSize] is in hand — held, or a movie's, which
  /// the movie tier holds: [surfaceOf] would read nothing.
  bool holds(BrushFrameKey cel, {required CanvasSize canvasSize}) {
    if (store.hasMovieCel(cel, canvasSize)) {
      return true;
    }
    final looked = _lookedAt(cel, canvasSize);
    return _thisFrame.containsKey(looked) || _frameBefore.containsKey(looked);
  }

  /// Reads [cels] at [canvasSize] AHEAD of a frame's drawing, off the UI
  /// thread ([BrushFrameStore.lookAhead]): each held as [surfaceOf] holds
  /// it, one held already or being read for another frame read by no one
  /// again — and all of them in hand for that frame's drawing, whatever
  /// frames the looks go on to before it ([LooksAhead]).
  ///
  /// Never throws: a cel that will not read is left to the drawing, which
  /// reads it and says why ([surfaceOf]). A movie's is the movie tier's.
  Future<LooksAhead> ahead(
    Iterable<BrushFrameKey> cels, {
    required CanvasSize canvasSize,
  }) async {
    final read = <_Looked, BitmapSurface?>{};
    await Future.wait([
      for (final cel in cels)
        if (!store.hasMovieCel(cel, canvasSize))
          _readAheadInto(read, cel, canvasSize),
    ]);
    return LooksAhead._(read);
  }

  Future<void> _readAheadInto(
    Map<_Looked, BitmapSurface?> read,
    BrushFrameKey cel,
    CanvasSize canvasSize,
  ) async {
    final asked = _lookedAt(cel, canvasSize);
    if (!_takes(asked)) {
      final BitmapSurface? surface;
      try {
        surface = await _reading.join(asked, () {
          _reads += 1;
          return store.lookAhead(asked.cel, canvasSize: canvasSize);
        });
      } on Object {
        return;
      }
      // An edit that landed while it was read gave the cel another
      // revision, and what was read is not known to be of either: the
      // drawing reads it.
      if (_lookedAt(cel, canvasSize) != asked) {
        return;
      }
      _thisFrame[asked] = surface;
    }
    read[asked] = _thisFrame[asked];
  }

  /// Whether [looked] is held — this frame's, or the frame before's, which
  /// this frame takes.
  bool _takes(_Looked looked) {
    if (_thisFrame.containsKey(looked)) {
      return true;
    }
    if (!_frameBefore.containsKey(looked)) {
      return false;
    }
    _thisFrame[looked] = _frameBefore.remove(looked);
    return true;
  }

  /// Keeps what [cels] were looked at as at [canvasSize] for one more
  /// frame — the cels of a picture handed again, which looks at none of
  /// them: without it, the frame after a held drawing that changes one row
  /// would read every row again.
  void carry(Iterable<BrushFrameKey> cels, {required CanvasSize canvasSize}) {
    for (final cel in cels) {
      _takes(_lookedAt(cel, canvasSize));
    }
  }

  /// Starts the next frame: what the frame before the last one looked at,
  /// and the last one did not, is let go; what the last one looked at is
  /// kept for one more.
  void nextFrame() {
    _frameBefore = _thisFrame;
    _thisFrame = {};
  }

  /// Lets go of everything held — the run is over.
  void letGo() {
    _thisFrame = {};
    _frameBefore = {};
  }

  _Looked _lookedAt(BrushFrameKey cel, CanvasSize canvasSize) {
    final canonical = store.canonicalKeyOf(cel);
    return (
      cel: canonical,
      revision: store.sourceRevisionOf(canonical),
      canvasSize: canvasSize,
    );
  }

  BitmapSurface? _read(BrushFrameKey cel, CanvasSize canvasSize) {
    _reads += 1;
    return store.currentSurfaceWithoutReplay(
      cel,
      canvasSize: canvasSize,
      read: CelRead.look,
    );
  }
}

typedef _Looked = ({BrushFrameKey cel, int revision, CanvasSize canvasSize});

/// What one frame read ahead of its drawing ([CelLooks.ahead]): in hand for
/// that drawing ([CelLooks.surfaceOf]) whatever frames the looks went on to
/// meanwhile, and let go with the frame that holds it — nobody is told, so
/// nobody can forget to.
final class LooksAhead {
  LooksAhead._(this._read);

  final Map<_Looked, BitmapSurface?> _read;

  /// The surfaces read, for whoever weighs them while the frame holds this.
  Iterable<BitmapSurface> get surfaces => _read.values.nonNulls;
}
