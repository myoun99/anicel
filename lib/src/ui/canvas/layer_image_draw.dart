/// How a POSED LAYER IMAGE reaches a canvas — the one place that decides
/// it (P2a).
///
/// Four routes composite the same thing (playback's cache, the camera
/// render, the editing stack, and export) and each hand-rolled the same
/// four steps: save, apply the pose, build a paint out of opacity, blend
/// mode and the effect chain, draw, restore. They agreed on the shape and
/// disagreed in the details — most visibly on sampling quality, where the
/// editing stack drew the ACTIVE layer's tiles unfiltered and everything
/// else at `FilterQuality.low`, so zooming in made the layer you were
/// drawing on the only jagged one on screen.
///
/// This converges the DRAW. It deliberately does not converge the INPUTS,
/// where the same four routes also disagree — which canvas size owns the
/// pose, whether pasteboard artwork is cropped first — because those
/// change rendered bytes and belong in their own change.
///
/// It is for LAYER images only. The same `applyLayerPlacement` also
/// carries the cut pose and the V-track pose, but those apply to an
/// already-composed frame in output space and must not quietly inherit a
/// layer-level sampling policy.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/draw_space.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../services/composite_effect_paint.dart';
import '../../services/import/cel_picture.dart'
    show isPastTheSide, pictureSideLimitIfMeasured;
import 'display_resample.dart' show rectOutwardOnGrid;
import 'image_pieces.dart';
import 'raster_picture.dart';
import 'subtree_image_composite.dart';
import '../../services/layer_pose_paint.dart';

/// Runs [body] under [placement].
///
/// Separate from [drawPosedLayerImage] because the editing stack's wrap
/// straddles a node that HAS a placement and has no image: the live
/// surface is painted tile by tile by its own painter, and it still has to
/// sit under the same transform as everything else in the stack.
///
/// A null placement runs [body] with no save/restore at all, which is what
/// all three call sites already did — an identity layer should not pay for
/// a matrix, and more importantly the balance is easier to see this way
/// than as a save whose restore is fifty lines below.
T withLayerPlacement<T>(
  ui.Canvas canvas, {
  required LayerPlacement? placement,
  double rasterScale = 1,
  required T Function() body,
}) {
  if (placement == null) {
    return body();
  }
  canvas.save();
  try {
    applyLayerPlacement(canvas, placement, rasterScale: rasterScale);
    return body();
  } finally {
    canvas.restore();
  }
}

