import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;

import '../core/argb_channels.dart';
import '../core/color_matrix.dart';
import '../core/draw_space.dart';
import '../models/canvas_size.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import 'camera_lens_blur_passes.dart';
import 'cel_source_effect_pass.dart';
import 'directional_blur_passes.dart';
import 'shaded_passes.dart';

/// How much a blur RADIUS parameter spreads, as a Gaussian sigma. A radius
/// is the visible reach of the blur; three sigma covers it, so a radius of
/// 3 canvas px reads as sigma 1 — the convention Photoshop's radius slider
/// follows closely enough that a number typed from muscle memory lands
/// where the artist expects.
const double blurSigmaPerRadius = 1 / 3;

/// How far past its own coverage a blur of [radius] paints. Used to outset
/// `saveLayer` bounds so a group's blur is not clipped at the buffer edge.
double blurSpreadForRadius(double radius) => radius;

/// An alpha-only colour: black at [opacity], which a `Paint` reads purely as
/// a multiplier over whatever it draws.
///
/// ⛔CLAMPED HERE, because `ui.Color.fromRGBO` does NOT — its constructor is
/// `a = opacity`, stored raw, so 1.5 stays 1.5 and −0.2 stays −0.2, and what
/// a backend makes of an alpha outside the unit range is its own business.
/// `Layer.opacity` is a bare `double` off the JSON with no model guard.
ui.Color alphaOnly(double opacity) =>
    ui.Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

/// The paint one node composites with: its opacity, its blend, and its own
/// effect chain, in that order.
///
/// ⛔ONE FUNCTION, because four places build it — the editing stack twice (a
/// folder and the live layer), the playback cache, and the camera. #1304
/// unified the WALK those routes share and left this hand-written in each,
/// and the copies had already drifted: the editing stack clamped the
/// opacity, the camera and the playback cache did not. Same document, two
/// answers, decided by which panel you were looking at.
///
/// ⛔A BEHAVIOUR TEST CANNOT HOLD THIS SHUT — copies that agree today pass
/// every pixel comparison, and what breaks is the route added next year.
/// `one_composite_paint_test` scans the source instead. That the chain
/// reaches the PICTURE is behaviour, and `camera_frame_render_service_test`
/// (R6) already holds it — a second pixel test here would be a copy.
///
/// ⚠️IT TAKES A RESOLVED CHAIN, NOT THE EFFECT LIST. `rasterScale` is NOT the
/// same at every site and must not be folded in here: a route drawing under
/// a scaled CTM leaves it 1 (Skia maps the sigma through the matrix), while
/// the playback cache rasters at 1:1 and multiplies the sigma itself — see
/// [resolveCompositeEffectPaint]'s contract.
ui.Paint layerCompositePaint({
  required double opacity,
  required LayerBlendMode blendMode,
  required CompositeEffectPaint effects,
}) {
  final paint = ui.Paint()
    ..color = alphaOnly(opacity)
    ..blendMode = blendMode.paintBlendMode;
  effects.applyTo(paint);
  return paint;
}

/// The Skia form of a resolved effect chain — ONE pure translation from
/// effect samples to paint state, shared by every composite route (editing
/// stack, playback cache, camera renders, export). The R5b lesson applied:
/// one resolver, one painter, no surface deciding for itself what a blur
/// means.
///
/// The chain lands in exactly one of the two fields:
/// - **colorFilter** while the chain is colors only. Color filters run
///   INLINE, with no offscreen, so the overwhelmingly common case
///   ("brighten this layer") costs a matrix multiply per pixel and nothing
///   else. Several colour effects fold into one matrix
///   ([composeColorMatrices]).
/// - **imageFilter** as soon as a blur appears — a blur needs an offscreen
///   anyway, so the colours ride along inside the composed filter (setting
///   both fields would leave Skia's application order deciding the look).
class CompositeEffectPaint {
  const CompositeEffectPaint({
    this.colorFilter,
    this.imageFilter,
    this.outsetPixels = 0,
  });

  static const CompositeEffectPaint none = CompositeEffectPaint();

  final ui.ColorFilter? colorFilter;
  final ui.ImageFilter? imageFilter;

  /// How far the chain paints beyond its input's bounds (blur spread, in
  /// the same space the plan was resolved for).
  final double outsetPixels;

  bool get isEmpty => colorFilter == null && imageFilter == null;
  bool get isNotEmpty => !isEmpty;

  /// Writes the plan onto [paint] — the ONLY way a route should apply
  /// effects.
  ///
  /// [paint] must arrive with NO `colorFilter` of its own. It once arrived
  /// carrying the onion tint, and that is exactly what this class now takes
  /// over ([resolveCompositeEffectPaint]'s `tint`) — the slot holds one
  /// filter, so anything writing it beforehand silently decided the ghost
  /// could not also wear its row's chain. The assert makes a second writer
  /// a test failure rather than a look nobody can explain.
  void applyTo(ui.Paint paint) {
    if (isEmpty) {
      return;
    }
    assert(
      paint.colorFilter == null,
      'A paint already carrying a colorFilter (the onion tint) must not '
      'also take effects — ghosts resolve to CompositeEffectPaint.none.',
    );
    if (colorFilter != null) {
      paint.colorFilter = colorFilter;
      return;
    }
    paint.imageFilter = imageFilter;
  }

