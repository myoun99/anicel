import 'dart:math' as math;
import 'dart:typed_data';

/// The one image resampler: **one inverse map, and two ways of reading the
/// preimage it produces — averaged, or elected.**
///
/// The transform tool goes through here — affine, perspective quad and
/// mesh, preview and commit alike, which is what makes those two the same
/// bytes. The rest do not yet: the composite path still hands its scaling
/// to Skia, import fit still uses `FilterQuality.high`, and on-screen
/// minification is still a `FilterQuality` too. Those move over one at a
/// time.
///
/// Once they have, every surface that turns pixels into other pixels
/// arrives here. They differ in what matrix they hand in, never in how a
/// destination pixel is built.
///
/// ## Why two modes and not two resamplers
///
/// Preserving the source colours exactly means the last operation has to be
/// a CHOICE, not a mixture — and "smooth when enlarged" is precisely the
/// production of in-between values. Those requirements collide head-on, so
/// no single accumulator can serve both. What CAN be shared is everything
/// before it: the inverse map, the Jacobian, the exact-translation short
/// circuit and the flat-support early-out. The accumulator splits, and so
/// does the way each one reaches into the source:
///
/// * [ResampleMode.blend] — gathers taps under a tent and takes their
///   weighted mean. New colours by definition.
/// * [ResampleMode.pick] — supersamples the preimage and elects the colour
///   holding the most of it, copying its 32-bit word through byte for
///   byte.
///
/// The bit that selects the branch comes from a property the user set, not
/// from inspecting the picture.
///
/// ## The contract Pick keeps
///
/// > Every output pixel is a byte-exact copy of some input pixel that
/// > overlapped that pixel's preimage.
///
/// Stated about provenance rather than about colour counts, it is
/// content-independent and mechanically testable.
///
/// The invariant that makes it true: **a Pick payload never enters colour
/// arithmetic.** It is carried as one 32-bit word, compared as one word and
/// stored as one word. Splitting it into channels, premultiplying it, or
/// letting it through an unpremultiply is how a resampler that advertises
/// "no anti-aliasing" still leaks a couple of least-significant bits.
///
/// ## Footprint
///
/// A destination pixel is not a point: it is a unit square whose preimage
/// is a parallelogram, and sampling it as a point is exactly what makes
/// nearest-neighbour drop thin lines under reduction. Both modes read that
/// preimage — but they read it in different ways, and the difference is
/// the whole design.
///
/// **Blend reconstructs**, so it needs a filter support. The radius comes
/// from the inverse Jacobian — one output step along x moves `(a, d)` in
/// source space, one along y moves `(b, e)` — so the tent reaches
/// `|a| + |b|` horizontally and `|d| + |e|` vertically. Those extents
/// describe the preimage's axis-aligned BOUNDING BOX rather than the
/// preimage, which for a weighted mean is a slightly wider blur and
/// nothing worse.
///
/// **Pick elects**, and an election held over the bounding box is not an
/// election over the preimage. A rotation makes the box bigger than what
/// it contains by `1 + |sin 2θ|` — twice the area at 45° — and every
/// square unit of the excess is ground the destination pixel never
/// reached. Three rounds of separable weighting tried to shrink that box
/// back down onto the parallelogram, and all three failed the same way,
/// because a product of two one-dimensional weights integrates over a
/// RECTANGLE and a rotated anisotropic preimage is not one: shrink the box
/// and no tap scores at all, so opaque artwork grows transparent holes;
/// leave it and taps outside the image outvote the taps inside it. The
/// problem is not which box.
///
/// So Pick does not use a box. It SUPERSAMPLES: the destination pixel is
/// cut into an N×N grid, every subsample goes through the same inverse
/// map, and whichever source pixel it lands in gets a vote. The colour
/// holding the most votes wins, and that IS the area argmax by
/// construction — of the true preimage, at any angle, under any
/// anisotropy, through a perspective divide, none of which the accumulator
/// needs to know about. There is no footprint to starve and none to flood.
/// `test/services/resample/coverage_truth.dart` is the same computation
/// written for clarity rather than speed, and the kernel is pinned against
/// it.
///
/// The measured consequence: a one-pixel LINE now survives while
/// `scale > 0.5` at EVERY angle, where the boxed version needed
/// `scale > (|cos θ| + |sin θ|)/2` — 0.707 at 45°, which is why an
/// ordinary rotate-and-shrink used to erase line art.
///
/// An ISOLATED one-pixel mark is a different sum and a different bound: it
/// holds `scale²` of its preimage against a ground that votes as one
/// token, so it needs `scale > 1/√2` at every angle including 0°. That is
/// the area argmax answering correctly rather than a footprint failing —
/// the oracle drops it in the same place.
///
/// The radius floor is 1.0 and belongs to Blend alone now; Pick has no
/// radius left to floor. See [resampleRadiusFloor].
///
/// ## Byte order
///
/// Pixels are straight-alpha RGBA8, `[R, G, B, A]` ascending in memory, and
/// this file reads them four bytes at a time as one machine word. On the
/// little-endian targets the app ships to that word is `A<<24 | B<<16 |
/// G<<8 | R`, which is what the shifts below assume — the same assumption
/// the C kernel makes, so the two stay byte-identical. A big-endian port
/// would have to revisit both together.
enum ResampleMode {
  /// Weighted mean through a tent kernel. Produces new colours; that is the
  /// point.
  ///
  /// Tent, not a cubic: cubics have negative lobes, and a negative lobe
  /// beside a dark line produces a pixel BRIGHTER than anything in its own
  /// footprint — the pale halo that shows up along every inked edge. A tent
  /// is a convex combination, so its output is confined to the min..max of
  /// the pixels it read and the halo cannot exist.
  blend,

  /// Area argmax over a supersampled preimage. The source colours come
  /// through untouched.
  pick,
}

