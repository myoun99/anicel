import '../models/brush_tip_entry.dart';
import '../models/brush_tip_mask.dart';
import 'brush_tip_image_codec.dart';
import 'brush_tip_mask_defaults.dart';
import 'brush_preset_defaults.dart' show BuiltinBrushName;

/// The tips that ship with the app, as library entries.
///
/// These are GENERATED (fixed-seed, see `brush_tip_mask_defaults.dart`), so
/// they never touch the disk: the library merges them in on every launch and
/// the index only records the tips a user brought. That also keeps their
/// bytes exactly what the fingerprint tests lock — a file could drift, a
/// generator cannot.
final List<BrushTipEntry> defaultBrushTipEntries = List.unmodifiable([
  _entry(chalkBrushTipMask, 'Chalk'),
  _entry(splatterBrushTipMask, 'Splatter'),
  _entry(grainBrushTipMask, 'Grain'),
  _entry(bristleBrushTipMask, 'Bristle'),
  _entry(spongeBrushTipMask, 'Sponge'),
  _entry(wetBlotBrushTipMask, 'Wet Blot'),
  _entry(starBrushTipMask, 'Star'),
  _entry(flakeBrushTipMask, 'Snowflake'),
  _entry(ringBrushTipMask, 'Ring'),
  _entry(leafBrushTipMask, 'Leaf'),
  _entry(paperGrainTextureMask, 'Paper Grain'),
  _entry(canvasWeaveTextureMask, 'Canvas Weave'),
]);

BrushTipEntry _entry(BrushTipMask mask, String name) => BrushTipEntry(
  id: mask.id,
  name: name,
  size: mask.size,
  thumbnail: brushTipThumbnailAlpha(mask, side: brushTipThumbnailSide),
  mask: mask,
  builtIn: true,
);

/// [defaultBrushTipEntries], each named by [nameOf] — made at every launch,
/// since the tips are generated and never stored.
List<BrushTipEntry> namedDefaultBrushTips(BuiltinBrushName nameOf) => [
  for (final entry in defaultBrushTipEntries)
    entry.copyWith(name: nameOf(entry.id, entry.name)),
];