  /// [inner], then the plan, as ONE image filter — what [applyTo] gives a
  /// draw whose own shading is [inner], for a layer that filter carries.
  /// The plan holds one filter or the other, never both, so the order is
  /// the draw's: its shading first, the plan over it.
  ui.ImageFilter after(ui.ImageFilter inner) {
    final outer = colorFilter ?? imageFilter;
    return outer == null
        ? inner
        : ui.ImageFilter.compose(outer: outer, inner: inner);
  }

  // A VALUE, so a painter can ask "is this the same filter as last frame?"
  // in `shouldRepaint` — the V row's cut chain is resolved fresh every build,
  // and identity would call a static grade a change on every rebuild.
  // dart:ui's filters carry value equality themselves.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompositeEffectPaint &&
          other.colorFilter == colorFilter &&
          other.imageFilter == imageFilter &&
          other.outsetPixels == outsetPixels;

  @override
  int get hashCode => Object.hash(colorFilter, imageFilter, outsetPixels);
}

/// The single folded matrix for a COLOUR-ONLY chain; null as soon as the
/// chain holds anything a matrix cannot say — a blur, which reads past the
/// pixel, or a colour key, which rides the raster — and null for a chain
/// with no colour in it at all.
///
/// STRICT on purpose: a caller that gets a matrix may paint it INSTEAD of
/// the chain, so answering "here is the colour part" for a chain with
/// anything else in it would silently drop the rest. The adjustment scope
/// relies on that to fold its MIX into the matrix
/// ([lerpColorMatrixFromIdentity]) and paint one pass. ↩️It asked after a
/// blur alone, so an adjustment's key went unpainted below full mix —
/// keyed at 100 % and gone at 99.
List<double>? resolveColorOnlyMatrix(List<ResolvedLayerEffect> effects) {
  List<double>? matrix;
  for (final effect in effects) {
    if (effect.kind.spreadsPixels) {
      return null;
    }
    switch (_paintPartOf(effect, DrawSpace.canvas)) {
      case _ColourPart(:final next):
        matrix = matrix == null ? next : composeColorMatrices(next, matrix);
      case _NoPart():
        break;
      case _:
        return null;
    }
  }
  return matrix;
}

/// ONE straight pixel through [effects] IN THEIR ORDER — what the composite
/// draws there, as the eyedropper reads it: a colour effect's matrix, a key
/// over its run's input ([resolveCompositeEffectPlan]'s runs — the keys
/// standing together), and the spatial ones skipped: one pixel cannot
/// reach its neighbours, and dropping the colour with them would be
/// strictly worse.
///
/// ↩️The eyedropper ran every key first and every matrix after, which read
/// a key under a colour effect as if it stood above it — and every key of
/// the chain as one run.
///
/// The colour may come in between bytes — a stack an adjustment grades is
/// laid up from many rows — and the alpha comes out a byte, as a raster
/// holds it.
({double red, double green, double blue, int alpha}) pixelThroughChain(
  List<ResolvedLayerEffect> effects, {
  required num red,
  required num green,
  required num blue,
  required num alpha,
}) {
  var (r, g, b) = (red.toDouble(), green.toDouble(), blue.toDouble());
  var a = _byte(alpha.toDouble());
  int? runInput;
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key == null) {
      runInput = null;
      final part = _paintPartOf(effect, DrawSpace.canvas);
      if (part is _ColourPart) {
        final filtered = applyColorMatrixToStraightColor(
          part.next,
          r,
          g,
          b,
          a.toDouble(),
        );
        (r, g, b) = (filtered.r, filtered.g, filtered.b);
      }
    } else if (!key.isNoOp) {
      runInput ??= a;
      a = key.alphaFor(_byte(r), _byte(g), _byte(b), a, original: runInput);
    }
  }
  return (red: r, green: g, blue: b, alpha: a);
}

int _byte(double channel) => channel.round().clamp(0, 255);

/// What ONE sampled effect is to a paint — the one place each kind's paint
/// is written (I-132 「fx 하나 = 한 곳」): a colour matrix, a spatial filter, or
/// nothing a paint can carry. Every reader of a chain — the painter
/// ([resolveCompositeEffectPaint]), an adjustment's one pass
/// ([resolveColorOnlyMatrix]) and the eyedropper ([pixelThroughChain]) —
/// asks it, so a colour kind's matrix is spelled once. ↩️Each wrote its own
/// switch, the matrices twice.
sealed class _PaintPart {
  const _PaintPart();
}

final class _ColourPart extends _PaintPart {
  const _ColourPart(this.next);

  final List<double> next;
}

final class _SpatialPart extends _PaintPart {
  const _SpatialPart(this.filter, {required this.outset});

  final ui.ImageFilter filter;
  final double outset;
}

/// A sample that changes no pixel though its values are not its defaults.
final class _NoPart extends _PaintPart {
  const _NoPart();
}

/// A kind a fragment shader draws over a whole raster, in [passes], because
/// it reads past the pixel and no `ui.ImageFilter` carries it — a step of
/// its own ([ShadedEffect]), [reach] past its input.
final class _StepPart extends _PaintPart {
  const _StepPart(this.passes, {required this.reach});

  final List<ShadedPass> passes;

  /// How far past its input it paints.
  final double reach;
}

/// A blur that reads past the paper's edge as its edge's own pixels and
/// paints no further than it — AE's Repeat Edge Pixels ([PaperEdgeEffect]):
/// [filter] repeats the edge of the image it is drawn with, so it is drawn
/// over the paper cut out alone, a step of its own.
final class _PaperEdgePart extends _PaintPart {
  const _PaperEdgePart(this.filter, {required this.reach});

  final ui.ImageFilter filter;