/// One layer's image, posed, faded, blended, filtered and drawn.
///
/// [pieces] are the image and where its pixels belong in canvas space — one
/// piece, or several side by side for a picture past the side this engine
/// holds ([_drawInPieces]) — and [extent] the rect the image stands for —
/// the canvas grown by any pasteboard tiles; every pixel of [extent] outside
/// the pieces is transparent. A cached cel may be stored as its ink alone
/// (`LayerFrameImage`), and [_laidDown] decides whether that crop can be
/// drawn as it is or the whole image has to be laid back first. Pass the
/// piece's rect as [extent] for an image that was never cropped. A holder
/// that draws
/// the same crop again and again passes its [laidBack], so the whole is laid
/// back once rather than per draw. [rasterScale] is the
/// quality tier the destination canvas is rastering at — it scales the
/// destination rect AND reaches the effect resolver, because the images
/// are already at that tier and a canvas-pixel blur radius that ignored it
/// would show at double strength in a half-size preview.
///
/// [drawAtOriginWhen] is a route's rule for taking the legacy
/// `drawImage(Offset.zero)` path instead of `drawImageRect`, asked about
/// the image and rect ACTUALLY laid down. It is a byte pin rather than an
/// optimisation: two of the routes have always drawn their canvas-extent
/// images that way and their output is held to the pixel by composite
/// parity suites, so switching them to the general path is a change of
/// rendered bytes and does not belong in a convergence.
///
/// [texelScale] is how many target pixels one canvas unit is on [canvas]
/// when [canvas] is a pixel raster whose grid is aligned to canvas space —
/// the display buffer, a sub-tree raster, a camera's output where its
/// projection moves canvas pixels onto it whole — and null when it is not
/// (the screen, a projection that turns, zooms or stands between pixels).
/// It is what tells a texel copy from a resample ([_isTexelCopy]).
/// ⛔REQUIRED, the A4 way: a route that inherited a guess would draw a
/// resample unfiltered.
///
/// A4 — [filterQuality] is REQUIRED, deliberately. A default here is how
/// the sampling drift this file exists to end comes back: a new route
/// "just draws" and inherits a quality nobody chose. Requiring the
/// argument blocks the CLASS, not the instance — every route answers the
/// sampling question at its call site, in writing, and the source
/// contract test (`layer_image_draw_contract_test.dart`) freezes the
/// raw-draw census so new image draws have to come through here. It is the
/// answer for a draw that RESAMPLES; a texel copy resamples nothing and is
/// drawn at `none` whatever the route asked.
void drawPosedLayerImage(
  ui.Canvas canvas, {
  required List<ImagePiece> pieces,
  required ui.Rect extent,
  required LayerPlacement? placement,
  required double opacity,
  required LayerBlendMode blendMode,
  List<ResolvedLayerEffect> effects = const <ResolvedLayerEffect>[],
  double rasterScale = 1,
  required double? texelScale,
  required ui.FilterQuality filterQuality,
  int? tint,
  bool Function(ui.Rect worldRect, ui.Image image)? drawAtOriginWhen,
  LaidBackWhole? laidBack,
}) {
  withLayerPlacement(
    canvas,
    placement: placement,
    rasterScale: rasterScale,
    body: () {
      final paint = ui.Paint()
        ..color = alphaOnly(opacity)
        // R26 #30: the layer blend applies at composite time, so every
        // route shows the picture playback composes.
        ..blendMode = blendMode.paintBlendMode;
      // Onion-skin Colors mode: the ghost converts fully to the tint —
      // every drawn pixel takes the tint's RGB and only alpha survives.
      //
      // ★IT GOES THROUGH THE RESOLVER NOW, not onto the paint here. Written
      // straight to `Paint.colorFilter` it OWNED that slot, so a ghost could
      // wear the tint or the row's chain and never both — which is why
      // ghosts used to carry no effects at all. Folded into the resolver's
      // matrix it composes with the colour effects, and 유저 2026-08-27
      // (I-8-Q5) asked for exactly that: the ghost shows what the screen
      // shows.
      // 🚨A CHAIN IS NOT ALWAYS ONE DRAW. A colour key is a fragment shader,
      // so a key that comes after painted state needs its own raster — the
      // same steps a group takes, asked of one layer's image.
      final plan = resolveCompositeEffectPlan(
        effects,
        // The pose above already scaled this canvas, so there is no CTM left
        // for Skia to map the sigma through — the chain arrives multiplied.
        space: rasterScale == 1
            ? DrawSpace.canvas
            : DrawSpace.preScaled(rasterScale),
        tint: tint,
      );
      plan.finalPaint.applyTo(paint);
      final copyScale = placement == null ? texelScale : null;
      void draw(_Stored stored, LaidBackWhole? laidBack) {
        final laid = _laidDown(
          stored,
          texelScale: copyScale,
          inkDrawsTheSame: plan.outsetPixels == 0,
          laidBack: laidBack,
        );
        // ⛔THE STEP SCALE IS NOT `rasterScale`, even though it equals it here.
        // `rasterScale` answers "what space does the DRAW land in"; the steps
        // ask "how many image pixels is a canvas pixel". On this route the
        // image is at the same raster the canvas is, so the two numbers agree
        // — which is exactly why one parameter was answering both until the
        // playback painter needed them to differ. Derived, so it cannot drift.
        final stepped = steppedForChain(
          image: laid.image,
          plan: plan,
          canvasExtent: laid.worldRect.width,
        );
        // 🚨★★★A TEXEL COPY RESAMPLES NOTHING, SO IT IS DRAWN AT `none` (유저
        // 2026-09-24 「통일해서」). The law the 1:1 blits beside it already keep
        // — the sub-tree blit, the tile blits, the buffer carry — asked of a
        // layer image: below 100% the buffer lays each level image down one
        // texel per pixel, and so does a camera that moves pixels whole, and
        // filtering that is only a copy on paper. 🔬Measured against the source image: bilinear
        // at 1:1 IS the copy on the Windows app (Impeller GLES) and the test
        // runner, and is NOT on Impeller Vulkan — Android's default — up to
        // 9/255 off at a 2340×1654 image and 4/255 at the fit-zoom level,
        // growing with the size. `none` is the copy on all three. So a layer
        // drawn this way was a hair softer on Android than the same layer
        // being drawn on, whose tiles are `none` — the active/inactive split
        // D14 ruled out (「그림 자체에 통일해서 적용」).
        final copies = _isTexelCopy(stepped, laid.worldRect, copyScale);
        assert(() {
          if (copies) {
            debugTexelCopies += 1;
          }
          return true;
        }());
        paint.filterQuality = copies ? ui.FilterQuality.none : filterQuality;
        final source = ui.Rect.fromLTWH(
          0,
          0,
          stepped.width.toDouble(),
          stepped.height.toDouble(),
        );
        try {
          // ↩️🚨F-243: in an advanced blend the image was held to where it
          // landed — a layer whose ink reached the edge of its image
          // stretched that edge across the pasteboard (`drawHeldToItsRect`)
          // — until such a layer painted normal over its backdrop
          // (a-blurred-folder-cut-by-the-view-moves-on-vulkan). A row's
          // blend here is `srcOver` or `plus`, both in place.
          if (drawAtOriginWhen?.call(laid.worldRect, stepped) ?? false) {
            canvas.drawImage(stepped, ui.Offset.zero, paint);
            return;
          }
          final destination = ui.Rect.fromLTWH(
            laid.worldRect.left * rasterScale,
            laid.worldRect.top * rasterScale,
            laid.worldRect.width * rasterScale,
            laid.worldRect.height * rasterScale,
          );
          canvas.drawImageRect(stepped, source, destination, paint);
        } finally {
          // ⛔The steps made a NEW image, and a whole image laid back for this
          // draw alone is this draw's; the one handed in belongs to the cache
          // and a kept whole to its holder. Disposing either would take pixels
          // someone still draws with. The draw above holds its own reference
          // to whatever it drew.
          if (!identical(stepped, laid.image)) {
            stepped.dispose();
          }
          if (laid.drawOwnsIt) {
            laid.image.dispose();
          }
        }
      }

      if (pieces case [final whole]) {
        draw(
          (image: whole.image, worldRect: whole.worldRect, extent: extent),
          laidBack,
        );
        return;
      }
      _drawInPieces(
        pieces,
        // Grown by as far as the chain reads past a pixel, in canvas pixels
        // — what a seen part has to hold beyond what is seen
        // ([inkCropDrawsTheSame] asks the same number).
        seen: _seenBy(
          canvas,
          rasterScale,
        ).inflate(resolveCompositeEffectPlan(effects).outsetPixels),
        extent: extent,
        draw: (stored) => draw(stored, null),
      );
    },
  );
}

