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
class CelLooks {
  CelLooks(this.store);

  /// The store looked at.
  final BrushFrameStore store;

  var _thisFrame = <_Looked, BitmapSurface?>{};
  var _frameBefore = <_Looked, BitmapSurface?>{};

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

  /// [cel]'s pixels at [canvasSize] as a look reads them
  /// ([BrushFrameStore.currentSurfaceWithoutReplay]) — this frame's, or the
  /// frame before's, else read now — or null where the store keeps none at
  /// that size.
  ///
  /// A movie's picture is read and never held: the movie tier keeps it,
  /// and its budget says for how long.
  BitmapSurface? surfaceOf(
    BrushFrameKey cel, {
    required CanvasSize canvasSize,
  }) {
    if (store.hasMovieCel(cel, canvasSize)) {
      return _read(cel, canvasSize);
    }
    final looked = _lookedAt(cel, canvasSize);
    if (_thisFrame.containsKey(looked)) {
      return _thisFrame[looked];
    }
    return _thisFrame[looked] = _frameBefore.containsKey(looked)
        ? _frameBefore.remove(looked)
        : _read(cel, canvasSize);
  }

  /// Keeps what [cels] were looked at as at [canvasSize] for one more
  /// frame — the cels of a picture handed again, which looks at none of
  /// them: without it, the frame after a held drawing that changes one row
  /// would read every row again.
  void carry(Iterable<BrushFrameKey> cels, {required CanvasSize canvasSize}) {
    for (final cel in cels) {
      final looked = _lookedAt(cel, canvasSize);
      if (!_thisFrame.containsKey(looked) && _frameBefore.containsKey(looked)) {
        _thisFrame[looked] = _frameBefore.remove(looked);
      }
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
