import 'dart:ui' show BlendMode;

import 'non_separable_blend_mode.dart';
import 'separable_blend_mode.dart';

/// The layer's compositing blend against everything below it (R26 #30).
///
/// Applied at COMPOSITE time on every route (playback cache, editing
/// stack, camera renders, export) — never baked into the artwork.
/// [normal] is plain srcOver and the serialized default (omitted from
/// JSON, so pre-blend files read back unchanged). ONE value across a link
/// group — 유저 2026-10-04 (F-278): 「겸용컷 블렌드모드도 공유하도록 하자 …
/// 보이기만 독립적으로 하고」 (`UpdateLayerBlendModeCommand`).
///
/// ↩️T9 (유저 확정 2026-08-13) had stopped it mirroring, along with the eye
/// and static opacity — the opacity mirrors again too (the same day's
/// answer), and the eye is still each use's own.
enum LayerBlendMode {
  /// GROUP ROWS ONLY — the folder's default, and Photoshop/CSP's ("통과").
  ///
  /// A pass-through folder creates NO composite buffer: its members blend
  /// straight against everything below the folder, exactly as if the
  /// folder were not there. It is a STRUCTURAL answer, not a blend
  /// formula — [paintBlendMode] never runs for it, because nothing is
  /// ever drawn as "the folder".
  ///
  /// Giving a folder any OTHER mode isolates it: the members compose into
  /// one buffer and that buffer blends once ([isolatesGroup]).
  passThrough,
  normal,
  // Clip Studio's order (brush-fidelity-Q5), the brush list's too.
  darken,
  multiply,
  colorBurn,
  linearBurn,
  subtract,
  lighten,
  screen,
  colorDodge,
  add,
  overlay,
  softLight,
  hardLight,
  difference,
  vividLight,
  linearLight,
  pinLight,
  hardMix,
  exclusion,
  darkerColor,
  lighterColor,
  divide,
  hue,
  saturation,
  chroma,
  luminosity;

  /// Whether this mode makes a GROUP isolate into its own buffer. Only
  /// [passThrough] does not — every real blend formula needs the group
  /// composed first to have something to blend.
  bool get isolatesGroup => this != passThrough;

  /// The shared per-channel data for this mode, or `null` for the two heads
  /// ([passThrough]/[normal]) and the six that mix the channels
  /// ([nonSeparable]). The vocabulary (GPU blend + labels) lives once on
  /// [SeparableBlendMode].
  SeparableBlendMode? get separable => SeparableBlendMode.forName(name);

  /// The shared data of the six whose blend is a colour of three, or `null`
  /// for every other mode ([NonSeparableBlendMode]).
  NonSeparableBlendMode? get nonSeparable =>
      NonSeparableBlendMode.forName(name);

  /// Whether a row in this mode is composed over a picture of everything
  /// below it ([CompositeBackdropBlend], `shaders/layer_blend.frag`) rather
  /// than drawn in a GPU blend: every mode but the two the GPU lays pixel by
  /// pixel where it draws — normal and add.
  ///
  /// 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a layer takes
  /// every mode the brush does, and the ones the GPU has no blend for were
  /// composed over their backdrop. 🗣️Then every advanced blend
  /// (a-blurred-folder-cut-by-the-view-moves-on-vulkan Q3 · Q4, 유저
  /// 2026-10-16 · 10-22: 「제일 미래지향적인 근본적인 해결」, 「골은 b」): the
  /// GPU's own blends for multiply, screen, overlay … each came with a defect
  /// and a detour of its own (F-243 · F-172 · F-287 · flutter#179547 · GLES
  /// rounding), and the shader is the brush's formula on every device.
  /// ↩️Until then the twelve the list always had and the four that mix the
  /// channels kept the GPU's blend.
  bool get needsItsBackdrop => switch (this) {
    passThrough || normal || add => false,
    _ => true,
  };

  /// The ui.Paint blend for the composite draw. [passThrough] answers
  /// srcOver defensively; a pass-through folder is never drawn as a node
  /// at all, so this should not be reached for it.
  ///
  /// ⛔Only for the modes drawn in a GPU blend. Every other never reaches a
  /// paint: the plan composes it over its backdrop ([needsItsBackdrop]).
  BlendMode get paintBlendMode => switch (this) {
    passThrough || normal => BlendMode.srcOver,
    add => BlendMode.plus,
    _ => throw StateError(
      '$name is composed over its backdrop (CompositeBackdropBlend), never '
      'painted in a blend',
    ),
  };

  /// The menu label (the industry-standard English terms every paint
  /// tool shares).
  ///
  /// Japanese followed Clip Studio's terms (user rule 07-22: ja localized
  /// first; every other language keeps the shared English vocabulary artists
  /// already read). ↩️Every language has its own words now (유저 2026-09-15,
  /// blend-mode-names-language-Q1: 「블렌드 모드도 모든 언어로 번역」), keyed
  /// by `name` in the string tables — `LayerBlendModeWords` in
  /// `ui/text/model_vocabulary.dart`, which a model cannot import.
  String get label => switch (this) {
    passThrough => 'Pass Through',
    normal => 'Normal',
    _ => separable?.label ?? nonSeparable!.label,
  };

  String toJson() => name;

  static LayerBlendMode fromJson(Object? json) {
    return LayerBlendMode.values.firstWhere(
      (value) => value.name == json,
      orElse: () => LayerBlendMode.normal,
    );
  }

  /// The modes a row of this kind may be given. Only GROUP rows offer
  /// [passThrough] — a drawing layer has no members to pass through.
  static List<LayerBlendMode> optionsFor({required bool isGroup}) => [
    for (final mode in LayerBlendMode.values)
      if (isGroup || mode != LayerBlendMode.passThrough) mode,
  ];
}