  /// How far past its input it paints, inside the paper.
  final double reach;
}

/// A kind no paint carries: the chain is split before a paint is resolved.
final class _SplitPart extends _PaintPart {
  const _SplitPart(this.splitBy);

  /// What takes it out of the chain — the assert's word to a route that
  /// resolved a chain without splitting it.
  final String splitBy;
}

/// [paper] is where the paper lies in [space]'s pixels — what a radial
/// blur's centre stands on ([_radialBlurPart]); a reader that does no
/// spatial work at all, the eyedropper's, asks without one. [rasterWidth]
/// is how wide the raster a step is drawn in is, which a camera lens
/// blur's row sums run across ([_cameraLensBlurPart]) — null for a reader
/// that draws none, a plan's among them.
_PaintPart _paintPartOf(
  ResolvedLayerEffect effect,
  DrawSpace space, {
  ui.Rect? paper,
  int? rasterWidth,
}) => switch (effect.kind) {
    EffectKind.brightnessContrast => _ColourPart(
      brightnessContrastMatrix(
        brightness: effect.parameter('brightness'),
        contrast: effect.parameter('contrast'),
      ),
    ),
    EffectKind.hueSaturation => _ColourPart(
      hueSaturationMatrix(
        hueDegrees: effect.parameter('hue'),
        saturation: effect.parameter('saturation'),
        lightness: effect.parameter('lightness'),
      ),
    ),
    EffectKind.blur => _blurPart(effect, space),
    EffectKind.directionalBlur => _directionalBlurPart(effect, space),
    EffectKind.radialBlur => _radialBlurPart(effect, space, paper),
    EffectKind.cameraLensBlur => _cameraLensBlurPart(
      effect,
      space,
      paper,
      rasterWidth,
    ),
    // ⛔THE CPU HALF MUST BE GONE BY NOW. `splitSourceEffects` takes the
    // color keys out in the shared visit and `celSurfaceWithSourceEffects`
    // has already applied them to the surface this paint will draw. A
    // color key changes ALPHA by a threshold test — there is no color
    // matrix for it, the same way there is none for a blur; the eyedropper
    // applies the keys itself (`CelColorKey.alphaFor`).
    EffectKind.colorKey => const _SplitPart(
      'Source-pixel effects must be split off before a paint is '
      'resolved — see splitSourceEffects.',
    ),
    // ⛔AND SO MUST A CEL NUMBER. It is no paint state but a picture of
    // its own: the row's tree splits the chain where it stands
    // (`celNumberedRow`), so no chain handed to a paint holds one. Letters
    // laid over the picture are spatial work too — what stands at one
    // point is the picture's, as under a blur.
    EffectKind.celNumber => const _SplitPart(
      'A cel number splits the chain before a paint is resolved — see '
      'celNumberedRow.',
    ),
  };

/// A Gaussian of no blurriness changes no pixel, whichever way it runs — as
/// [_directionalBlurPart]'s length.
_PaintPart _blurPart(ResolvedLayerEffect effect, DrawSpace space) {
  final radius = effect.parameter('blurriness') * space.scale;
  if (radius <= 0) {
    return const _NoPart();
  }
  // The words of Blur Dimensions, in order: both, across, up and down.
  final dimensions = effect.parameter('blurDimensions').round();
  final radiusX = dimensions == 2 ? 0.0 : radius;
  final radiusY = dimensions == 1 ? 0.0 : radius;
  final repeatsTheEdge = effect.flag('repeatEdgePixels');
  final filter = ui.ImageFilter.blur(
    sigmaX: radiusX * blurSigmaPerRadius,
    sigmaY: radiusY * blurSigmaPerRadius,
    // DECAL, not the clamp default: a layer's artwork must not smear its
    // edge pixels outward forever — outside its coverage there is nothing,
    // and that is what the picture should show. CLAMP where the edge is to
    // be repeated: drawn over the paper cut out alone, it is the paper's.
    tileMode: repeatsTheEdge ? ui.TileMode.clamp : ui.TileMode.decal,
  );
  final spread = blurSpreadForRadius(radiusX > radiusY ? radiusX : radiusY);
  return repeatsTheEdge
      ? _PaperEdgePart(filter, reach: spread)
      : _SpatialPart(filter, outset: spread);
}

/// A directional blur of no length changes no pixel, whichever way it
/// points — [ResolvedLayerEffect.isNoOp] reads only "at its defaults".
_PaintPart _directionalBlurPart(ResolvedLayerEffect effect, DrawSpace space) {
  final length = effect.parameter('blurLength') * space.scale;
  if (length <= 0) {
    return const _NoPart();
  }
  final radians = effect.parameter('direction') * math.pi / 180;
  return _StepPart(
    directionalBlurPasses(
      dx: math.sin(radians),
      dy: -math.cos(radians),
      length: length,
    ),
    // Half the line each way, and the texel a sample at its end reads.
    reach: length / 2 + 1,
  );
}