/// What one draw stands on: an image, where its pixels belong, and the rect
/// it stands for ([drawPosedLayerImage]'s `extent`).
typedef _Stored = ({ui.Image image, ui.Rect worldRect, ui.Rect extent});

/// 🚨★★★A PICTURE IN PIECES IS DRAWN AS ONE IMAGE: THE PART OF IT THIS DRAW
/// CAN SHOW ([piecesOver] says why a picture is held in pieces).
///
/// Drawn piece by piece, a pose would sample each piece's edge clamped where
/// the whole image samples its neighbour, a blur would stop at every cut,
/// and an advanced blend would blend each piece through its own area — a
/// seam the whole picture never had. So the pieces are laid into ONE image,
/// texel for texel ([_laidInto]), over the part of [extent] the draw can
/// [seen] — in canvas pixels, grown by as far as the chain reads — and two
/// texels for the sampler; and that image is drawn the one way ([draw]), as
/// the part a whole image stands for: every pixel this draw can land on
/// reads the texels the whole image would hand it. It is the same lay
/// [_wholeOf] makes of a crop.
///
/// A part longer on a side than the engine holds — a picture shrunk on a
/// canvas that sees more of it than that, or a canvas that does not say
/// what it sees — is drawn piece by piece ([debugPiecesDrawnApart]). Every
/// canvas a cel is drawn onto says: the screen by its clip, a raster by
/// its bounds (the display buffer, a sub-tree's, the bake's, a film
/// frame's).
void _drawInPieces(
  List<ImagePiece> pieces, {
  required ui.Rect seen,
  required ui.Rect extent,
  required void Function(_Stored stored) draw,
}) {
  final texels = _texelsOf(pieces);
  final window = seen.inflate(2 / texels);
  if (!window.overlaps(extent)) {
    return;
  }
  final part = rectOutwardOnGrid(
    window.intersect(extent),
    texels,
    origin: pieces.first.worldRect.topLeft,
  ).intersect(extent);
  final side = pictureSideLimitIfMeasured;
  if (side != null &&
      isPastTheSide(
        (part.width * texels).round(),
        (part.height * texels).round(),
        side,
      )) {
    assert(() {
      debugPiecesDrawnApart += 1;
      return true;
    }());
    for (final piece in pieces) {
      draw((
        image: piece.image,
        worldRect: piece.worldRect,
        extent: piece.worldRect,
      ));
    }
    return;
  }
  assert(() {
    debugSeenPartsLaid += 1;
    return true;
  }());
  final laid = _laidInto(pieces, part);
  try {
    draw((image: laid, worldRect: part, extent: part));
  } finally {
    // The draw holds its own reference to what it drew.
    laid.dispose();
  }
}

