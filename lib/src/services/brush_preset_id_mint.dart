import '../models/brush_preset_id.dart';

/// Hands out preset ids that collide with none it has handed out — nor with
/// any it was told are [taken].
///
/// ⛔TWO DECODERS MINTED THEM, and the library file's loader healed its own
/// duplicates with a third copy of this numbering. A brush pack may name two
/// brushes the same (the same bitmap with different settings is common in
/// artist packs), so ids have to be de-collided, one way everywhere.
///
/// ↩️The suffixes were ORDER-DETERMINISTIC so that re-importing the same
/// file REPLACED its presets. 유저 F-433 (2026-10-21): an import never deletes
/// a brush that is already there, and two brushes of one name live side by
/// side — so an id the library already holds is minted afresh here too
/// (`mergeImportedBrushPresets`), and nothing relies on the numbering any
/// more beyond its being free.
class BrushPresetIdMint {
  BrushPresetIdMint({Iterable<String> taken = const <String>[]})
    : _used = {...taken};

  final Set<String> _used;

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
