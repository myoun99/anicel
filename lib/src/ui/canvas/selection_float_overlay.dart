import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../core/signed_memo.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/layer_effect.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/cel_source_effect_pass.dart'
    show
        celSourceEffectSignature,
        celSourcePlugin,
        sameCelSourceEffectSignature;
import '../../services/cel_surface_as_shown.dart';
import '../../services/cel_text_laying.dart' show celTextPlatesOver;
import 'bitmap_surface_painter.dart';
import 'display_resample.dart' show drawImageRectOnThePixelGrid;
import 'landing_preview.dart';
import 'tile_picture_budget.dart' show TilePictureBudget;
import 'viewport_canvas_transform.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart' show ByList;

/// What a selection MOVE or TRANSFORM is holding, described in CANVAS space
/// so that whoever draws the active layer can draw it AT THAT LAYER'S DEPTH.
///
/// 🚨TS1 (유저: 변형 도중에 다른 레이어에 그려진 게 무시되서 라이브로 안보임 …
/// 변형중인 레이어 위에 흰 선으로 그린게있으면 그 선에 의해 가려져야하는데
/// 안가려짐): the float used to be a widget in the selection layer's own
/// Stack, which sits ABOVE the whole composite picture — so nothing could
/// ever occlude it, and the layers above only took effect once the pixels
/// landed in the cel. Live STROKES never had that problem because the merged
/// canvas draws them through the active layer's own painter, inside the one
/// picture that holds every layer. This is how the float gets into the same
/// place.
///
/// CANVAS space, not screen space: the slot's canvas arrives already
/// viewport-transformed (that is why the surface painter is asked for
/// `paintContentInto` there), so a screen-space offset would be wrong by the
/// zoom. The selection layer converts its drag delta on the way in.
///
/// The chrome does NOT come along — ants, handles and the confirm button stay
/// above everything, because they are about the drawing rather than part of
/// it.
@immutable
class SelectionFloatPaint implements LandingPreview {
  SelectionFloatPaint({
    this.surface,
    CanvasPoint? surfaceOffset,
    this.image,
    this.imageLeft = 0,
    this.imageTop = 0,
    this.clip,
    this.lands,
  }) : surfaceOffset = surfaceOffset ?? CanvasPoint(x: 0, y: 0);

  /// The float's own surface (a pure MOVE: the translation is byte-exact, so
  /// drawing the untouched lift at an offset IS the result).
  final BitmapSurfacePainter? surface;
  final CanvasPoint surfaceOffset;

  /// The resampled preview (an open warp: the preview IS the result, drawn
  /// unfiltered at the rect it will land in).
  final ui.Image? image;
  final double imageLeft;
  final double imageTop;

  /// The pasteboard wall, in canvas coordinates. The landing clips there too,
  /// so a preview that kept showing pixels past it would promise something
  /// the commit will not deliver.
  final Rect? clip;

  /// What this float lands as ([FloatLanding]) — null where nothing lands
  /// it here: a host with no composite behind it, a layer mounted alone.
  final FloatLanding? lands;

  bool get isEmpty => surface == null && image == null;

  /// Everything this float draws, in canvas space — what a buffer holding it
  /// has to cover — or [Rect.zero] when nothing floats.
  ///
  /// 🚨F-85 (유저 2026-09-11): 「변형시 캔버스 밖, 페이스트보드에서 그림이
  /// 사라짐」 — the composite sized the active slot by its committed surface
  /// alone, and a float carried past that surface's ink was cut at the edge.
  /// The same two draws [paintInto] makes, in the same order, under the same
  /// clip.
  @override
  Rect get drawnWorldRect {
    final image = this.image;
    final surface = this.surface;
    final Rect drawn;
    if (image != null) {
      drawn = Rect.fromLTWH(
        imageLeft,
        imageTop,
        image.width.toDouble(),
        image.height.toDouble(),
      );
    } else if (surface != null) {
      drawn = surface.drawnWorldRect.shift(
        Offset(surfaceOffset.x, surfaceOffset.y),
      );
    } else {
      return Rect.zero;
    }
    final bounds = clip;
    return bounds == null ? drawn : drawn.intersect(bounds);
  }

