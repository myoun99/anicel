import 'dart:math' as math;

import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';

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
/// 0.1px one almost nowhere. One pixel across reaches a pixel centre more
/// often — ⚠️not wherever it lies: a dab on a pixel's corner has every
/// centre √2/2 away ([onItsPixel] says what that cost and lands the aliased
/// one; the anti-aliased one is board
/// `a-one-pixel-dab-drops-out-by-where-it-lies-Q1`) — and the width the
/// mark lacks becomes how far it may build — a dab's opacity is its ceiling
/// (F-205) — so a line w < 1 wide settles at w.
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

/// [dab] as [markUnderAPixel] lands it, and — with anti-aliasing off — on
/// its pixel ([onItsPixel]). Every dab a stroke lays comes through here
/// (`BrushTipStampCache.resolveDab`). A stamp lands its own picture 1:1 and
/// is left as it is.
BrushDab liftedToOnePixel(BrushDab dab) {
  if (dab.stamp != null) {
    return dab;
  }
  final antiAliased = dab.antiAlias != BrushAntiAlias.none;
  final landed = markUnderAPixel(dab.size, antiAliased: antiAliased);
  final lifted = landed.width == dab.size
      ? dab
      : dab.copyWith(
          size: landed.width,
          opacity: dab.opacity * landed.opacity,
        );
  return antiAliased ? lifted : onItsPixel(lifted);
}

/// 🚨AN ALIASED ROUND DAB TOO SMALL TO BE SURE OF A PIXEL CENTRE STANDS ON
/// THE CENTRE OF THE PIXEL ITS OWN CENTRE IS IN
/// (a-one-pixel-dab-drops-out-by-where-it-lies, 2026-10-24).
///
/// With anti-aliasing off a pixel is laid when the dab covers its centre
/// at least half ([BrushAntiAlias.none]) — within `r(1 + hardness)/2` of
/// the dab's centre along its narrow axis. The pixel the dab's centre is in
/// can have its own centre √2/2 away (a dab on its corner), and a dab
/// reaching less than that laid nothing there: measured, a one-pixel line
/// along a row's edge vanished whole, and at 10° 14 of its 37 columns were
/// empty — what the pixel-wide mark above was lifted to reach. Stood on
/// that pixel's centre it lays that pixel (「AA 없음은 중심이 든 픽셀
/// 하나」), and, too small to reach the next centre a pixel away, no other.
/// A dab that reaches √2/2 is sure of the pixel wherever it lies, and is
/// left where it is.
///
/// ⛔Only an analytic round tip: its centre is its fullest point, so the
/// pixel it stands on is laid whatever its hardness. A raster tip's centre
/// may be a hole in its grain.
BrushDab onItsPixel(BrushDab dab) {
  if (dab.tipMask != null || dab.tipShape != BrushTipShape.round) {
    return dab;
  }
  final narrowRadius = dab.size * dab.roundness / 2.0;
  if (narrowRadius * (1.0 + dab.hardness) / 2.0 >= math.sqrt1_2) {
    return dab;
  }
  return dab.copyWith(
    center: CanvasPoint(
      x: dab.center.x.floorToDouble() + 0.5,
      y: dab.center.y.floorToDouble() + 0.5,
    ),
  );
}