/// Lower bound for the footprint radius — **Blend's radius, and only
/// Blend's.**
///
/// It stops a tent narrower than a pixel, which would sample nothing but
/// the pixel it sits on and make Blend a point sampler. That is the only
/// job it has left.
///
/// It used to be 1.5 for Pick, on the theory that a wider ring smooths the
/// jagged spurs a rotation leaves along an edge — measured on a dense
/// production cel, where it did. That number stopped meaning anything the
/// moment Pick's weight became a measure of AREA: a floor above the true
/// extent claims the preimage reaches further than it does, so the vote
/// counts area the destination pixel never covered. It was not a quality
/// knob, it was a lie about geometry, and it cost what a lie about
/// geometry costs — on 1px line art the inflated ring let ground outvote
/// ink and deleted the drawing.
///
/// Pick has since stopped having a radius at all: it supersamples the
/// preimage instead of gathering taps around it. The parameter survives on
/// both call paths because the native binding demands an explicit floor
/// while the Dart reference defaults one, and Pick ignores whatever it is
/// handed. The mode argument stays for the same reason it always did — so
/// callers ask a question rather than hard-code an answer.
double resampleRadiusFloor(ResampleMode mode) => 1.0;

/// Subsamples per axis at the two ends of [resampleSamplesPerAxis].
///
/// **8** is the floor as MARGIN above the two-per-source-pixel rate the
/// rule gives near 1:1 — not as a rescue, which is what an earlier version
/// of this comment claimed on a measurement that does not reproduce. Rate
/// 4 collapses on a hairline only with [kResampleRefineLimit] disabled;
/// with refinement in place the two are close, and over the sweep in
/// `resample_kernel_test.dart` rate 4 keeps 91.7% of the oracle's ink at
/// worst against 8's 95.8%, at the same worst disagreement. **8 buys the
/// margin. The refinement loop buys the drawing.**
///
/// **16** is the ceiling because nothing above it moved on the rotated
/// work the sampler is responsible for: 24 and 32 per axis returned the
/// same pixels for four and sixteen times the samples.
///
/// The ceiling is also what bounds Pick's work without a radius clamp. A
/// corner-pin that used to ask for 2.5×10⁸ taps in a single destination
/// pixel now asks for 256 samples like every other pixel, and aliases past
/// that exactly as a mip-less sampler does.
const int kResampleMinSamplesPerAxis = 8;
const int kResampleMaxSamplesPerAxis = 16;

/// How far a TIED vote is allowed to refine, per axis.
///
/// [resampleSamplesPerAxis] sets a rate that resolves an ordinary
/// preimage; a pixel whose top two colours come back with equal counts is
/// re-sampled at twice that, up to this.
///
/// Not refining at all is not an option: it kept 54% of the oracle's ink
/// at 0.55×, which is a hairline going missing.
///
/// 16 rather than 32 is a cost call, and the honest version of it is
/// narrower than the one this comment used to make. **A second doubling
/// does change pixels** — 397 across a three-fixture sweep, and it fixes
/// most of the decisively-wrong ones the sampler still has. What makes 16
/// defensible is that the failures it leaves are almost all AXIS-ALIGNED,
/// and those no longer reach the sampler at all: they go down the exact
/// path above, where there is no quantisation to refine away. What is left
/// for the sampler is rotated work, where one doubling is enough and a
/// second costs 1.1–1.7× on a full canvas for pixels nobody can pick out.
///
/// ⚠️ And do not repeat the claim this replaced — "ties that survive the
/// cap are the real ones, a feature covering exactly half". Traced, the
/// surviving ties were 55/45, not 50/50. The proof that SOME ties are
/// unbreakable is not a proof that all surviving ones are, which is the
/// same shape of error as the round before: a bound asserted in a comment,
/// believed, and wrong.
const int kResampleRefineLimit = 16;

/// Any source index this large is outside every possible image, so the
/// bounds test can be made before the rounding rather than after it.
///
/// 2⁵³ is where doubles stop representing consecutive integers, and well
/// past it `round()` saturates in Dart while `llround()` is undefined in
/// C — the two would disagree on a value neither can name. Both kernels
/// answer "outside" first, which is the same answer rounding would have
/// produced for every image size that fits in an int32.
const double kResampleIndexLimit = 9007199254740992.0;

/// How many subsamples one destination axis is cut into, given
/// [squaredStep] — the SQUARED length, in source pixels, of the step that
/// axis takes through the source.
///
/// Stepping one destination pixel along x moves `(a, d)` in source space
/// and along y moves `(b, e)`, so those two lengths are what decide how
/// densely each axis has to be cut. Taking the rate from the preimage's
/// AREA instead looks equivalent and is not: a map that shrinks 5:1 along
/// one axis while magnifying 2× along the other has an area of 2.5 and
/// needs ten samples across, and reading the area gave it four. Anisotropy
/// is the case this whole feature keeps failing on, so the rate is now
/// measured per axis or not at all.
///
/// The rule is `⌈2·√squaredStep⌉` — two samples per source pixel —
/// clamped to [kResampleMinSamplesPerAxis]..[kResampleMaxSamplesPerAxis].
/// It is written as a comparison chain against the SQUARED thresholds so
/// that no square root and no `ceil` appear: the answer is then a pure
/// ordering of doubles, which the C mirror cannot round differently and
/// which cannot overflow on the way to an integer. `n = ⌈2L⌉` means
/// `L² ∈ ((n−1)²/4, n²/4]`, and those quarters are the constants below.
///
/// A non-finite step — reachable from a matrix whose entries overflow —
/// fails every comparison and falls through to the ceiling, which
/// terminates on samples that all land outside. That is deliberate, and it
/// is why every test here is `<=`: NaN fails all of them in both
/// languages.
int resampleSamplesPerAxis(double squaredStep) {
  if (squaredStep <= 16) return 8;
  if (squaredStep <= 20.25) return 9;
  if (squaredStep <= 25) return 10;
  if (squaredStep <= 30.25) return 11;
  if (squaredStep <= 36) return 12;
  if (squaredStep <= 42.25) return 13;
  if (squaredStep <= 49) return 14;
  if (squaredStep <= 56.25) return 15;
  return 16;
}