/// What [canvas] can land on, in canvas pixels: its clip in this draw's
/// space, at [rasterScale].
ui.Rect _seenBy(ui.Canvas canvas, double rasterScale) {
  final clip = canvas.getLocalClipBounds();
  return ui.Rect.fromLTRB(
    clip.left / rasterScale,
    clip.top / rasterScale,
    clip.right / rasterScale,
    clip.bottom / rasterScale,
  );
}

/// How many texels a canvas pixel is in [pieces] — one scale for them all,
/// read off the first: every piece but a row's or a column's last is a
/// power of two texels across ([piecesOver]).
double _texelsOf(List<ImagePiece> pieces) =>
    pieces.first.image.width / pieces.first.worldRect.width;

/// How many draws of a picture in pieces laid the part they show into one
/// image ([_drawInPieces]), and how many drew the pieces apart. Written
/// under `assert`.
@visibleForTesting
int debugSeenPartsLaid = 0;

@visibleForTesting
int debugPiecesDrawnApart = 0;

/// Whether a layer drawn through [placement] and [effects] puts the
/// same bytes on a raster from its ink alone as from the whole image — so a
/// route that lays it down texel for texel may have it stored as its ink
/// (`LayerFrameImageCache.prepare`'s `inkSuffices`). [_laidDown] asks the
/// same of each draw.
///
/// 🚨★★★A CROP IS ONLY EVER DRAWN WHERE THAT IS EXACT (유저 2026-09-23:
/// 「1/4해상도같은 결과바뀌는건 절대로 허용안하고 … 보이는 결과 특히」). 🔬Measured
/// on three engines — the Windows app (Impeller GLES), the test runner (Skia)
/// and Impeller Vulkan, Android's default — the same ink drawn whole and
/// cropped:
/// · laid down texel for texel through `srcOver` or `plus`, with any opacity
///   or colour filter, the two are the same bytes on all three;
/// · posed, the sampler's coordinates are normalised by the texture's size,
///   so a smaller texture rounds differently on every GPU engine;
/// · a blur reads the texture's bounds.
/// Each of those gets the whole image; the whole image laid back from the
/// crop draws the same bytes as the one the cache used to keep, on all three.
/// ↩️So did a row in an advanced blend (multiply, screen, overlay,
/// difference …): Vulkan blended it through a snapshot of the area drawn,
/// and a smaller area rounded differently, up to 29/255 — drawing the crop
/// over the whole area did not close it. Such a row paints normal over its
/// backdrop now (a-blurred-folder-cut-by-the-view-moves-on-vulkan), so a
/// row's blend is `srcOver` or `plus` and never asks.
bool inkCropDrawsTheSame({
  required LayerPlacement? placement,
  required List<ResolvedLayerEffect> effects,
}) =>
    placement == null && resolveCompositeEffectPlan(effects).outsetPixels == 0;

