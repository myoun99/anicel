/// The separable blend modes — one B(Cs, Cd) per channel — shared by
/// [BrushBlendMode] (a stroke's composite onto the cel), [LayerBlendMode] (a
/// layer/group's composite onto everything below) and the dual tip's
/// composite. Their English labels live here ONCE, so the vocabularies
/// cannot drift — before D5 each enum carried its own copy of all three
/// tables, and a changed label or mapping had to be edited in both.
///
/// Each blend enum still lists these as its own enum values (it needs them for
/// exhaustive `switch` and by-name JSON) and resolves the shared data through
/// [forName], keyed on the enum value's `name`. `separable_blend_mode_test`
/// pins that every separable case on both enums maps here, so a renamed value
/// fails a test instead of resolving to `null` at runtime.
///
/// 🚨★NONE IS A GPU BLEND. The BRUSH composites every one on the CPU,
/// through the commit's own kernel, and a LAYER in one is composed over its
/// backdrop by the blend shader ([LayerBlendMode.needsItsBackdrop]) — add
/// alone is the GPU's `plus`, the premultiplied saturating add both sides
/// mean by it.
/// ↩️A column here mapped the twelve the layer list always offered onto
/// Impeller's blends, and the seven Photoshop and Clip Studio add (linear
/// burn … divide, brush-fidelity 유저 2026-10-17 Q3 「13개 + 클튜의 발광
/// 둘」) had none; the layer list took those seven in brush-fidelity-Q4
/// (유저 2026-10-17 「레이어까지 같이」), and every one went to the shader in
/// a-blurred-folder-cut-by-the-view-moves-on-vulkan Q4 (유저 2026-10-22).
enum SeparableBlendMode {
  darken('Darken'),
  multiply('Multiply'),
  colorBurn('Color Burn'),
  linearBurn('Linear Burn'),
  subtract('Subtract'),
  lighten('Lighten'),
  screen('Screen'),
  colorDodge('Color Dodge'),
  add('Add'),
  overlay('Overlay'),
  softLight('Soft Light'),
  hardLight('Hard Light'),
  difference('Difference'),
  vividLight('Vivid Light'),
  linearLight('Linear Light'),
  pinLight('Pin Light'),
  hardMix('Hard Mix'),
  exclusion('Exclusion'),
  divide('Divide');

  const SeparableBlendMode(this.label);

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
  /// `normal`) and the six that mix the three channels
  /// ([NonSeparableBlendMode]) have no counterpart here.
  static SeparableBlendMode? forName(String name) => values.asNameMap()[name];
}