/// The mode as the C kernel's integer selector. One definition, because
/// the alternative is every call site open-coding the same ternary and one
/// of them eventually getting it backwards.
int resampleModeCode(ResampleMode mode) => mode == ResampleMode.pick ? 1 : 0;

/// Upper bound for Blend's tent radius.
///
/// Unlike the floor this is not a quality knob. A homography re-derives the
/// radius per pixel from `1/w` while the destination size stays fixed, so
/// it grows as `1/w²` with nothing to cancel it: an ordinary corner-pin
/// whose far edge is 6% of its near edge reaches r=262 — 2.8e5 taps for ONE
/// output pixel, and about a second for a single 256×256 tile.
///
/// Clamping is contract-safe because a narrower tent is still convex, so
/// Blend still cannot ring. Past the bound minification aliases exactly as
/// a mip-less sampler does, which is the honest trade.
///
/// It also keeps the radius inside int32, where the C mirror's
/// `(int32_t)ceil(radius)` is defined at all.
///
/// Pick needs none of this. The same corner-pin costs it 256 samples like
/// every other pixel, because [kResampleMaxSamplesPerAxis] bounds the work
/// where a radius had to be clamped to.
const double kResampleRadiusCeiling = 16;

/// Fully transparent — what a destination pixel gets when its preimage
/// falls outside the source.
///
/// Alpha 0 rather than a background colour keeps the Pick contract honest
/// at the edge: the rule is "no new colours INSIDE, plus one designated
/// empty token", and alpha 0 is that token. It is also still two-valued
/// alpha, so it does not smuggle in the partial alpha the whole feature
/// exists to avoid.
const int kResampleOutsideToken = 0x00000000;

/// A destination-to-source map, row-major, with the homogeneous row last:
///
///     u' = a*x + b*y + c
///     v' = d*x + e*y + f
///     w  = g*x + h*y + i        (affine: 0, 0, 1)
///     (u, v) = (u'/w, v'/w)
///
/// One shape covers translation, scale, rotation, shear and the perspective
/// quad, so the kernel has a single geometry path. [isAffine] only skips
/// the divide; it never changes the result for a matrix that is genuinely
/// affine.
class ResampleTransform {
  ResampleTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
    this.g = 0,
    this.h = 0,
    this.i = 1,
  }) : isAffine = g == 0 && h == 0 && i == 1;

  /// Identity — used by the byte-exact short circuit and by tests.
  ResampleTransform.identity()
    : a = 1,
      b = 0,
      c = 0,
      d = 0,
      e = 1,
      f = 0,
      g = 0,
      h = 0,
      i = 1,
      isAffine = true;

  /// Inverse of "scale about the origin by [scale], then translate by
  /// ([tx], [ty])" — the shape import fit and screen zoom both need.
  factory ResampleTransform.scaleTranslate({
    required double scale,
    double tx = 0,
    double ty = 0,
  }) {
    final inverse = 1 / scale;
    return ResampleTransform(
      a: inverse,
      b: 0,
      c: -tx * inverse,
      d: 0,
      e: inverse,
      f: -ty * inverse,
    );
  }

  final double a, b, c, d, e, f, g, h, i;
  final bool isAffine;

  /// True when the map is a whole-pixel translation, which every mode must
  /// pass through untouched.
  ///
  /// This is a correctness contract, not a speed trick: moving a drawing by
  /// an exact pixel count and getting different bytes back would be a
  /// defect no filter quality could excuse.
  /// The finite checks are not decoration: `double.infinity.roundToDouble()`
  /// is infinity, so an infinite offset would pass "is a whole number",
  /// take this path, and then throw in `round()`. The C mirror rejects it
  /// through `isfinite`, so letting it through here would break parity as
  /// well as crash.
  bool get isIntegerTranslation =>
      isAffine &&
      a == 1 &&
      b == 0 &&
      d == 0 &&
      e == 1 &&
      c.isFinite &&
      f.isFinite &&
      c == c.roundToDouble() &&
      f == f.roundToDouble();
}

/// The Dart reference implementation. `qa_resample_rgba` in the native
/// engine must agree with this byte for byte.
///
/// [src] and the returned buffer are straight-alpha RGBA8, tightly packed,
/// `width * 4` bytes per row — the same convention as every tile in the
/// app. Premultiplication happens at the upload boundary and must never
/// happen before this runs.
Uint8List resampleRgbaReference({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required int dstWidth,
  required int dstHeight,
  required ResampleTransform transform,
  required ResampleMode mode,
  double? radiusFloor,
}) {
  final dst = Uint8List(dstWidth * dstHeight * 4);
  resampleRgbaReferenceInto(
    src: src,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    dst: dst,
    dstWidth: dstWidth,
    dstHeight: dstHeight,
    transform: transform,
    mode: mode,
    radiusFloor: radiusFloor,
  );
  return dst;
}

