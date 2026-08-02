import 'dart:math' as math;
import 'dart:typed_data';

/// The one image resampler: **one gather, one footprint, and a single line
/// at the end that decides whether colours are averaged or elected.**
///
/// ⚠️ NOTHING CALLS THIS YET. It is the kernel half of a larger change: the
/// transform tool still resamples through the Catmull-Rom in
/// `canvas_selection.dart`, the composite path still hands its scaling to
/// Skia, and import fit still uses `FilterQuality.high`. Those four move
/// over one at a time, and until they do the only importers are the tests
/// and `tool/resample_benchmark.dart`.
///
/// Once they have moved, every surface that turns pixels into other pixels
/// goes through here — transform tool, FX transform at composite time,
/// import fit, on-screen minification. They differ in what matrix they
/// hand in, never in how a destination pixel is built.
///
/// ## Why two modes and not two resamplers
///
/// Preserving the source colours exactly means the last operation has to be
/// a CHOICE, not a mixture — and "smooth when enlarged" is precisely the
/// production of in-between values. Those requirements collide head-on, so
/// no single accumulator can serve both. What CAN be shared is everything
/// before it: the inverse map, the Jacobian, the footprint radius, the
/// gather loop and the flat-support early-out. Only the accumulator splits:
///
/// * [ResampleMode.blend] — weighted mean. New colours by definition.
/// * [ResampleMode.pick] — the colour whose covered AREA is largest wins,
///   and its 32-bit word is copied through byte for byte.
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
/// nearest-neighbour drop thin lines under reduction. The radius comes from
/// the inverse Jacobian — one output step along x moves `(a, d)` in source
/// space, one along y moves `(b, e)` — so the preimage reaches `|a| + |b|`
/// horizontally and `|d| + |e|` vertically.
///
/// The floor differs by mode and the difference is not cosmetic. Blend at
/// r=1 is already bilinear and widening it only blurs; Pick at r=1 collapses
/// into nearest-neighbour, losing the majority vote it exists for. Measured
/// against a production cel (2150x1518, 16 colours), raising Pick's floor
/// from 1.0 to 1.5 took the jagged-spur count at a 15 degree rotation from
/// 90 to 65 while the ink pixel count stayed identical.
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

  /// Coverage argmax. The source colours come through untouched.
  pick,
}

/// Lower bound for the footprint radius, per mode. See [ResampleMode].
///
/// ⚠️ This DEFAULT is not right for every consumer. The 1.5 was tuned on a
/// dense production cel where it cut jagged spurs along rotated edges; on
/// two-value line art it deletes features outright, because the extra ring
/// of ground pixels outvotes a line one pixel wide. Measured on a 40×40
/// fixture holding a 1px diagonal and a 1px vertical (63 ink pixels): an
/// exact 90° rotation returns 32 ink pixels at floor 1.5 and all 63 at
/// floor 1.0. The selection transform therefore passes 1.0 explicitly —
/// see `kSelectionResampleRadiusFloor`.
///
/// The floor can only ever bite in the band `1.0 < extent < 1.5`, and a
/// pure rotation's extent is `|cos| + |sin| ∈ [1, √2]` — so this is a
/// rotation-only knob, inert under reduction and short-circuited under
/// magnification.
double resampleRadiusFloor(ResampleMode mode) =>
    mode == ResampleMode.pick ? 1.5 : 1.0;

/// The mode as the C kernel's integer selector. One definition, because
/// the alternative is every call site open-coding the same ternary and one
/// of them eventually getting it backwards.
int resampleModeCode(ResampleMode mode) => mode == ResampleMode.pick ? 1 : 0;