/// What a draw lays down: the [stored] image at its world rect where that is
/// exact, and otherwise the image its extent stands for — laid back byte for
/// byte, so the draw is the one this route always made.
///
/// A crop is drawn as it is only as a texel copy ([_isTexelCopy]) through a
/// chain that keeps the ink alone exact ([inkDrawsTheSame], the draw's half
/// of [inkCropDrawsTheSame]); anything else — the walk on the screen, a
/// pose, a blur — gets the whole image first:
/// the one [laidBack] keeps when the holder has one, else one this draw
/// makes and owns ([drawOwnsIt]).
({ui.Image image, ui.Rect worldRect, bool drawOwnsIt}) _laidDown(
  ({ui.Image image, ui.Rect worldRect, ui.Rect extent}) stored, {
  required double? texelScale,
  required bool inkDrawsTheSame,
  required LaidBackWhole? laidBack,
}) {
  final (:image, :worldRect, :extent) = stored;
  if (worldRect == extent) {
    return (image: image, worldRect: worldRect, drawOwnsIt: false);
  }
  if (inkDrawsTheSame && _isTexelCopy(image, worldRect, texelScale)) {
    assert(() {
      debugCropsLaidDown += 1;
      return true;
    }());
    return (image: image, worldRect: worldRect, drawOwnsIt: false);
  }
  if (laidBack != null) {
    return (image: laidBack._of(stored), worldRect: extent, drawOwnsIt: false);
  }
  return (
    image: _wholeOf(image, worldRect: worldRect, extent: extent),
    worldRect: extent,
    drawOwnsIt: true,
  );
}

/// The whole image a held crop stands for, laid back the first time a draw
/// needs it ([_laidDown]) and kept for every draw after, until the holder
/// lets the crop go and calls [dispose]. One per held crop, never shared: it
/// keeps the whole of the first crop it is asked about.
///
/// 🔬WHY IT IS KEPT (2026-09-24, the user's own project on the Windows app,
/// 유저 「성능적인 면은 아주 중요하니까 철저하게 하자」): crossing 50% while the
/// new level's images are still coming, the editing stack draws each row's
/// old level resampled and records its slots again on every frame the zoom
/// moves the buffer — and every one of those laid every crop back again:
/// 111 whole images for 8 rows over one pinch, frames at p95 75–104ms
/// against 15–27ms with the whole images kept. A crop's whole is the same
/// bytes every time it is laid back, so keeping one is the same picture.
final class LaidBackWhole {
  ui.Image? _whole;
  ({ui.Rect worldRect, ui.Rect extent, int width, int height})? _madeFrom;

  ui.Image _of(({ui.Image image, ui.Rect worldRect, ui.Rect extent}) stored) {
    final (:image, :worldRect, :extent) = stored;
    final from = (
      worldRect: worldRect,
      extent: extent,
      width: image.width,
      height: image.height,
    );
    assert(
      _madeFrom == null || _madeFrom == from,
      'one LaidBackWhole per held crop: kept $_madeFrom, asked about $from',
    );
    _madeFrom = from;
    if (_whole case final whole?) {
      return whole;
    }
    assert(() {
      debugKeptWholes += 1;
      return true;
    }());
    return _whole = _wholeOf(image, worldRect: worldRect, extent: extent);
  }