/// A radial blur of no amount changes no pixel, whichever way it turns —
/// as [_directionalBlurPart]'s length. Its centre stands on [paper] — where
/// its keys put it, or the paper's middle ([effectPointOnPaper]) — and the
/// paper's corner farthest from it is how far a pixel it blurs lies: what
/// it reaches past its input, and how finely it is laid
/// ([radialBlurPasses]). Ink past the paper is blurred as finely as its
/// edge is.
_PaintPart _radialBlurPart(
  ResolvedLayerEffect effect,
  DrawSpace space,
  ui.Rect? paper,
) {
  final amount = effect.parameter('amount');
  if (amount <= 0) {
    return const _NoPart();
  }
  // Asked by a reader that does no spatial work: it skips the part, so
  // nothing in it is read.
  if (paper == null) {
    return const _StepPart([], reach: 0);
  }
  final scale = space.scale;
  final point = effectPointOnPaper(
    effect.points['center'],
    CanvasSize(
      width: (paper.width / scale).round(),
      height: (paper.height / scale).round(),
    ),
  );
  final center = paper.topLeft + ui.Offset(point.x, point.y) * scale;
  final farthest = [
    paper.topLeft,
    paper.topRight,
    paper.bottomLeft,
    paper.bottomRight,
  ].map((corner) => (corner - center).distance).reduce(math.max);
  // The words of Type and of Antialiasing, in order: Spin, Zoom; Best,
  // Draft.
  final spin = effect.parameter('type').round() == 0;
  // Spin's Amount is degrees, Zoom's the streak a percent of the way out.
  final across = spin ? amount * math.pi / 180 : amount / 100;
  return _StepPart(
    radialBlurPasses(
      centerX: center.dx,
      centerY: center.dy,
      spin: spin,
      across: across,
      farthest: farthest,
      draft: effect.parameter('antialiasing').round() == 1,
    ),
    // How far a pixel out there moves: the chord of half the arc, or half
    // the ray outward — and the texel a sample at its end reads.
    reach:
        (spin
            ? 2 * farthest * math.sin(math.min(across / 2, math.pi) / 2)
            : farthest * (math.exp(across / 2) - 1)) +
        1,
  );
}

/// The row of its cut whose picture a step of [effect] reads — a camera
/// lens blur's blur map (🗣️I-132-Q16 a) — null where it reads none.
LayerId? effectReadsRow(ResolvedLayerEffect effect) =>
    effect.layers.values.nonNulls.firstOrNull;

/// A camera lens blur of no radius changes no pixel, whatever its iris —
/// as [_directionalBlurPart]'s length. Its iris covers pixel centres within
/// its radius (`shaders/iris_table.frag`): that is how far it reaches past
/// its input. Its edge, repeated, is the paper's on whole pixels, as the
/// Gaussian's is ([paperOnWholePixels]).
_PaintPart _cameraLensBlurPart(
  ResolvedLayerEffect effect,
  DrawSpace space,
  ui.Rect? paper,
  int? rasterWidth,
) {
  final radius = effect.parameter('blurRadius') * space.scale;
  if (radius <= 0) {
    return const _NoPart();
  }
  final repeatsTheEdge = effect.flag('repeatEdgePixels');
  return _StepPart(
    // Asked by a reader that draws no raster: it reads how far the part
    // reaches, or skips it, so nothing in its passes is read.
    rasterWidth == null || (repeatsTheEdge && paper == null)
        ? const []
        : cameraLensBlurPasses(
            (
              radius: radius,
              iris: (
                // The words of Shape, in order: a triangle's three sides to
                // a decagon's ten.
                sides: effect.parameter('irisShape').round() + 3,
                roundness: effect.parameter('irisRoundness') / 100,
                aspect: effect.parameter('irisAspectRatio'),
                rotation: effect.parameter('irisRotation') * math.pi / 180,
                fringe: effect.parameter('irisDiffractionFringe'),
              ),
              light: (
                gain: effect.parameter('highlightGain'),
                threshold: effect.parameter('highlightThreshold') / 255,
                saturation: effect.parameter('highlightSaturation') / 100,
                linear: effect.flag('useLinearWorkingSpace'),
              ),
            ),
            rasterWidth: rasterWidth,
            paper: repeatsTheEdge ? paperOnWholePixels(paper!) : null,
            map: effectReadsRow(effect) == null
                ? null
                : (
                    // The words of Blur Map Channel, in order.
                    channel: IrisMapChannel
                        .values[effect.parameter('blurMapChannel').round()],
                    focal: effect.parameter('blurFocalDistance'),
                    inverts: effect.flag('invertBlurMap'),
                  ),
          ),
    reach: radius,
  );
}

/// [paper] on whole pixels: where a blur that repeats the paper's edge
/// pixels reads them past it and is cut to it — the Gaussian's
/// ([PaperEdgeEffect]) and the camera lens blur's alike.
ui.Rect paperOnWholePixels(ui.Rect paper) => ui.Rect.fromLTRB(
  paper.left.roundToDouble(),
  paper.top.roundToDouble(),
  paper.right.roundToDouble(),
  paper.bottom.roundToDouble(),
);

/// The rasters [effect] — a step's [ShadedEffect] — is drawn in at [space],
/// the raster's own, [rasterWidth] wide, with [paper] where the paper lies
/// in it: empty where it changes no pixel there.
List<ShadedPass> shadedPassesOf(
  ResolvedLayerEffect effect,
  DrawSpace space, {
  required ui.Rect paper,
  required int rasterWidth,
}) => switch (_paintPartOf(
  effect,
  space,
  paper: paper,
  rasterWidth: rasterWidth,
)) {
  _StepPart(:final passes) => passes,
  _ => const [],
};

/// The blur [effect] — a step's [PaperEdgeEffect] — draws over the paper
/// at [space], the raster's own: null where it changes no pixel there.
ui.ImageFilter? paperEdgeBlurOf(ResolvedLayerEffect effect, DrawSpace space) =>
    switch (_paintPartOf(effect, space)) {
      _PaperEdgePart(:final filter) => filter,
      _ => null,
    };

