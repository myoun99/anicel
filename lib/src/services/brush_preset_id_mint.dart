import '../models/brush_preset_id.dart';

/// Hands out preset ids that do not collide inside one imported file.
///
/// ⛔TWO DECODERS MINTED THEM. A brush pack may name two brushes the same
/// (the same bitmap with different settings is common in artist packs),
/// so ids have to be de-collided — and the suffixes are ORDER-DETERMINISTIC
/// on purpose, so re-importing the same file replaces its presets instead
/// of duplicating them. A second minter with its own numbering would break
/// that quietly, on the second import.
class BrushPresetIdMint {
  final Set<String> _used = <String>{};

  BrushPresetId next(String base) {
    if (_used.add(base)) {
      return BrushPresetId(base);
    }
    var suffix = 2;
    while (!_used.add('$base-$suffix')) {
      suffix += 1;
    }
    return BrushPresetId('$base-$suffix');
  }
}