  /// Lets the kept whole go. A slot recorded with it holds its own
  /// reference, so a replay before the holder's next build still draws.
  void dispose() {
    if (_whole case final whole?) {
      whole.dispose();
      _whole = null;
      assert(() {
        debugKeptWholes -= 1;
        return true;
      }());
    }
  }
}

/// How many wholes [LaidBackWhole]s keep right now — each one a whole cel
/// image resident, so one left behind is the memory the ink was stored to
/// save. Written under `assert`.
@visibleForTesting
int debugKeptWholes = 0;

/// The recording that copies [texels] of a cel's [whole] image out, texel
/// for texel — how a cache comes to store the ink alone
/// (`LayerFrameImageCache`). [_wholeOf] is its inverse: the two are the only
/// ways between the ink and the whole, and both are texel copies at the
/// identity, so the round trip is the same bytes.
ui.PictureRecorder recordInkCutOut(ui.Image whole, ui.Rect texels) {
  assert(() {
    debugInksCutOut += 1;
    return true;
  }());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    whole,
    texels,
    ui.Rect.fromLTWH(0, 0, texels.width, texels.height),
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  return recorder;
}

/// [image] laid back into [extent] at its own resolution — the whole image a
/// cache keeps when it does not store the ink alone, transparent wherever
/// the crop stores nothing. A texel copy at the identity, so its bytes are
/// exactly the part of that image the crop kept.
ui.Image _wholeOf(
  ui.Image image, {
  required ui.Rect worldRect,
  required ui.Rect extent,
}) {
  assert(() {
    debugWholesLaidBack += 1;
    return true;
  }());
  return _laidInto([(image: image, worldRect: worldRect)], extent);
}

/// [pieces] laid into [rect] at their own resolution — each texel for texel
/// where it lands, transparent wherever none lies: a crop laid back into its
/// whole ([_wholeOf]), and the part of a picture in pieces a draw shows
/// ([_drawInPieces]). A texel copy at the identity, so its bytes are exactly
/// the pieces' over [rect].
ui.Image _laidInto(List<ImagePiece> pieces, ui.Rect rect) {
  final texels = _texelsOf(pieces);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  for (final piece in pieces) {
    if (piece.worldRect.overlaps(rect)) {
      canvas.drawImage(
        piece.image,
        ui.Offset(
          (piece.worldRect.left - rect.left) * texels,
          (piece.worldRect.top - rect.top) * texels,
        ),
        paint,
      );
    }
  }
  return rasterPicture(
    recorder,
    (rect.width * texels).round(),
    (rect.height * texels).round(),
  );
}

/// How many draws laid a crop down as it is, and how many whole images were
/// laid back — the two arms of [_laidDown], so a pin can say the arm it
/// compares actually ran, and what [LaidBackWhole] spares. Written under
/// `assert`.
@visibleForTesting
int debugCropsLaidDown = 0;

@visibleForTesting
int debugWholesLaidBack = 0;

/// How many inks were cut out of a whole image ([recordInkCutOut]) — the
/// raster the full level no longer pays. Written under `assert`.
@visibleForTesting
int debugInksCutOut = 0;

/// Whether [image] laid at [worldRect] lands texel for texel on a canvas
/// at canvas resolution — what [drawPosedLayerImage] asks before it draws
/// at `none`, for a caller that has to know before anything is drawn.
bool drawsAsTexelCopy(ui.Image image, ui.Rect worldRect) =>
    _isTexelCopy(image, worldRect, 1);

/// [landsTexelForTexel] on a canvas that is a pixel raster [texelScale]
/// apart, and never on one that is not (null).
bool _isTexelCopy(ui.Image image, ui.Rect worldRect, double? texelScale) =>
    texelScale != null && landsTexelForTexel(image, worldRect, texelScale);

/// How many layer draws were texel copies — so a pin can say WHICH routes
/// copy: the test runner draws a bilinear 1:1 exactly as it draws a copy, so
/// the pixels cannot tell whether a route declared its raster. Written
/// under `assert`.
@visibleForTesting
int debugTexelCopies = 0;