  @override
  void paintInto(Canvas canvas, {required double pixelRatio}) {
    if (isEmpty) {
      return;
    }
    canvas.save();
    final bounds = clip;
    if (bounds != null) {
      canvas.clipRect(bounds);
    }
    final image = this.image;
    if (image != null) {
      // The transform preview (P3a): the RESAMPLED float, drawn at the
      // canvas rect it will land in, through the ordinary viewport
      // transform.
      //
      // `FilterQuality.none` is not a performance choice — it is the
      // contract. The image already holds the destination pixels, one for
      // one, so any filtering here would show the user something other than
      // the bytes Enter is about to write. Zoomed in that means visible
      // blocks, which is correct: those blocks ARE the result. This replaced
      // three different screen approximations (a widget `Transform` for the
      // affine, a homography matrix for the quad, and a `drawVertices` mesh
      // at `FilterQuality.medium`), none of which agreed with the commit and
      // none of which agreed with each other.
      //
      // Its edge is one more texel boundary, cut on the grid as the
      // surface's coordinates are (`_drawImageAtTile`): drawn where it
      // falls, Impeller blends it inside a pixel.
      drawImageRectOnThePixelGrid(
        canvas,
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(
          imageLeft,
          imageTop,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        filterQuality: FilterQuality.none,
        pixelRatio: pixelRatio,
      );
    } else {
      canvas.translate(surfaceOffset.x, surfaceOffset.y);
      surface!.paintContentInto(canvas, pixelRatio: pixelRatio);
    }
    canvas.restore();
  }

  /// This float as a row whose leading colour keys are [keys] shows it:
  /// itself — CANVAS space, [canvasToRow] takes it into the row — where its
  /// own pixels are what its landing will show, and where they are not,
  /// what the landing shows there.
  ///
  /// 🚨★★★F-240 (유저 2026-09-29: 「변형중에도 필터 통일적용하도록 근본/구조적
  /// 해결」): WHAT FLOATS IS WHAT LANDS, on every row. Two things make a
  /// float's own pixels something else once they land, and neither is the
  /// float's to know: a row that keys its colours keys the landed pixels
  /// with the ink under them, and a cel's texts stand over its drawing, so
  /// a float that lands goes under them (transform-float-skips-colour-key,
  /// measured: a keyed sheet's ground showed bare while carried, 3,712
  /// pixels apart from its landing).
  ///
  /// So the row asks, and the answer is one of three:
  /// · no keys, no text under it — the float itself, as it always was: its
  ///   pixels are its landing's, but where a partly clear pixel lies over
  ///   ink (one apart at most, `a_carried_text_shows_what_it_lands_as_test`).
  /// · keys, and the landing there is the float's pixels landed on nothing
  ///   ([_KeyedFloat]) — made ONCE, and moved as the float moves.
  /// · anything else — the landing itself, made again at each place it is
  ///   carried to ([FloatLandsOn.landingShown]); the F-344-Q3 answer for a
  ///   text in hand (유저 2026-10-15: 「놓을 때와 같은 코드로 — 완전히
  ///   같게」), and as slow for a large float as it was for a large text.
  ///
  /// ⚠️A float drawn by no row — a host with no composite — is never asked:
  /// those hosts key nothing.
  RowFloat shownOn(List<ResolvedLayerEffect> keys, {Matrix4? canvasToRow}) {
    final RowFloat itself = (preview: this, canvasToRow: canvasToRow);
    final lands = this.lands;
    final holed = lands?.on.holed;
    if (lands == null || holed == null) {
      return itself;
    }
    // A plugin may change the cel anywhere (🗣️I-132-Q32 b): a float on a
    // row that runs one is always its landing.
    final plugin = celSourcePlugin(keys) != null;
    final keyed = celSourceEffectSignature(keys).isNotEmpty || plugin;
    final onGrid = lands.on.onCanvasGrid;
    final rect = drawnWorldRect;
    // Under a pose a rect of the float is no rect of the cel, so a cel that
    // carries a text at all may carry it under the float.
    final textUnder =
        holed.texts.isNotEmpty && (!onGrid || _textsTouch(holed, rect));
    if (!keyed && !textUnder) {
      return itself;
    }
    final floatSurface = surface?.surface;
    final landsOnNothing =
        floatSurface != null &&
        !plugin &&
        onGrid &&
        !textUnder &&
        !(_holdsPartlyClearPixels(lands.stamp) && _inkTouches(holed, rect));
    if (landsOnNothing) {
      return (
        preview: _KeyedFloat(this, _keyedFloatPainter(floatSurface, keys)),
        canvasToRow: canvasToRow,
      );
    }
    final landed = lands.on.landingShown(lands.stamp, keys);
    // The landing is on the cel's own grid, which is the row's.
    return landed == null ? itself : (preview: landed, canvasToRow: null);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionFloatPaint &&
          identical(other.surface, surface) &&
          other.surfaceOffset.x == surfaceOffset.x &&
          other.surfaceOffset.y == surfaceOffset.y &&
          identical(other.image, image) &&
          other.imageLeft == imageLeft &&
          other.imageTop == imageTop &&
          other.clip == clip &&
          _landsAlike(other.lands, lands);

  @override
  int get hashCode => Object.hash(
    identityHashCode(surface),
    surfaceOffset.x,
    surfaceOffset.y,
    identityHashCode(image),
    imageLeft,
    imageTop,
    clip,
    identityHashCode(lands?.on),
    identityHashCode(lands?.stamp.stamp),
    lands?.stamp.center,
  );
}

/// The cel a float was taken up from, as the lift holds it — what a row
/// asks where the float's own pixels are not what its landing will show
/// there ([SelectionFloatPaint.shownOn]). The lift answers
/// (`_CanvasPanelLift`): the hole it cut, and the landing its confirm makes.
abstract interface class FloatLandsOn {
  /// The cel with the hole the lift cut — what its row shows under the
  /// float — or null once the session holds the cel no more.
  BitmapSurface? get holed;

  /// Whether the cel's own grid is the canvas's: no pose stands between
  /// them, so a rect of the float is a rect of the cel.
  bool get onCanvasGrid;

  /// What the cel will SHOW where [stamp] — on the canvas — lands, through
  /// its row's leading [keys]: the landing its confirm makes, as its row
  /// shows it, drawn over the region it lands in in place of what the row
  /// shows there (`CelTextLanding`, the text in hand's own). In the cel's
  /// own space. Null when it lands nowhere, or the session holds the cel no
  /// more.
  ///
  /// ⚠️Made once for each place a hand carries the float to, and let go of
  /// by the lift that made it, once it is shown no more.
  LandingPreview? landingShown(
    BrushDab stamp,
    List<ResolvedLayerEffect> keys,
  );
}

/// What a float lands as: the stamp it shows, as a dab on the canvas, and
/// the cel it lands on.
typedef FloatLanding = ({BrushDab stamp, FloatLandsOn on});

/// Whether [a] and [b] land the same pixels in the same place on one cel.
bool _landsAlike(FloatLanding? a, FloatLanding? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  return identical(a.on, b.on) &&
      identical(a.stamp.stamp, b.stamp.stamp) &&
      a.stamp.center == b.stamp.center;
}

/// The float's own surface through its row's keys, by the surface: one per
/// lift (`_buildFloatSurface` keeps it for the session), so a carry moves
/// the keyed pixels and makes none — by the keys' values, as the keyed
/// surface and tile are kept.
final SignedMemo<List<double>, BitmapSurfacePainter> _keyedFloats =
    SignedMemo('selectionFloatKeyed', same: sameCelSourceEffectSignature);

BitmapSurfacePainter _keyedFloatPainter(
  BitmapSurface floatSurface,
  List<ResolvedLayerEffect> keys,
) => _keyedFloats.resolve(
  floatSurface,
  celSourceEffectSignature(keys),
  () => floatPainter(floatSurface, keys),
);

/// A painter of what floats — pixels a hand carries, as the row they float
/// in shows them ([celSurfaceAsShown], through its leading [keys]): drawn in
/// that row's own space by the painter it floats over, so it brings no
/// paper and is nobody's cel.
///
/// Nobody's cel: what it shows is counted under the picture budget's one
/// scope for floats ([TilePictureBudget.noLineage]). ↩️The level pyramid
/// filed a float's level tiles under it too — one scope, not one a float,
/// for the pyramid kept eight and a session of transforms would have
/// pushed out the brush's — until nothing drew a level tile
/// (one-picture-per-frame ②-5b-2).
BitmapSurfacePainter floatPainter(
  BitmapSurface surface,
  List<ResolvedLayerEffect> keys,
) => BitmapSurfacePainter(
  surface: celSurfaceAsShown(surface, keys),
  showTransparentBackground: false,
  lineage: TilePictureBudget.noLineage,
);

/// Whether [stamp] holds a pixel neither clear nor opaque — asked once of
/// each picture ([_partlyClear]).
bool _holdsPartlyClearPixels(BrushDab stamp) {
  final image = stamp.stamp;
  if (image == null) {
    return false;
  }
  return _partlyClear[image] ??= () {
    final rgba = image.rgba;
    for (var alpha = 3; alpha < rgba.length; alpha += 4) {
      final a = rgba[alpha];
      if (a != 0 && a != 255) {
        return true;
      }
    }
    return false;
  }();
}

final Expando<bool> _partlyClear = Expando('selectionFloatPartlyClear');

/// Whether [holed]'s ink reaches into [rect].
bool _inkTouches(BitmapSurface holed, Rect rect) {
  final ink = bitmapSurfaceContentBounds(holed);
  return ink != null &&
      rect.overlaps(
        Rect.fromLTRB(
          ink.left.toDouble(),
          ink.top.toDouble(),
          ink.rightExclusive.toDouble(),
          ink.bottomExclusive.toDouble(),
        ),
      );
}

/// Whether a text of [holed] stands over a coordinate [rect] reaches.
bool _textsTouch(BitmapSurface holed, Rect rect) {
  final plates = celTextPlatesOver(holed);
  if (plates == null) {
    return false;
  }
  final size = holed.tileSize.toDouble();
  for (final coord in plates.keys) {
    final tile = Rect.fromLTWH(coord.x * size, coord.y * size, size, size);
    if (tile.overlaps(rect)) {
      return true;
    }
  }
  return false;
}

/// A float that lands as its own pixels landed on nothing, on a row that
/// keys its colours: those pixels through the row's keys, in place of what
/// the row shows wherever the float covers.
///
/// Exact, because a stamp is a byte copy where it is opaque, and lands as
/// the float surface itself holds it where nothing is under it
/// (`BrushStampBlitter`, the landing's own kernel) — so where no partly
/// clear pixel meets ink, the landed cel IS the float surface, pixel for
/// pixel, and the keys are each pixel's own answer. The row is cleared
/// first where the float covers, because the landing replaces what was
/// there and a keyed pixel may be clear.
class _KeyedFloat implements LandingPreview {
  _KeyedFloat(this._float, this._keyed);

  final SelectionFloatPaint _float;

  /// [_float]'s own surface through the row's keys.
  final BitmapSurfacePainter _keyed;

  static final Paint _clearing = Paint()..blendMode = BlendMode.dstOut;

  @override
  Rect get drawnWorldRect => _float.drawnWorldRect;

  @override
  void paintInto(Canvas canvas, {required double pixelRatio}) {
    canvas.save();
    final bounds = _float.clip;
    if (bounds != null) {
      canvas.clipRect(bounds);
    }
    canvas.translate(_float.surfaceOffset.x, _float.surfaceOffset.y);
    _float.surface!.paintContentInto(
      canvas,
      layerPaint: _clearing,
      pixelRatio: pixelRatio,
    );
    _keyed.paintContentInto(canvas, pixelRatio: pixelRatio);
    canvas.restore();
  }
}

/// The channel between the selection layer (which owns the float) and the
/// composite that draws it. Null value = nothing floating.
typedef SelectionFloatOverlay = ValueNotifier<SelectionFloatPaint?>;

/// A cel a move session holds lifted beside the live one — a folder's rows
/// (I-37), a frame range's across rows (F-329): [surface] — the cel
/// with the hole the lift cut — with [float] over it, drawn in its own row's
/// slot, with its own row's opacity, blend and effects.
///
/// 🗣️유저 2026-10-02 (I-37): 「폴더 전체를 하나로 들도록」. A folder's rows
/// show at the SAME frame, so each one's hole and each one's float have to
/// be on screen while the box is open — one float merged from all of them
/// would composite differently from what each row lands as.
///
/// ⛔Not a live row: a row stays live because a stroke draws into it, and a
/// lifted row only shows. While one is up the display keeps no buffer —
/// exactly as while the active row's float is up ([SelectionFloatPaint]).
///
/// ⚠️A SURFACE, not a painter: the composite draws it as its row's cel is
/// shown — through the seam, with that row's keys (`celSurfaceAsShown`) —
/// which the composite knows from the row and the lift does not.
typedef LiftedCel = ({BitmapSurface surface, SelectionFloatOverlay float});

/// Draws [SelectionFloatPaint]s for hosts with NO composite behind them (the
/// conte, the timesheet, the cut envelope, and tests that mount the selection
/// layer alone) — every float the session holds, in the order it holds them.
///
/// The description is in canvas space, so this applies the viewport itself —
/// the only difference from the merged route, where the stack painter has
/// already applied it. Same bytes, same rects, one implementation of the
/// drawing.
class SelectionFloatPainter extends CustomPainter with RepaintOnProps {
  SelectionFloatPainter({
    required this.floats,
    required this.viewport,
    this.devicePixelRatio = 1.0,
  });

  final List<SelectionFloatPaint> floats;
  final CanvasViewport viewport;

  /// The pan-phase snap's device grid — the ink view behind this float
  /// snaps its translation, and a float on the raw transform would sit a
  /// sub-pixel off the pixels it is about to land in.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    for (final float in floats) {
      float.paintInto(canvas, pixelRatio: devicePixelRatio);
    }
    canvas.restore();
  }

  @override
  Object get props => (ByList(floats), viewport, devicePixelRatio);
}