/// Translates [effects] (already sampled at a frame) into paint state.
///
/// [rasterScale] is the ratio between the space this paint draws in and
/// CANVAS space. Colour is scale-free, but a blur radius is measured in
/// canvas pixels: the playback cache composes at a reduced raster and draws
/// its pre-scaled images 1:1, so without this a half-size preview would
/// show a double-strength blur. Routes that draw under a scaled CANVAS
/// TRANSFORM (the editing stack, the camera projection) leave it 1 — Skia
/// maps the sigma through the CTM for them.
/// The onion-skin Colors tint as a color matrix: every pixel takes the
/// tint's RGB and keeps only its own alpha (scaled by the tint's).
///
/// 🚨THIS EXISTS SO THE GHOST CAN HAVE BOTH. The tint used to be written
/// straight onto `Paint.colorFilter`, which is ONE slot — so a ghost could
/// wear the tint or the row's effects, never both, and the chain was
/// dropped with a comment calling ghosts "editing scaffolding". That was
/// the slot talking, not a decision. ✅유저 2026-08-27 (I-8-Q5) chose "the
/// ghost shows the pixels the screen shows", and a matrix composes with the
/// color effects for free — only a blur still needs its own buffer.
///
/// Rows are `ColorFilter.mode(tint, srcIn)` written out: out.rgb = tint.rgb,
/// out.a = tint.a × in.a. The translation column is 0…255, per
/// `ColorFilter.matrix`'s contract.
List<double> onionTintColorMatrix(int argb) {
  final alpha = argbAlpha(argb) / 255.0;
  final red = argbRed(argb).toDouble();
  final green = argbGreen(argb).toDouble();
  final blue = argbBlue(argb).toDouble();
  return <double>[
    0, 0, 0, 0, red, //
    0, 0, 0, 0, green,
    0, 0, 0, 0, blue,
    0, 0, 0, alpha, 0,
  ];
}

CompositeEffectPaint resolveCompositeEffectPaint(
  List<ResolvedLayerEffect> effects, {
  DrawSpace space = DrawSpace.canvas,
  int? tint,
}) {
  if (effects.isEmpty && tint == null) {
    return CompositeEffectPaint.none;
  }

  // Colour matrices accumulate until a blur forces an offscreen; then the
  // pending matrix becomes the innermost node of the image-filter chain.
  List<double>? pendingColor;
  ui.ImageFilter? chain;
  var outset = 0.0;

  void flushPendingColor() {
    if (pendingColor == null) {
      return;
    }
    final filter = ui.ColorFilter.matrix(pendingColor!);
    chain = chain == null
        ? filter
        : ui.ImageFilter.compose(outer: filter, inner: chain!);
    pendingColor = null;
  }

  for (final effect in effects) {
    switch (_paintPartOf(effect, space)) {
      // Reaching here means a route resolved a chain without splitting it —
      // an assert rather than a silent skip, because the silent version
      // looks exactly like "the artist set Amount to 0".
      case _SplitPart(:final splitBy):
        assert(false, splitBy);
      case _StepPart() || _PaperEdgePart():
        assert(
          false,
          'A shaded effect and a blur on the paper are steps of their own — '
          'see resolveCompositeEffectPlan.',
        );
      case _NoPart():
        break;
      case _ColourPart(:final next):
        pendingColor = pendingColor == null
            ? next
            : composeColorMatrices(next, pendingColor!);
      case _SpatialPart(:final filter, outset: final spread):
        flushPendingColor();
        chain = chain == null
            ? filter
            : ui.ImageFilter.compose(outer: filter, inner: chain!);
        outset += spread;
    }
  }

  if (tint != null) {
    // LAST, over the finished pixel: the ghost is a picture of the row as
    // the screen shows it, converted to the peg's colour.
    final tintMatrix = onionTintColorMatrix(tint);
    pendingColor = pendingColor == null
        ? tintMatrix
        : composeColorMatrices(tintMatrix, pendingColor!);
  }

  if (chain == null) {
    // Null when the chain held nothing this function paints — a release
    // build reaching the assert above lands here, and "no paint state" is
    // the honest answer for it.
    final matrix = pendingColor;
    if (matrix == null || colorMatrixIsIdentity(matrix)) {
      return CompositeEffectPaint.none;
    }
    return CompositeEffectPaint(colorFilter: ui.ColorFilter.matrix(matrix));
  }
  flushPendingColor();
  return CompositeEffectPaint(imageFilter: chain, outsetPixels: outset);
}

/// What a step draws before its painted effects — each draw a fragment
/// shader over the whole raster, at the identity.
sealed class EffectStepLead {
  const EffectStepLead();
}

/// The colour keys standing together in the chain: a draw a key, each over
/// the picture the key before it made and the step's input — what a
/// restore gives back to ([CelColorKey.alphaFor]).
final class KeyRun extends EffectStepLead {
  const KeyRun(this.keys);

  final List<CelColorKey> keys;
}

/// An effect that reads past the pixel and that no `ui.ImageFilter` carries:
/// a directional, a radial or a camera lens blur, drawn in
/// [shadedPassesOf]'s rasters.
///
/// 🔬WHY NOT `ImageFilter.shader`. Measured on Impeller (10-28,
/// `flutter_tester --enable-impeller`): a shader filter is evaluated in
/// device space — a canvas turned 90° left a horizontal blur horizontal,
/// where the Gaussian turned with it — and paints no further than the
/// picture it is handed: a blur 16 long over a dot spread it ±1 px. A step
/// rasters at the identity over a buffer the plan already grew
/// ([CompositeEffectPlan.outsetPixels]) — and INSIDE that raster, where
/// neither holds, a directional or a radial blur's passes are shader
/// filters on Impeller: the layers of one picture, not a raster a pass
/// (🗣️effect-step-passes-each-pay-a-snapshot-Q1 a, `_passesInOnePicture`).
final class ShadedEffect extends EffectStepLead {
  const ShadedEffect(this.effect);