/// [resampleRgbaReference] into a caller-owned buffer, optionally for one
/// band of destination rows.
///
/// The band parameters exist so the native kernel's pooled row split and
/// this reference can be compared item for item: a band must produce the
/// same bytes it would have produced as part of the whole, which is what
/// makes worker count invisible in the output.
void resampleRgbaReferenceInto({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required Uint8List dst,
  required int dstWidth,
  required int dstHeight,
  required ResampleTransform transform,
  required ResampleMode mode,
  double? radiusFloor,
  int rowStart = 0,
  int? rowEnd,
  int clipX = 0,
  int clipY = 0,
}) {
  final endRow = math.min(rowEnd ?? dstHeight, dstHeight);
  if (dstWidth <= 0 || endRow <= rowStart) {
    return;
  }
  final srcWords = _readableWords(src, srcWidth * srcHeight);
  final dstWords = _writableWords(dst, dstWidth * dstHeight);

  final floor = radiusFloor ?? resampleRadiusFloor(mode);
  final t = transform;

  // Whole-pixel translation: copy the overlapping rectangle verbatim. The
  // gather below would agree numerically, but "agrees numerically" is not
  // the promise callers rely on — "these are the same bytes" is.
  if (t.isIntegerTranslation) {
    final shiftX = -t.c.round();
    final shiftY = -t.f.round();
    for (var y = rowStart; y < endRow; y += 1) {
      final sourceY = y + clipY - shiftY;
      final rowBase = y * dstWidth;
      if (sourceY < 0 || sourceY >= srcHeight) {
        for (var x = 0; x < dstWidth; x += 1) {
          dstWords[rowBase + x] = kResampleOutsideToken;
        }
        continue;
      }
      final srcRowBase = sourceY * srcWidth;
      for (var x = 0; x < dstWidth; x += 1) {
        final sourceX = x + clipX - shiftX;
        dstWords[rowBase + x] = (sourceX < 0 || sourceX >= srcWidth)
            ? kResampleOutsideToken
            : srcWords[srcRowBase + sourceX];
      }
    }
    return;
  }

  final isPick = mode == ResampleMode.pick;

  // Footprint extents from the inverse Jacobian: the size of the
  // preimage's bounding box. Blend clamps them into its tent radius; Pick
  // uses the raw pair to size its flat-support probe, and — when the box
  // and the preimage are the same rectangle — to weigh with. Constant for
  // an affine map, so hoist them; a homography re-derives them per pixel
  // below.
  var extentX = t.a.abs() + t.b.abs();
  var extentY = t.d.abs() + t.e.abs();
  var radiusX = math.max(floor, extentX);
  var radiusY = math.max(floor, extentY);
  if (radiusX > kResampleRadiusCeiling) radiusX = kResampleRadiusCeiling;
  if (radiusY > kResampleRadiusCeiling) radiusY = kResampleRadiusCeiling;

  // ⚠️ READ THIS BEFORE CONCLUDING THE FOOTPRINT BOX IS BACK. It is not.
  //
  // A destination pixel's preimage is a parallelogram, and the reason
  // three rounds of separable weighting failed is that a product of two
  // one-dimensional weights integrates over a RECTANGLE. But the preimage
  // sometimes IS a rectangle — sides parallel to the axes, by construction
  // rather than by approximation — and then the separable product is not
  // an estimate of the area, it is the area.
  //
  // Exactly when: the two destination steps are `(a, d)` and `(b, e)`, so
  // they land on the axes either when `b` and `d` are both zero (no
  // rotation, or a half turn) or when `a` and `e` are both zero (a quarter
  // turn, which swaps the axes and is just as rectangular). The quarter
  // turn is not an afterthought — it is where the worst measured failures
  // were, and it reaches this test exactly because `SelectionAffine`
  // carries cos and sin from a table, so 90° really does give `a == 0`
  // rather than 6.1e-17.
  //
  // That distinction is worth the paragraph, because the two look
  // identical in the code and only one of them is a lie. Every failure
  // this exactness fixes lives at 0°, 90° and 180°; every failure the
  // supersampler fixes lives everywhere else.
  //
  // Why it MATTERS rather than merely being cheaper: counting n samples
  // quantises coverage to multiples of 1/n, so a feature owning `scale` of
  // its preimage only wins when `n·scale` rounds strictly past n/2. That
  // leaves an ambiguity band of `(0.5, 0.5 + 1/(2n))` where the vote comes
  // back exactly tied, and a tie goes to the token met first, which under
  // reduction is systematically the ground. An axis-aligned 1px line
  // presents the SAME coverage at every pixel along its length, so the
  // whole line flips together: measured on the supersampler alone, a 90°
  // reduction to 0.525 kept 5 ink pixels where the truth keeps 38. The
  // line did not thin. It vanished — the exact failure this feature exists
  // to end, reappearing at the least exotic angle there is. Raising the
  // refinement cap narrows the band and never closes it. Computing the
  // area instead of sampling it closes it.
  //
  // The bound: `extentX <= kResampleRadiusCeiling`, so the tap window
  // stays bounded. Past a 16× reduction a one-pixel feature has long lost
  // its own area argmax and the supersampler's cap is the honest answer.
  final pickExact =
      isPick &&
      t.isAffine &&
      ((t.b == 0 && t.d == 0) || (t.a == 0 && t.e == 0)) &&
      extentX > 0 &&
      extentY > 0 &&
      extentX <= kResampleRadiusCeiling &&
      extentY <= kResampleRadiusCeiling;

  // The squared source-space length of one destination step along each
  // axis — the columns of the same Jacobian, and the only thing that sets
  // Pick's sample rate. Squared, because that is the form
  // [resampleSamplesPerAxis] compares against.
  var stepXSquared = t.a * t.a + t.d * t.d;
  var stepYSquared = t.b * t.b + t.e * t.e;

  // Vote table. Sixteen slots is not a guess: a cel's preimage at these
  // sizes holds a handful of flat colours, and the two-value line art this
  // exists for holds two. On overflow the LIGHTEST incumbent is evicted and
  // hands its count to the newcomer, which is what makes the guarantee
  // statable: any token owning more than a sixteenth of the samples is
  // still in the table when the vote is counted. Dropping the newcomer
  // instead — the obvious cheap policy — lets a colour covering 99% of a
  // preimage lose to one covering 0.1%.
  //
  // One table serves both of Pick's gathers. The supersampler adds 1.0 per
  // landing rather than an integer, which costs nothing (a double counts
  // whole numbers exactly far past the 1024 it can reach) and buys one
  // election instead of two.
  final keys = Uint32List(_kVoteSlots);
  final weights = Float64List(_kVoteSlots);

  // Where the subsamples land, filled once per sampling round and read
  // again when an eviction forces an exact recount. Keeping the landings
  // instead of the sample coordinates is what makes that recount cheap:
  // it re-reads a scratch array rather than re-running the inverse map.
  final landings = isPick && !pickExact
      ? Uint32List(kResampleRefineLimit * kResampleRefineLimit)
      : Uint32List(0);

  // Subsample centres for every count either axis can take, so a
  // refinement round never has to rebuild a table and the two languages
  // never differ over when one was rebuilt. `(s + 0.5) / n` and not a
  // multiply by a reciprocal, because those do not round alike and the
  // oracle in `coverage_truth.dart` is written the first way.
  final offsets = Float64List(
    (kResampleRefineLimit + 1) * kResampleRefineLimit,
  );
  if (isPick && !pickExact) {
    for (var n = 1; n <= kResampleRefineLimit; n += 1) {
      for (var s = 0; s < n; s += 1) {
        offsets[n * kResampleRefineLimit + s] = (s + 0.5) / n;
      }
    }
  }

  for (var y = rowStart; y < endRow; y += 1) {
    // The ABSOLUTE destination row, formed once as an int so every reader
    // below keeps the two-term sum it had. Adding the clip in doubles
    // instead would make these three-term sums, and the C kernel's parity
    // with this reference is expression identity, not value identity.
    final absoluteY = y + clipY;
    final centreOfY = absoluteY + 0.5;
    final rowBase = y * dstWidth;
    for (var x = 0; x < dstWidth; x += 1) {
      final absoluteX = x + clipX;
      final centreOfX = absoluteX + 0.5;

      double u, v;
      if (t.isAffine) {
        u = t.a * centreOfX + t.b * centreOfY + t.c - 0.5;
        v = t.d * centreOfX + t.e * centreOfY + t.f - 0.5;
      } else {
        final w = t.g * centreOfX + t.h * centreOfY + t.i;
        if (w == 0) {
          dstWords[rowBase + x] = kResampleOutsideToken;
          continue;
        }
        final inverseW = 1 / w;
        // Projected source point BEFORE the half-pixel shift — the
        // quotient rule below differentiates this value, not the shifted
        // one.
        final projectedU = (t.a * centreOfX + t.b * centreOfY + t.c) * inverseW;
        final projectedV = (t.d * centreOfX + t.e * centreOfY + t.f) * inverseW;
        u = projectedU - 0.5;
        v = projectedV - 0.5;
        // Perspective scales differently at every pixel, so the footprint
        // is re-derived here: d(N/w)/dx = (Nx - (N/w) * wx) / w.
        final dudx = (t.a - projectedU * t.g) * inverseW;
        final dudy = (t.b - projectedU * t.h) * inverseW;
        final dvdx = (t.d - projectedV * t.g) * inverseW;
        final dvdy = (t.e - projectedV * t.h) * inverseW;
        extentX = dudx.abs() + dudy.abs();
        extentY = dvdx.abs() + dvdy.abs();
        // Per-pixel, from the per-pixel Jacobian. Taking these from the
        // matrix entries instead would describe a pixel somewhere else in
        // the image, which is a mistake this file has made once already.
        stepXSquared = dudx * dudx + dvdx * dvdx;
        stepYSquared = dudy * dudy + dvdy * dvdy;
        radiusX = math.max(floor, extentX);
        radiusY = math.max(floor, extentY);
        if (radiusX > kResampleRadiusCeiling) radiusX = kResampleRadiusCeiling;
        if (radiusY > kResampleRadiusCeiling) radiusY = kResampleRadiusCeiling;
      }

      // A degenerate map — scale zero, a non-finite matrix entry, or a
      // homography whose w is subnormal enough that 1/w overflows — puts
      // u, v or a radius outside the finite doubles. `round()` throws
      // there and the C mirror's `llround()` is undefined, so both
      // kernels declare the pixel outside instead: the same answer the
      // `w == 0` early-out already gives.
      if (!u.isFinite ||
          !v.isFinite ||
          !radiusX.isFinite ||
          !radiusY.isFinite) {
        dstWords[rowBase + x] = kResampleOutsideToken;
        continue;
      }

      final centreX = u.round();
      final centreY = v.round();

      final samplesX = isPick && !pickExact
          ? resampleSamplesPerAxis(stepXSquared)
          : 0;
      final samplesY = isPick && !pickExact
          ? resampleSamplesPerAxis(stepYSquared)
          : 0;

      // The exact path's half-widths. The preimage spans `u ± extentX/2`,
      // and NO FLOOR is applied: a floor above the true extent claims the
      // preimage reaches further than it does, which is what deleted line
      // art when the floor was 1.5.
      final halfX = extentX * 0.5;
      final halfY = extentY * 0.5;
      // A tap further than half the preimage plus half a pixel cannot
      // overlap it at all, so it has nothing to say about area.
      final exactRadX = pickExact ? (halfX + 0.5).ceil() : 0;
      final exactRadY = pickExact ? (halfY + 0.5).ceil() : 0;

      // The window for the flat-support probe. For Blend and for exact
      // Pick it IS the gather window, so "flat here" and "every tap reads
      // this" are the same statement.
      //
      // For the supersampler it has to be derived, and derived
      // conservatively: a subsample lands in `round(u_s)`, `u_s` stays
      // within `extent/2` of `u`, and `u` stays within half a pixel of
      // `centreX`, so no landing is further than `extent/2 + 1` away and
      // the floor of that is a true bound because landings are whole
      // numbers. That argument needs the preimage to actually BE the
      // parallelogram the extents describe, which is true of an affine map
      // and only linearly approximate under a perspective divide — so the
      // supersampler does not probe a homography at all. A window that
      // disagrees with the thing it stands in for is how the previous
      // design elected a colour by a loop bound.
      var runFlat = true;
      int flatRadX, flatRadY;
      if (pickExact) {
        flatRadX = exactRadX;
        flatRadY = exactRadY;
      } else if (isPick) {
        final spanX = (extentX * 0.5 + 1).floorToDouble();
        final spanY = (extentY * 0.5 + 1).floorToDouble();
        // Only while the probe is cheaper than the sampling it would save.
        // Compared as doubles because a big reduction makes these numbers
        // large enough to overflow an int32 before the comparison happens
        // — the C mirror has to survive the same expression.
        runFlat =
            t.isAffine &&
            (2 * spanX + 1) * (2 * spanY + 1) <= samplesX * samplesY;
        flatRadX = runFlat ? spanX.toInt() : 0;
        flatRadY = runFlat ? spanY.toInt() : 0;
      } else {
        flatRadX = radiusX.ceil();
        flatRadY = radiusY.ceil();
      }

      // Flat support: when every source pixel in reach holds the same word
      // there is nothing to average and nothing to elect, so both modes
      // must return that word. Most of a cel is one colour, which is why
      // this is here at all.
      if (runFlat) {
        var flatToken = 0;
        var flat = true;
        var seenAny = false;
        for (var dy = -flatRadY; dy <= flatRadY && flat; dy += 1) {
          final sourceY = centreY + dy;
          final rowOffset = sourceY * srcWidth;
          final rowInside = sourceY >= 0 && sourceY < srcHeight;
          for (var dx = -flatRadX; dx <= flatRadX; dx += 1) {
            final sourceX = centreX + dx;
            final token = (!rowInside || sourceX < 0 || sourceX >= srcWidth)
                ? kResampleOutsideToken
                : srcWords[rowOffset + sourceX];
            if (!seenAny) {
              flatToken = token;
              seenAny = true;
            } else if (token != flatToken) {
              flat = false;
              break;
            }
          }
        }
        if (flat) {
          dstWords[rowBase + x] = flatToken;
          continue;
        }
      }

      if (pickExact) {
        // Exact area, gathered rather than sampled. Every tap's weight is
        // the length its source pixel shares with the preimage along x,
        // times the same along y — and because the preimage is an
        // axis-aligned rectangle here, that product IS the shared area.
        // No quantisation, so no tie band: a feature owning 50.8% of the
        // preimage wins with 50.8%.
        var slots = 0;
        var evicted = false;
        for (var dy = -exactRadY; dy <= exactRadY; dy += 1) {
          final sourceY = centreY + dy;
          final weightY = _coverage(sourceY, v, halfY);
          if (weightY <= 0) continue;
          final rowOffset = sourceY * srcWidth;
          final rowInside = sourceY >= 0 && sourceY < srcHeight;
          for (var dx = -exactRadX; dx <= exactRadX; dx += 1) {
            final sourceX = centreX + dx;
            final weightX = _coverage(sourceX, u, halfX);
            if (weightX <= 0) continue;
            final token = (!rowInside || sourceX < 0 || sourceX >= srcWidth)
                ? kResampleOutsideToken
                : srcWords[rowOffset + sourceX];
            final weight = weightX * weightY;
            var slot = -1;
            for (var s = 0; s < slots; s += 1) {
              if (keys[s] == token) {
                slot = s;
                break;
              }
            }
            if (slot >= 0) {
              weights[slot] += weight;
            } else if (slots < _kVoteSlots) {
              keys[slots] = token;
              weights[slots] = weight;
              slots += 1;
            } else {
              var lightest = 0;
              for (var s = 1; s < _kVoteSlots; s += 1) {
                if (weights[s] < weights[lightest]) lightest = s;
              }
              keys[lightest] = token;
              weights[lightest] += weight;
              evicted = true;
            }
          }
        }
        if (slots == 0) {
          dstWords[rowBase + x] = kResampleOutsideToken;
          continue;
        }
        if (evicted) {
          for (var s = 0; s < slots; s += 1) {
            weights[s] = 0;
          }
          for (var dy = -exactRadY; dy <= exactRadY; dy += 1) {
            final sourceY = centreY + dy;
            final weightY = _coverage(sourceY, v, halfY);
            if (weightY <= 0) continue;
            final rowOffset = sourceY * srcWidth;
            final rowInside = sourceY >= 0 && sourceY < srcHeight;
            for (var dx = -exactRadX; dx <= exactRadX; dx += 1) {
              final sourceX = centreX + dx;
              final weightX = _coverage(sourceX, u, halfX);
              if (weightX <= 0) continue;
              final token = (!rowInside || sourceX < 0 || sourceX >= srcWidth)
                  ? kResampleOutsideToken
                  : srcWords[rowOffset + sourceX];
              for (var s = 0; s < slots; s += 1) {
                if (keys[s] == token) {
                  weights[s] += weightX * weightY;
                  break;
                }
              }
            }
          }
        }
        // A tie here is REAL: the areas are equal and nothing further will
        // separate them. It goes to the token met first, in a fixed scan
        // order, which is what keeps the answer identical on every
        // platform and worker count.
        //
        // ⚠️ The visible cost, written down because it looks like a defect
        // and is not one: at EXACTLY half scale a one-pixel line covers
        // exactly one of the two source pixels its preimage spans, every
        // pixel along an axis-aligned line ties at once, and the whole line
        // goes to the ground. Measured: 1 ink pixel kept where a
        // supersampled oracle keeps 32 — the oracle differing only because
        // its own tie-break is a map's insertion order. Both answers ARE
        // the area argmax; neither is more correct, and the kernel this
        // replaced behaves the same way.
        //
        // Two tie-breaks were built and measured and both were reverted,
        // so do not reach for a third without a sweep. Deciding by the
        // pixel's own centre fixes 0.500 and destroys 0.750 — 95 ink pixels
        // down to 3 — because at 0.750 the tie is between a feature and a
        // ground the centre happens to sit in. The same rule on the
        // supersampled path traded 0.55 for 0.70 in exactly the same shape.
        // The tie is genuinely undecidable from area, and every rule that
        // decides it anyway wins one scale by losing another.
        var best = 0;
        for (var s = 1; s < slots; s += 1) {
          if (weights[s] > weights[best]) best = s;
        }
        dstWords[rowBase + x] = keys[best];
        continue;
      }

      if (isPick) {
        // Sample, count, and if the count came back TIED, sample again at
        // twice the rate.
        //
        // A tie is nearly always the grid's fault rather than the
        // geometry's. A one-pixel line at 0.55× covers 55% of its
        // preimage and ought to win outright, but eight samples across a
        // 1.818-wide preimage land four on the line and four off it, and
        // whichever tie-break is applied then decides the pixel by
        // something that is not area. Measured on a horizontal hairline
        // that cost 51 of 71 ink pixels — and a hairline is not a corner
        // case, it is the drawing.
        //
        // Refining answers the question instead of guessing at it: at 16
        // per axis the same 55% reads as 8.8 of 16 rather than 4.4 of 8,
        // which rounds to 9 and wins. Only tied pixels pay, which on line
        // art is a fraction of one edge, and the whole sweep says one
        // doubling is all of it — see [kResampleRefineLimit].
        //
        // Ties that survive the cap are the real ones — a feature covering
        // EXACTLY half, where no sample count will separate the two — and
        // those fall through to the token met first, in a fixed scan
        // order, which is what keeps the result identical on every
        // platform and at every worker count.
        var nx = samplesX;
        var ny = samplesY;
        var slots = 0;
        var best = 0;
        while (true) {
          final baseX = nx * kResampleRefineLimit;
          final baseY = ny * kResampleRefineLimit;
          var votes = 0;
          for (var sy = 0; sy < ny; sy += 1) {
            final sampleY = absoluteY + offsets[baseY + sy];
            for (var sx = 0; sx < nx; sx += 1) {
              final sampleX = absoluteX + offsets[baseX + sx];
              double sampleU, sampleV;
              if (t.isAffine) {
                sampleU = t.a * sampleX + t.b * sampleY + t.c - 0.5;
                sampleV = t.d * sampleX + t.e * sampleY + t.f - 0.5;
              } else {
                final sampleW = t.g * sampleX + t.h * sampleY + t.i;
                if (sampleW == 0) continue;
                sampleU = (t.a * sampleX + t.b * sampleY + t.c) / sampleW - 0.5;
                sampleV = (t.d * sampleX + t.e * sampleY + t.f) / sampleW - 0.5;
              }
              if (!sampleU.isFinite || !sampleV.isFinite) continue;
              if (sampleU.abs() >= kResampleIndexLimit ||
                  sampleV.abs() >= kResampleIndexLimit) {
                landings[votes] = kResampleOutsideToken;
                votes += 1;
                continue;
              }
              final sourceX = sampleU.round();
              final sourceY = sampleV.round();
              landings[votes] =
                  (sourceX < 0 ||
                      sourceX >= srcWidth ||
                      sourceY < 0 ||
                      sourceY >= srcHeight)
                  ? kResampleOutsideToken
                  : srcWords[sourceY * srcWidth + sourceX];
              votes += 1;
            }
          }

          slots = 0;
          var evicted = false;
          for (var s = 0; s < votes; s += 1) {
            final token = landings[s];
            var slot = -1;
            for (var k = 0; k < slots; k += 1) {
              if (keys[k] == token) {
                slot = k;
                break;
              }
            }
            if (slot >= 0) {
              weights[slot] += 1;
            } else if (slots < _kVoteSlots) {
              keys[slots] = token;
              weights[slots] = 1;
              slots += 1;
            } else {
              // The weakest slot yields its key and keeps its count, so a
              // token can only be evicted while it holds less than a
              // sixteenth of the samples. Lowest index on a tie, so the
              // choice is identical on every platform and worker count.
              var lightest = 0;
              for (var k = 1; k < _kVoteSlots; k += 1) {
                if (weights[k] < weights[lightest]) lightest = k;
              }
              keys[lightest] = token;
              weights[lightest] += 1;
              evicted = true;
            }
          }
          if (slots == 0) {
            break;
          }
          if (evicted) {
            // An inherited count over-estimates its new owner, which could
            // hand the election to a token that merely arrived late. Once
            // the surviving keys are known, recount them exactly. Gated on
            // the eviction, so the ordinary preimage — line art holds two
            // or three colours — never pays for it.
            //
            // ⚠️ This branch is DEFENSIVE and the suite does not pin it. A
            // search over a thousand fixtures found none where an
            // inherited count actually beats the true argmax, so no test
            // fails if the recount is deleted. Said out loud rather than
            // left to look like coverage: the eviction ITSELF is pinned
            // (see "a dominant colour still wins past 16 distinct
            // tokens"), the correction on top of it is not.
            for (var s = 0; s < slots; s += 1) {
              weights[s] = 0;
            }
            for (var s = 0; s < votes; s += 1) {
              final token = landings[s];
              for (var k = 0; k < slots; k += 1) {
                if (keys[k] == token) {
                  weights[k] += 1;
                  break;
                }
              }
            }
          }
          best = 0;
          for (var s = 1; s < slots; s += 1) {
            if (weights[s] > weights[best]) best = s;
          }
          var tied = false;
          for (var s = 0; s < slots; s += 1) {
            if (s != best && weights[s] == weights[best]) {
              tied = true;
              break;
            }
          }
          if (!tied ||
              (nx >= kResampleRefineLimit && ny >= kResampleRefineLimit)) {
            break;
          }
          nx = math.min(nx * 2, kResampleRefineLimit);
          ny = math.min(ny * 2, kResampleRefineLimit);
        }
        if (slots == 0) {
          // Every subsample was degenerate — a homography pole through
          // this pixel, or a matrix that maps it nowhere finite.
          dstWords[rowBase + x] = kResampleOutsideToken;
          continue;
        }
        dstWords[rowBase + x] = keys[best];
        continue;
      }

      final radX = radiusX.ceil();
      final radY = radiusY.ceil();

      var accRed = 0.0;
      var accGreen = 0.0;
      var accBlue = 0.0;
      var accAlpha = 0.0;
      var weightSum = 0.0;
      for (var dy = -radY; dy <= radY; dy += 1) {
        final sourceY = centreY + dy;
        final weightY = 1 - (sourceY - v).abs() / radiusY;
        if (weightY <= 0) continue;
        final rowOffset = sourceY * srcWidth;
        final rowInside = sourceY >= 0 && sourceY < srcHeight;
        for (var dx = -radX; dx <= radX; dx += 1) {
          final sourceX = centreX + dx;
          final weightX = 1 - (sourceX - u).abs() / radiusX;
          if (weightX <= 0) continue;
          final token = (!rowInside || sourceX < 0 || sourceX >= srcWidth)
              ? kResampleOutsideToken
              : srcWords[rowOffset + sourceX];
          final weight = weightX * weightY;
          final alpha = (token >> 24) & 0xff;
          // Colour is averaged weighted by alpha as well: a transparent tap
          // has no colour to contribute, and letting its zeroes into the
          // mean is what fringes a soft edge with black.
          final colourWeight = weight * alpha;
          accRed += (token & 0xff) * colourWeight;
          accGreen += ((token >> 8) & 0xff) * colourWeight;
          accBlue += ((token >> 16) & 0xff) * colourWeight;
          accAlpha += alpha * weight;
          weightSum += weight;
        }
      }
      if (weightSum <= 0 || accAlpha <= 0) {
        dstWords[rowBase + x] = kResampleOutsideToken;
        continue;
      }
      final outAlpha = (accAlpha / weightSum).round().clamp(0, 255);
      if (outAlpha == 0) {
        dstWords[rowBase + x] = kResampleOutsideToken;
        continue;
      }
      final outRed = (accRed / accAlpha).round().clamp(0, 255);
      final outGreen = (accGreen / accAlpha).round().clamp(0, 255);
      final outBlue = (accBlue / accAlpha).round().clamp(0, 255);
      dstWords[rowBase + x] =
          (outAlpha << 24) | (outBlue << 16) | (outGreen << 8) | outRed;
    }
  }
}

