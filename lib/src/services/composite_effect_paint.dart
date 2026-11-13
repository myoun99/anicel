import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;

import '../core/argb_channels.dart';
import '../core/color_matrix.dart';
import '../models/canvas_size.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import 'camera_lens_blur_passes.dart';
import 'cel_source_effect_pass.dart';
import 'directional_blur_passes.dart';
import 'fx_plugin_values.dart' show fxPluginRowsOf, fxPluginValuesOf;
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
    switch (_paintPartOf(effect)) {
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
      final part = _paintPartOf(effect);
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
/// nothing a paint can carry. Every reader of a chain — the plan
/// ([paintedEffectsOf]), an adjustment's one pass
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

/// The part a paint carries past colour: a Gaussian.
final class _SpatialPart extends _PaintPart {
  const _SpatialPart(this.blur);

  final GaussianBlur blur;
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
/// its filter repeats the edge of the image it is drawn with, so it is
/// drawn over the paper cut out alone, a step of its own.
final class _PaperEdgePart extends _PaintPart {
  const _PaperEdgePart(this.blur);

  final GaussianBlur blur;

  /// How far past its input it paints, inside the paper.
  double get reach => blur.reach;
}

/// A plugin's effect: a step of its own over the picture before it, read
/// back from the GPU ([PluginEffect]), [reach] past its input.
final class _PluginPart extends _PaintPart {
  const _PluginPart({required this.reach});

  /// How far past its input it paints, as its plugin says.
  final double reach;
}

/// A kind no paint carries: the chain is split before a paint is resolved.
final class _SplitPart extends _PaintPart {
  const _SplitPart(this.splitBy);

  /// What takes it out of the chain — the assert's word to a route that
  /// resolved a chain without splitting it.
  final String splitBy;
}

/// [paper] is where the paper lies — what a radial blur's centre stands on
/// ([_radialBlurPart]); a reader that does no spatial work at all, the
/// eyedropper's, asks without one.
///
/// 🚨IN CANVAS PIXELS, a canvas pixel a pixel: the engine runs a chain at
/// the canvas's own. ↩️A draw space scaled what reaches past the pixel
/// (`DrawSpace`, 유저 2026-08-28 「남은 개선안까지 깔끔하게가자」): Skia mapped a
/// sigma through a canvas-space CTM, and the playback cache rastered pre-
/// scaled with none, till every row stood on the engine and the Flutter
/// chain went (the-flutter-fx-chain-is-a-second-chain).
_PaintPart _paintPartOf(ResolvedLayerEffect effect, {ui.Rect? paper}) {
  // An effect that changes no pixel is no part, whatever its kind
  // ([ResolvedLayerEffect.isNoOp]: its defaults, or its strength of nothing).
  if (effect.isNoOp) {
    return const _NoPart();
  }
  return switch (effect.kind) {
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
    EffectKind.blur => _blurPart(effect),
    EffectKind.directionalBlur => _directionalBlurPart(effect),
    EffectKind.radialBlur => _radialBlurPart(effect, paper),
    EffectKind.cameraLensBlur => _cameraLensBlurPart(effect, paper),
    // ⛔A KEY IS A LEAD OF THE PLAN, NEVER A PAINT: `resolveCompositeEffectPlan`
    // takes each into a `KeyRun` before a paint is resolved. A color key
    // changes ALPHA by a threshold test — there is no color matrix for it,
    // the same way there is none for a blur; the eyedropper applies the
    // keys itself (`CelColorKey.alphaFor`).
    EffectKind.colorKey => const _SplitPart(
      'Colour keys are a plan\'s leads, taken before a paint is '
      'resolved — see resolveCompositeEffectPlan.',
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
    // 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고」 — a plugin,
    // at the head of a cel's chain or past anything, runs over the picture
    // the chain made before it, read back.
    EffectKind.plugin => _pluginPart(effect, paper),
  };
}

/// A plugin's step ([PluginEffect]), reaching as far as its plugin says —
/// where it has a run on this device ([ResolvedLayerEffect.run]); none
/// where it has not, or where its plugin cannot say: drawn as if off, as a
/// plugin that fails.
_PaintPart _pluginPart(ResolvedLayerEffect effect, ui.Rect? paper) {
  final run = effect.run;
  if (run == null) {
    return const _NoPart();
  }
  final canvas = paper == null
      ? const CanvasSize(width: 0, height: 0)
      : CanvasSize(
          width: paper.width.round(),
          height: paper.height.round(),
        );
  final across = paper == null
      ? double.infinity
      : math.max(paper.width, paper.height);
  if (run.runner.toCome != null) {
    // 🚨NOT KNOWN YET, AS FAR AS THE PAPER: its build is still being opened
    // off the isolate that asks (an-endless-plugin-stalls-the-app ④,
    // 2026-11-12). No step of it is run till it is — a recording waits and
    // is made again then (`FrameKernelsToCome.forAPlugin`) —, so this
    // reach is drawn by none; a route that draws it as if off is told it
    // reads as far as any plugin may, never less than this one will (0
    // would cut what it reads at the row's own extent,
    // [rowExtentWithItsReach]).
    return _PluginPart(reach: across);
  }
  final values = fxPluginValuesOf(
    effect,
    paper: canvas,
    rows: fxPluginRowsOf(effect, run),
  );
  final reach = run.runner.reach(values, (
    frameIndex: run.moment.frameIndex,
    time: run.moment.time,
    frameRate: run.moment.frameRate,
    // A canvas pixel a pixel, as the chain runs ([_paintPartOf]).
    scale: 1,
  ));
  if (reach == null) {
    // What it draws tells the rest, once its step has run (FxPluginStages).
    run.told?.call(failed: true);
    return const _NoPart();
  }
  // No farther than the paper is long: a plugin that names a wild reach is
  // not handed a picture past what the device can hold — the device's guard
  // of the first cut (`_bounded`, 2c09ca4c5, 2026-10-30, 🗣️I-132-Q32 「b 로
  // 첫 판」). ↩️That guard bounded the head of a cel's chain alone, by what
  // the cel could store (its storable rect's long side, the pasteboard
  // with it), while that plugin ran on the CPU over the cel. A step of a
  // chain is planned where its space's paper is known and no cel is — a
  // folder's, an adjustment's and the V row's chains have none — so the
  // bound every chain has is the paper's long side, and one plugin has one
  // bound wherever it stands (관제 2026-11-11, ⓓ; 절대명령 1): only a reach
  // past the paper's long side reads less than it did
  // (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
  return _PluginPart(reach: math.min(math.max(0, reach).toDouble(), across));
}

/// A Gaussian: a filter the composite draw carries, or a step where it
/// repeats the paper's edge ([PaperEdgeEffect]).
_PaintPart _blurPart(ResolvedLayerEffect effect) {
  final radius = effect.parameter('blurriness');
  // The words of Blur Dimensions, in order: both, across, up and down.
  final dimensions = effect.parameter('blurDimensions').round();
  final radiusX = dimensions == 2 ? 0.0 : radius;
  final radiusY = dimensions == 1 ? 0.0 : radius;
  final blur = GaussianBlur(
    sigmaX: radiusX * blurSigmaPerRadius,
    sigmaY: radiusY * blurSigmaPerRadius,
    reachX: blurSpreadForRadius(radiusX),
    reachY: blurSpreadForRadius(radiusY),
    repeatsTheEdge: effect.flag('repeatEdgePixels'),
  );
  return blur.repeatsTheEdge ? _PaperEdgePart(blur) : _SpatialPart(blur);
}

/// What a run of a chain's painted effects paints, one after another
/// ([paintedEffectsOf]).
sealed class PaintedEffect {
  const PaintedEffect();
}

/// The colour effects standing together, folded into one 4×5 matrix.
final class PaintedColour extends PaintedEffect {
  const PaintedColour(this.matrix);

  final List<double> matrix;
}

/// fx Gaussian Blur at a draw's scale ([_blurPart]) as the engine takes it:
/// its sigma each way, how far each way it reaches past a pixel
/// ([blurSpreadForRadius]), and whether it repeats its input's edge — the
/// engine lays the Gaussian itself from these numbers (🗣️유저
/// gpu-canonical-store-Q2, composite_tree_plan.dart).
@immutable
final class GaussianBlur extends PaintedEffect {
  const GaussianBlur({
    required this.sigmaX,
    required this.sigmaY,
    required this.reachX,
    required this.reachY,
    required this.repeatsTheEdge,
  });

  final double sigmaX;
  final double sigmaY;
  final double reachX;
  final double reachY;

  /// Whether it reads past its input as the input's edge pixels. Not as a
  /// rule: a layer's artwork must not smear its edge pixels outward forever
  /// — outside its coverage there is nothing, and that is what the picture
  /// should show. Over the paper cut out alone, the edge is the paper's.
  /// ↩️The Flutter walk drew it by a `ui.ImageFilter.blur`, DECAL, CLAMP for
  /// this, till the Flutter chain went (the-flutter-fx-chain-is-a-second-chain).
  final bool repeatsTheEdge;

  /// How far past its input it paints: the farther way's reach.
  double get reach => math.max(reachX, reachY);

  /// The whole pixels its spread touches each way: how far the engine's
  /// weights reach either side of a pixel, and so how far past what it
  /// reads a chain puts it — one answer for both, or a reach put short
  /// leaves its last pixels out.
  (int, int) get wholeReach => (reachX.ceil(), reachY.ceil());
}

/// What [effects] — a run of a chain's painted effects, which a draw
/// carries ([CompositeEffectPlan.finalEffects], a step's `then`) — paint,
/// in their order: each Gaussian, and the colour between them folded into
/// one matrix; nothing for an effect that changes no pixel. The engine
/// lays each (composite_tree_plan.dart).
List<PaintedEffect> paintedEffectsOf(List<ResolvedLayerEffect> effects) {
  final painted = <PaintedEffect>[];
  for (final effect in effects) {
    switch (_paintPartOf(effect)) {
      // Reaching here means a route resolved a chain without splitting it —
      // an assert rather than a silent skip, because the silent version
      // looks exactly like "the artist set Amount to 0".
      case _SplitPart(:final splitBy):
        assert(false, splitBy);
      case _StepPart() || _PaperEdgePart() || _PluginPart():
        assert(
          false,
          'A shaded effect, a blur on the paper and a plugin are steps of '
          'their own — see resolveCompositeEffectPlan.',
        );
      case _NoPart():
        break;
      case _ColourPart(:final next):
        if (painted.lastOrNull case PaintedColour(:final matrix)) {
          painted.last = PaintedColour(composeColorMatrices(next, matrix));
        } else {
          painted.add(PaintedColour(next));
        }
      case _SpatialPart(:final blur):
        painted.add(blur);
    }
  }
  return painted;
}

/// A directional blur: a step of passes along its way.
_PaintPart _directionalBlurPart(ResolvedLayerEffect effect) {
  final length = effect.parameter('blurLength');
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
_PaintPart _radialBlurPart(ResolvedLayerEffect effect, ui.Rect? paper) {
  final amount = effect.parameter('amount');
  // Asked by a reader that does no spatial work: it skips the part, so
  // nothing in it is read.
  if (paper == null) {
    return const _StepPart([], reach: 0);
  }
  final point = effectPointOnPaper(
    effect.points['center'],
    CanvasSize(width: paper.width.round(), height: paper.height.round()),
  );
  final center = paper.topLeft + ui.Offset(point.x, point.y);
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
/// its radius (the engine's iris_table.wgsl): that is how far it reaches
/// past its input. Its edge, repeated, is the paper's on whole pixels, as
/// the Gaussian's is ([paperOnWholePixels]).
_PaintPart _cameraLensBlurPart(ResolvedLayerEffect effect, ui.Rect? paper) {
  final radius = effect.parameter('blurRadius');
  final repeatsTheEdge = effect.flag('repeatEdgePixels');
  return _StepPart(
    // Asked with no paper where it repeats the paper's edge: a reader that
    // does no spatial work, which skips the part, so nothing in it is read.
    repeatsTheEdge && paper == null
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

/// The rasters [effect] — a step's [ShadedEffect] — is drawn in, with
/// [paper] where the paper lies: empty where it changes no pixel there.
List<ShadedPass> shadedPassesOf(
  ResolvedLayerEffect effect, {
  required ui.Rect paper,
}) => switch (_paintPartOf(effect, paper: paper)) {
  _StepPart(:final passes) => passes,
  _ => const [],
};

/// The blur [effect] — a step's [PaperEdgeEffect] — draws over the paper:
/// null where it changes no pixel there.
GaussianBlur? paperEdgeBlurOf(ResolvedLayerEffect effect) =>
    switch (_paintPartOf(effect)) {
      _PaperEdgePart(:final blur) => blur,
      _ => null,
    };

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
/// (🗣️effect-step-passes-each-pay-a-snapshot-Q1 a, `applyEffectSteps`, as
/// the Flutter chain ran them till it went —
/// the-flutter-fx-chain-is-a-second-chain).
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

/// A plugin's effect past a cel's own pixels (🗣️I-132-Q34 a), run over the
/// step's input read back from the GPU — where a route can wait for it
/// (`FxPluginStages`); drawn as if off where it cannot.
final class PluginEffect extends EffectStepLead {
  const PluginEffect(this.effect);

  /// The sample with its run ([ResolvedLayerEffect.run]); the step's scale
  /// is the raster's, given where it runs.
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
/// that happen before the composite draw and [finalEffects] are what that
/// draw carries. Running a step's effects twice, or forgetting the last
/// ones, would be a rendering bug with no error; there is no way to spell
/// either here.
///
/// ↩️The draw carried them as a `ui.Paint` too (`CompositeEffectPaint`, put
/// on every Flutter route by one `layerCompositePaint` once #1304 found the
/// routes clamping opacity apart), till every row stood on the engine and
/// the Flutter chain went (the-flutter-fx-chain-is-a-second-chain): the
/// engine lays them (composite_tree_plan.dart).
@immutable
class CompositeEffectPlan {
  const CompositeEffectPlan._({
    required this.preSteps,
    required this.finalEffects,
    required this.outsetPixels,
  });

  static const CompositeEffectPlan none = CompositeEffectPlan._(
    preSteps: [],
    finalEffects: [],
    outsetPixels: 0,
  );

  final List<CompositeEffectStep> preSteps;

  /// The painted effects the composite draw carries, unresolved — what the
  /// engine lays after the last step ([paintedEffectsOf]).
  final List<ResolvedLayerEffect> finalEffects;

  /// How far the whole chain paints beyond its input's bounds, summed over
  /// every step — ONE number for ONE buffer. Every step rasterises at the
  /// same rect, which costs a little more memory than growing it step by step
  /// and removes every chance of a seam between two of them.
  final double outsetPixels;

  /// True when the chain is what it always was: one draw, no shader.
  bool get isSingleDraw => preSteps.isEmpty;
}

/// [effects] as the steps a composited picture takes. A step's own effects
/// are left unresolved for the renderer, which lays the raster it runs in.
///
/// [paper] is where the paper lies, in canvas space: a radial blur reaches
/// as far past its input as the paper's corners lie from its centre
/// ([_radialBlurPart]), so every route that grows a buffer by the plan
/// says where its paper is.
CompositeEffectPlan resolveCompositeEffectPlan(
  List<ResolvedLayerEffect> effects, {
  required ui.Rect paper,
}) {
  // Each run is "the lead that opens it — keys, or a shaded effect — then
  // the painted effects until the next lead". The first run has no lead.
  final leads = <EffectStepLead?>[null];
  final runs = <List<ResolvedLayerEffect>>[<ResolvedLayerEffect>[]];
  var outset = 0.0;
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key == null) {
      final (lead, reach) = switch (_paintPartOf(effect, paper: paper)) {
        _StepPart(:final reach) => (ShadedEffect(effect), reach),
        _PaperEdgePart(:final reach) => (PaperEdgeEffect(effect), reach),
        _PluginPart(:final reach) => (PluginEffect(effect), reach),
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
  final carried = paintedEffectsOf(runs[last]);
  outset += _reachOf(carried);
  if (last == 0) {
    // No lead survived: the chain is one draw, exactly as it always was.
    return _paints(carried)
        ? CompositeEffectPlan._(
            preSteps: const [],
            finalEffects: runs[last],
            outsetPixels: outset,
          )
        : CompositeEffectPlan.none;
  }
  final steps = <CompositeEffectStep>[];
  for (var i = 0; i < last; i += 1) {
    if (leads[i] == null && runs[i].isEmpty) {
      // The leading run is empty whenever the chain opens with a lead,
      // which is the ordinary shape.
      continue;
    }
    outset += _reachOf(paintedEffectsOf(runs[i]));
    steps.add(CompositeEffectStep(lead: leads[i], then: runs[i]));
  }
  // The last lead has to happen before the final draw carries what follows
  // it.
  steps.add(CompositeEffectStep(lead: leads[last], then: const []));
  return CompositeEffectPlan._(
    preSteps: steps,
    finalEffects: runs[last],
    outsetPixels: outset,
  );
}

/// How far [painted] paints past its input: each Gaussian's reach, summed,
/// as each blurs what the one before it made.
double _reachOf(List<PaintedEffect> painted) => painted.fold(
  0.0,
  (reach, each) => each is GaussianBlur ? reach + each.reach : reach,
);

/// Whether [painted] changes a pixel: a Gaussian does, a colour where it is
/// not the identity.
bool _paints(List<PaintedEffect> painted) => painted.any(
  (each) => switch (each) {
    GaussianBlur() => true,
    PaintedColour(:final matrix) => !colorMatrixIsIdentity(matrix),
  },
);

/// The `saveLayer` bounds for a buffered group whose chain paints
/// [outsetPixels] past its input: [bounds] grown by them, so a group blur is
/// not clipped at the buffer edge it was meant to bleed past.
ui.Rect effectBufferBounds(ui.Rect bounds, double outsetPixels) {
  if (outsetPixels <= 0) {
    return bounds;
  }
  return bounds.inflate(outsetPixels);
}

/// The rect a row STANDS FOR — [content], all it holds and draws, in its
/// own space — grown by how far its own chain [effects] paints past it, as
/// a folder's buffer is ([effectBufferBounds]): what a frame's world, a
/// folder's buffer and the row's own chain take it to be.
///
/// 🗣️pasteboard-blur-cut-at-row-extent-Q1 (유저 2026-11-08 19:56): 「행
/// 범위에 그 행의 번짐을 넣는다」. ↩️A row stood for its content alone: a
/// blur on it was cut on the pasteboard at the edge of its last tile, and
/// differed there between a float held and the float landed — and a
/// plug-in at the head of a cel's chain, a step of it now, had its reach
/// cut so (float-warp-resamples-in-the-c-engine (2) ⓑ, 2026-11-11).
ui.Rect rowExtentWithItsReach(
  ui.Rect content,
  List<ResolvedLayerEffect> effects, {
  required ui.Rect paper,
}) => effects.isEmpty
    ? content
    : effectBufferBounds(
        content,
        resolveCompositeEffectPlan(effects, paper: paper).outsetPixels,
      );
