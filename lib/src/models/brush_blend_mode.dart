import 'dart:ui' show BlendMode;

import 'separable_blend_mode.dart';

/// The BRUSH's own composite against the cel it paints on (R26 #9, BB-1).
///
/// Distinct from the layer blend: this decides how a STROKE lands on the
/// active cel's pixels — [color] is plain srcOver (the default), [behind]
/// paints only where the cel is still empty (PS 'Behind'), [erase] uses
/// the brush as an eraser (rides the existing dab erase flag), and the
/// separable modes share the layer vocabulary. Applied ONCE per stroke at
/// pen-up (never dab-by-dab — overlapping dabs must not double-apply),
/// with the live overlay previewing through the matching ui.BlendMode.
///
/// ⛔R26 #10 called this a HAND setting that preset application carries over
/// unchanged. That ruling is RETIRED — 유저 2026-09-08: 「툴/손 설정 구분
/// 없애고 모든 설정이 내보낼때 나르도록. 브러시든 지우개든 블렌드 모드를
/// 나른단거야 … 완벽통일해도 문제없으니」. A brush now simply HAS a blend the
/// way it has a size: [BrushShape.blendMode], non-null, [color] by default —
/// because [color] IS 通常, "normal" is a value here, never an absence. Every
/// intermediate contraption that existed to express "this brush departs from
/// the default" (a nullable pin, `clearBlendLock`, the padlock) is gone with
/// it, and import carries what the file says without asking whether it
/// departed. An ERASER is not a special case: it is a brush whose blend is
/// [erase], and exporting it exports that.
///
/// The fill and the stamp keep their own separate fields in
/// `BrushToolState`: they have no preset for a value to belong to.
enum BrushBlendMode {
  color,
  behind,
  erase,
  darken,
  multiply,
  colorBurn,
  lighten,
  screen,
  colorDodge,
  add,
  overlay,
  softLight,
  hardLight,
  difference,
  exclusion;

  /// The shared separable data for this mode, or `null` for the three
  /// porter-duff-style heads ([color]/[behind]/[erase]). The separable
  /// vocabulary (GPU blend + labels) lives once on [SeparableBlendMode].
  SeparableBlendMode? get separable => SeparableBlendMode.forName(name);

  /// Whether this mode composites through the SEPARABLE blend kernel at
  /// commit (everything except the three porter-duff-style modes).
  bool get isSeparable => separable != null;

  /// The GPU BlendMode this brush mode maps to.
  ///
  /// R27 #4: live STROKES no longer preview through this — every
  /// non-[color] mode pre-blends its overlay tiles with the commit's own
  /// CPU kernels (`preBlendStrokeOverlayPixels`), so the pixels on screen
  /// while drawing ARE the committed pixels, byte for byte. This mapping
  /// remains for [color]'s plain srcOver and as the identity the painter
  /// keys its fallback branch on.
  BlendMode get previewBlendMode => switch (this) {
    color => BlendMode.srcOver,
    behind => BlendMode.dstOver,
    erase => BlendMode.dstOut,
    _ => separable!.blendMode,
  };

  /// The industry-standard English label.
  ///
  /// ja followed the PS/CSP Japanese terms (user rule 07-22: ja localized
  /// first, other languages keep the shared English vocabulary). ↩️Every
  /// language has its own words now (유저 2026-09-15,
  /// blend-mode-names-language-Q1: 「블렌드 모드도 모든 언어로 번역」), keyed
  /// by `name` in the string tables — `BrushBlendModeWords` in
  /// `ui/text/model_vocabulary.dart`, which a model cannot import.
  String get label => switch (this) {
    color => 'Color',
    behind => 'Behind',
    erase => 'Erase',
    _ => separable!.label,
  };

  String toJson() => name;

  /// The mode written under [name], or null when it is absent or unknown.
  ///
  /// ⚠️THE one place that turns a stored name back into a mode. Every
  /// reader wants one of two things on a miss — 通常, or "nothing was
  /// stored" — and both are this plus a `??`, so neither is worth its own
  /// loop (two private copies of exactly this scan were written and
  /// deleted on 2026-09-08; the clone ratchet caught the second).
  static BrushBlendMode? named(String? name) {
    for (final mode in values) {
      if (mode.name == name) {
        return mode;
      }
    }
    return null;
  }

  /// The mode written under [json], falling back to 通常 — an unreadable
  /// blend must not fail the load that carries it.
  static BrushBlendMode fromJson(Object? json) =>
      named(json is String ? json : null) ?? color;
}
