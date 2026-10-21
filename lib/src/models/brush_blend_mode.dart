import 'dart:ui' show BlendMode;

import 'separable_blend_mode.dart';

/// The BRUSH's own composite against the cel it paints on (R26 #9, BB-1).
///
/// Distinct from the layer blend: this decides how a STROKE lands on the
/// active cel's pixels — [color] is plain srcOver (the default), [behind]
/// paints only where the cel is still empty (PS 'Behind'), [erase] uses
/// the brush as an eraser (rides the existing dab erase flag), the
/// separable modes share the layer vocabulary, and the six from
/// [darkerColor] on mix the three channels — the brush's own. Applied ONCE
/// per stroke at pen-up (never dab-by-dab — overlapping dabs must not
/// double-apply), with the live overlay pre-blended by the same kernel
/// (R27 #4).
///
/// The ORDER is the list the blend flyout shows and the order its default
/// shortcuts F1–F12 are handed out in (I-31): the three heads, then Clip
/// Studio's 合成モード order (brush-fidelity-Q5).
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
  // ⚠️Photoshop's and Clip Studio's "Color" (カラー): [color] already
  // names 通常, the default every stored brush carries.
  chroma,
  luminosity;

  /// The shared separable data for this mode, or `null` for the three
  /// porter-duff-style heads ([color]/[behind]/[erase]) and the six that
  /// mix the channels. The separable vocabulary (GPU blend + labels) lives
  /// once on [SeparableBlendMode].
  SeparableBlendMode? get separable => SeparableBlendMode.forName(name);

  /// Whether this mode lands through the STROKE BLEND KERNEL — the whole
  /// stroke blended once against the cel (BB-1) — rather than the ordinary
  /// stamp kernels: everything but [color]'s srcOver and [erase]'s dstOut.
  ///
  /// ↩️This was `isSeparable`, asked together with `== behind` at its one
  /// caller — the same set while every mode the kernel took was separable
  /// or [behind]. The six that mix the channels are neither, and a stamp
  /// blending through one would have gone dab by dab as plain colour.
  bool get blendsTheWholeStroke => this != color && this != erase;

  /// The GPU BlendMode this brush mode maps to, or null where the GPU has
  /// none (seven separable modes and darker/lighter colour).
  ///
  /// R27 #4: live STROKES no longer preview through this — every
  /// non-[color] mode pre-blends its overlay tiles with the commit's own
  /// CPU kernels (`preBlendStrokeOverlayPixels`), so the pixels on screen
  /// while drawing ARE the committed pixels, byte for byte. This mapping
  /// remains for [color]'s plain srcOver and as the identity the painter
  /// keys its fallback branch on.
  BlendMode? get previewBlendMode => switch (this) {
    color => BlendMode.srcOver,
    behind => BlendMode.dstOver,
    erase => BlendMode.dstOut,
    darkerColor || lighterColor => null,
    hue => BlendMode.hue,
    saturation => BlendMode.saturation,
    chroma => BlendMode.color,
    luminosity => BlendMode.luminosity,
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
  ///
  /// ↩️[color] read 'Color' from BB-1 (07-22) on — its enum name, where every
  /// other language reads "normal" (通常 · 표준 · Normal · 正常). It reads
  /// 'Normal' since [chroma] brought Photoshop's own 'Color' into the list.
  String get label => switch (this) {
    color => 'Normal',
    behind => 'Behind',
    erase => 'Erase',
    darkerColor => 'Darker Color',
    lighterColor => 'Lighter Color',
    hue => 'Hue',
    saturation => 'Saturation',
    chroma => 'Color',
    luminosity => 'Luminosity',
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
