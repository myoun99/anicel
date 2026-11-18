import 'package:gpu_engine/gpu_engine.dart';

import '../services/canvas_flood_fill.dart' show FloodFillRegion;

/// The mask the range a fill holds is marked under on the engine
/// (`EngineMark.mask`), by the cover it was made of: made once for as long
/// as the range lasts — a press pushing its checker marks the same one —
/// and let go by the first frame that marks none ([settle]). One range at
/// most, the range in hand: what it holds is that range's box, a byte a
/// pixel.
final class EngineRangeMask {
  /// The masks of ranges marked on [composite]'s engine.
  EngineRangeMask(this._composite);

  final GpuComposite _composite;

  ({FloodFillRegion cover, GpuMask mask})? _kept;

  /// Whether a frame asked for a mask since the last [settle].
  bool _asked = false;

  /// [cover]'s mask: the one kept, or made in its place.
  GpuMask of(FloodFillRegion cover) {
    _asked = true;
    final kept = _kept;
    if (kept != null && identical(kept.cover, cover)) {
      return kept.mask;
    }
    kept?.mask.free();
    final mask = GpuMask(
      _composite,
      cover.mask,
      x: cover.left,
      y: cover.top,
      width: cover.width,
      height: cover.height,
    );
    _kept = (cover: cover, mask: mask);
    return mask;
  }

  /// Ends a frame: the mask kept is let go where the frame marked none.
  void settle() {
    if (!_asked) {
      free();
    }
    _asked = false;
  }

  /// Lets go of the mask kept; a plan that names it keeps its own hold.
  void free() {
    _kept?.mask.free();
    _kept = null;
  }
}