  /// ⛔UNRESOLVED, as [CompositeEffectStep.then]: its length belongs to the
  /// raster the step runs in.
  final ResolvedLayerEffect effect;
}

/// A blur repeating the paper's edge pixels past it and cut to it — a
/// Gaussian's Repeat Edge Pixels (🗣️I-132-Q14 a, 유저 2026-10-28: the
/// paper's edge, on a layer and a folder alike), drawn in
/// [paperEdgeBlurOf]'s raster over the paper cut out of the step's input.
///
/// 🔬WHY A STEP. Measured on Impeller (10-28, `flutter_tester
/// --enable-impeller`): a blur's clamp repeats the edge of the image it is
/// drawn with and paints past it, and drawn from a part of a larger image
/// it repeats nothing — the decal's pixels. The paper has to be an image of
/// its own, and only a step holds one.
final class PaperEdgeEffect extends EffectStepLead {
  const PaperEdgeEffect(this.effect);

  /// ⛔UNRESOLVED, as [ShadedEffect.effect]: its radius belongs to the
  /// raster the step runs in, and the paper to where that raster lies.
  final ResolvedLayerEffect effect;
}

/// One raster a chain takes before the draw that composites it — more than
/// one where its [lead] draws more.
///
/// A step is its [lead] and then the painted effects that follow it, with
/// the lead's last draw: a `ui.Paint` applies its shader, then its colour
/// filter, then its image filter, so "key, then blur" is one raster and
/// needs no second. "Blur, then key" is two, and the first of them has no
/// lead.
@immutable
class CompositeEffectStep {
  const CompositeEffectStep({this.lead, required this.then});

  /// Drawn first; null for a step that only paints.
  final EffectStepLead? lead;

  /// Applied after [lead], in its last draw. ⛔UNRESOLVED, because a blur's
  /// radii belong to the RASTER this step runs in, and only the renderer
  /// knows that scale.
  final List<ResolvedLayerEffect> then;
}

/// A chain that reaches a COMPOSITED picture, in the steps a canvas can take.
///
/// 🚨WHY A CHAIN IS NOT ALWAYS ONE DRAW. Everything a chain used to hold
/// folded into a `ui.Paint`'s colour filter and image filter, so a chain was
/// one draw. A COLOUR KEY is a fragment shader — it can LEAD a draw but never
/// follow anything inside one — so a key that comes after painted state is a
/// second draw, and this is the list of them.
///
/// ⛔The split is not the caller's to get right. [preSteps] are the rasters
/// that happen before the composite draw and [finalPaint] is what that draw
/// carries — the same thing a route folded into its group paint before passes
/// existed. Applying a step's paint twice, or forgetting the last one, would
/// be a rendering bug with no error; there is no way to spell either here.
@immutable
class CompositeEffectPlan {
  const CompositeEffectPlan._({
    required this.preSteps,
    required this.finalPaint,
    required this.outsetPixels,
  });

  static const CompositeEffectPlan none = CompositeEffectPlan._(
    preSteps: [],
    finalPaint: CompositeEffectPaint.none,
    outsetPixels: 0,
  );

  final List<CompositeEffectStep> preSteps;

  /// The paint state the composite draw carries.
  final CompositeEffectPaint finalPaint;

  /// How far the whole chain paints beyond its input's bounds, summed over
  /// every step — ONE number for ONE buffer. Every step rasterises at the
  /// same rect, which costs a little more memory than growing it step by step
  /// and removes every chance of a seam between two of them.
  final double outsetPixels;

  /// True when the chain is what it always was: one draw, no shader.
  bool get isSingleDraw => preSteps.isEmpty;
}

