import '../../models/layer_blend_mode.dart';

/// Photoshop's four-character blend codes, each the one [LayerBlendMode] it
/// is. Read both ways: a document read in takes its rows' modes from it
/// (`psd_layer_plan.dart`), and one written out names them from it
/// ([psdBlendKeyOf]) — so the two directions cannot drift apart.
///
/// Everything absent from this map arrives as [LayerBlendMode.normal] with
/// the layer named in a warning: silently drawing "linear burn" as normal
/// is a picture that is wrong in a way nobody can see the reason for.
const Map<String, LayerBlendMode> psdBlendModes = {
  'pass': LayerBlendMode.passThrough,
  'norm': LayerBlendMode.normal,
  'dark': LayerBlendMode.darken,
  'mul ': LayerBlendMode.multiply,
  'idiv': LayerBlendMode.colorBurn,
  'lite': LayerBlendMode.lighten,
  'scrn': LayerBlendMode.screen,
  'div ': LayerBlendMode.colorDodge,
  'lddg': LayerBlendMode.add,
  'over': LayerBlendMode.overlay,
  'sLit': LayerBlendMode.softLight,
  'hLit': LayerBlendMode.hardLight,
  'diff': LayerBlendMode.difference,
  'smud': LayerBlendMode.exclusion,
};

/// The code Photoshop stores [mode] under — every mode has one.
String psdBlendKeyOf(LayerBlendMode mode) => psdBlendModes.entries
    .firstWhere((entry) => entry.value == mode)
    .key;
