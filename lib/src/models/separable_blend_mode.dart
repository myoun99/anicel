import 'dart:ui' show BlendMode;

/// The 12 separable blend modes shared, byte-for-byte, by [BrushBlendMode]
/// (a stroke's composite onto the cel) and [LayerBlendMode] (a layer/group's
/// composite onto everything below). Their GPU [BlendMode] and English
/// labels live here ONCE, so the two vocabularies cannot drift — before D5
/// each enum carried its own copy of all three tables, and a changed label
/// or mapping had to be edited in both.
///
/// Each blend enum still lists these as its own enum values (it needs them for
/// exhaustive `switch` and by-name JSON) and resolves the shared data through
/// [forName], keyed on the enum value's `name`. `separable_blend_mode_test`
/// pins that every separable case on both enums maps here, so a renamed value
/// fails a test instead of resolving to `null` at runtime.
enum SeparableBlendMode {
  darken(BlendMode.darken, 'Darken'),
  multiply(BlendMode.multiply, 'Multiply'),
  colorBurn(BlendMode.colorBurn, 'Color Burn'),
  lighten(BlendMode.lighten, 'Lighten'),
  screen(BlendMode.screen, 'Screen'),
  colorDodge(BlendMode.colorDodge, 'Color Dodge'),
  add(BlendMode.plus, 'Add'),
  overlay(BlendMode.overlay, 'Overlay'),
  softLight(BlendMode.softLight, 'Soft Light'),
  hardLight(BlendMode.hardLight, 'Hard Light'),
  difference(BlendMode.difference, 'Difference'),
  exclusion(BlendMode.exclusion, 'Exclusion');

  const SeparableBlendMode(this.blendMode, this.label);

  /// The GPU blend this separable mode composites through.
  final BlendMode blendMode;

  /// The industry-standard English label every paint tool shares.
  ///
  /// ja followed the PS/CSP Japanese terms, carried here as a third column
  /// (user rule 07-22: ja localized first, every other language keeps the
  /// shared English vocabulary). ↩️Every language has its own words now
  /// (유저 2026-09-15, blend-mode-names-language-Q1: 「블렌드 모드도 모든
  /// 언어로 번역」), keyed by `name` in the string tables where the layer and
  /// brush heads are keyed too, so one row still serves every list —
  /// `SeparableBlendModeWords` in `ui/text/model_vocabulary.dart`, which a
  /// model cannot import. The ja words did not change.
  final String label;

  /// The separable mode whose `name` equals [name], or `null` when none does
  /// — the non-separable heads (`color`/`behind`/`erase`, `passThrough`/
  /// `normal`) have no counterpart here.
  static SeparableBlendMode? forName(String name) => values.asNameMap()[name];
}