/// [effects] as the steps a composited picture takes.
///
/// [rasterScale] is the scale [finalPaint] will be drawn at, exactly as
/// [resolveCompositeEffectPaint] means it. A step's own effects are left
/// unresolved for the renderer, which knows the scale of the raster it is
/// about to make.
///
/// [paper] is where the paper lies, in canvas space: a radial blur reaches
/// as far past its input as the paper's corners lie from its centre
/// ([_radialBlurPart]), so every route that grows a buffer by the plan
/// says where its paper is.
CompositeEffectPlan resolveCompositeEffectPlan(
  List<ResolvedLayerEffect> effects, {
  DrawSpace space = DrawSpace.canvas,
  int? tint,
  required ui.Rect paper,
}) {
  // Each run is "the lead that opens it — keys, or a shaded effect — then
  // the painted effects until the next lead". The first run has no lead.
  final leads = <EffectStepLead?>[null];
  final runs = <List<ResolvedLayerEffect>>[<ResolvedLayerEffect>[]];
  var outset = 0.0;
  // In the space's own pixels, as the reach it gives is.
  final scaled = ui.Rect.fromLTRB(
    paper.left * space.scale,
    paper.top * space.scale,
    paper.right * space.scale,
    paper.bottom * space.scale,
  );
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key == null) {
      final (lead, reach) = switch (_paintPartOf(
        effect,
        space,
        paper: scaled,
      )) {
        _StepPart(:final reach) => (ShadedEffect(effect), reach),
        _PaperEdgePart(:final reach) => (PaperEdgeEffect(effect), reach),
        _ => (null, 0.0),
      };
      if (lead == null) {
        runs.last.add(effect);
      } else {
        outset += reach;
        leads.add(lead);
        runs.add(<ResolvedLayerEffect>[]);
      }
      continue;
    }
    // ⛔A key at Amount 0 is dropped, not rasterised. The CPU pass drops it
    // for the same reason: "add effect" promises to change nothing, and a
    // raster that changes nothing is still a raster.
    if (key.isNoOp) {
      continue;
    }
    // A key right after a key joins its run: a restore gives back what the
    // keys before it took, so they share the picture they started from.
    if (leads.last case KeyRun(:final keys) when runs.last.isEmpty) {
      keys.add(key);
      continue;
    }
    leads.add(KeyRun([key]));
    runs.add(<ResolvedLayerEffect>[]);
  }
  final last = runs.length - 1;
  final finalPaint = resolveCompositeEffectPaint(
    runs[last],
    space: space,
    tint: tint,
  );
  outset += finalPaint.outsetPixels;
  if (last == 0) {
    // No lead survived: the chain is one draw, exactly as it always was.
    return finalPaint.isEmpty
        ? CompositeEffectPlan.none
        : CompositeEffectPlan._(
            preSteps: const [],
            finalPaint: finalPaint,
            outsetPixels: outset,
          );
  }
  final steps = <CompositeEffectStep>[];
  for (var i = 0; i < last; i += 1) {
    if (leads[i] == null && runs[i].isEmpty) {
      // The leading run is empty whenever the chain opens with a lead,
      // which is the ordinary shape.
      continue;
    }
    outset += resolveCompositeEffectPaint(
      runs[i],
      space: space,
    ).outsetPixels;
    steps.add(CompositeEffectStep(lead: leads[i], then: runs[i]));
  }
  // The last lead has to happen before the final draw carries what follows
  // it.
  steps.add(CompositeEffectStep(lead: leads[last], then: const []));
  return CompositeEffectPlan._(
    preSteps: steps,
    finalPaint: finalPaint,
    outsetPixels: outset,
  );
}

/// The `saveLayer` bounds for a buffered group whose chain paints
/// [outsetPixels] past its input: [bounds] grown by them, so a group blur is
/// not clipped at the buffer edge it was meant to bleed past.
ui.Rect effectBufferBounds(ui.Rect bounds, double outsetPixels) {
  if (outsetPixels <= 0) {
    return bounds;
  }
  return bounds.inflate(outsetPixels);
}

/// How a route paints an ADJUSTMENT scope (R6b) — the semantics in ONE
/// place, so the four composite routes only have to run the steps.
///
/// The row's opacity is a MIX, not a fade: half strength means half a
/// grade, never a half-transparent stack. Getting that right is the whole
/// content of this class, and the naive spelling is wrong twice over:
///
/// - `saveLayer(alpha)` around the filtered scope thins the picture toward
///   transparent — the shocking answer;
/// - drawing the scope unfiltered and then the filtered copy over it with
///   src-over gives `m·F + (1 − m·aF)·U`, which is `lerp(U, F, m)` only
///   where the scope is fully OPAQUE. On a translucent picture it COMPOUNDS
///   alpha (a 50 % layer under a 50 % mix came out at 62.5 %).
///
/// So a colour-only chain folds the mix into its own matrix
/// ([lerpColorMatrixFromIdentity]) and paints in ONE pass — exact, and no
/// second draw of the scope at all. Only a chain with a BLUR needs the two
/// passes, and those are done inside one crossfade buffer with the second
/// pass ADDED (`BlendMode.plus`) onto a `1 − mix` first pass, which is a
/// true lerp with alpha left alone.
class AdjustmentScopePass {
  const AdjustmentScopePass({
    required this.bufferBounds,
    required this.filteredPaint,
    this.crossfadeLayerPaint,
    this.unfilteredPaint,
    this.blitEffects = CompositeEffectPaint.none,
    this.preSteps = const [],
    this.outsetPixels = 0,
  });

  /// How far the chain paints past the scope, summed over its steps — what
  /// says the raster is read by a chain that spreads (`rasterCellFor`).
  final double outsetPixels;

  /// The chain the filtered pass's BLIT carries: the whole of it where it
  /// spreads (a blur), else none — the chain then rides [filteredPaint].
  ///
  /// 🚨A BLUR READS THE SCOPE'S RASTER, NEVER A LAYER (card
  /// nested-folder-buffers-read-past-the-view). A blur reduces what it reads
  /// on a grid counted from that picture's own corner, and a `saveLayer`'s
  /// picture starts where the clip cuts it — at the view's edge, one pixel
  /// further at each pan — while the raster lies on the canvas's grid
  /// (`blurReductionCell`'s law). 🔬On the Windows app (2026-10-27) a blurred
  /// adjustment by the view's edge came out 2/255 apart pan to pan, and
  /// 4/255 apart from a blurred folder over the same row; with the blur on
  /// the blit, 0 and 0. The layer keeps the pass's alpha and blend, so the
  /// crossfade still adds layers ([composeAdjustmentScope]).
  final CompositeEffectPaint blitEffects;

  /// The rasters the chain takes before either pass composites the scope —
  /// its colour keys, which are shaders and cannot ride a pass's paint.
  ///
  /// ⚠️Only the FILTERED pass blits the result. The mix crossfades between
  /// the scope and the scope with the chain on it, so the unfiltered pass
  /// blits the raw raster (see [composeAdjustmentScope]).
  final List<CompositeEffectStep> preSteps;

