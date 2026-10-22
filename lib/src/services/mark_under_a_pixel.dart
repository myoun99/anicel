import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';

/// 🚨A MARK NARROWER THAN A PIXEL LANDS ONE PIXEL ACROSS, ITS OPACITY
/// SCALED BY ITS WIDTH (size-rack-0-7-under-the-brush-floor — 유저
/// 2026-10-12 「브러시 사이즈 최소치만 0.1까지 내림」, 10-17 「다른부분
/// 발견되는거있으면 법 통일」).
///
/// What lands a mark takes a pixel by its centre: both kernels skip a pixel
/// whose centre lies outside the dab (`|tip| > radius`), and an area — the
/// shape tool's plain line — takes the pixels whose centre it covers. So a
/// mark under a pixel landed only where a pixel centre happened to fall
/// inside it: a 0.5px line drew whole or not at all by where it lay, and a
/// 0.1px one almost nowhere. One pixel across reaches a pixel centre, and
/// the width the mark lacks becomes how far it may build — a dab's opacity
/// is its ceiling (F-205) — so a line w < 1 wide settles at w.
///
/// ⛔Not with anti-aliasing off: that lays no partly covered pixel (H39
/// 「진짜 안티앨리어싱 완전없었으면」), so its pixel-wide mark lands whole.
/// A width of zero or less is left as it is — nothing here says what it is.
({double width, double opacity}) markUnderAPixel(
  double width, {
  required bool antiAliased,
}) => width > 0.0 && width < 1.0
    ? (width: 1.0, opacity: antiAliased ? width : 1.0)
    : (width: width, opacity: 1.0);

/// [dab] as [markUnderAPixel] lands it — every dab a stroke lays comes
/// through here (`BrushTipStampCache.resolveDab`). A stamp lands its own
/// picture 1:1 and is left as it is.
BrushDab liftedToOnePixel(BrushDab dab) {
  if (dab.stamp != null) {
    return dab;
  }
  final landed = markUnderAPixel(
    dab.size,
    antiAliased: dab.antiAlias != BrushAntiAlias.none,
  );
  return landed.width == dab.size
      ? dab
      : dab.copyWith(
          size: landed.width,
          opacity: dab.opacity * landed.opacity,
        );
}
