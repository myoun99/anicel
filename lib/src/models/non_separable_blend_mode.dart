import 'dart:ui' show BlendMode;

/// The blend modes whose B is a COLOUR of three rather than one channel at a
/// time — W3C Compositing's non-separable four and Photoshop's darker and
/// lighter colour, which keep one of the two colours whole. Shared by
/// [BrushBlendMode] (a stroke's composite onto the cel) and [LayerBlendMode]
/// (a layer's composite onto everything below), as [SeparableBlendMode] is
/// for the per-channel ones: their GPU [BlendMode] and English labels live
/// here ONCE.
///
/// 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」) gave the layer
/// list the six the brush already had, and a second enum carrying the same
/// six labels would be the copy D5 took out of the separable vocabulary.
///
/// 🚨NOT EVERY ONE HAS A GPU BLEND: darker and lighter colour have none, so
/// a layer in them is composed over its backdrop instead
/// ([LayerBlendMode.needsItsBackdrop]); the brush composites all six on the
/// CPU (`brush_stroke_blend.dart`, `_ChannelMix`).
enum NonSeparableBlendMode {
  darkerColor(null, 'Darker Color'),
  lighterColor(null, 'Lighter Color'),
  hue(BlendMode.hue, 'Hue'),
  saturation(BlendMode.saturation, 'Saturation'),
  // Photoshop's and Clip Studio's "Color" (カラー) — named apart because the
  // brush's `color` already names its 通常.
  chroma(BlendMode.color, 'Color'),
  luminosity(BlendMode.luminosity, 'Luminosity');

  const NonSeparableBlendMode(this.blendMode, this.label);

  /// The GPU blend this mode composites through, or null where the GPU has
  /// none (see the class doc).
  final BlendMode? blendMode;

  /// The industry-standard English label; every language's own words are
  /// keyed by `name` in the string tables, where the separable and head
  /// modes are keyed too.
  final String label;

  /// The mode whose `name` equals [name], or `null` when none does.
  static NonSeparableBlendMode? forName(String name) =>
      values.asNameMap()[name];
}