const int _kVoteSlots = 16;

/// How much of the destination pixel's preimage source pixel [source]
/// covers, along one axis: the preimage spans `centre ± half`, a source
/// pixel spans `source ± 0.5`, and this is the length they share.
///
/// ⚠️ This is separable, and separability is what made three rounds of this
/// feature wrong. It is used on exactly one path — `b == 0 && d == 0` —
/// where the preimage is an axis-aligned RECTANGLE and the product of the
/// two lengths is therefore the shared AREA rather than an estimate of it.
/// Off that path the preimage is a rotated parallelogram, the product
/// integrates over its bounding box instead, and the supersampler is what
/// answers.
///
/// The reason exactness earns its own path rather than being left to the
/// sampler: counting quantises. A one-pixel feature owning `scale` of its
/// preimage only beats the ground when `n·scale` rounds past `n/2`, so
/// coverages in `(0.5, 0.5 + 1/(2n))` come back tied however large `n` is,
/// and an axis-aligned line — presenting identical coverage at every pixel
/// along its length — loses all of itself at once. Measured on the sampler
/// alone: a 90° reduction to 0.525 kept 5 ink pixels where the truth keeps
/// 38. Here 0.525 simply beats 0.475.
double _coverage(int source, double centre, double half) {
  final low = math.max(source - 0.5, centre - half);
  final high = math.min(source + 0.5, centre + half);
  return high - low;
}

