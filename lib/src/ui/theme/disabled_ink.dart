import 'dart:ui' show Color;

/// 🚨★★★**A DISABLED CONTROL DIMS ITS OWN COLOURS. IT NEVER WEARS A LAYER.**
///
/// 유저 확정 2026-09-22 (보드 `a-disabled-bar-dims-without-a-layer-Q1`:
/// 「요소별로 흐리게 칠한다」), after the panel sweep measured what the
/// alternative costs.
///
/// `Opacity` is the obvious way to dim a group of pixels and it is the
/// expensive one: `RenderOpacity` composites at ANY alpha above zero, so it
/// is a repaint boundary — and a boundary anywhere inside a panel makes that
/// panel's `StaticRaster` give up and pay its FULL raster price on every
/// frame the app produces, looking identical while it does. 🔬Measured
/// 2026-09-22: one disabled `FieldSlider` cost the whole brush settings
/// panel its bake.
///
/// ⚠️The two are not pixel-identical where a control's own pieces overlap
/// (a value text over its fill picks up 24% of the fill). Everything that
/// does not overlap is the pixel that was there before.
///
/// ⛔This is for a control that IS its own ground — a bar, a well, a
/// swatch. A control whose ground stays put dims its FOREGROUND instead and
/// already has a home for that: `AppIconButton`'s `disabledForegroundColor`,
/// `DragValueLabel`'s disabled text.
const double disabledInkOpacity = 0.4;

/// [color] as [enabled] draws it — itself, or [disabledInkOpacity] of itself.
Color dimmedIfDisabled(Color color, {required bool enabled}) => enabled
    ? color
    : color.withValues(alpha: color.a * disabledInkOpacity);
