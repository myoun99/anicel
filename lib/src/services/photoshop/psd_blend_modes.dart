import '../../models/layer_blend_mode.dart';

/// Photoshop's four-character blend codes, each the one [LayerBlendMode] it
/// is. Read both ways: a document read in takes its rows' modes from it
/// (`psd_layer_plan.dart`), and one written out names them from it
/// ([psdBlendKeyOf]) — so the two directions cannot drift apart.
///
/// Everything absent from this map arrives as [LayerBlendMode.normal] with
/// the layer named in a warning: silently drawing "dissolve" as normal is a
/// picture that is wrong in a way nobody can see the reason for.
///
/// ↩️Linear burn and the twelve others Photoshop has beyond our first
/// fourteen came in that way until brush-fidelity-Q4 (유저 2026-10-17
/// 「레이어까지 같이」) gave a layer every mode the brush has.
const Map<String, LayerBlendMode> psdBlendModes = {
  'pass': LayerBlendMode.passThrough,
  'norm': LayerBlendMode.normal,
  'dark': LayerBlendMode.darken,
  'mul ': LayerBlendMode.multiply,
  'idiv': LayerBlendMode.colorBurn,
  'lbrn': LayerBlendMode.linearBurn,
  'fsub': LayerBlendMode.subtract,
  'lite': LayerBlendMode.lighten,
  'scrn': LayerBlendMode.screen,
  'div ': LayerBlendMode.colorDodge,
  'lddg': LayerBlendMode.add,
  'over': LayerBlendMode.overlay,
  'sLit': LayerBlendMode.softLight,
  'hLit': LayerBlendMode.hardLight,
  'diff': LayerBlendMode.difference,
  'vLit': LayerBlendMode.vividLight,
  'lLit': LayerBlendMode.linearLight,
  'pLit': LayerBlendMode.pinLight,
  'hMix': LayerBlendMode.hardMix,
  'smud': LayerBlendMode.exclusion,
  'dkCl': LayerBlendMode.darkerColor,
  'lgCl': LayerBlendMode.lighterColor,
  'fdiv': LayerBlendMode.divide,
  'hue ': LayerBlendMode.hue,
  'sat ': LayerBlendMode.saturation,
  'colr': LayerBlendMode.chroma,
  'lum ': LayerBlendMode.luminosity,
};

/// The code Photoshop stores [mode] under — every mode has one.
String psdBlendKeyOf(LayerBlendMode mode) => psdBlendModes.entries
    .firstWhere((entry) => entry.value == mode)
    .key;