/// A 32-bit word view for READING.
///
/// `Uint32List.view` refuses an offset that is not four-byte aligned, and a
/// caller handing in a sublist of a tile buffer can land on one. Copying is
/// safe here because nothing writes back through this view, and it keeps
/// exactly one pixel-reading code path in existence rather than a byte-wise
/// twin that would then need its own parity test.
Uint32List _readableWords(Uint8List bytes, int wordCount) {
  if (bytes.offsetInBytes % 4 == 0) {
    return Uint32List.view(bytes.buffer, bytes.offsetInBytes, wordCount);
  }
  return Uint32List.view(Uint8List.fromList(bytes).buffer, 0, wordCount);
}

/// A 32-bit word view for WRITING.
///
/// The read path may quietly copy; this one must not, because a copy would
/// swallow every pixel the kernel produced. An unaligned destination is a
/// caller bug rather than a case to accommodate — every buffer the app
/// hands in is either freshly allocated or a whole tile.
Uint32List _writableWords(Uint8List bytes, int wordCount) {
  if (bytes.offsetInBytes % 4 != 0) {
    throw ArgumentError.value(
      bytes.offsetInBytes,
      'dst.offsetInBytes',
      'resample destination must be four-byte aligned; a copy here would '
          'discard the result',
    );
  }
  return Uint32List.view(bytes.buffer, bytes.offsetInBytes, wordCount);
}