/// Upper bound for the footprint radius.
///
/// Unlike the floor this is not a quality knob. A homography re-derives the
/// radius per pixel from `1/w` while the destination size stays fixed, so
/// it grows as `1/w²` with nothing to cancel it: an ordinary corner-pin
/// whose far edge is 6% of its near edge reaches r=262 — 2.8e5 taps for ONE
/// output pixel, and about a second for a single 256×256 tile.
///
/// Clamping is contract-safe because the clamped window is a SUBSET of the
/// true preimage: Pick still copies a tap that overlapped it, and a
/// narrower tent is still convex. Past the bound minification aliases
/// exactly as a mip-less sampler does, which is the honest trade.
///
/// It also keeps the radius inside int32, where the C mirror's
/// `(int32_t)ceil(radius)` is defined at all.
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
      final sourceY = y - shiftY;
      final rowBase = y * dstWidth;
      if (sourceY < 0 || sourceY >= srcHeight) {
        for (var x = 0; x < dstWidth; x += 1) {
          dstWords[rowBase + x] = kResampleOutsideToken;
        }
        continue;
      }
      final srcRowBase = sourceY * srcWidth;
      for (var x = 0; x < dstWidth; x += 1) {
        final sourceX = x - shiftX;
        dstWords[rowBase + x] = (sourceX < 0 || sourceX >= srcWidth)
            ? kResampleOutsideToken
            : srcWords[srcRowBase + sourceX];
      }
    }
    return;
  }

  // Footprint extents from the inverse Jacobian, and the sampling radii
  // clamped from them. The RAW extent is kept because it is the honest
  // answer to "how much source does this destination pixel actually
  // cover" — the floor and ceiling are sampling policy, and Pick has to
  // tell the two apart. Constant for an affine map, so hoist them; a
  // homography re-derives them per pixel below.
  var extentX = t.a.abs() + t.b.abs();
  var extentY = t.d.abs() + t.e.abs();
  var radiusX = math.max(floor, extentX);
  var radiusY = math.max(floor, extentY);
  if (radiusX > kResampleRadiusCeiling) radiusX = kResampleRadiusCeiling;
  if (radiusY > kResampleRadiusCeiling) radiusY = kResampleRadiusCeiling;

  // Vote table. Sixteen slots is not a guess: a cel's support at these radii
  // holds a handful of flat colours, and the two-value line art this exists
  // for holds two. On overflow the LIGHTEST incumbent is evicted and hands
  // its weight to the newcomer, which is what makes the guarantee
  // statable: any token owning more than a sixteenth of the footprint's
  // weight is still in the table when the vote is counted. Dropping the
  // newcomer instead — the obvious cheap policy — lets a colour covering
  // 99% of a footprint lose to one covering 0.1%.
  final keys = Uint32List(_kVoteSlots);
  final weights = Float64List(_kVoteSlots);

  for (var y = rowStart; y < endRow; y += 1) {
    final centreOfY = y + 0.5;
    final rowBase = y * dstWidth;
    for (var x = 0; x < dstWidth; x += 1) {
      final centreOfX = x + 0.5;

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

      // Magnifying on BOTH axes: the preimage is narrower than one source
      // pixel, so at most two pixels per axis touch it and the one holding
      // (u, v) always holds the larger share — point sampling IS the area
      // argmax here, and under integer magnification it is exact block
      // replication.
      //
      // The floor exists to give reduction and rotation a neighbourhood to
      // vote in. Applying it here instead lets pixels the preimage never
      // reached outvote the one it did, which deletes every 1px feature
      // that is not axis-aligned — a provenance breach, not a quality
      // preference. Requiring both axes keeps an anisotropic map (magnify
      // one, reduce the other) on the vote path, where the floor is still
      // doing real work. Pick only: Blend must keep interpolating under
      // magnification, which is what its 1.0 floor is for.
      if (mode == ResampleMode.pick && extentX < 1 && extentY < 1) {
        dstWords[rowBase + x] =
            (centreX < 0 ||
                centreX >= srcWidth ||
                centreY < 0 ||
                centreY >= srcHeight)
            ? kResampleOutsideToken
            : srcWords[centreY * srcWidth + centreX];
        continue;
      }

      final radX = radiusX.ceil();
      final radY = radiusY.ceil();

      // Flat support: when every tap reads the same word there is nothing
      // to average and nothing to elect, so both modes must return that
      // word. The window scanned here is the whole integer box, which can
      // be a ring wider than the taps the gather will actually weigh —
      // that only ever makes the test stricter, never wrong.
      var flatToken = 0;
      var flat = true;
      var seenAny = false;
      for (var dy = -radY; dy <= radY && flat; dy += 1) {
        final sourceY = centreY + dy;
        final rowOffset = sourceY * srcWidth;
        final rowInside = sourceY >= 0 && sourceY < srcHeight;
        for (var dx = -radX; dx <= radX; dx += 1) {
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

      if (mode == ResampleMode.pick) {
        var slots = 0;
        var evicted = false;
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
              // The weakest slot yields its key and keeps its weight, so a
              // token can only be evicted while it holds less than a
              // sixteenth of the footprint. Lowest index on a tie, so the
              // choice is identical on every platform and worker count.
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
          // An inherited weight over-estimates its new owner, which could
          // hand the election to a token that merely arrived late. Once
          // the surviving keys are known, re-weigh them exactly. Gated on
          // the eviction so the ordinary footprint — line art holds two or
          // three colours — never pays for it.
          for (var s = 0; s < slots; s += 1) {
            weights[s] = 0;
          }
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
              for (var s = 0; s < slots; s += 1) {
                if (keys[s] == token) {
                  weights[s] += weightX * weightY;
                  break;
                }
              }
            }
          }
        }
        var best = 0;
        for (var s = 1; s < slots; s += 1) {
          // Strictly greater, so a tie goes to whichever token was met
          // first — and taps are visited in a fixed order, which is what
          // makes the tie deterministic across platforms and worker counts.
          if (weights[s] > weights[best]) best = s;
        }
        dstWords[rowBase + x] = keys[best];
        continue;
      }

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