  /// The buffer bounds for every pass.
  final ui.Rect bufferBounds;

  /// The filtered pass's layer: its alpha and blend, and the chain where it
  /// does not spread ([blitEffects]). Non-null always.
  final ui.Paint filteredPaint;

  /// Non-null ONLY when the scope must crossfade (a blur below full mix):
  /// the outer buffer the two passes add up inside.
  final ui.Paint? crossfadeLayerPaint;

  /// The unfiltered pass's paint; non-null exactly when
  /// [crossfadeLayerPaint] is.
  final ui.Paint? unfilteredPaint;

  /// Whether the route has to COMPOSITE the scope a second time. It does not
  /// have to PAINT it twice — see [composeAdjustmentScope].
  bool get crossfades => crossfadeLayerPaint != null;
}

/// How the passes go over a scope that has already been rasterised — the
/// `compose` a route hands to `drawSubtreeAsImage`.
///
/// ⛔ONE COPY. Three routes ran these six lines and the shape is easy to get
/// subtly wrong (a mutation that fed the FILTERED paint to the unfiltered
/// pass survived every test in the repo, because each route held its own
/// copy and no test drove the branch at any of them). Now there is one
/// implementation, and the proof that it equals the recipe it replaced tests
/// that implementation.
///
/// 🧪THE LAYERS ARE WHY IT IS EXACT. Blitting with a pass's own paint instead
/// of restoring a layer into it rounds each pass separately, and a crossfade
/// ADDS two of them: measured at 2/255 over 488 pixels. Painting the scope
/// once was always the win; the saveLayer was never the cost.
void Function(void Function(ui.Paint paint, {bool stepped}) blit)
composeAdjustmentScope(
  ui.Canvas canvas,
  AdjustmentScopePass pass,
) => (blit) {
  if (pass.crossfades) {
    canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
    canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
    // ⛔THE RAW SCOPE. The mix crossfades between the scope and the scope
    // WITH the chain on it, and the chain now includes colour keys — which
    // ride the raster rather than a paint. An unfiltered pass that blitted
    // the keyed raster would key at full strength however low the mix went.
    blit(ui.Paint(), stepped: false);
    canvas.restore();
  }
  canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
  final carried = ui.Paint();
  pass.blitEffects.applyTo(carried);
  blit(carried);
  canvas.restore();
  if (pass.crossfades) {
    canvas.restore();
  }
};

/// Resolves the pass for an adjustment scope of [effects] at [mix] over
/// [bounds]. [rasterScale] follows the same rule as
/// [resolveCompositeEffectPaint].
///
/// A route runs it as ONE raster and one or two blits. The scope is the same
/// picture in both passes, so it is rasterised once — on the playback route
/// "drawing the scope" means awaiting every layer image in it, and the second
/// pass was not a rounding error. The blits go as [composeAdjustmentScope]
/// lays them.
///
/// [paper] is where the paper lies, as [resolveCompositeEffectPlan] asks.
AdjustmentScopePass resolveAdjustmentScopePass({
  required ui.Rect bounds,
  required List<ResolvedLayerEffect> effects,
  required double mix,
  DrawSpace space = DrawSpace.canvas,
  required ui.Rect paper,
}) {
  final strength = mix.clamp(0.0, 1.0);
  if (strength < 1) {
    final colorMatrix = resolveColorOnlyMatrix(effects);
    if (colorMatrix != null) {
      // The exact answer in one pass: the mix IS part of the matrix.
      return AdjustmentScopePass(
        bufferBounds: bounds,
        filteredPaint: ui.Paint()
          ..colorFilter = ui.ColorFilter.matrix(
            lerpColorMatrixFromIdentity(colorMatrix, strength),
          ),
      );
    }
  }
  final resolved = resolveCompositeEffectPlan(
    effects,
    space: space,
    paper: paper,
  );
  final plan = resolved.finalPaint;
  final bufferBounds = effectBufferBounds(bounds, resolved.outsetPixels);
  // What spreads rides the blit ([AdjustmentScopePass.blitEffects]); a
  // chain per pixel rides the pass's layer, as it always did.
  final blitEffects = plan.imageFilter == null
      ? CompositeEffectPaint.none
      : plan;
  final layerEffects = blitEffects.isEmpty ? plan : CompositeEffectPaint.none;
  if (strength >= 1) {
    final paint = ui.Paint();
    layerEffects.applyTo(paint);
    return AdjustmentScopePass(
      bufferBounds: bufferBounds,
      filteredPaint: paint,
      blitEffects: blitEffects,
      preSteps: resolved.preSteps,
      outsetPixels: resolved.outsetPixels,
    );
  }
  // A spatial chain below full strength: two passes ADDED inside one
  // buffer. `plus` on premultiplied colour gives (1−m)·U + m·F exactly,
  // and the two alphas sum back to the scope's own.
  final filtered = ui.Paint()
    ..color = alphaOnly(strength)
    ..blendMode = ui.BlendMode.plus;
  layerEffects.applyTo(filtered);
  return AdjustmentScopePass(
    bufferBounds: bufferBounds,
    filteredPaint: filtered,
    crossfadeLayerPaint: ui.Paint(),
    unfilteredPaint: ui.Paint()
      ..color = alphaOnly(1 - strength),
    blitEffects: blitEffects,
    preSteps: resolved.preSteps,
    outsetPixels: resolved.outsetPixels,
  );
}
