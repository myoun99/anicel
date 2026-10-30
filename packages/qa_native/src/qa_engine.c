// Anicel native engine core (R18 A-track).
//
// ONE portable C source, cross-compiled per platform (Windows DLL, macOS
// dylib, Android .so, ...). Every function here has a Dart REFERENCE
// implementation that stays in the tree forever; byte-parity between the
// two is pinned by tests, so the native core can never silently diverge.
//
// Arithmetic contract: Dart's double.round() rounds half AWAY FROM ZERO,
// exactly like C llround(); both sides run IEEE-754 doubles, so identical
// expressions produce identical bytes.

#include <math.h>
// ptrdiff_t lives here. MSVC drags it in through another header, so the
// omission was invisible for as long as Windows was the only build —
// Apple clang rejected the file outright on CI's first run.
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// qa_physical_memory_bytes is the one OS-API call in this file: each
// platform answers "how much RAM does this machine have" its own way,
// and keeping the three arms here means Dart needs no method channel and
// the answer works from any isolate.
#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#if TARGET_OS_IPHONE
// os_proc_available_memory: what is left of THIS APP's allowance, which
// is the only number that predicts a jetsam kill. iOS/iPadOS only.
#include <os/proc.h>
#endif
#else
#include <sys/sysinfo.h>
#endif
// stdio for /proc/self/smaps_rollup in qa_process_footprint_bytes -- libc,
// not a link dependency.
#include <stdio.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

// The arithmetic contract's rounding (above) for a channel byte: llround,
// then clamped to [0, 255] — the ONE spelling every blend here uses, and
// without the library call (board `brush-kernel-next`). Inside
// [0.5, 254.5) llround's half-away-from-zero is the integer part plus one
// when the fraction reaches a half, and that fraction is exact for any
// double this small; below the range llround is at most 0 and above it at
// least 255, which is where the clamp put them.
static inline int32_t qa_round_byte(double value) {
  if (!(value >= 0.5)) return 0;
  if (value >= 254.5) return 255;
  const int32_t whole = (int32_t)value;
  return whole + (value - (double)whole >= 0.5 ? 1 : 0);
}

// The same rounding onto the stroke's 16-bit plane (ABI 40): llround,
// clamped to [0, 65535].
static inline int32_t qa_round_wide(double value) {
  if (!(value >= 0.5)) return 0;
  if (value >= 65534.5) return 65535;
  const int32_t whole = (int32_t)value;
  return whole + (value - (double)whole >= 0.5 ? 1 : 0);
}

// The SIMD this build has — one fact for the file, read by the flood
// fill's spans and the dab's pixel pairs. SSE2 is baseline on x64 and NEON
// on aarch64, so neither needs a runtime dispatch; 32-bit ARM keeps the
// scalar paths.
#if defined(_M_X64) || defined(__x86_64__) || defined(__SSE2__) || \
    (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#define QA_SSE2 1
#include <emmintrin.h>
#elif defined(__aarch64__)
#define QA_NEON 1
#include <arm_neon.h>
#endif

// Blends one stamp row span into a tile row (straight-alpha RGBA both
// sides) - the inner loop of the stamp dab path
// (materializeBrushDabSequenceOnBitmapSurface._blendStampDab).
//
//   tile_row:   tile pixels at the span start (4 bytes per pixel)
//   stamp_row:  stamp pixels at the span start (4 bytes per pixel)
//   count:      pixels in the span
//   opacity:    dab opacity in [0, 1]
//   erase:      nonzero = destination-out from stamp alpha
//
// Returns nonzero when any destination byte changed (the caller marks the
// tile dirty).
QA_EXPORT int32_t qa_stamp_blend_row(
    uint8_t* tile_row,
    const uint8_t* stamp_row,
    int32_t count,
    double opacity,
    int32_t erase) {
  int32_t changed = 0;
  for (int32_t i = 0; i < count; i += 1) {
    const uint8_t* src = stamp_row + (ptrdiff_t)i * 4;
    uint8_t* dst = tile_row + (ptrdiff_t)i * 4;
    const uint8_t stamp_a = src[3];
    if (stamp_a == 0) {
      continue;
    }

    // Opaque full-coverage fast paths (byte copy / byte zero) - must stay
    // semantically identical to the general math below at alpha 255,
    // opacity 1.
    if (stamp_a == 255 && opacity == 1.0) {
      if (erase) {
        if (dst[0] != 0 || dst[1] != 0 || dst[2] != 0 || dst[3] != 0) {
          dst[0] = 0;
          dst[1] = 0;
          dst[2] = 0;
          dst[3] = 0;
          changed = 1;
        }
      } else {
        if (dst[0] != src[0] || dst[1] != src[1] || dst[2] != src[2] ||
            dst[3] != 255) {
          dst[0] = src[0];
          dst[1] = src[1];
          dst[2] = src[2];
          dst[3] = 255;
          changed = 1;
        }
      }
      continue;
    }

    const double source_alpha = ((double)stamp_a / 255.0) * opacity;
    const uint8_t dest_r = dst[0];
    const uint8_t dest_g = dst[1];
    const uint8_t dest_b = dst[2];
    const uint8_t dest_a = dst[3];
    const double destination_alpha = (double)dest_a / 255.0;

    int32_t out_r;
    int32_t out_g;
    int32_t out_b;
    int32_t out_a;
    if (erase) {
      const double out_alpha = destination_alpha * (1.0 - source_alpha);
      if (out_alpha == 0.0) {
        out_r = 0;
        out_g = 0;
        out_b = 0;
        out_a = 0;
      } else {
        out_r = dest_r;
        out_g = dest_g;
        out_b = dest_b;
        out_a = qa_round_byte(out_alpha * 255.0);
      }
    } else {
      const double out_alpha =
          source_alpha + destination_alpha * (1.0 - source_alpha);
      if (out_alpha == 0.0) {
        out_r = 0;
        out_g = 0;
        out_b = 0;
        out_a = 0;
      } else {
        const double inverse_source_alpha = 1.0 - source_alpha;
        out_r = qa_round_byte(((double)src[0] * source_alpha +
                               (double)dest_r * destination_alpha *
                                   inverse_source_alpha) /
                              out_alpha);
        out_g = qa_round_byte(((double)src[1] * source_alpha +
                               (double)dest_g * destination_alpha *
                                   inverse_source_alpha) /
                              out_alpha);
        out_b = qa_round_byte(((double)src[2] * source_alpha +
                               (double)dest_b * destination_alpha *
                                   inverse_source_alpha) /
                              out_alpha);
        out_a = qa_round_byte(out_alpha * 255.0);
      }
    }

    if ((uint8_t)out_r != dest_r || (uint8_t)out_g != dest_g ||
        (uint8_t)out_b != dest_b || (uint8_t)out_a != dest_a) {
      dst[0] = (uint8_t)out_r;
      dst[1] = (uint8_t)out_g;
      dst[2] = (uint8_t)out_b;
      dst[3] = (uint8_t)out_a;
      changed = 1;
    }
  }
  return changed;
}

// ---------------------------------------------------------------------------
// Generic dab blend (R18 A-1): the per-pixel section of
// materializeBrushDabSequenceOnBitmapSurface ported verbatim. All per-dab
// setup (trig, axis lattices, mask normalization) stays in Dart - this
// kernel only consumes precomputed data, so the float expressions here are
// EXACT transcriptions of the Dart reference (same grouping, same clamps,
// llround == double.round()). The Dart loop remains the reference oracle;
// the parity suite pins byte-identity.

enum {
  QA_DAB_FLAG_ERASE = 1,
  QA_DAB_FLAG_ROUND = 2,
  QA_DAB_FLAG_ELLIPSE = 4,
  QA_DAB_FLAG_TIP_UNROTATED = 16,
  // 없음: the edge is a hard cut at half coverage. Set INSTEAD of an
  // aa_contrast; the two never both apply (see BrushAntiAlias).
  QA_DAB_FLAG_AA_THRESHOLD = 32,
  // 高さ: the paper texture's height cuts the coverage instead of
  // multiplying it (BrushTextureMode.height, F-451). v53.
  QA_DAB_FLAG_TEXTURE_HEIGHT = 64,
  // The tip holds an edge that does not pile (`tipHoldsAnEdge`): what of a
  // pixel's coverage piles is read off round_pile, and the rest sets the
  // level the stroke settles at there (qa_dab_source_alpha). v56.
  QA_DAB_FLAG_EDGE_HELD = 128,
  // The dab is the SECOND tip's: it piles on the tile's second plane, alpha
  // alone, and moves no byte — the view does (qa_dual_view_rows). v60.
  QA_DAB_FLAG_SECOND = 256,
};

/* paperHeightBand (brush_stroke_blend.dart): how far above a dab's floor
   the paper must stand to take the dab fully. */
#define QA_PAPER_HEIGHT_BAND 0.25

// Mode ids: a fixed FFI contract - the Dart side maps BrushBlendMode
// through `strokeBlendModeNativeId` with EXACTLY these values. color and
// erase never reach the stroke kernel (they ride the ordinary stamp path).
//
// 🚨TWO KERNELS READ THIS ONE TABLE. The stroke blend composites a whole
// stroke against the cel; the dual view combines a stroke's two planes
// (v33, v60). They are the same separable vocabulary and the same ids, so
// the enum and `qa_stroke_blend_channel` sit above both rather than being
// written twice.
enum {
  QA_STROKE_BLEND_BEHIND = 0,
  QA_STROKE_BLEND_ADD = 1,
  QA_STROKE_BLEND_DARKEN = 2,
  QA_STROKE_BLEND_MULTIPLY = 3,
  QA_STROKE_BLEND_COLOR_BURN = 4,
  QA_STROKE_BLEND_LIGHTEN = 5,
  QA_STROKE_BLEND_SCREEN = 6,
  QA_STROKE_BLEND_COLOR_DODGE = 7,
  QA_STROKE_BLEND_OVERLAY = 8,
  QA_STROKE_BLEND_SOFT_LIGHT = 9,
  QA_STROKE_BLEND_HARD_LIGHT = 10,
  QA_STROKE_BLEND_DIFFERENCE = 11,
  QA_STROKE_BLEND_EXCLUSION = 12,
  // v51 (brush-fidelity, 유저 2026-10-17 Q3: 「13개 + 클튜의 발광 둘」): the
  // separable seven Photoshop and Clip Studio share...
  QA_STROKE_BLEND_LINEAR_BURN = 13,
  QA_STROKE_BLEND_SUBTRACT = 14,
  QA_STROKE_BLEND_VIVID_LIGHT = 15,
  QA_STROKE_BLEND_LINEAR_LIGHT = 16,
  QA_STROKE_BLEND_PIN_LIGHT = 17,
  QA_STROKE_BLEND_HARD_MIX = 18,
  QA_STROKE_BLEND_DIVIDE = 19,
  // ...and the six that mix the three channels — NOT in the channel table:
  // a pixel's B is a colour of three, `qa_stroke_blend_triple`. The dual
  // view combines one coverage with another and never sees these.
  QA_STROKE_BLEND_DARKER_COLOR = 20,
  QA_STROKE_BLEND_LIGHTER_COLOR = 21,
  QA_STROKE_BLEND_HUE = 22,
  QA_STROKE_BLEND_SATURATION = 23,
  QA_STROKE_BLEND_CHROMA = 24,
  QA_STROKE_BLEND_LUMINOSITY = 25,
};

static double qa_stroke_blend_channel(int32_t mode, double cs, double cd);

/* How the SECOND tip's coverage combines with the first's (v33, v60).
   [dual] is the SOURCE, [coverage] the destination.

   ⛔ADD IS NOT IN THE B(Cs, Cd) TABLE, in either language. Skia's `plus` is
   a saturating add of PREMULTIPLIED colour, so the stroke kernel answers it
   before the channel table is ever reached — and on a single coverage that
   same operation is min(1, cs + cd). Routing it through the table would
   fall out of the switch's default and silently compute EXCLUSION, which is
   the kind of wrong that looks plausible. Clip Studio's index 12 is 加算, so
   this is not a hypothetical arm: it is one of the two modes actually found
   in the user's files. */
static double qa_dual_combine(int32_t mode, double dual, double coverage) {
  if (mode == QA_STROKE_BLEND_ADD) {
    const double sum = dual + coverage;
    return sum > 1.0 ? 1.0 : sum;
  }
  return qa_stroke_blend_channel(mode, dual, coverage);
}

// Field order/types MUST match the Dart QaDabSpecStruct exactly; the
// loader cross-checks qa_dab_spec_sizeof() against Dart's sizeOf<>().
// Layout: doubles, then an even number of int32s, then pointers - natural
// alignment with no implicit padding on every supported ABI.
typedef struct {
  double center_x;
  double center_y;
  double radius;
  /* An analytic round tip's profile (`RoundTipProfile`, v56): entries a
     canvas pixel, nothing at or past round_reach, 1 at or within
     round_inner. The tables are round_coverage and round_pile. */
  double round_scale;
  double round_reach;
  double round_inner;
  /* Entries a row of the round tables holds where they are SQUARE - a small
     circle's, read at (|dx|, |dy|) (qa_round_square_at) - or 0 where they
     run along the radius. v57. */
  double round_row_length;
  double minor_radius;
  double tip_cos;
  double tip_sin;
  double inverse_roundness;
  double dab_opacity;
  double dab_flow;
  double source_alpha_norm;
  double radius_sq_skip;
  double texture_density;
  double texture_one_minus_density;
  // The brush edge step, already resolved: 1.0 leaves the coverage ramp
  // alone, otherwise it scales about 0.5. Ignored when the threshold flag
  // is set. v31.
  double aa_contrast;
  int32_t source_r;
  int32_t source_g;
  int32_t source_b;
  int32_t flags;
  int32_t region_left;
  int32_t region_top;
  int32_t tip_size;
  int32_t tex_size;
  // Tip mask (alpha pre-divided by 255, row-major size*size doubles) plus
  // the unrotated-tip axis lattices (null when the tip is rotated).
  const double* tip_alpha;
  const int32_t* tip_u_texel0;
  const double* tip_u_fraction;
  const double* tip_u_one_minus;
  const uint8_t* tip_u_in_range;
  const int32_t* tip_v_texel0;
  const double* tip_v_fraction;
  const double* tip_v_one_minus;
  const uint8_t* tip_v_in_range;
  // Paper-texture tiled mask lattices (canvas anchored).
  const double* tex_alpha;
  const int32_t* tex_u_texel0;
  const int32_t* tex_u_texel1;
  const double* tex_u_fraction;
  const double* tex_u_one_minus;
  const int32_t* tex_v_texel0;
  const int32_t* tex_v_texel1;
  const double* tex_v_fraction;
  const double* tex_v_one_minus;
  // For each tip mask row, its first and last inked column (first > last:
  // a bare row). Null when the tip is rotated or absent. v39.
  const int32_t* tip_row_ink;
  // The table the dab lays its share through (qa_dab_even), or NULL where
  // it lays whole. v41.
  const double* evening;
  // An analytic round tip's two tables (qa_round_profile_at), or NULL for
  // any other tip. v56.
  const double* round_coverage;
  const double* round_pile;
} qa_dab_spec;

QA_EXPORT int32_t qa_dab_spec_sizeof(void) {
  return (int32_t)sizeof(qa_dab_spec);
}

// Dart num.clamp(0.0, 1.0): lower on <, upper on >, otherwise the value.
static double qa_clamp01(double value) {
  if (value < 0.0) return 0.0;
  if (value > 1.0) return 1.0;
  return value;
}

// Dart .round().clamp(0, 255): llround is half-away-from-zero like Dart.

// sampleBrushTipMaskCoverage: scalar bilinear tip sample (rotated tips).
static double qa_sample_tip_scalar(
    const double* alpha,
    int32_t size,
    double tip_u,
    double tip_v,
    double radius) {
  const double scale = (double)size / (2.0 * radius);
  const double mask_x = (tip_u + radius) * scale - 0.5;
  const double mask_y = (tip_v + radius) * scale - 0.5;
  const double floor_x = floor(mask_x);
  const double floor_y = floor(mask_y);
  const int64_t x0 = (int64_t)floor_x;
  const int64_t y0 = (int64_t)floor_y;
  const double fraction_x = mask_x - floor_x;
  const double fraction_y = mask_y - floor_y;
  const int64_t x1 = x0 + 1;
  const int64_t y1 = y0 + 1;
  const int x0_in = x0 >= 0 && x0 < size;
  const int x1_in = x1 >= 0 && x1 < size;
  const double one_minus_fraction_x = 1.0 - fraction_x;

  double top = 0.0;
  if (y0 >= 0 && y0 < size) {
    const int64_t row = y0 * size;
    top = (x0_in ? alpha[row + x0] : 0.0) * one_minus_fraction_x +
          (x1_in ? alpha[row + x1] : 0.0) * fraction_x;
  }
  double bottom = 0.0;
  if (y1 >= 0 && y1 < size) {
    const int64_t row = y1 * size;
    bottom = (x0_in ? alpha[row + x0] : 0.0) * one_minus_fraction_x +
             (x1_in ? alpha[row + x1] : 0.0) * fraction_x;
  }
  return qa_clamp01(top * (1.0 - fraction_y) + bottom * fraction_y);
}

// The unrotated tip's mask row `y`, or NULL off the mask.
static inline const double* qa_tip_row(const qa_dab_spec* s, int32_t y) {
  return y >= 0 && y < s->tip_size
      ? s->tip_alpha + (ptrdiff_t)y * s->tip_size
      : NULL;
}

// The texel at column `x` of a mask row (NULL off the mask), 0.0 off the
// mask — the one read of an unrotated tip, for a pixel alone or a pair.
static inline double qa_tip_texel(const double* row, int32_t x, int32_t size) {
  return row != NULL && x >= 0 && x < size ? row[x] : 0.0;
}

// sampleBrushTipMaskCoverageLattice: unrotated tip through axis lattices.
static double qa_sample_tip_lattice(
    const qa_dab_spec* s,
    int32_t u_index,
    int32_t v_index) {
  const int32_t size = s->tip_size;
  const int32_t x0 = s->tip_u_texel0[u_index];
  const int32_t y0 = s->tip_v_texel0[v_index];
  const double* row0 = qa_tip_row(s, y0);
  const double* row1 = qa_tip_row(s, y0 + 1);
  const double fraction_x = s->tip_u_fraction[u_index];
  const double one_minus_fraction_x = s->tip_u_one_minus[u_index];

  double top = 0.0;
  if (row0 != NULL) {
    top = qa_tip_texel(row0, x0, size) * one_minus_fraction_x +
          qa_tip_texel(row0, x0 + 1, size) * fraction_x;
  }
  double bottom = 0.0;
  if (row1 != NULL) {
    bottom = qa_tip_texel(row1, x0, size) * one_minus_fraction_x +
             qa_tip_texel(row1, x0 + 1, size) * fraction_x;
  }
  return qa_clamp01(
      top * s->tip_v_one_minus[v_index] + bottom * s->tip_v_fraction[v_index]);
}

// sampleBrushTipMaskTiledCoverageLattice: the paper texture's tiled mask
// through wrapped axis lattices.
static double qa_sample_tiled_lattice(
    const double* alpha,
    int32_t size,
    const int32_t* u_texel0,
    const int32_t* u_texel1,
    const double* u_fraction,
    const double* u_one_minus,
    const int32_t* v_texel0,
    const int32_t* v_texel1,
    const double* v_fraction,
    const double* v_one_minus,
    int32_t u_index,
    int32_t v_index) {
  const int32_t x0 = u_texel0[u_index];
  const int32_t x1 = u_texel1[u_index];
  const int32_t row0 = v_texel0[v_index] * size;
  const int32_t row1 = v_texel1[v_index] * size;
  const double fraction_x = u_fraction[u_index];
  const double one_minus_fraction_x = u_one_minus[u_index];
  const double top =
      alpha[row0 + x0] * one_minus_fraction_x + alpha[row0 + x1] * fraction_x;
  const double bottom =
      alpha[row1 + x0] * one_minus_fraction_x + alpha[row1 + x1] * fraction_x;
  return qa_clamp01(
      top * v_one_minus[v_index] + bottom * v_fraction[v_index]);
}

// The brush's own EDGE on a coverage, in place — the anti-alias setting,
// before anything tiles over it. Same place and same arithmetic as
// blendDabTilesDart (유저 확정). Returns 0 when the pixel ends up bare.
static inline int qa_dab_edge(
    double* coverage,
    int aa_threshold,
    double aa_contrast) {
  if (aa_threshold) {
    *coverage = *coverage >= 0.5 ? 1.0 : 0.0;
    return !(*coverage <= 0.0);
  }
  if (aa_contrast != 1.0) {
    double edged = (*coverage - 0.5) * aa_contrast + 0.5;
    if (edged < 0.0) {
      edged = 0.0;
    } else if (edged > 1.0) {
      edged = 1.0;
    }
    *coverage = edged;
    return !(edged <= 0.0);
  }
  return 1;
}

// 🚨★★★A DAB LAYS ITS SHARE OF ONE STAMP PER TENTH OF ITS SIZE (ABI 41; 유저
// 2026-10-01, board `one-pixel-steps-change-a-brush-with-its-size`: 「엔진이
// 쌓임을 환산 — 크기와 무관하게(클튜처럼)」, 「환산은 커널에서 — 모든
// 브러시」). The law and its reasons are written once, beside `stampShareOf`
// in brush_dab_share.dart. A dab that lays a share lays `1 - (1 - a)^share`
// where it would lay `a` whole — read off the table Dart built for that
// share (`evening`: entries 0..1024 over a in [0, 1], and a 1026th that
// repeats a = 1, so a laid alpha of 1 reads its pair like any other and no
// pixel branches), linearly between two entries: no pixel pays a power, and
// the Dart and C kernels read the same numbers. `evenedLaid`'s arithmetic,
// operation by operation — and qa_d2_even's, lane by lane.
static inline double qa_dab_even(const double* table, double whole) {
  const double scaled = whole * 1024.0;
  const double x = scaled < 1024.0 ? scaled : 1024.0;
  const int32_t i = (int32_t)x;
  const double low = table[i];
  return low + (table[i + 1] - low) * (x - (double)i);
}

// 🚨★★★A ROUND TIP IS TWO RAMPS AND A PIXEL'S SQUARE, READ ALONG ITS RADIUS
// (board a-one-pixel-dab-drops-out-by-where-it-lies Q4, 유저 2026-10-25
// 「AA 가장자리는 쌓이지 않는다」). The law and its reasons are written once,
// beside `RoundTipProfile` in round_tip_profile.dart, and THE TABLES ARE
// THE LAW: Dart builds them, and this is `readAt`'s arithmetic, operation
// by operation, so both kernels read the same numbers.
static inline double qa_round_profile_at(
    const double* table,
    double scale,
    double distance) {
  const double x = distance * scale;
  const int32_t i = (int32_t)x;
  const double low = table[i];
  return low + (table[i + 1] - low) * (x - (double)i);
}

// 🚨★★A SMALL CIRCLE IS READ BY ITS SQUARE'S WHOLE AREA (board
// a-one-pixel-dab-drops-out-by-where-it-lies Q6, 유저 2026-10-25): its
// tables are square, `row_length` entries a row, and this is
// `readSquareAt`'s arithmetic, operation by operation.
static inline double qa_round_square_at(
    const double* table,
    int32_t row_length,
    double scale,
    double across,
    double down) {
  const double x = across * scale;
  const double y = down * scale;
  const int32_t i = (int32_t)x;
  const int32_t j = (int32_t)y;
  const double along_row = x - (double)i;
  const int32_t above = j * row_length + i;
  const int32_t below = above + row_length;
  const double top =
      table[above] + (table[above + 1] - table[above]) * along_row;
  const double bottom =
      table[below] + (table[below + 1] - table[below]) * along_row;
  return top + (bottom - top) * (y - (double)j);
}

// 🚨★★★A DAB'S OPACITY IS THE LEVEL IT SETTLES AT (F-205, 유저 2026-09-28:
// 「최대 100%로 해두더라도 필압 약하게하면 해당 선들 겹쳐도 필압에맞춰서
// 10%만큼만 진해진다」). A dab raises what is under it TOWARDS its opacity,
// at its flow, and never past it: the ink its coverage and flow would lay
// over nothing, scaled by how much of the way to the ceiling is left —
// (o - d) / (1 - d). Over nothing that is exactly the old alpha, so a first
// dab lands what it always did; where dabs pile up they settle at o, not at
// opaque. ↩️Opacity multiplied the dab's alpha like flow did, and a light
// press piled up to the full slider wherever a stroke crossed itself.
//
// ⚠️What is under the dab is its STROKE's own buffer: a stroke of brush dabs
// never lands on artwork dab by dab — it piles up on an empty buffer and
// composites once (brush_commit_builder, erase-live-and-dab-route-round-
// apart) — so d is how far the stroke itself has got, never the paint below.
//
// An opacity of 1 settles at opaque, which is plain source-over — the old
// arithmetic, kept byte for byte, so a brush whose opacity no dynamic moves
// lands exactly what it did. An ERASE dab keeps the multiplier: a brush
// eraser piles up coverage on its buffer (where this applies) and erases
// once, and nothing else raises an alpha.
//
// Same arithmetic, operation by operation, as blendDabTilesDart and the
// reference blendBrushDabStrokePixel. Returns a negative alpha where the
// pixel already stands at the ceiling and the dab lays nothing.
//
// What the dab would lay whole goes through its share first (qa_dab_even).
//
// 🚨★★★AN EDGE SETTLES LOWER (board a-one-pixel-dab-drops-out-by-where-it-
// lies Q4, 유저 2026-10-25 「AA 가장자리는 쌓이지 않는다」): where the tip's
// coverage is part edge, [ceiling] — the share of it that does not pile
// (`edgeCeiling`) — scales the level it settles at, and what it lays toward
// it is the share that piles. At a ceiling of 1 both are the numbers above
// to the bit; an erase keeps its multiplier.
static inline double qa_dab_source_alpha(
    const qa_dab_spec* s,
    double coverage,
    double effective_opacity,
    double destination_alpha,
    double ceiling,
    int erase) {
  if (erase || (s->dab_opacity >= 1.0 && ceiling >= 1.0)) {
    const double whole = s->source_alpha_norm * effective_opacity * s->dab_flow;
    return s->evening == NULL ? whole : qa_dab_even(s->evening, whole);
  }
  const double settle = s->dab_opacity * ceiling;
  if (destination_alpha >= settle) {
    return -1.0;
  }
  // The share that piles, no more than whole (`edgePiledShare`).
  const double share = coverage / ceiling;
  const double whole =
      s->source_alpha_norm * (share < 1.0 ? share : 1.0) * s->dab_flow;
  return (s->evening == NULL ? whole : qa_dab_even(s->evening, whole)) *
         (settle - destination_alpha) / (1.0 - destination_alpha);
}

// 🚨A STROKE PILES UP ON A 16-BIT PLANE (ABI 40; board
// `one-pixel-steps-change-a-brush-with-its-size` Q2, 유저 2026-10-01 「a는
// 제안한대로 16비트?」). Every dab rounded what it left to a byte and the next
// dab read that byte back, so a soft tail laying under half a level a dab
// never piled up at all, and the rest piled up one rounding a dab — 10
// levels off a float pile at flow 3%, size 160 (measured). A stroke tile now
// carries a second plane, RGBA at 16 bits (alpha * 65535, a channel * 257),
// and a dab reads what is under it THERE and writes both planes from the
// same double. The bytes are the plane's view: the display, the commit and
// every kernel downstream read them exactly as before.
//
// ⚠️The view is rounded from the double, not from the plane, so a first dab
// over nothing lands exactly the byte it always did.
//
// 🚨A DAB OVER NOTHING OR OVER ITS OWN COLOUR LANDS ITS OWN COLOUR, EXACTLY
// (ABI 40). The blend's colour, (c·a + d·b·(1 − a)) / (a + b·(1 − a)), is c
// in real numbers when the plane under it holds c or nothing (b = 0); in
// doubles it lands within a few units in the last place of c — some 1e-11
// of a step on the 16-bit plane — so both planes round it to c and c·257,
// exactly what the formula would have rounded to. A one-colour stroke is
// this case from its second dab on, and the three divisions it skips were
// most of what the plane cost (2026-10-01, a soft size-100 stroke: 9.6 ms
// before the plane, 24.1 ms with it, measured before this was written).
// `own` holds the dab's colour widened (c · 257); the Dart kernel and the
// reference (`strokeSourceOverAt`) take the same road.
static inline int qa_dab_over_own_colour(
    const uint16_t* wide,
    const int32_t* own) {
  return wide[3] == 0 ||
         (wide[0] == own[0] && wide[1] == own[1] && wide[2] == own[2]);
}

// qa_dab_store for a pixel on the own-colour road (qa_dab_over_own_colour,
// out_alpha above 0): the channels are the dab's own colour exactly, so
// only the alpha rounds — `own` holds the colour widened (0..2) and as
// bytes (3..5). The same bytes qa_dab_store would write.
static inline int32_t qa_dab_store_own(
    uint8_t* pixel,
    uint16_t* wide,
    double out_alpha,
    const int32_t* own) {
  const int32_t out_a = qa_round_byte(out_alpha * 255.0);
  const int32_t wide_a = qa_round_wide(out_alpha * 65535.0);
  if (wide[3] != (uint16_t)wide_a || wide[0] != (uint16_t)own[0] ||
      wide[1] != (uint16_t)own[1] || wide[2] != (uint16_t)own[2]) {
    wide[0] = (uint16_t)own[0];
    wide[1] = (uint16_t)own[1];
    wide[2] = (uint16_t)own[2];
    wide[3] = (uint16_t)wide_a;
  }
  const uint8_t out_r = out_a == 0 ? 0 : (uint8_t)own[3];
  const uint8_t out_g = out_a == 0 ? 0 : (uint8_t)own[4];
  const uint8_t out_b = out_a == 0 ? 0 : (uint8_t)own[5];
  if (pixel[3] != (uint8_t)out_a || pixel[0] != out_r ||
      pixel[1] != out_g || pixel[2] != out_b) {
    pixel[0] = out_r;
    pixel[1] = out_g;
    pixel[2] = out_b;
    pixel[3] = (uint8_t)out_a;
    return 1;
  }
  return 0;
}

// Returns 1 when a BYTE moved — the change set is the view's: a tile whose
// bytes never moved has nothing for the commit to adopt.
static inline int32_t qa_dab_store(
    uint8_t* pixel,
    uint16_t* wide,
    double out_alpha,
    double red,
    double green,
    double blue,
    int erase) {
  int32_t out_r;
  int32_t out_g;
  int32_t out_b;
  int32_t out_a;
  int32_t wide_r;
  int32_t wide_g;
  int32_t wide_b;
  int32_t wide_a;
  if (out_alpha == 0.0) {
    out_r = 0;
    out_g = 0;
    out_b = 0;
    out_a = 0;
    wide_r = 0;
    wide_g = 0;
    wide_b = 0;
    wide_a = 0;
  } else {
    if (erase) {
      out_r = pixel[0];
      out_g = pixel[1];
      out_b = pixel[2];
      wide_r = wide[0];
      wide_g = wide[1];
      wide_b = wide[2];
    } else {
      out_r = qa_round_byte(red);
      out_g = qa_round_byte(green);
      out_b = qa_round_byte(blue);
      wide_r = qa_round_wide(red * 257.0);
      wide_g = qa_round_wide(green * 257.0);
      wide_b = qa_round_wide(blue * 257.0);
    }
    out_a = qa_round_byte(out_alpha * 255.0);
    wide_a = qa_round_wide(out_alpha * 65535.0);
    if (out_a == 0) {
      // No colour under a zero alpha in the view (`StrokePixel.rounded`
      // has why); the plane keeps its colour for the dabs that pile on.
      out_r = 0;
      out_g = 0;
      out_b = 0;
    }
  }
  if ((uint16_t)wide_r != wide[0] || (uint16_t)wide_g != wide[1] ||
      (uint16_t)wide_b != wide[2] || (uint16_t)wide_a != wide[3]) {
    wide[0] = (uint16_t)wide_r;
    wide[1] = (uint16_t)wide_g;
    wide[2] = (uint16_t)wide_b;
    wide[3] = (uint16_t)wide_a;
  }
  if ((uint8_t)out_r != pixel[0] || (uint8_t)out_g != pixel[1] ||
      (uint8_t)out_b != pixel[2] || (uint8_t)out_a != pixel[3]) {
    pixel[0] = (uint8_t)out_r;
    pixel[1] = (uint8_t)out_g;
    pixel[2] = (uint8_t)out_b;
    pixel[3] = (uint8_t)out_a;
    return 1;
  }
  return 0;
}

/* 🚨★★★THE SECOND TIP IS A SECOND STROKE (v60; board
   an-imported-pencil-drops-its-second-brush Q3 b, 유저 2026-10-25 「두 번째
   획으로 다시 만든다」). Its dabs are stamped along the same path and pile on
   the tile's SECOND plane (alpha * 65535, QA_DAB_FLAG_SECOND); the first
   tip's dabs pile on the 16-bit plane as any stroke's do. The BYTES are the
   view of the two, rebuilt here over every row a batch touched: the first
   plane's colour, and its alpha combined with the second's through the
   tip's mode at its density. Outside the first tip's ink nothing shows — a
   second tip lays only where both lay (Photoshop's Dual Brush, and the mask
   brush Krita draws it with lays its mask over the WHOLE stroke). A pure
   function of the two planes, so the order the two strokes' dabs land in
   moves no byte, and what the stroke shows as it is drawn is what it lands.
   ↩️Until v60 the second tip was a tiled mask over each dab, at a random
   phase a dab: a grain inside each stamp, never a stroke of its own.

   🚨THE SECOND TIP HAS A MODE (v33). Both formats say so: Clip Studio writes
   `DualBrushCompositeMode` (the 合成モード menu index — 1 and 12 seen in the
   wild) and Photoshop writes `dualBrush.BlnM` (eight four-char codes across
   765 brushes).

   ⛔MULTIPLY KEEPS ITS OWN LINE. The general form below is
   `lerp(a, B(s, a), d)`, which for B = multiply is the SAME NUMBER and NOT
   THE SAME BYTES: `a * ((1-d) + d*s)` and `a*(1-d) + d*s*a` differ in the
   last bit of a double, and the default should be the one written plainly.

   ⚠️SOURCE = THE SECOND TIP, DESTINATION = THE FIRST. Multiply is commutative
   so nothing that exists today can tell, and the non-commutative modes are
   REASONED, not measured: the second tip is applied over the first, so it
   is the source. Worth a side-by-side against Clip Studio before anyone
   builds on the order.

   Returns 1 when a byte moved. */
static int32_t qa_dual_view_rows(
    uint8_t* tile_pixels,
    const uint16_t* tile_wide,
    const uint16_t* tile_second,
    int32_t tile_size,
    int32_t tile_left,
    int32_t tile_top,
    int32_t left,
    int32_t right_exclusive,
    int32_t top,
    int32_t bottom_exclusive,
    int32_t mode,
    double density) {
  const double one_minus_density = 1.0 - density;
  int32_t changed = 0;
  for (int32_t y = top; y < bottom_exclusive; y += 1) {
    const int32_t row = (y - tile_top) * tile_size;
    for (int32_t x = left; x < right_exclusive; x += 1) {
      const int32_t index = row + (x - tile_left);
      uint8_t* pixel = tile_pixels + (ptrdiff_t)index * 4;
      const uint16_t* wide = tile_wide + (ptrdiff_t)index * 4;
      int32_t out_r = 0;
      int32_t out_g = 0;
      int32_t out_b = 0;
      int32_t out_a = 0;
      if (wide[3] != 0) {
        const double first = (double)wide[3] / 65535.0;
        const double level = (double)tile_second[index] / 65535.0;
        double alpha;
        if (mode == QA_STROKE_BLEND_MULTIPLY) {
          alpha = first * (one_minus_density + density * level);
        } else {
          alpha = first * one_minus_density +
                  density * qa_dual_combine(mode, level, first);
          if (alpha > 1.0) {
            alpha = 1.0;
          }
        }
        out_a = qa_round_byte(alpha * 255.0);
        if (out_a != 0) {
          out_r = qa_round_byte((double)wide[0] / 257.0);
          out_g = qa_round_byte((double)wide[1] / 257.0);
          out_b = qa_round_byte((double)wide[2] / 257.0);
        }
      }
      if ((uint8_t)out_r != pixel[0] || (uint8_t)out_g != pixel[1] ||
          (uint8_t)out_b != pixel[2] || (uint8_t)out_a != pixel[3]) {
        pixel[0] = (uint8_t)out_r;
        pixel[1] = (uint8_t)out_g;
        pixel[2] = (uint8_t)out_b;
        pixel[3] = (uint8_t)out_a;
        changed = 1;
      }
    }
  }
  return changed;
}

// 🚨A PLAIN TIPPED DAB BLENDS TWO PIXELS AT A TIME (board `brush-kernel-next`
// ①, 유저 2026-09-25 「1번 할 생각 있어」 — SIMD). A raster tip and a square
// reach the kernel as a tip mask and most carry no texture mask, so
// this path is their brush work. ↩️A round tip rode it too, baked into a
// mask (BrushTipStampCache), until it became its profile (v56): read
// scalar off its two tables it costs 0.75–0.91 of what its mask did here
// from 20px up, and about the same below (2026-10-25, measured through the
// live rasterizer — and no bake, no upload). Two
// doubles a register on both baselines (SSE2 / NEON): the four divisions a
// pixel pays, and the sampling and alpha arithmetic around them, run for a
// pair at once.
//
// ⛔BYTE-IDENTICAL BY CONSTRUCTION: each lane runs the scalar loop's own
// arithmetic, operation by operation and in the scalar's order — a multiply
// is a multiply and an add an add, nothing fused (MSVC /fp:precise, clang
// -ffp-contract=off) — and an IEEE add, subtract, multiply or divide rounds
// the same in a lane as in a scalar. The texel reads, the clamp, the edge
// step and the byte rounding are the scalar's own functions, called per
// lane. A lane the scalar loop would `continue` on is never written, and a
// row's odd pixel is left to the scalar loop.
#if defined(QA_SSE2) || defined(QA_NEON)
#define QA_DAB_PAIRS 1
#if defined(QA_SSE2)
typedef __m128d qa_d2;
static inline qa_d2 qa_d2_splat(double v) { return _mm_set1_pd(v); }
static inline qa_d2 qa_d2_load(const double* p) { return _mm_loadu_pd(p); }
static inline void qa_d2_store(double* p, qa_d2 v) { _mm_storeu_pd(p, v); }
static inline qa_d2 qa_d2_add(qa_d2 a, qa_d2 b) { return _mm_add_pd(a, b); }
static inline qa_d2 qa_d2_sub(qa_d2 a, qa_d2 b) { return _mm_sub_pd(a, b); }
static inline qa_d2 qa_d2_mul(qa_d2 a, qa_d2 b) { return _mm_mul_pd(a, b); }
static inline qa_d2 qa_d2_div(qa_d2 a, qa_d2 b) { return _mm_div_pd(a, b); }
// qa_dab_even for a pair, in registers: each lane reads its two entries with
// one load. ↩️The lanes went through memory one by one — two scalar stores
// and a vector reload the CPU cannot forward — and a soft size-300 stroke
// laying its share cost a third more than laying it whole (2026-10-01).
static inline qa_d2 qa_d2_even(const double* table, qa_d2 whole) {
  const qa_d2 top = _mm_set1_pd(1024.0);
  const qa_d2 x = _mm_min_pd(_mm_mul_pd(whole, top), top);
  const __m128i i = _mm_cvttpd_epi32(x);
  const qa_d2 pair0 = _mm_loadu_pd(table + _mm_cvtsi128_si32(i));
  const qa_d2 pair1 =
      _mm_loadu_pd(table + _mm_cvtsi128_si32(_mm_srli_si128(i, 4)));
  const qa_d2 low = _mm_unpacklo_pd(pair0, pair1);
  const qa_d2 high = _mm_unpackhi_pd(pair0, pair1);
  return _mm_add_pd(
      low, _mm_mul_pd(_mm_sub_pd(high, low), _mm_sub_pd(x, _mm_cvtepi32_pd(i))));
}
#else
typedef float64x2_t qa_d2;
static inline qa_d2 qa_d2_splat(double v) { return vdupq_n_f64(v); }
static inline qa_d2 qa_d2_load(const double* p) { return vld1q_f64(p); }
static inline void qa_d2_store(double* p, qa_d2 v) { vst1q_f64(p, v); }
static inline qa_d2 qa_d2_add(qa_d2 a, qa_d2 b) { return vaddq_f64(a, b); }
static inline qa_d2 qa_d2_sub(qa_d2 a, qa_d2 b) { return vsubq_f64(a, b); }
static inline qa_d2 qa_d2_mul(qa_d2 a, qa_d2 b) { return vmulq_f64(a, b); }
static inline qa_d2 qa_d2_div(qa_d2 a, qa_d2 b) { return vdivq_f64(a, b); }
static inline qa_d2 qa_d2_even(const double* table, qa_d2 whole) {
  const qa_d2 top = vdupq_n_f64(1024.0);
  const qa_d2 x = vminq_f64(vmulq_f64(whole, top), top);
  const int64x2_t i = vcvtq_s64_f64(x);
  const qa_d2 pair0 = vld1q_f64(table + vgetq_lane_s64(i, 0));
  const qa_d2 pair1 = vld1q_f64(table + vgetq_lane_s64(i, 1));
  const qa_d2 low = vzip1q_f64(pair0, pair1);
  const qa_d2 high = vzip2q_f64(pair0, pair1);
  return vaddq_f64(
      low, vmulq_f64(vsubq_f64(high, low), vsubq_f64(x, vcvtq_f64_s64(i))));
}
#endif

// One channel of a pair's source-over: (source * alpha + destination *
// its alpha * (1 - alpha)) / out alpha, in the scalar's grouping.
static inline qa_d2 qa_d2_over(
    qa_d2 source,
    qa_d2 source_alpha,
    const double* destination,
    qa_d2 destination_alpha,
    qa_d2 inverse,
    qa_d2 out_alpha) {
  return qa_d2_div(
      qa_d2_add(qa_d2_mul(source, source_alpha),
                qa_d2_mul(qa_d2_mul(qa_d2_load(destination),
                                    destination_alpha),
                          inverse)),
      out_alpha);
}

// Blends pixels [x, x_end) of one row of a plain tipped dab two at a time
// while a pair fits; returns the first pixel it left for the scalar loop.
// `row` and `wide_row` are the tile row's first pixel on its two planes
// (canvas x = tile_left).
static int32_t qa_dab_blend_pairs(
    const qa_dab_spec* s,
    uint8_t* row,
    uint16_t* wide_row,
    int32_t tile_left,
    int32_t x,
    int32_t x_end,
    int32_t v_index,
    int erase,
    int aa_threshold,
    double aa_contrast,
    const int32_t* own,
    int32_t* changed) {
  const int32_t size = s->tip_size;
  const int32_t y0 = s->tip_v_texel0[v_index];
  const double* row0 = qa_tip_row(s, y0);
  const double* row1 = qa_tip_row(s, y0 + 1);
  const qa_d2 v_one_minus = qa_d2_splat(s->tip_v_one_minus[v_index]);
  const qa_d2 v_fraction = qa_d2_splat(s->tip_v_fraction[v_index]);
  const qa_d2 one = qa_d2_splat(1.0);
  const qa_d2 wide_max = qa_d2_splat(65535.0);
  const qa_d2 alpha_norm = qa_d2_splat(s->source_alpha_norm);
  const qa_d2 flow = qa_d2_splat(s->dab_flow);

  for (; x + 1 < x_end; x += 2) {
    const int32_t u = x - s->region_left;
    int keep[2];
    double t00[2], t01[2], t10[2], t11[2];
    for (int i = 0; i < 2; i += 1) {
      keep[i] = s->tip_u_in_range[u + i] != 0;
      const int32_t x0 = s->tip_u_texel0[u + i];
      t00[i] = qa_tip_texel(row0, x0, size);
      t01[i] = qa_tip_texel(row0, x0 + 1, size);
      t10[i] = qa_tip_texel(row1, x0, size);
      t11[i] = qa_tip_texel(row1, x0 + 1, size);
    }
    if (!keep[0] && !keep[1]) {
      continue;
    }
    // A mask row off the mask reads as a row of zeros here, where the
    // scalar sampler skips it: 0.0 times a fraction in [0, 1] plus 0.0 is
    // the same +0.0 it starts from.
    const qa_d2 one_minus_x = qa_d2_load(s->tip_u_one_minus + u);
    const qa_d2 fraction_x = qa_d2_load(s->tip_u_fraction + u);
    const qa_d2 top = qa_d2_add(qa_d2_mul(qa_d2_load(t00), one_minus_x),
                                qa_d2_mul(qa_d2_load(t01), fraction_x));
    const qa_d2 bottom = qa_d2_add(qa_d2_mul(qa_d2_load(t10), one_minus_x),
                                   qa_d2_mul(qa_d2_load(t11), fraction_x));
    double coverage[2];
    qa_d2_store(coverage, qa_d2_add(qa_d2_mul(top, v_one_minus),
                                    qa_d2_mul(bottom, v_fraction)));
    double effective[2];
    for (int i = 0; i < 2; i += 1) {
      effective[i] = 0.0;
      if (!keep[i]) {
        continue;
      }
      coverage[i] = qa_clamp01(coverage[i]);
      if (coverage[i] <= 0.0 ||
          !qa_dab_edge(&coverage[i], aa_threshold, aa_contrast)) {
        keep[i] = 0;
        continue;
      }
      effective[i] = s->dab_opacity * coverage[i];
      if (effective[i] == 0.0) {
        keep[i] = 0;
      }
    }
    if (!keep[0] && !keep[1]) {
      continue;
    }

    uint8_t* pixel = row + (ptrdiff_t)(x - tile_left) * 4;
    uint16_t* wide = wide_row + (ptrdiff_t)(x - tile_left) * 4;
    const double lanes_a[2] = {(double)wide[3], (double)wide[7]};
    const qa_d2 destination_alpha = qa_d2_div(qa_d2_load(lanes_a), wide_max);
    qa_d2 source_alpha;
    if (erase || s->dab_opacity >= 1.0) {
      source_alpha =
          qa_d2_mul(qa_d2_mul(alpha_norm, qa_d2_load(effective)), flow);
      if (s->evening != NULL) {
        // Its share (qa_d2_even). A lane the loop drops lays 0, reads the
        // table's first pair and is never written.
        source_alpha = qa_d2_even(s->evening, source_alpha);
      }
    } else {
      // Under its ceiling a dab's alpha depends on what each pixel already
      // holds (qa_dab_source_alpha), so the lanes take the scalar's own
      // function one by one.
      double lanes_d[2];
      double settled[2] = {0.0, 0.0};
      qa_d2_store(lanes_d, destination_alpha);
      for (int i = 0; i < 2; i += 1) {
        if (!keep[i]) {
          continue;
        }
        settled[i] = qa_dab_source_alpha(s, coverage[i], effective[i],
                                         lanes_d[i], 1.0, erase);
        if (settled[i] < 0.0) {
          keep[i] = 0;
          settled[i] = 0.0;
        }
      }
      if (!keep[0] && !keep[1]) {
        continue;
      }
      source_alpha = qa_d2_load(settled);
    }
    const qa_d2 inverse = qa_d2_sub(one, source_alpha);
    double out_alpha[2];
    double red[2] = {0.0, 0.0};
    double green[2] = {0.0, 0.0};
    double blue[2] = {0.0, 0.0};
    if (erase) {
      qa_d2_store(out_alpha, qa_d2_mul(destination_alpha, inverse));
    } else {
      const qa_d2 alpha =
          qa_d2_add(source_alpha, qa_d2_mul(destination_alpha, inverse));
      qa_d2_store(out_alpha, alpha);
      // Over nothing or over its own colour a lane lands its own colour
      // exactly (qa_dab_over_own_colour); the pair pays the colour blend
      // only when a lane needs it.
      const int own_colour[2] = {qa_dab_over_own_colour(wide, own),
                                 qa_dab_over_own_colour(wide + 4, own)};
      if (!own_colour[0] || !own_colour[1]) {
        const double lanes_r[2] = {(double)wide[0] / 257.0,
                                   (double)wide[4] / 257.0};
        const double lanes_g[2] = {(double)wide[1] / 257.0,
                                   (double)wide[5] / 257.0};
        const double lanes_b[2] = {(double)wide[2] / 257.0,
                                   (double)wide[6] / 257.0};
        qa_d2_store(red, qa_d2_over(qa_d2_splat((double)s->source_r),
                                    source_alpha, lanes_r, destination_alpha,
                                    inverse, alpha));
        qa_d2_store(green, qa_d2_over(qa_d2_splat((double)s->source_g),
                                      source_alpha, lanes_g,
                                      destination_alpha, inverse, alpha));
        qa_d2_store(blue, qa_d2_over(qa_d2_splat((double)s->source_b),
                                     source_alpha, lanes_b, destination_alpha,
                                     inverse, alpha));
      }
      for (int i = 0; i < 2; i += 1) {
        if (keep[i] && own_colour[i] && out_alpha[i] != 0.0) {
          if (qa_dab_store_own(pixel + i * 4, wide + i * 4, out_alpha[i],
                               own)) {
            *changed = 1;
          }
          keep[i] = 0;
        }
      }
    }

    for (int i = 0; i < 2; i += 1) {
      if (!keep[i]) {
        continue;
      }
      if (qa_dab_store(pixel + i * 4, wide + i * 4, out_alpha[i],
                       erase ? 0.0 : red[i], erase ? 0.0 : green[i],
                       erase ? 0.0 : blue[i], erase)) {
        *changed = 1;
      }
    }
  }
  return x;
}
#endif

// 🚨A ROW OF AN UNROTATED TIP VISITS ONLY THE PIXELS WHOSE TEXELS CAN HOLD
// INK (ABI 39, 2026-09-25, board `brush-kernel-next` ②; 유저 「2번도
// 있고」 — the skip of the pixels outside the dab). Every ANALYTIC brush dab
// reaches this kernel as a mask prerendered per quantized size
// (BrushTipStampCache; a raster tip arrives as its own mask, and a rotated
// one takes the scalar loop — F-251), so the ROUND case is this path, not
// the analytic one below: a round mask
// is bare in its corners, about a fifth of the box, and each of those
// pixels was sampled bilinearly to a coverage of 0 and thrown away.
//
// A pixel samples texels texel0 and texel0 + 1 of the two mask rows its row
// maps to, so it can meet ink only when texel0 lies in [first - 1, last] of
// the columns those two rows ink together. Narrows [*left, *right) to the
// pixels inside that reach, from both ends, and returns 0 when neither row
// holds any ink.
//
// ⛔BYTE-IDENTICAL BY CONSTRUCTION: only a pixel whose four texels are all
// bare leaves — its coverage is exactly 0, which the pixel loop `continue`s
// on — and a row whose two mask rows are bare is such a pixel end to end.
static int qa_tip_row_reach(
    const qa_dab_spec* s,
    int32_t v_index,
    int32_t* left,
    int32_t* right) {
  const int32_t size = s->tip_size;
  const int32_t y0 = s->tip_v_texel0[v_index];
  int32_t first = INT32_MAX;
  int32_t last = INT32_MIN;
  for (int32_t ty = y0; ty <= y0 + 1; ty += 1) {
    if (ty < 0 || ty >= size) {
      continue;
    }
    const int32_t row_first = s->tip_row_ink[ty * 2];
    const int32_t row_last = s->tip_row_ink[ty * 2 + 1];
    if (row_first > row_last) {
      continue;
    }
    if (row_first < first) first = row_first;
    if (row_last > last) last = row_last;
  }
  if (first > last) {
    return 0;
  }
  while (*left < *right &&
         s->tip_u_texel0[*left - s->region_left] < first - 1) {
    *left += 1;
  }
  while (*right > *left &&
         s->tip_u_texel0[*right - 1 - s->region_left] > last) {
    *right -= 1;
  }
  return 1;
}

// Blends one dab into one tile over the given canvas-space spans. Pixel
// visit set and math are identical to the Dart loop (which walks rows
// outermost; per-dab each pixel is touched exactly once either way).
// [tile_wide] is the tile's 16-bit plane on the same grid (see
// qa_dab_store), and [tile_second] its second plane (qa_dual_view_rows) —
// NULL for a stroke with one tip. Returns nonzero when any destination byte
// changed.
QA_EXPORT int32_t qa_dab_blend_tile(
    uint8_t* tile_pixels,
    uint16_t* tile_wide,
    uint16_t* tile_second,
    int32_t tile_size,
    int32_t tile_left,
    int32_t tile_top,
    int32_t span_left,
    int32_t span_right_exclusive,
    int32_t span_top,
    int32_t span_bottom_exclusive,
    const qa_dab_spec* s) {
  const int32_t flags = s->flags;
  const int erase = (flags & QA_DAB_FLAG_ERASE) != 0;
  const int is_round = (flags & QA_DAB_FLAG_ROUND) != 0;
  const int is_ellipse = (flags & QA_DAB_FLAG_ELLIPSE) != 0;
  const int unrotated_tip = (flags & QA_DAB_FLAG_TIP_UNROTATED) != 0;
  const int second = (flags & QA_DAB_FLAG_SECOND) != 0;
  const int has_tip = s->tip_alpha != NULL;
  const int has_tex = s->tex_alpha != NULL;
  const int aa_threshold = (flags & QA_DAB_FLAG_AA_THRESHOLD) != 0;
  const int texture_height = (flags & QA_DAB_FLAG_TEXTURE_HEIGHT) != 0;
  const double aa_contrast = s->aa_contrast;
  const int edge_held = (flags & QA_DAB_FLAG_EDGE_HELD) != 0;
  const int32_t round_row_length = (int32_t)s->round_row_length;
  // A tile with a second plane shows its view (qa_dual_view_rows): a dab
  // writes its planes there and no byte — the view writes those, and says
  // which moved. The bytes a store would write go to `sink`.
  const int viewed = tile_second != NULL;
  uint8_t sink[4] = {0, 0, 0, 0};
  if (second && !viewed) {
    return 0;
  }
#if defined(QA_DAB_PAIRS)
  const int pairs = has_tip && unrotated_tip && !has_tex && !viewed;
#endif
  // The dab's colour on the 16-bit plane, then as bytes
  // (qa_dab_over_own_colour, qa_dab_store_own).
  const int32_t own[6] = {s->source_r * 257, s->source_g * 257,
                          s->source_b * 257, s->source_r,
                          s->source_g,       s->source_b};
  int32_t changed = 0;

  for (int32_t y = span_top; y < span_bottom_exclusive; y += 1) {
    const int32_t v_index = y - s->region_top;
    if (has_tip && unrotated_tip && s->tip_v_in_range[v_index] == 0) {
      continue;
    }
    const double dy = (double)y + 0.5 - s->center_y;
    const double dy_squared = dy * dy;
    const int32_t local_row_offset = (y - tile_top) * tile_size;
    int32_t row_left = span_left;
    int32_t row_right = span_right_exclusive;
    if (has_tip && unrotated_tip && s->tip_row_ink != NULL &&
        !qa_tip_row_reach(s, v_index, &row_left, &row_right)) {
      continue;
    }

    int32_t x = row_left;
#if defined(QA_DAB_PAIRS)
    if (pairs) {
      x = qa_dab_blend_pairs(
          s, tile_pixels + (ptrdiff_t)local_row_offset * 4,
          tile_wide + (ptrdiff_t)local_row_offset * 4, tile_left, row_left,
          row_right, v_index, erase, aa_threshold, aa_contrast, own,
          &changed);
    }
#endif
    for (; x < row_right; x += 1) {
      double coverage;
      // What of it piles where the tip holds an edge (QA_DAB_FLAG_EDGE_HELD);
      // unread everywhere else, where all of it piles.
      double pile = 0.0;
      if (has_tip) {
        if (unrotated_tip) {
          const int32_t u_index = x - s->region_left;
          if (s->tip_u_in_range[u_index] == 0) {
            continue;
          }
          coverage = qa_sample_tip_lattice(s, u_index, v_index);
        } else {
          const double dx = (double)x + 0.5 - s->center_x;
          const double tip_u = dx * s->tip_cos - dy * s->tip_sin;
          const double tip_v =
              (dx * s->tip_sin + dy * s->tip_cos) * s->inverse_roundness;
          if (fabs(tip_u) > s->radius || fabs(tip_v) > s->radius) {
            continue;
          }
          coverage = qa_sample_tip_scalar(
              s->tip_alpha, s->tip_size, tip_u, tip_v, s->radius);
        }
        if (coverage <= 0.0) {
          continue;
        }
      } else if (is_round && round_row_length > 0) {
        // A small circle: its square tables at the pixel's (|dx|, |dy|).
        const double across = fabs((double)x + 0.5 - s->center_x);
        const double down = fabs(dy);
        if (across >= s->round_reach || down >= s->round_reach) {
          continue;
        }
        coverage = qa_round_square_at(
            s->round_coverage, round_row_length, s->round_scale, across, down);
        if (edge_held) {
          pile = qa_round_square_at(
              s->round_pile, round_row_length, s->round_scale, across, down);
        }
        if (coverage <= 0.0) {
          continue;
        }
      } else if (is_round) {
        const double dx = (double)x + 0.5 - s->center_x;
        double distance;
        if (is_ellipse) {
          const double tip_u = dx * s->tip_cos - dy * s->tip_sin;
          const double tip_v =
              (dx * s->tip_sin + dy * s->tip_cos) * s->inverse_roundness;
          distance = sqrt(tip_u * tip_u + tip_v * tip_v);
        } else {
          const double dx_squared = dx * dx;
          if (dx_squared + dy_squared > s->radius_sq_skip) {
            continue;
          }
          distance = sqrt(dx_squared + dy_squared);
        }
        if (distance >= s->round_reach) {
          continue;
        }
        if (distance <= s->round_inner) {
          coverage = 1.0;
          pile = 1.0;
        } else {
          coverage =
              qa_round_profile_at(s->round_coverage, s->round_scale, distance);
          if (edge_held) {
            pile = qa_round_profile_at(s->round_pile, s->round_scale, distance);
          }
        }
        if (coverage <= 0.0) {
          continue;
        }
      } else {
        /* A square dab is axis-aligned by construction now, so there is no
           rotated-rect case left to test for. */
        coverage = 1.0;
      }

      if (!qa_dab_edge(&coverage, aa_threshold, aa_contrast)) {
        continue;
      }
      // 🚨★★★THE EDGE DOES NOT PILE (`edgeCeiling`, and the reasons beside
      // the Dart kernel's own line): the share of the dab's opacity the
      // stroke may come up to here.
      const double ceiling =
          edge_held && pile > coverage ? coverage / pile : 1.0;

      if (has_tex) {
        const double texture_sample = qa_sample_tiled_lattice(
            s->tex_alpha, s->tex_size, s->tex_u_texel0, s->tex_u_texel1,
            s->tex_u_fraction, s->tex_u_one_minus, s->tex_v_texel0,
            s->tex_v_texel1, s->tex_v_fraction, s->tex_v_one_minus,
            x - s->region_left, v_index);
        /* paperHeightCoverage (brush_stroke_blend.dart), same grouping.
           ⛔MULTIPLY KEEPS ITS OWN LINE: every brush before F-451 drew it,
           and its bytes stay as written. */
        if (texture_height) {
          const double touched =
              (texture_sample + s->texture_density * coverage - 1.0) /
              QA_PAPER_HEIGHT_BAND;
          coverage = touched <= 0.0 ? 0.0 : (touched >= 1.0 ? 1.0 : touched);
        } else {
          coverage *= s->texture_one_minus_density +
                      s->texture_density * texture_sample;
        }
        if (coverage <= 0.0) {
          continue;
        }
      }

      const double effective_opacity = s->dab_opacity * coverage;
      if (effective_opacity == 0.0) {
        continue;
      }

      if (second) {
        // The second tip's dab piles on the second plane as any dab piles
        // over its alpha — over, never an erase — and the view shows it.
        uint16_t* level = tile_second + local_row_offset + (x - tile_left);
        const double under = (double)*level / 65535.0;
        const double laid = qa_dab_source_alpha(
            s, coverage, effective_opacity, under, ceiling, 0);
        if (laid < 0.0) {
          continue;
        }
        // qa_dab_store's alpha, the same grouping.
        const double piled = laid + under * (1.0 - laid);
        const uint16_t stored = (uint16_t)qa_round_wide(piled * 65535.0);
        if (stored != *level) {
          *level = stored;
        }
        continue;
      }

      const ptrdiff_t at = (ptrdiff_t)(local_row_offset + (x - tile_left)) * 4;
      uint8_t* pixel = viewed ? sink : tile_pixels + at;
      uint16_t* wide = tile_wide + at;
      const double destination_alpha = (double)wide[3] / 65535.0;
      const double source_alpha = qa_dab_source_alpha(
          s, coverage, effective_opacity, destination_alpha, ceiling, erase);
      if (source_alpha < 0.0) {
        continue;
      }

      const double inverse_source_alpha = 1.0 - source_alpha;
      double out_alpha;
      double red = 0.0;
      double green = 0.0;
      double blue = 0.0;
      if (erase) {
        out_alpha = destination_alpha * inverse_source_alpha;
      } else {
        out_alpha = source_alpha + destination_alpha * inverse_source_alpha;
        if (out_alpha != 0.0 && qa_dab_over_own_colour(wide, own)) {
          if (qa_dab_store_own(pixel, wide, out_alpha, own)) {
            changed = 1;
          }
          continue;
        }
        if (out_alpha != 0.0) {
          red = ((double)s->source_r * source_alpha +
                 (double)wide[0] / 257.0 * destination_alpha *
                     inverse_source_alpha) /
                out_alpha;
          green = ((double)s->source_g * source_alpha +
                   (double)wide[1] / 257.0 * destination_alpha *
                       inverse_source_alpha) /
                  out_alpha;
          blue = ((double)s->source_b * source_alpha +
                  (double)wide[2] / 257.0 * destination_alpha *
                      inverse_source_alpha) /
                 out_alpha;
        }
      }
      if (qa_dab_store(pixel, wide, out_alpha, red, green, blue, erase)) {
        changed = 1;
      }
    }
  }
  return viewed ? 0 : changed;
}

// ---------------------------------------------------------------------------
// Alpha premultiply (R18 A-2a): the display upload path's per-tile
// conversion (BitmapTileImageCache.premultipliedTilePixels) - straight
// alpha to premultiplied with Skia's own SkMulDiv255Round so uploads
// round identically to Skia's rasterization. Pure integer math, ported
// verbatim from the Dart reference.
//
// FOUR PIXELS A STEP where the build has the SIMD (2026-10-12): a tile's
// premultiply was ~14% of the UI thread while playback made the camera
// view's pictures (board playback-plays-the-screen-material), one byte at a
// time behind a branch per pixel. The formula needs no branch — alpha 255
// gives the byte back and alpha 0 gives 0, whatever the colour — so the
// fast paths were only that, and every lane takes the same steps: the
// product and its 128 fit sixteen bits (65,153 at most), and so does the
// rounding added to it (65,407), so the bytes are the scalar's.
//
// ⛔Not spread across the worker pool (lane tile-pictures-in-one-call,
// 10-12, not landed): a run of tiles staged in one pooled call was never
// faster where it was measured, the call waits for every worker it woke,
// and the composes that give way between pictures took the one staging
// block from each other — one make on a loaded machine staged its 72 runs
// 945 times.
static inline void qa_premultiply_pixel(uint8_t* d, const uint8_t* s) {
  const int32_t alpha = s[3];
  // SkMulDiv255Round: round(value * alpha / 255) for bytes.
  int32_t product = s[0] * alpha + 128;
  d[0] = (uint8_t)((product + (product >> 8)) >> 8);
  product = s[1] * alpha + 128;
  d[1] = (uint8_t)((product + (product >> 8)) >> 8);
  product = s[2] * alpha + 128;
  d[2] = (uint8_t)((product + (product >> 8)) >> 8);
  d[3] = (uint8_t)alpha;
}

#if defined(QA_SSE2)
static inline __m128i qa_premultiply4(__m128i px) {
  const __m128i zero = _mm_setzero_si128();
  const __m128i half = _mm_set1_epi16(128);
  const __m128i alpha_bytes = _mm_set1_epi32((int32_t)0xFF000000u);
  __m128i lo = _mm_unpacklo_epi8(px, zero);
  __m128i hi = _mm_unpackhi_epi8(px, zero);
  const __m128i alpha_lo = _mm_shufflehi_epi16(
      _mm_shufflelo_epi16(lo, _MM_SHUFFLE(3, 3, 3, 3)),
      _MM_SHUFFLE(3, 3, 3, 3));
  const __m128i alpha_hi = _mm_shufflehi_epi16(
      _mm_shufflelo_epi16(hi, _MM_SHUFFLE(3, 3, 3, 3)),
      _MM_SHUFFLE(3, 3, 3, 3));
  lo = _mm_add_epi16(_mm_mullo_epi16(lo, alpha_lo), half);
  hi = _mm_add_epi16(_mm_mullo_epi16(hi, alpha_hi), half);
  lo = _mm_srli_epi16(_mm_add_epi16(lo, _mm_srli_epi16(lo, 8)), 8);
  hi = _mm_srli_epi16(_mm_add_epi16(hi, _mm_srli_epi16(hi, 8)), 8);
  const __m128i colour = _mm_packus_epi16(lo, hi);
  return _mm_or_si128(_mm_and_si128(px, alpha_bytes),
                      _mm_andnot_si128(alpha_bytes, colour));
}
#elif defined(QA_NEON)
static inline uint8x16_t qa_premultiply4(uint8x16_t px) {
  static const uint8_t alpha_of[16] = {3,  3,  3,  3,  7,  7,  7,  7,
                                       11, 11, 11, 11, 15, 15, 15, 15};
  const uint8x16_t alpha = vqtbl1q_u8(px, vld1q_u8(alpha_of));
  const uint16x8_t half = vdupq_n_u16(128);
  uint16x8_t lo = vaddq_u16(vmull_u8(vget_low_u8(px), vget_low_u8(alpha)),
                            half);
  uint16x8_t hi = vaddq_u16(vmull_high_u8(px, alpha), half);
  lo = vaddq_u16(lo, vshrq_n_u16(lo, 8));
  hi = vaddq_u16(hi, vshrq_n_u16(hi, 8));
  const uint8x16_t colour =
      vcombine_u8(vshrn_n_u16(lo, 8), vshrn_n_u16(hi, 8));
  return vbslq_u8(vreinterpretq_u8_u32(vdupq_n_u32(0xFF000000u)), px,
                  colour);
}
#endif

// Fused copy + premultiply (R19-Z): reads straight-alpha [src], writes
// premultiplied bytes into [dst] in one pass - the decode-start path
// used to pay a copy AND an in-place premultiply. [dst] may be [src]: a
// step reads its pixels before it writes them.
QA_EXPORT void qa_premultiply_rgba_copy(
    uint8_t* dst,
    const uint8_t* src,
    int32_t pixel_count) {
  int32_t i = 0;
#if defined(QA_SSE2)
  for (; i + 4 <= pixel_count; i += 4) {
    const ptrdiff_t at = (ptrdiff_t)i * 4;
    const __m128i px = _mm_loadu_si128((const __m128i*)(src + at));
    _mm_storeu_si128((__m128i*)(dst + at), qa_premultiply4(px));
  }
#elif defined(QA_NEON)
  for (; i + 4 <= pixel_count; i += 4) {
    const ptrdiff_t at = (ptrdiff_t)i * 4;
    vst1q_u8(dst + at, qa_premultiply4(vld1q_u8(src + at)));
  }
#endif
  for (; i < pixel_count; i += 1) {
    qa_premultiply_pixel(dst + (ptrdiff_t)i * 4, src + (ptrdiff_t)i * 4);
  }
}

QA_EXPORT void qa_premultiply_rgba(uint8_t* pixels, int32_t pixel_count) {
  qa_premultiply_rgba_copy(pixels, pixels, pixel_count);
}

// The same copy a row at a time between two strides (ABI 46): [rows] rows
// of [width] straight pixels, [src_stride] bytes apart, premultiplied into
// [dst] at rows [dst_stride] bytes apart - a tile laid into a picture of
// several tiles in one call, where a call a row costs more than its pixels.
QA_EXPORT void qa_premultiply_rgba_rows(
    uint8_t* dst,
    int64_t dst_stride,
    const uint8_t* src,
    int64_t src_stride,
    int32_t width,
    int32_t rows) {
  for (int32_t y = 0; y < rows; y += 1) {
    qa_premultiply_rgba_copy(dst + (ptrdiff_t)y * dst_stride,
                             src + (ptrdiff_t)y * src_stride, width);
  }
}

// A row's colour keys over straight pixels, IN PLACE (ABI 49, 58): every
// alpha what the keys leave it, every colour as it was - and 1 when any
// alpha changed, 0 when none did.
//
// ⛔NO KEY IS DEFINED HERE. Which keys name a pixel, and what each leaves of
// an alpha it erases, are TABLES the Dart side makes from the one definition
// (`CelColorKey`, lib/src/services/cel_source_effect_pass.dart): bit k of
// red[r], green[g] and blue[b] says key k is within its tolerance of the
// pixel in that channel, bit k of [restores] that key k gives back what the
// run erased of what it names instead (AE's Keep Colors, I-132-Q2), and
// alpha_maps[k * 256 + a] is what key k leaves of an alpha a. [originals]
// is the run's input, whose alphas a restore gives back to - [pixels]
// itself in a run's first call; a pixel empty there stays empty.
// So the float32 mix the shader shares (`shaders/colour_key.frag`) stays
// computed in one place, and this walks as the Dart walk does, byte for byte
// (`the_keys_walk_the_same_in_c_test`). Thirty-two keys at most a call; a
// longer chain is walked thirty-two at a time, in its order.
//
// 🔬Why it is in C: asking each key of each pixel in Dart took 1.1-3.4 ms
// over one 256 px tile of a keyed sheet and this takes 0.13 ms (10-16), and
// a live stroke on a keyed row keys every tile it changes on every flush
// (board a-stroke-on-a-keyed-row-shows-its-tiles-unkeyed).
QA_EXPORT int32_t qa_key_rgba(
    uint8_t* pixels,
    const uint8_t* originals,
    int32_t pixel_count,
    const uint32_t* red,
    const uint32_t* green,
    const uint32_t* blue,
    uint32_t restores,
    const uint8_t* alpha_maps) {
  int32_t changed = 0;
  for (int32_t i = 0; i < pixel_count; i += 1) {
    uint8_t* pixel = pixels + (ptrdiff_t)i * 4;
    // Read before the write below: [originals] may be [pixels].
    const int32_t original = originals[(ptrdiff_t)i * 4 + 3];
    if (original == 0) {
      continue;
    }
    const int32_t alpha = pixel[3];
    uint32_t naming = red[pixel[0]] & green[pixel[1]] & blue[pixel[2]];
    uint32_t restoring = restores;
    int32_t next = alpha;
    for (const uint8_t* map = alpha_maps; naming != 0;
         naming >>= 1, restoring >>= 1, map += 256) {
      if (naming & 1u) {
        next = (restoring & 1u) ? original - map[original - next] : map[next];
      }
    }
    if (next != alpha) {
      pixel[3] = (uint8_t)next;
      changed = 1;
    }
  }
  return changed;
}

// Plain memcpy exposed to Dart (R19-Z): native-to-native tile staging at
// true memcpy speed - the VM's typed-data setRange was several times
// slower in debug builds, and staging copies 256KB per touched tile.
QA_EXPORT void qa_copy_bytes(
    uint8_t* dst,
    const uint8_t* src,
    int64_t length) {
  memcpy(dst, src, (size_t)length);
}

// Plain memset exposed to Dart (ABI 40), for the same reason as
// qa_copy_bytes: the VM's typed-data fillRange runs a loop in debug builds,
// and since the stroke's 16-bit plane a new stroke tile zeroes three times
// the bytes it did (measured 2026-10-01: with the loop, a 600-dab size-30
// stroke's commit took 9.7 ms against 5.2 without the plane, nearly all of
// the difference spent zeroing and widening its four tiles).
QA_EXPORT void qa_zero_bytes(uint8_t* dst, int64_t length) {
  memset(dst, 0, (size_t)length);
}

// A stroke tile's 16-bit plane widened from its bytes (ABI 40): each value
// a byte * 257, which reads back as exactly that byte (qa_dab_store) — the
// commit scratch's `widenStrokeBytes` at native speed.
QA_EXPORT void qa_widen_bytes(
    const uint8_t* bytes,
    uint16_t* wide,
    int64_t count) {
  for (int64_t i = 0; i < count; i += 1) {
    wide[i] = (uint16_t)(bytes[i] * 257);
  }
}

// ---------------------------------------------------------------------------
// Flood fill's tolerance tests (R18 A-2b; 4-byte pixels + SSE2 R22-D) -
// the wave flood below and the close-gap fill share them.
//
// R22-D: the fill raster is 4 bytes per pixel - premultiplied RGB and
// the coverage (F-416: it was RGBX over the paper, X always 0). One pixel
// is one 32-bit word and four pixels fill an SSE2 register, so the span
// loops below test 4 px per step; scalar tails keep every DECISION
// byte-identical to the Dart reference (which stays scalar - the parity
// suite pins identical filled sets).

#if defined(QA_SSE2)
#define QA_FLOOD_SSE2 1
typedef __m128i qa_vec4;
static inline qa_vec4 qa_vec4_splat(uint32_t word) {
  return _mm_set1_epi32((int32_t)word);
}
#elif defined(QA_NEON)
// R28 NEON port: the ARM mirror of the SSE2 compare - same saturating
// abs-diff (vabd) over all four lanes, same <= tol semantics, so the
// decisions stay byte-identical (the permanent Dart oracle pins them
// on-device). aarch64 only (vaddvq); 32-bit ARM keeps the scalar path.
#define QA_FLOOD_NEON 1
typedef uint8x16_t qa_vec4;
static inline qa_vec4 qa_vec4_splat(uint32_t word) {
  return vreinterpretq_u8_u32(vdupq_n_u32(word));
}
#endif

#if defined(QA_FLOOD_SSE2) || defined(QA_FLOOD_NEON)
#define QA_FLOOD_SIMD 1
#endif

// One-pixel tolerance test against the seed (RGBA layout: the seed is
// packed as the raster holds a pixel, red in the low byte). Coverage is a
// lane like the colours - a drawn pixel and the empty canvas differ by it
// however alike their colour (F-416).
static inline int qa_tol_ok1(
    const uint8_t* px,
    uint32_t seed,
    int32_t tolerance) {
  for (int32_t lane = 0; lane < 4; lane += 1) {
    const int32_t d =
        (int32_t)px[lane] - (int32_t)((seed >> (8 * lane)) & 0xFFu);
    if (d > tolerance || -d > tolerance) {
      return 0;
    }
  }
  return 1;
}

// [tolerance] in each of a pixel's four lanes - the SIMD compare's bound.
static inline uint32_t qa_tol_lanes(int32_t tolerance) {
  return (uint32_t)tolerance * 0x01010101u;
}

#if defined(QA_FLOOD_SSE2)
// Bit i (0..3) set = pixel i of the 16-byte RGBA block is within
// tolerance of the seed on every lane. The per-byte |p-seed| <= tol via
// saturating unsigned abs-diff is exact for the integer compare above.
static inline int qa_tol_ok4(const uint8_t* rgba, qa_vec4 seed4, qa_vec4 tol4) {
  const __m128i p = _mm_loadu_si128((const __m128i*)rgba);
  const __m128i d =
      _mm_or_si128(_mm_subs_epu8(p, seed4), _mm_subs_epu8(seed4, p));
  const __m128i ok8 =
      _mm_cmpeq_epi8(_mm_subs_epu8(d, tol4), _mm_setzero_si128());
  const __m128i ok32 = _mm_cmpeq_epi32(ok8, _mm_set1_epi32(-1));
  return _mm_movemask_ps(_mm_castsi128_ps(ok32));
}
#elif defined(QA_FLOOD_NEON)
static inline int qa_tol_ok4(const uint8_t* rgba, qa_vec4 seed4, qa_vec4 tol4) {
  const uint8x16_t p = vld1q_u8(rgba);
  const uint8x16_t d = vabdq_u8(p, seed4);
  const uint8x16_t ok8 = vcleq_u8(d, tol4);
  const uint32x4_t ok32 =
      vceqq_u32(vreinterpretq_u32_u8(ok8), vdupq_n_u32(0xFFFFFFFFu));
  const uint32x4_t weights = {1u, 2u, 4u, 8u};
  return (int)vaddvq_u32(vandq_u32(ok32, weights));
}
#endif

// ---------------------------------------------------------------------------
// Fill raster compose (R18 A-2c): LazyCanvasRasterRgb's per-tile compose
// ported verbatim - the clean-run lab showed the lazy compose (clearing
// + integer source-over of layer tiles onto the raster) is most of what
// remains inside the fill.flood probe now that the flood itself is
// native.

// Clears a raster rect to nothing drawn: every lane 0 (the raster is
// premultiplied RGBA - no paper under it, F-416).
QA_EXPORT void qa_fill_clear_rect(
    uint8_t* rgb,
    int32_t raster_width,
    int32_t left,
    int32_t top,
    int32_t right_exclusive,
    int32_t bottom_exclusive) {
  for (int32_t y = top; y < bottom_exclusive; y += 1) {
    memset(
        rgb + (((ptrdiff_t)y * raster_width + left) << 2), 0,
        (size_t)(right_exclusive - left) << 2);
  }
}

// Integer source-over of one RGBA surface-tile clip onto the
// premultiplied raster (byte-rounded, exactly the Dart loop: effective =
// (a*o+127)/255 etc.); the fourth lane gathers the coverage the same way.
QA_EXPORT void qa_fill_compose_tile(
    uint8_t* rgb,
    int32_t raster_width,
    const uint8_t* tile_pixels,
    int32_t tile_size,
    int32_t base_x,
    int32_t base_y,
    int32_t clip_left,
    int32_t clip_top,
    int32_t clip_right_exclusive,
    int32_t clip_bottom_exclusive,
    int32_t opacity_int) {
  for (int32_t y = clip_top; y < clip_bottom_exclusive; y += 1) {
    const uint8_t* src =
        tile_pixels +
        ((ptrdiff_t)(y - base_y) * tile_size + (clip_left - base_x)) * 4;
    uint8_t* dst = rgb + (((ptrdiff_t)y * raster_width + clip_left) << 2);
    for (int32_t x = clip_left; x < clip_right_exclusive; x += 1) {
      const int32_t alpha = src[3];
      if (alpha != 0) {
        const int32_t effective = (alpha * opacity_int + 127) / 255;
        const int32_t inverse = 255 - effective;
        dst[0] = (uint8_t)((src[0] * effective + dst[0] * inverse + 127) / 255);
        dst[1] = (uint8_t)((src[1] * effective + dst[1] * inverse + 127) / 255);
        dst[2] = (uint8_t)((src[2] * effective + dst[2] * inverse + 127) / 255);
        dst[3] = (uint8_t)((255 * effective + dst[3] * inverse + 127) / 255);
      }
      src += 4;
      dst += 4;
    }
  }
}

// ---------------------------------------------------------------------------
// Fill mask finish (R18 A-2d / R24-A1 parallel): crop + expand +
// anti-alias, byte-identical to the Dart tail. Every pass reads one
// generation and writes another, so ROW BANDS are embarrassingly
// parallel - they fan out across the worker pool (R24-A1: at 8K these
// full-region passes were the largest remaining sequential slice of
// fill.flood). Generations ping-pong between `mask` and `scratch`; a
// final banded copy lands the result in `mask` when the pass count is
// odd.

// The pool lives further down with the tile-batch machinery.
typedef void (*qa_job_fn)(int32_t item_index, void* context);
static void qa_pool_run(qa_job_fn job_fn, void* context, int32_t item_count);

#define QA_FINISH_BAND_ROWS 64

typedef struct {
  const uint8_t* filled; // Crop source (mode 0 only).
  int32_t canvas_width;
  int32_t crop_left;
  int32_t crop_top;
  const uint8_t* src; // Read generation (modes 1-3).
  uint8_t* dst;       // Write generation.
  int32_t region_width;
  int32_t region_height;
  int32_t mode; // 0=crop, 1=expand, 2=anti-alias, 3=plain copy.
} qa_finish_band_context;

static void qa_finish_band_item(int32_t item_index, void* context) {
  const qa_finish_band_context* c = (const qa_finish_band_context*)context;
  const int32_t width = c->region_width;
  const int32_t y0 = item_index * QA_FINISH_BAND_ROWS;
  int32_t y1 = y0 + QA_FINISH_BAND_ROWS;
  if (y1 > c->region_height) {
    y1 = c->region_height;
  }
  switch (c->mode) {
    case 0:
      for (int32_t y = y0; y < y1; y += 1) {
        memcpy(
            c->dst + (ptrdiff_t)y * width,
            c->filled + (ptrdiff_t)(c->crop_top + y) * c->canvas_width +
                c->crop_left,
            (size_t)width);
      }
      return;
    case 3:
      memcpy(
          c->dst + (ptrdiff_t)y0 * width,
          c->src + (ptrdiff_t)y0 * width,
          (size_t)(y1 - y0) * (size_t)width);
      return;
    case 1:
      // Expand: dst = src, then zero pixels touching a nonzero
      // 4-neighbor become 255 - identical to the Dart grown-copy.
      for (int32_t y = y0; y < y1; y += 1) {
        const uint8_t* src_row = c->src + (ptrdiff_t)y * width;
        uint8_t* dst_row = c->dst + (ptrdiff_t)y * width;
        memcpy(dst_row, src_row, (size_t)width);
        for (int32_t x = 0; x < width; x += 1) {
          if (src_row[x] != 0) {
            continue;
          }
          const int touches =
              (x > 0 && src_row[x - 1] != 0) ||
              (x < width - 1 && src_row[x + 1] != 0) ||
              (y > 0 && c->src[(ptrdiff_t)(y - 1) * width + x] != 0) ||
              (y < c->region_height - 1 &&
               c->src[(ptrdiff_t)(y + 1) * width + x] != 0);
          if (touches) {
            dst_row[x] = 255;
          }
        }
      }
      return;
    default:
      // Anti-alias: boundary pixels average their 4-neighbors; the
      // Dart formula rounds a double division, so this stays double +
      // the contract's rounding (qa_round_byte) for byte identity.
      for (int32_t y = y0; y < y1; y += 1) {
        const uint8_t* src_row = c->src + (ptrdiff_t)y * width;
        uint8_t* dst_row = c->dst + (ptrdiff_t)y * width;
        memcpy(dst_row, src_row, (size_t)width);
        for (int32_t x = 0; x < width; x += 1) {
          const int32_t center = src_row[x];
          const int32_t left_v = x > 0 ? src_row[x - 1] : 0;
          const int32_t right_v = x < width - 1 ? src_row[x + 1] : 0;
          const int32_t up_v =
              y > 0 ? c->src[(ptrdiff_t)(y - 1) * width + x] : 0;
          const int32_t down_v = y < c->region_height - 1
              ? c->src[(ptrdiff_t)(y + 1) * width + x]
              : 0;
          const int32_t sum = center + left_v + right_v + up_v + down_v;
          if (sum != center * 5) {
            dst_row[x] = (uint8_t)qa_round_byte(
                (double)(center * 3 + (sum - center)) / 7.0);
          }
        }
      }
      return;
  }
}

QA_EXPORT void qa_fill_finish_mask(
    const uint8_t* filled,
    int32_t canvas_width,
    int32_t crop_left,
    int32_t crop_top,
    int32_t region_width,
    int32_t region_height,
    int32_t expand_px,
    int32_t anti_alias,
    uint8_t* mask,
    uint8_t* scratch) {
  const int32_t bands =
      (region_height + QA_FINISH_BAND_ROWS - 1) / QA_FINISH_BAND_ROWS;
  qa_finish_band_context context;
  context.filled = filled;
  context.canvas_width = canvas_width;
  context.crop_left = crop_left;
  context.crop_top = crop_top;
  context.region_width = region_width;
  context.region_height = region_height;

  context.mode = 0;
  context.src = NULL;
  context.dst = mask;
  qa_pool_run(qa_finish_band_item, &context, bands);

  // Ping-pong generations through the passes; land back in `mask`.
  uint8_t* current = mask;
  uint8_t* other = scratch;
  for (int32_t pass = 0; pass < expand_px; pass += 1) {
    context.mode = 1;
    context.src = current;
    context.dst = other;
    qa_pool_run(qa_finish_band_item, &context, bands);
    uint8_t* swap = current;
    current = other;
    other = swap;
  }
  if (anti_alias) {
    context.mode = 2;
    context.src = current;
    context.dst = other;
    qa_pool_run(qa_finish_band_item, &context, bands);
    uint8_t* swap = current;
    current = other;
    other = swap;
  }
  if (current != mask) {
    context.mode = 3;
    context.src = current;
    context.dst = mask;
    qa_pool_run(qa_finish_band_item, &context, bands);
  }
}

// ---------------------------------------------------------------------------
// Batched fill compose (R25-3): the lazy raster used to compose each
// 256px tile through per-tile serial FFI calls (a clear + one call per
// intersecting layer tile). One batch call now fans compose TILES across
// the worker pool; within one tile the clear and the layer blends run
// sequentially in order (source-over order IS the bytes),
// and tiles are disjoint - so the result is byte-identical to the
// serial path while the wall time divides by cores.

// One layer-tile blend of a batch. Field order/types MUST match the
// Dart QaComposeBlendStruct exactly; the loader cross-checks sizeof.
typedef struct {
  uint8_t* tile_pixels;
  int32_t tile_size;
  int32_t base_x;
  int32_t base_y;
  int32_t clip_left;
  int32_t clip_top;
  int32_t clip_right_exclusive;
  int32_t clip_bottom_exclusive;
  int32_t opacity_int;
  int32_t reserved;
} qa_compose_blend;

QA_EXPORT int32_t qa_compose_blend_sizeof(void) {
  return (int32_t)sizeof(qa_compose_blend);
}

// One compose TILE of a batch: clear its rect, then run its slice
// of the shared blend array in order. Mirrors QaComposeTileItemStruct.
typedef struct {
  int32_t tile_left;
  int32_t tile_top;
  int32_t tile_right_exclusive;
  int32_t tile_bottom_exclusive;
  int32_t first_blend;
  int32_t blend_count;
} qa_compose_tile_item;

QA_EXPORT int32_t qa_compose_tile_item_sizeof(void) {
  return (int32_t)sizeof(qa_compose_tile_item);
}

// One call's job, on its caller's stack. ↩️It was a static, and two
// callers at once — two isolates, each on a thread of its own — would
// each have run the other's tiles (card clip-import-hangs-on-three-samples,
// 2026-10-23).
typedef struct {
  uint8_t* rgb;
  int32_t raster_width;
  const qa_compose_tile_item* items;
  const qa_compose_blend* blends;
} qa_compose_job;

static void qa_compose_batch_item(int32_t item_index, void* context) {
  const qa_compose_job* job = (const qa_compose_job*)context;
  const qa_compose_tile_item* item = &job->items[item_index];
  qa_fill_clear_rect(
      job->rgb, job->raster_width, item->tile_left, item->tile_top,
      item->tile_right_exclusive, item->tile_bottom_exclusive);
  for (int32_t i = 0; i < item->blend_count; i += 1) {
    const qa_compose_blend* blend = &job->blends[item->first_blend + i];
    qa_fill_compose_tile(
        job->rgb, job->raster_width, blend->tile_pixels, blend->tile_size,
        blend->base_x, blend->base_y, blend->clip_left, blend->clip_top,
        blend->clip_right_exclusive, blend->clip_bottom_exclusive,
        blend->opacity_int);
  }
}

QA_EXPORT void qa_fill_compose_batch(
    uint8_t* rgb,
    int32_t raster_width,
    const qa_compose_tile_item* items,
    int32_t item_count,
    const qa_compose_blend* blends) {
  qa_compose_job job = {rgb, raster_width, items, blends};
  qa_pool_run(qa_compose_batch_item, &job, item_count);
}

// ---------------------------------------------------------------------------
// Close-gap fill (R20-C1) - mirrors the Dart reference pipeline in
// canvas_flood_fill.dart EXACTLY (integer chamfer math; parity-pinned):
// tolerance mask, 3-4 chamfer distance transform, erode by 3*gap, flood,
// grow back by 3*gap clipped to fillable.

static void qa_chamfer_distance(
    uint16_t* dist,
    const uint8_t* from,
    uint8_t zero_when,
    int32_t width,
    int32_t height) {
  const int32_t infinity = 60000;
  const int64_t count = (int64_t)width * height;
  for (int64_t i = 0; i < count; i += 1) {
    dist[i] = from[i] == zero_when ? 0 : (uint16_t)infinity;
  }
  for (int32_t y = 0; y < height; y += 1) {
    const int64_t row = (int64_t)y * width;
    for (int32_t x = 0; x < width; x += 1) {
      const int64_t index = row + x;
      int32_t best = dist[index];
      if (best == 0) {
        continue;
      }
      if (x > 0 && dist[index - 1] + 3 < best) best = dist[index - 1] + 3;
      if (y > 0) {
        const int64_t up = index - width;
        if (dist[up] + 3 < best) best = dist[up] + 3;
        if (x > 0 && dist[up - 1] + 4 < best) best = dist[up - 1] + 4;
        if (x < width - 1 && dist[up + 1] + 4 < best) best = dist[up + 1] + 4;
      }
      dist[index] = (uint16_t)(best > infinity ? infinity : best);
    }
  }
  for (int32_t y = height - 1; y >= 0; y -= 1) {
    const int64_t row = (int64_t)y * width;
    for (int32_t x = width - 1; x >= 0; x -= 1) {
      const int64_t index = row + x;
      int32_t best = dist[index];
      if (best == 0) {
        continue;
      }
      if (x < width - 1 && dist[index + 1] + 3 < best) {
        best = dist[index + 1] + 3;
      }
      if (y < height - 1) {
        const int64_t down = index + width;
        if (dist[down] + 3 < best) best = dist[down] + 3;
        if (x < width - 1 && dist[down + 1] + 4 < best) {
          best = dist[down + 1] + 4;
        }
        if (x > 0 && dist[down - 1] + 4 < best) best = dist[down - 1] + 4;
      }
      dist[index] = (uint16_t)(best > infinity ? infinity : best);
    }
  }
}

// Returns the EFFECTIVE gap used (>= 0; seed-survival may have halved
// it), -1 on stack overflow (caller falls back to the Dart reference),
// -2 when nothing fills. bounds_out = {minX, maxX, minY, maxY}.
QA_EXPORT int32_t qa_fill_gap_close_run(
    const uint8_t* rgb,
    int32_t width,
    int32_t height,
    int32_t seed_x,
    int32_t seed_y,
    uint32_t seed,
    int32_t tolerance,
    int32_t gap_px,
    uint8_t* fillable,
    uint16_t* dist,
    uint8_t* filled,
    int32_t* stack,
    int32_t stack_capacity,
    int32_t* bounds_out) {
  const int64_t count = (int64_t)width * height;
  int64_t i = 0;
#ifdef QA_FLOOD_SIMD
  // Full-canvas tolerance mask, 4 px per step (RGBA) - at 8K this pass
  // alone walks 132MB.
  const qa_vec4 seed4 = qa_vec4_splat(seed);
  const qa_vec4 tol4 = qa_vec4_splat(qa_tol_lanes(tolerance));
  for (; i + 4 <= count; i += 4) {
    const int32_t ok = qa_tol_ok4(rgb + (i << 2), seed4, tol4);
    fillable[i] = (uint8_t)(ok & 1);
    fillable[i + 1] = (uint8_t)((ok >> 1) & 1);
    fillable[i + 2] = (uint8_t)((ok >> 2) & 1);
    fillable[i + 3] = (uint8_t)((ok >> 3) & 1);
  }
#endif
  for (; i < count; i += 1) {
    fillable[i] = qa_tol_ok1(
                      rgb + (i << 2), seed, tolerance)
                      ? 1
                      : 0;
  }
  qa_chamfer_distance(dist, fillable, 0, width, height);

  int32_t gap = gap_px;
  const int64_t seed_index = (int64_t)seed_y * width + seed_x;
  while (gap > 0 && dist[seed_index] <= 3 * gap) {
    gap /= 2;
  }
  const int32_t threshold = 3 * gap;

  memset(filled, 0, (size_t)count);
  if (dist[seed_index] <= threshold) {
    return -2;
  }
  int32_t stack_size = 0;
  filled[seed_index] = 255;
  stack[stack_size++] = (int32_t)seed_index;
  while (stack_size > 0) {
    const int32_t index = stack[--stack_size];
    const int32_t y = index / width;
    const int32_t row = y * width;
    int32_t left = index - row;
    while (left > 0 && filled[row + left - 1] == 0 &&
           dist[row + left - 1] > threshold) {
      left -= 1;
      filled[row + left] = 255;
    }
    int32_t right = index - row;
    while (right < width - 1 && filled[row + right + 1] == 0 &&
           dist[row + right + 1] > threshold) {
      right += 1;
      filled[row + right] = 255;
    }
    for (int32_t dy = -1; dy <= 1; dy += 2) {
      const int32_t neighbor_y = y + dy;
      if (neighbor_y < 0 || neighbor_y >= height) {
        continue;
      }
      const int32_t neighbor_row = neighbor_y * width;
      int32_t run_open = 0;
      for (int32_t x = left; x <= right; x += 1) {
        const int32_t neighbor = neighbor_row + x;
        if (filled[neighbor] == 0 && dist[neighbor] > threshold) {
          if (!run_open) {
            if (stack_size >= stack_capacity) {
              return -1;
            }
            filled[neighbor] = 255;
            stack[stack_size++] = neighbor;
            run_open = 1;
          }
        } else {
          run_open = 0;
        }
      }
    }
  }

  // Grow back to the real barriers (dist reused for the second
  // transform, sourced from the flooded set this time).
  qa_chamfer_distance(dist, filled, 255, width, height);
  int32_t min_x = width, max_x = -1, min_y = height, max_y = -1;
  for (int32_t y = 0; y < height; y += 1) {
    const int32_t row = y * width;
    for (int32_t x = 0; x < width; x += 1) {
      const int32_t i = row + x;
      if (fillable[i] != 0 && dist[i] <= threshold) {
        filled[i] = 255;
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
      } else {
        filled[i] = 0;
      }
    }
  }
  if (max_x < 0) {
    return -2;
  }
  bounds_out[0] = min_x;
  bounds_out[1] = max_x;
  bounds_out[2] = min_y;
  bounds_out[3] = max_y;
  return gap;
}

// ---------------------------------------------------------------------------
// Stamp blend, whole tile span (R18 F-1): the Dart driver used to make
// one FFI call PER ROW - a full-canvas fill stamp was ~10k calls whose
// call overhead dwarfed the blend (commit.edit 55-95ms warm). One call
// per (dab, tile) loops the rows here, through the SAME row kernel, so
// the math (and its parity pins) are untouched.
QA_EXPORT int32_t qa_stamp_blend_tile(
    uint8_t* tile_pixels,
    int32_t tile_size,
    int32_t tile_left,
    int32_t tile_top,
    const uint8_t* stamp,
    int32_t stamp_width,
    int32_t stamp_left,
    int32_t stamp_top,
    int32_t span_left,
    int32_t span_right_exclusive,
    int32_t span_top,
    int32_t span_bottom_exclusive,
    double opacity,
    int32_t erase) {
  int32_t changed = 0;
  const int32_t count = span_right_exclusive - span_left;
  for (int32_t y = span_top; y < span_bottom_exclusive; y += 1) {
    uint8_t* tile_row =
        tile_pixels +
        ((ptrdiff_t)(y - tile_top) * tile_size + (span_left - tile_left)) * 4;
    const uint8_t* stamp_row =
        stamp +
        ((ptrdiff_t)(y - stamp_top) * stamp_width + (span_left - stamp_left)) *
            4;
    if (qa_stamp_blend_row(tile_row, stamp_row, count, opacity, erase)) {
      changed = 1;
    }
  }
  return changed;
}

// ---------------------------------------------------------------------------
// Worker pool (R18 A-3a): tile batches fan out across a small persistent
// thread pool. Tiles are DISJOINT memory, each tile's pixel loop runs
// sequentially inside exactly one thread with the exact single-thread
// kernels, so results are byte-identical regardless of worker count -
// the parity suites keep pinning the whole path.
//
// Windows uses event-pair workers; every other platform runs the
// pthread mirror below (R22-E2) - same dynamic atomic distribution,
// same byte-identical contract. QA_ENGINE_THREADS caps the TOTAL
// thread count including the caller (0 or 1 disables the pool).
//
// 🚨ONE CALLER OWNS THE POOL AT A TIME; ANY OTHER RUNS ITS OWN ITEMS ON
// ITS OWN THREAD (qa_pool_run). The pool is one for the process and so
// are its job slot and its wake-ups, while every isolate that loads the
// engine calls it from a thread of its own. Two at once overwrote each
// other's job, and with auto-reset wake-ups a worker woken once for two
// jobs left one caller waiting on a signal nobody would send: a .clip
// whose vector layers were drawn on several workers never finished
// opening (card clip-import-hangs-on-three-samples, 2026-10-23 — three
// samples, every time, and none with QA_ENGINE_THREADS=1).
// ⛔Not a wait for the pool: a caller held behind another's job — the UI
// thread behind an import's — is the stall the pool is here to shorten,
// and the items come out byte-identical on any number of threads.

// One tile's span of a batch job. Field order/types MUST match the Dart
// QaTileSpanStruct exactly; the loader cross-checks qa_tile_span_sizeof.
//
// ABI 24 appended the four pre-blend fields. The older kernels
// (dab/stamp/stroke/alpha-bounds) never read them, so they keep working
// on spans staged without them - but both sides must still agree on the
// struct size, which the sizeof cross-check enforces.
typedef struct {
  uint8_t* tile_pixels;
  int32_t tile_left;
  int32_t tile_top;
  int32_t span_left;
  int32_t span_right_exclusive;
  int32_t span_top;
  int32_t span_bottom_exclusive;
  int32_t reserved;
  // --- ABI 24: the fused pre-blend's per-tile inputs/outputs.
  // Tile-local buffers, all on the SAME tile_size grid as tile_pixels.
  const uint8_t* base_pixels;    // committed bytes to stage; NULL = empty
  const uint8_t* stroke_pixels;  // the live stroke's straight RGBA
  const uint8_t* mask_pixels;    // selection coverage, 1 byte/px; NULL = all
  uint8_t* premul_out;           // premultiplied upload; NULL = skip
  // --- ABI 40: the stroke tile's 16-bit plane, RGBA on the same grid as
  // tile_pixels — what the dab kernel piles up in (qa_dab_store). Only the
  // dab batch reads it; every other kernel's spans leave it NULL.
  uint16_t* tile_wide;
  // --- ABI 60: the stroke tile's SECOND plane, alpha * 65535 a pixel, where
  // a second tip's dabs pile (qa_dual_view_rows). NULL for a stroke with
  // one tip, and on every other kernel's spans.
  uint16_t* tile_second;
} qa_tile_span;

QA_EXPORT int32_t qa_tile_span_sizeof(void) {
  return (int32_t)sizeof(qa_tile_span);
}

// qa_job_fn is declared with the fill-finish machinery above.

// R22-E1: cap raised 8 -> 32 for future many-core CPUs. Default stays
// "logical cores - 1, clamped"; past ~8 workers the tile kernels go
// memory-bandwidth-bound and scale sublinearly - expected, recorded in
// the lab notes, not a regression.
#define QA_MAX_WORKERS 32

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <process.h>
#include <stdlib.h>

// A flag one thread holds at a time: qa_claim answers whether this one now
// does — until it calls qa_release.
typedef volatile LONG qa_claim_flag;

static int qa_claim(qa_claim_flag* flag) {
  return InterlockedCompareExchange(flag, 1, 0) == 0;
}

static void qa_release(qa_claim_flag* flag) {
  InterlockedExchange(flag, 0);
}

static struct {
  int initialized;
  int worker_count;
  HANDLE threads[QA_MAX_WORKERS];
  HANDLE work_ready[QA_MAX_WORKERS];
  HANDLE work_done[QA_MAX_WORKERS];
  qa_job_fn job_fn;
  void* job_context;
  volatile LONG next_item;
  int32_t item_count;
  qa_claim_flag owned;
} g_pool;

static void qa_pool_run_items(void) {
  for (;;) {
    const LONG item = InterlockedIncrement(&g_pool.next_item) - 1;
    if (item >= g_pool.item_count) {
      return;
    }
    g_pool.job_fn((int32_t)item, g_pool.job_context);
  }
}

static unsigned __stdcall qa_pool_worker(void* arg) {
  const int index = (int)(intptr_t)arg;
  for (;;) {
    WaitForSingleObject(g_pool.work_ready[index], INFINITE);
    qa_pool_run_items();
    SetEvent(g_pool.work_done[index]);
  }
}

static void qa_pool_init_once(void) {
  if (g_pool.initialized) {
    return;
  }
  g_pool.initialized = 1;
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  int workers = (int)info.dwNumberOfProcessors - 1;
  const char* override_text = getenv("QA_ENGINE_THREADS");
  if (override_text != NULL) {
    const int override_value = atoi(override_text);
    // The override is TOTAL threads including the caller.
    workers = override_value - 1;
  }
  if (workers > QA_MAX_WORKERS) workers = QA_MAX_WORKERS;
  if (workers < 0) workers = 0;
  g_pool.worker_count = 0;
  for (int i = 0; i < workers; i += 1) {
    g_pool.work_ready[i] = CreateEventW(NULL, FALSE, FALSE, NULL);
    g_pool.work_done[i] = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (g_pool.work_ready[i] == NULL || g_pool.work_done[i] == NULL) {
      break;
    }
    const uintptr_t handle = _beginthreadex(
        NULL, 0, qa_pool_worker, (void*)(intptr_t)i, 0, NULL);
    if (handle == 0) {
      break;
    }
    g_pool.threads[i] = (HANDLE)handle;
    g_pool.worker_count += 1;
  }
}

// Runs job_fn(0..item_count-1, context) across the workers + the caller,
// which owns the pool; returns only when every item completed.
static void qa_pool_spread(
    qa_job_fn job_fn,
    void* context,
    int32_t item_count) {
  g_pool.job_fn = job_fn;
  g_pool.job_context = context;
  g_pool.item_count = item_count;
  g_pool.next_item = 0;
  int engaged = g_pool.worker_count;
  if (engaged > item_count - 1) {
    engaged = (int)item_count - 1;
  }
  for (int i = 0; i < engaged; i += 1) {
    SetEvent(g_pool.work_ready[i]);
  }
  qa_pool_run_items();
  for (int i = 0; i < engaged; i += 1) {
    WaitForSingleObject(g_pool.work_done[i], INFINITE);
  }
}

#else  // !_WIN32: pthread mirror of the Windows pool (R22-E2).
// Structure-identical: persistent workers, dynamic atomic item counter
// (P/E-hybrid friendly), caller participates, byte-identical results by
// construction. Auto-reset event pairs become a token count + two
// condition variables (macOS has no unnamed semaphores, so mutex+cond
// is the portable pair). This lock is DISTINCT from the tile-pool lock
// (qa_tile_free on the GC thread) - no ordering between them.

#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

// A flag one thread holds at a time: qa_claim answers whether this one now
// does — until it calls qa_release.
typedef int32_t qa_claim_flag;

static int qa_claim(qa_claim_flag* flag) {
  qa_claim_flag unclaimed = 0;
  return __atomic_compare_exchange_n(
      flag, &unclaimed, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

static void qa_release(qa_claim_flag* flag) {
  __atomic_store_n(flag, 0, __ATOMIC_RELEASE);
}

static struct {
  int initialized;
  int worker_count;
  pthread_t threads[QA_MAX_WORKERS];
  pthread_mutex_t lock;
  pthread_cond_t ready_cond;
  pthread_cond_t done_cond;
  int ready_tokens;
  int done_count;
  qa_job_fn job_fn;
  void* job_context;
  volatile int32_t next_item;
  int32_t item_count;
  qa_claim_flag owned;
} g_pool;

static void qa_pool_run_items(void) {
  for (;;) {
    const int32_t item =
        __atomic_fetch_add(&g_pool.next_item, 1, __ATOMIC_RELAXED);
    if (item >= g_pool.item_count) {
      return;
    }
    g_pool.job_fn(item, g_pool.job_context);
  }
}

static void* qa_pool_worker(void* arg) {
  (void)arg;
  for (;;) {
    pthread_mutex_lock(&g_pool.lock);
    while (g_pool.ready_tokens == 0) {
      pthread_cond_wait(&g_pool.ready_cond, &g_pool.lock);
    }
    g_pool.ready_tokens -= 1;
    pthread_mutex_unlock(&g_pool.lock);
    qa_pool_run_items();
    pthread_mutex_lock(&g_pool.lock);
    g_pool.done_count += 1;
    pthread_cond_signal(&g_pool.done_cond);
    pthread_mutex_unlock(&g_pool.lock);
  }
  return NULL;
}

static void qa_pool_init_once(void) {
  if (g_pool.initialized) {
    return;
  }
  g_pool.initialized = 1;
  pthread_mutex_init(&g_pool.lock, NULL);
  pthread_cond_init(&g_pool.ready_cond, NULL);
  pthread_cond_init(&g_pool.done_cond, NULL);
  int workers = (int)sysconf(_SC_NPROCESSORS_ONLN) - 1;
  const char* override_text = getenv("QA_ENGINE_THREADS");
  if (override_text != NULL) {
    const int override_value = atoi(override_text);
    // The override is TOTAL threads including the caller.
    workers = override_value - 1;
  }
  if (workers > QA_MAX_WORKERS) workers = QA_MAX_WORKERS;
  if (workers < 0) workers = 0;
  g_pool.worker_count = 0;
  for (int i = 0; i < workers; i += 1) {
    if (pthread_create(&g_pool.threads[i], NULL, qa_pool_worker, NULL) != 0) {
      break;
    }
    g_pool.worker_count += 1;
  }
}

// Runs job_fn(0..item_count-1, context) across the workers + the caller,
// which owns the pool; returns only when every item completed.
static void qa_pool_spread(
    qa_job_fn job_fn,
    void* context,
    int32_t item_count) {
  g_pool.job_fn = job_fn;
  g_pool.job_context = context;
  g_pool.item_count = item_count;
  g_pool.next_item = 0;
  int engaged = g_pool.worker_count;
  if (engaged > item_count - 1) {
    engaged = (int)item_count - 1;
  }
  pthread_mutex_lock(&g_pool.lock);
  g_pool.done_count = 0;
  g_pool.ready_tokens = engaged;
  pthread_cond_broadcast(&g_pool.ready_cond);
  pthread_mutex_unlock(&g_pool.lock);
  qa_pool_run_items();
  pthread_mutex_lock(&g_pool.lock);
  while (g_pool.done_count < engaged) {
    pthread_cond_wait(&g_pool.done_cond, &g_pool.lock);
  }
  pthread_mutex_unlock(&g_pool.lock);
}

#endif

// Runs job_fn(0..item_count-1, context) on the calling thread alone.
static void qa_run_here(qa_job_fn job_fn, void* context, int32_t item_count) {
  for (int32_t i = 0; i < item_count; i += 1) {
    job_fn(i, context);
  }
}

// Runs job_fn(0..item_count-1, context) across the pool + the caller — or
// on the caller's thread alone while another caller owns the pool (the
// head of the pool says why); returns only when every item completed.
static void qa_pool_run(qa_job_fn job_fn, void* context, int32_t item_count) {
  if (item_count <= 0) {
    return;
  }
  if (item_count == 1 || !qa_claim(&g_pool.owned)) {
    qa_run_here(job_fn, context, item_count);
    return;
  }
  // Started by its first owner, so never by two threads at once.
  qa_pool_init_once();
  if (g_pool.worker_count == 0) {
    qa_run_here(job_fn, context, item_count);
  } else {
    qa_pool_spread(job_fn, context, item_count);
  }
  qa_release(&g_pool.owned);
}

// --- Batched generic dab blend -------------------------------------------
//
// 🚨A CALL'S DABS GO IN ONE CALL, AND THEIR ROWS SHARE THE POOL (ABI 38,
// 2026-09-24, board `preset-spacing-minimum`). The presets moved to the 1%
// spacing (유저 09-24: 「프리셋 브러시들 간격이 너무 멀어서 … 최소치로
// 두자」), so a stroke lays a dab about every pixel, and one call per dab
// paid the pool twice over. Measured on a 20-thread desktop, one stroke of
// 100 px dabs took 510 ms with the pool and 503 ms without it: a dab under
// ~250 px covers one to four tiles, so one item per tile woke almost no one.
// Cutting that one dab into row bands still bought only 11%, because a
// sleeping worker takes ~0.2 ms to wake and the dab (~0.28 ms alone) was
// nearly done before one arrived — 200 px dabs, long enough to outlast the
// wake, went 4.4x.
//
// So the caller hands over every dab it has (a frame of the live stroke, a
// run of the commit), the kernel cuts the tiles they cover into bands of
// whole rows, and each band applies every dab that reaches it, in order.
// The wake is paid once a call, and the rows a band holds stay in cache
// from the first dab to the last.
//
// ⛔BYTE-IDENTICAL BY CONSTRUCTION: every pixel sees the same dabs in the
// same order through the same float expression — a pixel lives in exactly
// one band, a band applies the dabs in their order, and
// `qa_dab_blend_tile` carries nothing from one row to the next (each row
// derives `dy`, `v_index` and its offset from `y` alone). Which thread,
// which band and what else rode in the call change nothing.

// Pixel visits a band is cut to: ~50 µs of a round dab at ~25 ns a visit,
// work worth waking a thread for.
#define QA_DAB_BAND_WORK 2048
// Bands one call may be cut into. A call with more work than this covers
// enough tiles to fill the pool one tile an item.
#define QA_DAB_MAX_BANDS 256

typedef struct {
  int32_t tile;
  int32_t top;
  int32_t bottom_exclusive;
} qa_dab_band;

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  const qa_dab_spec* specs;
  const int32_t* clips;
  int32_t dab_count;
  uint8_t* changed_out;
  const qa_dab_band* bands;
  uint8_t* band_changed;
  // The view of a stroke with a second tip (qa_dual_view_rows): its mode
  // and density, read where a span carries the second plane.
  int32_t dual_mode;
  double dual_density;
} qa_dab_batch_context;

// Where dab `d`'s clip meets rows [top, bottom) of `span`: the rect it
// blends there, or a zero area.
static int64_t qa_dab_meet(
    const qa_dab_batch_context* batch,
    int32_t d,
    const qa_tile_span* span,
    int32_t top,
    int32_t bottom_exclusive,
    int32_t* out) {
  const int32_t* clip = batch->clips + (ptrdiff_t)d * 4;
  out[0] = clip[0] > span->span_left ? clip[0] : span->span_left;
  out[1] = clip[1] > top ? clip[1] : top;
  out[2] = clip[2] < span->span_right_exclusive ? clip[2]
                                                  : span->span_right_exclusive;
  out[3] = clip[3] < bottom_exclusive ? clip[3] : bottom_exclusive;
  if (out[0] >= out[2] || out[1] >= out[3]) {
    return 0;
  }
  return (int64_t)(out[2] - out[0]) * (out[3] - out[1]);
}

// Every dab of the call, in order, over rows [top, bottom) of one tile —
// each where its own clip meets the tile, exactly the span it had when it
// was a call of its own — and, where the tile carries a second plane, the
// view over those rows of the span once they have all landed.
static int32_t qa_dab_blend_rows(
    const qa_dab_batch_context* batch,
    const qa_tile_span* span,
    int32_t top,
    int32_t bottom_exclusive) {
  int32_t changed = 0;
  int32_t meet[4];
  for (int32_t d = 0; d < batch->dab_count; d += 1) {
    if (qa_dab_meet(batch, d, span, top, bottom_exclusive, meet) == 0) {
      continue;
    }
    if (qa_dab_blend_tile(span->tile_pixels, span->tile_wide,
                          span->tile_second, batch->tile_size,
                          span->tile_left, span->tile_top, meet[0], meet[2],
                          meet[1], meet[3], &batch->specs[d])) {
      changed = 1;
    }
  }
  if (span->tile_second != NULL) {
    const int32_t from = top > span->span_top ? top : span->span_top;
    const int32_t to = bottom_exclusive < span->span_bottom_exclusive
                           ? bottom_exclusive
                           : span->span_bottom_exclusive;
    if (qa_dual_view_rows(span->tile_pixels, span->tile_wide,
                          span->tile_second, batch->tile_size,
                          span->tile_left, span->tile_top, span->span_left,
                          span->span_right_exclusive, from, to,
                          batch->dual_mode, batch->dual_density)) {
      changed = 1;
    }
  }
  return changed;
}

// The pixel visits the call makes in one tile.
static int64_t qa_dab_tile_work(
    const qa_dab_batch_context* batch,
    const qa_tile_span* span) {
  int64_t work = 0;
  int32_t meet[4];
  for (int32_t d = 0; d < batch->dab_count; d += 1) {
    work += qa_dab_meet(batch, d, span, span->span_top,
                        span->span_bottom_exclusive, meet);
  }
  return work;
}

static void qa_dab_batch_item(int32_t item_index, void* context) {
  const qa_dab_batch_context* batch = (const qa_dab_batch_context*)context;
  const qa_tile_span* span = &batch->tiles[item_index];
  batch->changed_out[item_index] = (uint8_t)qa_dab_blend_rows(
      batch, span, span->span_top, span->span_bottom_exclusive);
}

static void qa_dab_band_item(int32_t item_index, void* context) {
  const qa_dab_batch_context* batch = (const qa_dab_batch_context*)context;
  const qa_dab_band* band = &batch->bands[item_index];
  batch->band_changed[item_index] = (uint8_t)qa_dab_blend_rows(
      batch, &batch->tiles[band->tile], band->top, band->bottom_exclusive);
}

// Cuts every tile's span into its share of `band_count` bands by work (at
// least one each), and returns how many it wrote — at most
// `band_count + tile_count`.
static int32_t qa_cut_dab_bands(
    const qa_dab_batch_context* batch,
    int32_t tile_count,
    int64_t work,
    int32_t band_count,
    qa_dab_band* bands) {
  int32_t written = 0;
  for (int32_t t = 0; t < tile_count; t += 1) {
    const qa_tile_span* span = &batch->tiles[t];
    const int32_t height = span->span_bottom_exclusive - span->span_top;
    if (height <= 0) {
      // Nothing to blend, but the tile still reports unchanged.
      bands[written].tile = t;
      bands[written].top = span->span_top;
      bands[written].bottom_exclusive = span->span_top;
      written += 1;
      continue;
    }
    int64_t share =
        (int64_t)band_count * qa_dab_tile_work(batch, span) / work;
    if (share < 1) share = 1;
    if (share > height) share = height;
    const int32_t rows = (int32_t)((height + share - 1) / share);
    for (int32_t top = span->span_top; top < span->span_bottom_exclusive;
         top += rows) {
      bands[written].tile = t;
      bands[written].top = top;
      bands[written].bottom_exclusive =
          top + rows < span->span_bottom_exclusive
              ? top + rows
              : span->span_bottom_exclusive;
      written += 1;
    }
  }
  return written;
}

// Blends `dab_count` dabs, in order, into the tiles they cover in ONE call,
// fanned across the pool. `tiles` holds each covered tile once, its span
// the rect every dab's clip makes there together; `clips` holds four ints a
// dab — left, top, right and bottom, exclusive — its region after the
// pasteboard clip. [dual_mode] and [dual_density] are the view of a stroke
// with a second tip, read only where a span carries its second plane.
QA_EXPORT void qa_dab_blend_batch(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    const qa_dab_spec* specs,
    const int32_t* clips,
    int32_t dab_count,
    int32_t dual_mode,
    double dual_density,
    uint8_t* changed_out) {
  qa_dab_band bands[QA_DAB_MAX_BANDS * 2];
  uint8_t band_changed[QA_DAB_MAX_BANDS * 2];
  qa_dab_batch_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.specs = specs;
  context.clips = clips;
  context.dab_count = dab_count;
  context.changed_out = changed_out;
  context.bands = bands;
  context.band_changed = band_changed;
  context.dual_mode = dual_mode;
  context.dual_density = dual_density;

  int64_t work = 0;
  for (int32_t t = 0; t < tile_count; t += 1) {
    work += qa_dab_tile_work(&context, &tiles[t]);
  }
  int64_t wanted = work / QA_DAB_BAND_WORK;
  if (wanted > QA_DAB_MAX_BANDS) wanted = QA_DAB_MAX_BANDS;
  if (wanted <= 1) {
    // Less than two bands of work: all of it here, nobody woken.
    for (int32_t t = 0; t < tile_count; t += 1) {
      qa_dab_batch_item(t, &context);
    }
    return;
  }
  if (wanted <= tile_count) {
    qa_pool_run(qa_dab_batch_item, &context, tile_count);
    return;
  }
  const int32_t band_count =
      qa_cut_dab_bands(&context, tile_count, work, (int32_t)wanted, bands);
  qa_pool_run(qa_dab_band_item, &context, band_count);
  memset(changed_out, 0, (size_t)tile_count);
  for (int32_t b = 0; b < band_count; b += 1) {
    changed_out[bands[b].tile] |= band_changed[b];
  }
}

// --- Blur brush (I-75, v58) ------------------------------------------------
//
// The C transcription of BrushBlurPicture (lib/src/services/
// brush_blur_picture.dart), which holds the law and its reasons; this
// matches it byte for byte (a_blur_brush_rubs_the_picture_it_finds_test,
// on both engines). A dab reads the picture where the stroke has rewritten
// it (`own`, premultiplied 16-bit) and the cel where it has not (`cel`,
// straight 8-bit); blurs it, three box passes along the rows and then three
// along the columns; and moves its pixels toward the blur by what it would
// have laid as paint, measured by the dab kernel itself (white onto
// nothing).

// One tile of the picture a blur reads: the stroke's rewritten tile, or
// the cel's where there is none yet (NULL both: nothing there).
typedef struct {
  uint16_t* own;
  const uint8_t* cel;
} qa_blur_tile;

QA_EXPORT int32_t qa_blur_tile_sizeof(void) {
  return (int32_t)sizeof(qa_blur_tile);
}

// The scratch tile the laid share is measured on (the Dart side's
// `_scratchTileSize`): its bytes, then its 16-bit plane.
#define QA_BLUR_SCRATCH 64
#define QA_BLUR_SCRATCH_PIXEL_BYTES (QA_BLUR_SCRATCH * QA_BLUR_SCRATCH * 4)
#define QA_BLUR_SCRATCH_BYTES (QA_BLUR_SCRATCH_PIXEL_BYTES * 3)

// Past this many window pixels a dab's passes are cut into bands for the
// pool; below it the wake costs more than the work.
#define QA_BLUR_POOL_PIXELS 16384
#define QA_BLUR_MAX_BANDS 64

static inline int32_t qa_blur_floor_div(int32_t value, int32_t by) {
  const int32_t q = value / by;
  return (value % by != 0 && (value < 0) != (by < 0)) ? q - 1 : q;
}

// round(channel * alpha * 257 / 255).
static inline uint16_t qa_blur_premultiplied(uint32_t channel,
                                             uint32_t alpha) {
  return (uint16_t)((channel * alpha * 514u + 255u) / 510u);
}

// round(difference * factor / whole), half away from zero.
static inline int64_t qa_blur_scaled(int64_t difference, int64_t factor,
                                     int64_t whole) {
  return difference >= 0
             ? (difference * factor * 2 + whole) / (whole * 2)
             : -((-difference * factor * 2 + whole) / (whole * 2));
}

// `from` moved toward `to` by share / 65535.
static inline uint16_t qa_blur_toward(uint16_t from, uint16_t to,
                                      int64_t share) {
  return (uint16_t)(from + qa_blur_scaled((int64_t)to - from, share, 65535));
}

typedef struct {
  const qa_blur_tile* tiles;
  int32_t tiles_wide;
  int32_t tile_x0;
  int32_t tile_y0;
  int32_t tile_size;
  int32_t left;
  int32_t top;
  int32_t width;
  int32_t height;
  int32_t radius;
  int32_t reach;
  int32_t wide;
  int32_t tall;
  const qa_dab_spec* spec;
  uint16_t* laid;
  uint16_t* across;
  uint16_t* lines;
  size_t line_values;
  // The scratch tiles the laid share is measured on: a grid of
  // `scratch_wide` a row from (`scratch_x0`, `scratch_y0`), one scratch a
  // band.
  uint8_t* scratch_tiles;
  int32_t scratch_x0;
  int32_t scratch_y0;
  int32_t scratch_wide;
  int32_t scratch_count;
  int32_t band_scratch;
  int32_t band_rows;
  int32_t band_columns;
} qa_blur_context;

static inline const qa_blur_tile* qa_blur_tile_at(const qa_blur_context* c,
                                                  int32_t tile_x,
                                                  int32_t tile_y) {
  return &c->tiles[(size_t)(tile_y - c->tile_y0) * c->tiles_wide +
                   (tile_x - c->tile_x0)];
}

// What the dab lays onto nothing over scratch tile `index` of its rect,
// alpha * 65535 a pixel - read off the kernel's own 16-bit plane.
static void qa_blur_laid_tile(const qa_blur_context* c, int32_t index,
                              uint8_t* pixels, uint16_t* wide) {
  const int32_t s = QA_BLUR_SCRATCH;
  const int32_t right = c->left + c->width;
  const int32_t bottom = c->top + c->height;
  const int32_t tile_left = (c->scratch_x0 + index % c->scratch_wide) * s;
  const int32_t tile_top = (c->scratch_y0 + index / c->scratch_wide) * s;
  const int32_t x0 = c->left > tile_left ? c->left : tile_left;
  const int32_t x1 = right < tile_left + s ? right : tile_left + s;
  const int32_t y0 = c->top > tile_top ? c->top : tile_top;
  const int32_t y1 = bottom < tile_top + s ? bottom : tile_top + s;
  memset(pixels, 0, (size_t)s * s * 4);
  memset(wide, 0, (size_t)s * s * 4 * sizeof(uint16_t));
  qa_dab_blend_tile(pixels, wide, NULL, s, tile_left, tile_top, x0, x1, y0,
                    y1, c->spec);
  for (int32_t y = y0; y < y1; y += 1) {
    const uint16_t* from =
        wide + ((size_t)(y - tile_top) * s + (x0 - tile_left)) * 4 + 3;
    uint16_t* to = c->laid + (size_t)(y - c->top) * c->width + (x0 - c->left);
    for (int32_t x = x0; x < x1; x += 1) {
      *to++ = *from;
      from += 4;
    }
  }
}

static void qa_blur_laid_item(int32_t band, void* context) {
  const qa_blur_context* c = (const qa_blur_context*)context;
  uint8_t* pixels = c->scratch_tiles + (size_t)band * QA_BLUR_SCRATCH_BYTES;
  uint16_t* wide = (uint16_t*)(pixels + QA_BLUR_SCRATCH_PIXEL_BYTES);
  const int32_t first = band * c->band_scratch;
  const int32_t last = first + c->band_scratch < c->scratch_count
                           ? first + c->band_scratch
                           : c->scratch_count;
  for (int32_t index = first; index < last; index += 1) {
    qa_blur_laid_tile(c, index, pixels, wide);
  }
}

// The picture as it stands along row `y` from `x0`, the window's width,
// premultiplied 16-bit (BrushBlurPicture._gatherRow).
static void qa_blur_gather_row(const qa_blur_context* c, uint16_t* into,
                               int32_t x0, int32_t y) {
  const int32_t size = c->tile_size;
  const int32_t tile_y = qa_blur_floor_div(y, size);
  const size_t row_offset = (size_t)(y - tile_y * size) * size;
  const int32_t x_end = x0 + c->wide;
  int32_t x = x0;
  while (x < x_end) {
    const int32_t tile_x = qa_blur_floor_div(x, size);
    const int32_t tile_left = tile_x * size;
    const int32_t span_end =
        x_end < tile_left + size ? x_end : tile_left + size;
    const size_t values = (size_t)(span_end - x) * 4;
    uint16_t* out = into + (size_t)(x - x0) * 4;
    const size_t from = (row_offset + (size_t)(x - tile_left)) * 4;
    const qa_blur_tile* tile = qa_blur_tile_at(c, tile_x, tile_y);
    if (tile->own != NULL) {
      memcpy(out, tile->own + from, values * sizeof(uint16_t));
    } else if (tile->cel != NULL) {
      const uint8_t* source = tile->cel + from;
      for (size_t i = 0; i < values; i += 4) {
        const uint32_t alpha = source[i + 3];
        out[i] = qa_blur_premultiplied(source[i], alpha);
        out[i + 1] = qa_blur_premultiplied(source[i + 1], alpha);
        out[i + 2] = qa_blur_premultiplied(source[i + 2], alpha);
        out[i + 3] = (uint16_t)(alpha * 257u);
      }
    } else {
      memset(out, 0, values * sizeof(uint16_t));
    }
    x = span_end;
  }
}

// floor(n / d) as a multiply and a shift, exact for every n < 2^n_bits
// (division by an invariant integer, Granlund & Montgomery): a box pass
// divides every value it writes by the same count, and a divide each was
// most of what a pass cost.
typedef struct {
  uint64_t multiplier;
  int shift;
} qa_blur_divisor;

static qa_blur_divisor qa_blur_divisor_of(uint64_t d, int n_bits) {
  int d_bits = 0;
  while (((uint64_t)1 << d_bits) < d) {
    d_bits += 1;
  }
  qa_blur_divisor v;
  v.shift = n_bits + d_bits;
  v.multiplier = (((uint64_t)1 << v.shift) + d - 1) / d;
  return v;
}

static inline uint16_t qa_blur_divided(uint64_t n, qa_blur_divisor v) {
  return (uint16_t)((n * v.multiplier) >> v.shift);
}

// Box pass `pass` along a line of `length` pixels, the first at `from` in
// `values`, each next `step` values on: every pixel `pass` radii in from
// either end takes into `target` the mean of the `radius` pixels either
// side of it and itself, rounded half up (BrushBlurPicture._box).
static void qa_blur_box(const uint16_t* values, size_t from, size_t step,
                        uint16_t* target, int32_t radius, int32_t pass,
                        int32_t length) {
  const int32_t start = radius * pass;
  const int32_t end = length - start;
  const int64_t count = (int64_t)radius * 2 + 1;
  // A sum is at most count * 65535, so what is divided stays under
  // count * 131071 + 1.
  int n_bits = 0;
  while (((uint64_t)1 << n_bits) <= (uint64_t)count * 131071) {
    n_bits += 1;
  }
  const qa_blur_divisor twice = qa_blur_divisor_of((uint64_t)count * 2, n_bits);
  int64_t r = 0, g = 0, b = 0, a = 0;
  for (int32_t at = start - radius; at <= start + radius; at += 1) {
    const uint16_t* p = values + from + (size_t)at * step;
    r += p[0];
    g += p[1];
    b += p[2];
    a += p[3];
  }
  for (int32_t at = start; at < end; at += 1) {
    uint16_t* o = target + (size_t)at * 4;
    o[0] = qa_blur_divided((uint64_t)(r * 2 + count), twice);
    o[1] = qa_blur_divided((uint64_t)(g * 2 + count), twice);
    o[2] = qa_blur_divided((uint64_t)(b * 2 + count), twice);
    o[3] = qa_blur_divided((uint64_t)(a * 2 + count), twice);
    if (at + 1 < end) {
      const uint16_t* enter = values + from + (size_t)(at + radius + 1) * step;
      const uint16_t* leave = values + from + (size_t)(at - radius) * step;
      r += (int64_t)enter[0] - leave[0];
      g += (int64_t)enter[1] - leave[1];
      b += (int64_t)enter[2] - leave[2];
      a += (int64_t)enter[3] - leave[3];
    }
  }
}

// The three passes along one line; the blur lands in `line_b`.
static void qa_blur_line(const qa_blur_context* c, const uint16_t* values,
                         size_t from, size_t step, int32_t length,
                         uint16_t* line_a, uint16_t* line_b) {
  qa_blur_box(values, from, step, line_b, c->radius, 1, length);
  qa_blur_box(line_b, 0, 4, line_a, c->radius, 2, length);
  qa_blur_box(line_a, 0, 4, line_b, c->radius, 3, length);
}

// The dab's pixels down `column` moved toward `blurred` by what it laid
// there (BrushBlurPicture._moveColumn). Every tile of the dab's rect has
// its `own` (the Dart side makes them first).
static void qa_blur_move_column(const qa_blur_context* c, int32_t column,
                                const uint16_t* blurred) {
  const int32_t size = c->tile_size;
  const int32_t x = c->left + column;
  const int32_t tile_x = qa_blur_floor_div(x, size);
  const int32_t local_x = x - tile_x * size;
  const int32_t bottom = c->top + c->height;
  for (int32_t at = c->top; at < bottom; at += 1) {
    const int64_t share = c->laid[(size_t)(at - c->top) * c->width + column];
    if (share == 0) {
      continue;
    }
    const int32_t tile_y = qa_blur_floor_div(at, size);
    uint16_t* p = qa_blur_tile_at(c, tile_x, tile_y)->own +
                  ((size_t)(at - tile_y * size) * size + local_x) * 4;
    const uint16_t* to = blurred + (size_t)(c->reach + at - c->top) * 4;
    p[0] = qa_blur_toward(p[0], to[0], share);
    p[1] = qa_blur_toward(p[1], to[1], share);
    p[2] = qa_blur_toward(p[2], to[2], share);
    p[3] = qa_blur_toward(p[3], to[3], share);
  }
}

static void qa_blur_rows_item(int32_t band, void* context) {
  const qa_blur_context* c = (const qa_blur_context*)context;
  uint16_t* line_a = c->lines + (size_t)band * 2 * c->line_values;
  uint16_t* line_b = line_a + c->line_values;
  const int32_t first = band * c->band_rows;
  const int32_t last =
      first + c->band_rows < c->tall ? first + c->band_rows : c->tall;
  const size_t row_values = (size_t)c->width * 4;
  for (int32_t row = first; row < last; row += 1) {
    qa_blur_gather_row(c, line_a, c->left - c->reach, c->top - c->reach + row);
    qa_blur_line(c, line_a, 0, 4, c->wide, line_a, line_b);
    memcpy(c->across + (size_t)row * row_values,
           line_b + (size_t)c->reach * 4, row_values * sizeof(uint16_t));
  }
}

static void qa_blur_columns_item(int32_t band, void* context) {
  const qa_blur_context* c = (const qa_blur_context*)context;
  uint16_t* line_a = c->lines + (size_t)band * 2 * c->line_values;
  uint16_t* line_b = line_a + c->line_values;
  const int32_t first = band * c->band_columns;
  const int32_t last = first + c->band_columns < c->width
                           ? first + c->band_columns
                           : c->width;
  for (int32_t column = first; column < last; column += 1) {
    qa_blur_line(c, c->across, (size_t)column * 4, (size_t)c->width * 4,
                 c->tall, line_a, line_b);
    qa_blur_move_column(c, column, line_b);
  }
}

// Runs `item` over `count` units cut into at most `bands` bands, each
// `*per_band` units: on the pool when the window is worth waking it for.
static void qa_blur_run(qa_job_fn item, qa_blur_context* c, int32_t count,
                        int32_t bands, int32_t* per_band) {
  *per_band = (count + bands - 1) / bands;
  const int32_t used = (count + *per_band - 1) / *per_band;
  if (used <= 1) {
    item(0, c);
    return;
  }
  qa_pool_run(item, c, used);
}

static size_t qa_blur_aligned(size_t bytes) {
  return (bytes + 15) & ~(size_t)15;
}

// Blurs the picture under one dab (BrushBlurPicture.blurDab): `spec` is
// the dab staged as paint - its coverage, white onto nothing; `tiles` the
// picture over the window the blur reads, `tiles_wide` a row from tile
// (`tile_x0`, `tile_y0`); the rect is the dab's clip; `radius` its box
// radius. Its buffers are carved from `scratch`, the caller's: when
// `scratch_bytes` is short it writes nothing and returns the bytes it
// needs, else 0. (A dab's buffers are megabytes at a large size; made
// and freed a dab, their pages were faulted in every time.)
QA_EXPORT int64_t qa_blur_dab(const qa_dab_spec* spec,
                              const qa_blur_tile* tiles, int32_t tiles_wide,
                              int32_t tile_x0, int32_t tile_y0,
                              int32_t tile_size, int32_t left, int32_t top,
                              int32_t right_exclusive,
                              int32_t bottom_exclusive, int32_t radius,
                              uint8_t* scratch, int64_t scratch_bytes) {
  qa_blur_context c;
  c.tiles = tiles;
  c.tiles_wide = tiles_wide;
  c.tile_x0 = tile_x0;
  c.tile_y0 = tile_y0;
  c.tile_size = tile_size;
  c.left = left;
  c.top = top;
  c.width = right_exclusive - left;
  c.height = bottom_exclusive - top;
  c.radius = radius;
  c.reach = radius * 3;
  c.wide = c.width + c.reach * 2;
  c.tall = c.height + c.reach * 2;
  c.line_values = (size_t)(c.wide > c.tall ? c.wide : c.tall) * 4;
  const int32_t bands = (int64_t)c.wide * c.tall < QA_BLUR_POOL_PIXELS
                            ? 1
                            : QA_BLUR_MAX_BANDS;
  const int32_t s = QA_BLUR_SCRATCH;
  c.spec = spec;
  c.scratch_x0 = qa_blur_floor_div(left, s);
  c.scratch_y0 = qa_blur_floor_div(top, s);
  c.scratch_wide = qa_blur_floor_div(right_exclusive - 1, s) - c.scratch_x0 + 1;
  c.scratch_count =
      c.scratch_wide *
      (qa_blur_floor_div(bottom_exclusive - 1, s) - c.scratch_y0 + 1);

  const size_t laid_bytes =
      qa_blur_aligned((size_t)c.width * c.height * sizeof(uint16_t));
  const size_t across_bytes =
      qa_blur_aligned((size_t)c.width * c.tall * 4 * sizeof(uint16_t));
  const size_t lines_bytes =
      qa_blur_aligned((size_t)bands * 2 * c.line_values * sizeof(uint16_t));
  const size_t need = laid_bytes + across_bytes + lines_bytes +
                      (size_t)bands * QA_BLUR_SCRATCH_BYTES;
  if (scratch_bytes < 0 || (size_t)scratch_bytes < need) {
    return (int64_t)need;
  }
  c.laid = (uint16_t*)scratch;
  c.across = (uint16_t*)(scratch + laid_bytes);
  c.lines = (uint16_t*)(scratch + laid_bytes + across_bytes);
  c.scratch_tiles = scratch + laid_bytes + across_bytes + lines_bytes;

  qa_blur_run(qa_blur_laid_item, &c, c.scratch_count, bands, &c.band_scratch);
  qa_blur_run(qa_blur_rows_item, &c, c.tall, bands, &c.band_rows);
  qa_blur_run(qa_blur_columns_item, &c, c.width, bands, &c.band_columns);
  return 0;
}

// The cel's `channel` (straight, under `cel_alpha`) moved toward the
// rewritten premultiplied `own` by cover / 255.
static inline int64_t qa_blur_covered(uint32_t channel, uint32_t cel_alpha,
                                      int64_t own, int64_t cover) {
  const int64_t cel = qa_blur_premultiplied(channel, cel_alpha);
  return cel + qa_blur_scaled(own - cel, cover, 255);
}

// A premultiplied 16-bit `channel` over `alpha` as a straight byte - none
// under an alpha that rounds to nothing.
static inline uint8_t qa_blur_straight(int64_t channel, int64_t alpha,
                                       int64_t out_alpha) {
  return out_alpha == 0 ? 0 : (uint8_t)((channel * 510 + alpha) / (alpha * 2));
}

// The finished tile (BrushBlurPicture.resultTile): the cel (`cel`, NULL =
// nothing there) moved toward the rewritten picture `own` by `mask` (NULL
// = all the way), straight 8-bit, into `out` - the cel's own bytes where
// the picture is still the cel's. Returns whether any pixel differs from
// the cel's.
QA_EXPORT int32_t qa_blur_result_tile(const uint16_t* own,
                                      const uint8_t* cel,
                                      const uint8_t* mask, int32_t tile_size,
                                      uint8_t* out) {
  const size_t count = (size_t)tile_size * tile_size;
  if (cel != NULL) {
    memcpy(out, cel, count * 4);
  } else {
    memset(out, 0, count * 4);
  }
  int32_t changed = 0;
  for (size_t p = 0; p < count; p += 1) {
    const int64_t cover = mask == NULL ? 255 : mask[p];
    if (cover == 0) {
      continue;
    }
    uint8_t* o = out + p * 4;
    const uint16_t* w = own + p * 4;
    const uint32_t cel_alpha = o[3];
    if (w[3] == cel_alpha * 257 &&
        w[0] == qa_blur_premultiplied(o[0], cel_alpha) &&
        w[1] == qa_blur_premultiplied(o[1], cel_alpha) &&
        w[2] == qa_blur_premultiplied(o[2], cel_alpha)) {
      continue;  // The picture is the cel's here: its bytes stand.
    }
    int64_t alpha = w[3];
    int64_t red = w[0];
    int64_t green = w[1];
    int64_t blue = w[2];
    if (cover != 255) {
      const int64_t cel_wide = (int64_t)cel_alpha * 257;
      alpha = cel_wide + qa_blur_scaled(alpha - cel_wide, cover, 255);
      red = qa_blur_covered(o[0], cel_alpha, red, cover);
      green = qa_blur_covered(o[1], cel_alpha, green, cover);
      blue = qa_blur_covered(o[2], cel_alpha, blue, cover);
    }
    const int64_t out_alpha = (alpha * 2 + 257) / 514;
    const uint8_t out_red = qa_blur_straight(red, alpha, out_alpha);
    const uint8_t out_green = qa_blur_straight(green, alpha, out_alpha);
    const uint8_t out_blue = qa_blur_straight(blue, alpha, out_alpha);
    if (out_red != o[0] || out_green != o[1] || out_blue != o[2] ||
        out_alpha != cel_alpha) {
      o[0] = out_red;
      o[1] = out_green;
      o[2] = out_blue;
      o[3] = (uint8_t)out_alpha;
      changed = 1;
    }
  }
  return changed;
}

// --- Batched stamp blend ---------------------------------------------------

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  const uint8_t* stamp;
  int32_t stamp_width;
  int32_t stamp_left;
  int32_t stamp_top;
  double opacity;
  int32_t erase;
  uint8_t* changed_out;
} qa_stamp_batch_context;

static void qa_stamp_batch_item(int32_t item_index, void* context) {
  const qa_stamp_batch_context* batch = (const qa_stamp_batch_context*)context;
  const qa_tile_span* span = &batch->tiles[item_index];
  batch->changed_out[item_index] = (uint8_t)qa_stamp_blend_tile(
      span->tile_pixels, batch->tile_size, span->tile_left, span->tile_top,
      batch->stamp, batch->stamp_width, batch->stamp_left, batch->stamp_top,
      span->span_left, span->span_right_exclusive, span->span_top,
      span->span_bottom_exclusive, batch->opacity, batch->erase);
}

// Blends one stamp dab into MANY tiles in one call, fanned across the pool.
QA_EXPORT void qa_stamp_blend_tiles(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    const uint8_t* stamp,
    int32_t stamp_width,
    int32_t stamp_left,
    int32_t stamp_top,
    double opacity,
    int32_t erase,
    uint8_t* changed_out) {
  qa_stamp_batch_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.stamp = stamp;
  context.stamp_width = stamp_width;
  context.stamp_left = stamp_left;
  context.stamp_top = stamp_top;
  context.opacity = opacity;
  context.erase = erase;
  context.changed_out = changed_out;
  qa_pool_run(qa_stamp_batch_item, &context, tile_count);
}

// ---------------------------------------------------------------------------
// Stroke blend (BB-N1, ABI 22): the ONCE-per-stroke brush blend
// (brush_stroke_blend.dart `blendStrokeRegionPixels`) ported verbatim -
// the pen-up pass blends the finished straight-alpha stroke buffer
// against the cel's pixels through the W3C separable equations (plus
// behind / add). The Dart function stays in the tree as the reference
// oracle AND the no-native fallback; every float expression below is an
// EXACT transcription (same grouping, llround == double.round()), so the
// parity suite pins byte-identity across the whole mode table.
//
// The C path reads the DESTINATION straight from the staged tile scratch
// and writes the result in place - the v1 Dart route's region extraction,
// result buffer, opaque rect and two-pass stamp landing all disappear.
// Untouched pixels (stroke alpha 0) copy the destination verbatim, so a
// span the stroke never inked reports unchanged.

// The mode ids and `qa_stroke_blend_channel`'s declaration moved up beside
// the dab spec (v33): the dual view reads the same table.

static inline int32_t qa_stroke_clamp_byte(double value) {
  return qa_round_byte(value * 255.0);
}

// `_blendChannel` transcribed: the separable B(Cs, Cd) table. overlay is
// hardLight with the operands swapped, exactly like the Dart reference.
static double qa_stroke_blend_channel(int32_t mode, double cs, double cd) {
  switch (mode) {
    case QA_STROKE_BLEND_DARKEN:
      return cs < cd ? cs : cd;
    case QA_STROKE_BLEND_MULTIPLY:
      return cs * cd;
    case QA_STROKE_BLEND_COLOR_BURN: {
      if (cd >= 1.0) return 1.0;
      if (cs <= 0.0) return 0.0;
      const double quotient = (1.0 - cd) / cs;
      return 1.0 - (quotient < 1.0 ? quotient : 1.0);
    }
    case QA_STROKE_BLEND_LIGHTEN:
      return cs > cd ? cs : cd;
    case QA_STROKE_BLEND_SCREEN:
      return cs + cd - cs * cd;
    case QA_STROKE_BLEND_COLOR_DODGE: {
      if (cd <= 0.0) return 0.0;
      if (cs >= 1.0) return 1.0;
      const double quotient = cd / (1.0 - cs);
      return quotient < 1.0 ? quotient : 1.0;
    }
    case QA_STROKE_BLEND_OVERLAY:
      return qa_stroke_blend_channel(QA_STROKE_BLEND_HARD_LIGHT, cd, cs);
    case QA_STROKE_BLEND_SOFT_LIGHT: {
      if (cs <= 0.5) {
        return cd - (1.0 - 2.0 * cs) * cd * (1.0 - cd);
      }
      const double d =
          cd <= 0.25 ? ((16.0 * cd - 12.0) * cd + 4.0) * cd : sqrt(cd);
      return cd + (2.0 * cs - 1.0) * (d - cd);
    }
    case QA_STROKE_BLEND_HARD_LIGHT:
      return cs <= 0.5 ? 2.0 * cs * cd
                       : (2.0 * cs - 1.0) + cd - (2.0 * cs - 1.0) * cd;
    case QA_STROKE_BLEND_DIFFERENCE:
      return fabs(cs - cd);
    case QA_STROKE_BLEND_LINEAR_BURN: {
      const double sum = cs + cd - 1.0;
      return sum > 0.0 ? sum : 0.0;
    }
    case QA_STROKE_BLEND_SUBTRACT: {
      const double rest = cd - cs;
      return rest > 0.0 ? rest : 0.0;
    }
    case QA_STROKE_BLEND_VIVID_LIGHT:
      // colorBurn(2cs, cd) below the pivot, colorDodge(2cs-1, cd) above —
      // hardLight's split with the two dodge/burn heads in place of
      // multiply/screen.
      return cs <= 0.5
                 ? qa_stroke_blend_channel(QA_STROKE_BLEND_COLOR_BURN,
                                           2.0 * cs, cd)
                 : qa_stroke_blend_channel(QA_STROKE_BLEND_COLOR_DODGE,
                                           2.0 * cs - 1.0, cd);
    case QA_STROKE_BLEND_LINEAR_LIGHT: {
      const double sum = cd + 2.0 * cs - 1.0;
      return sum < 0.0 ? 0.0 : (sum > 1.0 ? 1.0 : sum);
    }
    case QA_STROKE_BLEND_PIN_LIGHT: {
      if (cs <= 0.5) {
        const double doubled = 2.0 * cs;
        return cd < doubled ? cd : doubled;
      }
      const double raised = 2.0 * cs - 1.0;
      return cd > raised ? cd : raised;
    }
    case QA_STROKE_BLEND_HARD_MIX:
      // Every channel goes all the way: white where the two reach a whole,
      // black where they fall short — on bytes, s + d >= 255. 🔬Every pair
      // of bytes summing to 255 lands on exactly 1.0 here (all 256 checked,
      // 2026-10-17), so the plain comparison is the byte rule.
      return cs + cd >= 1.0 ? 1.0 : 0.0;
    case QA_STROKE_BLEND_DIVIDE: {
      // The destination divided by the source. Nothing divided is nothing;
      // anything divided by nothing is as bright as a channel goes.
      if (cd <= 0.0) return 0.0;
      if (cs <= 0.0) return 1.0;
      const double quotient = cd / cs;
      return quotient < 1.0 ? quotient : 1.0;
    }
    case QA_STROKE_BLEND_EXCLUSION:
    default:
      return cs + cd - 2.0 * cs * cd;
  }
}

// ---- The six that mix the three channels (brush-fidelity) ----
//
// Their B is a COLOUR of three, so they are not in the table above:
// W3C Compositing and Blending Level 1's non-separable modes — Lum,
// ClipColor, SetLum, Sat, SetSat — plus Photoshop's darker/lighter colour,
// which keep one of the two colours whole. SetSat is written the way Skia
// writes it (every channel (c - min) * s / (max - min)): the spec's
// max/mid/min assignment without ranking the three, ties included.
//
// 🚨Every expression keeps the Dart reference's grouping
// (brush_stroke_blend.dart `_ChannelMix`); FP contraction is
// off in every build, so the parity suite holds them byte for byte.

static int32_t qa_stroke_blend_is_triple(int32_t mode) {
  return mode >= QA_STROKE_BLEND_DARKER_COLOR &&
         mode <= QA_STROKE_BLEND_LUMINOSITY;
}

static double qa_triple_min(const double* c) {
  const double low = c[0] < c[1] ? c[0] : c[1];
  return low < c[2] ? low : c[2];
}

static double qa_triple_max(const double* c) {
  const double high = c[0] > c[1] ? c[0] : c[1];
  return high > c[2] ? high : c[2];
}

static double qa_triple_lum(const double* c) {
  return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];
}

// ⚠️The two `!= 0.0` guards are Skia's: a grey whose luminosity landed an
// ulp under 0 (or over 1) would otherwise divide 0 by 0, and the Dart
// reference's `round()` throws on NaN.
static void qa_triple_clip(double* c) {
  const double l = qa_triple_lum(c);
  const double low = qa_triple_min(c);
  const double high = qa_triple_max(c);
  for (int32_t k = 0; k < 3; k += 1) {
    double v = c[k];
    if (low < 0.0 && l - low != 0.0) {
      v = l + (v - l) * l / (l - low);
    }
    if (high > 1.0 && high - l != 0.0) {
      v = l + (v - l) * (1.0 - l) / (high - l);
    }
    c[k] = v;
  }
}

static void qa_triple_set_lum(double* c, double l) {
  const double d = l - qa_triple_lum(c);
  c[0] = c[0] + d;
  c[1] = c[1] + d;
  c[2] = c[2] + d;
  qa_triple_clip(c);
}

static double qa_triple_sat(const double* c) {
  return qa_triple_max(c) - qa_triple_min(c);
}

static void qa_triple_set_sat(double* c, double s) {
  const double low = qa_triple_min(c);
  const double sat = qa_triple_max(c) - low;
  for (int32_t k = 0; k < 3; k += 1) {
    c[k] = sat > 0.0 ? (c[k] - low) * s / sat : 0.0;
  }
}

// B(Cs, Cd) for the six, into [b]. Takes the BYTES because darker/lighter
// colour compare the two colours' channel totals, and a total of thirds
// of 255 in doubles can call two equal totals unequal.
static void qa_stroke_blend_triple(int32_t mode, const uint8_t* src,
                                   const uint8_t* dst, double* b) {
  const double cs[3] = {src[0] / 255.0, src[1] / 255.0, src[2] / 255.0};
  const double cd[3] = {dst[0] / 255.0, dst[1] / 255.0, dst[2] / 255.0};
  const int32_t source_total = src[0] + src[1] + src[2];
  const int32_t dest_total = dst[0] + dst[1] + dst[2];
  const double* whole = cd;
  switch (mode) {
    case QA_STROKE_BLEND_DARKER_COLOR:
      // A tie keeps what is there.
      whole = source_total < dest_total ? cs : cd;
      break;
    case QA_STROKE_BLEND_LIGHTER_COLOR:
      whole = source_total > dest_total ? cs : cd;
      break;
    case QA_STROKE_BLEND_HUE:
      b[0] = cs[0];
      b[1] = cs[1];
      b[2] = cs[2];
      qa_triple_set_sat(b, qa_triple_sat(cd));
      qa_triple_set_lum(b, qa_triple_lum(cd));
      return;
    case QA_STROKE_BLEND_SATURATION:
      b[0] = cd[0];
      b[1] = cd[1];
      b[2] = cd[2];
      qa_triple_set_sat(b, qa_triple_sat(cs));
      qa_triple_set_lum(b, qa_triple_lum(cd));
      return;
    case QA_STROKE_BLEND_CHROMA:
      b[0] = cs[0];
      b[1] = cs[1];
      b[2] = cs[2];
      qa_triple_set_lum(b, qa_triple_lum(cd));
      return;
    case QA_STROKE_BLEND_LUMINOSITY:
    default:
      b[0] = cd[0];
      b[1] = cd[1];
      b[2] = cd[2];
      qa_triple_set_lum(b, qa_triple_lum(cs));
      return;
  }
  b[0] = whole[0];
  b[1] = whole[1];
  b[2] = whole[2];
}

// Blends one stroke row span into a tile row in place. Returns nonzero
// when any destination byte changed.
static int32_t qa_stroke_blend_row(
    uint8_t* tile_row,
    const uint8_t* stroke_row,
    int32_t count,
    int32_t mode) {
  int32_t changed = 0;
  for (int32_t i = 0; i < count; i += 1) {
    uint8_t* dst = tile_row + (ptrdiff_t)i * 4;
    const uint8_t* src = stroke_row + (ptrdiff_t)i * 4;
    const int32_t sa = src[3];
    if (sa == 0) {
      // Alpha-0 copies the destination through - EXCEPT that the Dart
      // reference's erase+rewrite landing zeroes the RGB of any pixel
      // that ends fully transparent (its srcOver pass skips alpha-0
      // result pixels after the erase pass cleared them). Mirror that
      // byte-exactly; real surfaces never carry RGB under alpha 0, so
      // this branch is parity insurance, not a visible behavior.
      if (dst[3] == 0 && (dst[0] != 0 || dst[1] != 0 || dst[2] != 0)) {
        dst[0] = 0;
        dst[1] = 0;
        dst[2] = 0;
        changed = 1;
      }
      continue;
    }
    const int32_t da = dst[3];
    int32_t out_r, out_g, out_b, out_a;
    if (mode == QA_STROKE_BLEND_BEHIND) {
      if (da == 255) {
        continue; // Fully covered: destination-over changes nothing.
      }
      if (da == 0) {
        out_r = src[0];
        out_g = src[1];
        out_b = src[2];
        out_a = sa;
      } else {
        // destination-over on straight alpha.
        const double as_ = sa / 255.0, ad = da / 255.0;
        const double ao = ad + as_ * (1.0 - ad);
        out_r = qa_stroke_clamp_byte(
            (ad * dst[0] / 255.0 + (1.0 - ad) * as_ * src[0] / 255.0) / ao);
        out_g = qa_stroke_clamp_byte(
            (ad * dst[1] / 255.0 + (1.0 - ad) * as_ * src[1] / 255.0) / ao);
        out_b = qa_stroke_clamp_byte(
            (ad * dst[2] / 255.0 + (1.0 - ad) * as_ * src[2] / 255.0) / ao);
        out_a = qa_stroke_clamp_byte(ao);
      }
    } else if (da == 0) {
      out_r = src[0];
      out_g = src[1];
      out_b = src[2];
      out_a = sa;
    } else {
      const double as_ = sa / 255.0, ad = da / 255.0;
      if (mode == QA_STROKE_BLEND_ADD) {
        // Skia plus: saturating premultiplied add.
        double ao = as_ + ad;
        if (ao > 1.0) ao = 1.0;
        double premul_r = src[0] / 255.0 * as_ + dst[0] / 255.0 * ad;
        if (premul_r > 1.0) premul_r = 1.0;
        double premul_g = src[1] / 255.0 * as_ + dst[1] / 255.0 * ad;
        if (premul_g > 1.0) premul_g = 1.0;
        double premul_b = src[2] / 255.0 * as_ + dst[2] / 255.0 * ad;
        if (premul_b > 1.0) premul_b = 1.0;
        out_r = qa_stroke_clamp_byte(premul_r / ao);
        out_g = qa_stroke_clamp_byte(premul_g / ao);
        out_b = qa_stroke_clamp_byte(premul_b / ao);
        out_a = qa_stroke_clamp_byte(ao);
      } else {
        const double ao = as_ + ad * (1.0 - as_);
        const double cs_r = src[0] / 255.0, cd_r = dst[0] / 255.0;
        const double cs_g = src[1] / 255.0, cd_g = dst[1] / 255.0;
        const double cs_b = src[2] / 255.0, cd_b = dst[2] / 255.0;
        // One composite for both kinds of B: per channel, or a colour of
        // three (the six that mix the channels).
        double b[3];
        if (qa_stroke_blend_is_triple(mode)) {
          qa_stroke_blend_triple(mode, src, dst, b);
        } else {
          b[0] = qa_stroke_blend_channel(mode, cs_r, cd_r);
          b[1] = qa_stroke_blend_channel(mode, cs_g, cd_g);
          b[2] = qa_stroke_blend_channel(mode, cs_b, cd_b);
        }
        out_r = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_r + ad * (1.0 - as_) * cd_r +
             as_ * ad * b[0]) /
            ao);
        out_g = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_g + ad * (1.0 - as_) * cd_g +
             as_ * ad * b[1]) /
            ao);
        out_b = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_b + ad * (1.0 - as_) * cd_b +
             as_ * ad * b[2]) /
            ao);
        out_a = qa_stroke_clamp_byte(ao);
      }
    }
    if ((uint8_t)out_r != dst[0] || (uint8_t)out_g != dst[1] ||
        (uint8_t)out_b != dst[2] || (uint8_t)out_a != dst[3]) {
      dst[0] = (uint8_t)out_r;
      dst[1] = (uint8_t)out_g;
      dst[2] = (uint8_t)out_b;
      dst[3] = (uint8_t)out_a;
      changed = 1;
    }
  }
  return changed;
}

QA_EXPORT int32_t qa_stroke_blend_tile(
    uint8_t* tile_pixels,
    int32_t tile_size,
    int32_t tile_left,
    int32_t tile_top,
    const uint8_t* stroke,
    int32_t stroke_width,
    int32_t stroke_left,
    int32_t stroke_top,
    int32_t span_left,
    int32_t span_right_exclusive,
    int32_t span_top,
    int32_t span_bottom_exclusive,
    int32_t mode) {
  int32_t changed = 0;
  const int32_t count = span_right_exclusive - span_left;
  for (int32_t y = span_top; y < span_bottom_exclusive; y += 1) {
    uint8_t* tile_row =
        tile_pixels +
        ((ptrdiff_t)(y - tile_top) * tile_size + (span_left - tile_left)) * 4;
    const uint8_t* stroke_row =
        stroke + ((ptrdiff_t)(y - stroke_top) * stroke_width +
                  (span_left - stroke_left)) *
                     4;
    if (qa_stroke_blend_row(tile_row, stroke_row, count, mode)) {
      changed = 1;
    }
  }
  return changed;
}

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  const uint8_t* stroke;
  int32_t stroke_width;
  int32_t stroke_left;
  int32_t stroke_top;
  int32_t mode;
  uint8_t* changed_out;
} qa_stroke_batch_context;

static void qa_stroke_batch_item(int32_t item_index, void* context) {
  const qa_stroke_batch_context* batch =
      (const qa_stroke_batch_context*)context;
  const qa_tile_span* span = &batch->tiles[item_index];
  batch->changed_out[item_index] = (uint8_t)qa_stroke_blend_tile(
      span->tile_pixels, batch->tile_size, span->tile_left, span->tile_top,
      batch->stroke, batch->stroke_width, batch->stroke_left,
      batch->stroke_top, span->span_left, span->span_right_exclusive,
      span->span_top, span->span_bottom_exclusive, batch->mode);
}

// Blends the stroke buffer into MANY tiles in one call, fanned across the
// pool. Tiles are disjoint and every pixel's math is independent, so the
// result is byte-identical regardless of worker count.
QA_EXPORT void qa_stroke_blend_tiles(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    const uint8_t* stroke,
    int32_t stroke_width,
    int32_t stroke_left,
    int32_t stroke_top,
    int32_t mode,
    uint8_t* changed_out) {
  qa_stroke_batch_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.stroke = stroke;
  context.stroke_width = stroke_width;
  context.stroke_left = stroke_left;
  context.stroke_top = stroke_top;
  context.mode = mode;
  context.changed_out = changed_out;
  qa_pool_run(qa_stroke_batch_item, &context, tile_count);
}

// ---------------------------------------------------------------------------
// Tile alpha bounds (BB-N1, ABI 22): the per-tile word scan of
// bitmapSurfaceContentBounds (R26 #13) - RGBA little-endian, alpha in the
// word's top byte. Pure integer logic, so parity is structural. Each item
// writes only its own 4-int slot; the Dart driver merges tile-local
// bounds into world coordinates.

// bounds_out per tile: minX, minY, maxX, maxY in TILE-LOCAL pixels;
// an ink-free tile reports minX=0x7fffffff / maxX=-0x7fffffff (the same
// sentinels the Dart merge loop starts from).
QA_EXPORT void qa_tile_alpha_bounds(
    const uint8_t* tile_pixels,
    int32_t tile_size,
    int32_t* bounds_out) {
  int32_t min_x = 0x7fffffff, min_y = 0x7fffffff;
  int32_t max_x = -0x7fffffff, max_y = -0x7fffffff;
  const uint32_t* words = (const uint32_t*)tile_pixels;
  for (int32_t y = 0; y < tile_size; y += 1) {
    const uint32_t* row = words + (ptrdiff_t)y * tile_size;
    for (int32_t x = 0; x < tile_size; x += 1) {
      if ((row[x] & 0xff000000u) == 0) {
        continue;
      }
      if (x < min_x) min_x = x;
      if (x > max_x) max_x = x;
      if (y < min_y) min_y = y;
      if (y > max_y) max_y = y;
    }
  }
  bounds_out[0] = min_x;
  bounds_out[1] = min_y;
  bounds_out[2] = max_x;
  bounds_out[3] = max_y;
}

// ---------------------------------------------------------------------------
// Fused PRE-BLEND (ABI 24): one call does a whole frame's overlay tiles.
//
// The live overlay shows the commit's finished bytes, so every touched
// tile has to be staged from the cel, blended with the stroke, and
// premultiplied for upload. That ran per tile from Dart — a base row copy
// in the VM plus two count=1 kernel calls, which never engage the worker
// pool (a one-item batch runs inline). Measured on a debug build at
// 256px tiles: ~2ms PER TILE, so a 1000px brush spent 34ms of every frame
// there and an 1800px brush 122ms. Here the three passes fuse and the
// tiles fan out across the pool; the per-pixel math is untouched, so the
// bytes are identical to the Dart reference (parity-pinned).
//
// SELECTION MASK: `mask_pixels` (1 byte per pixel, tile-local) scales the
// STROKE's alpha before the blend — `a = mul255(a, mask)`. It is applied
// to the ACCUMULATED stroke, never per dab: masking each dab would break
// soft masks, since srcOver(a1·m, a2·m) != srcOver(a1, a2)·m. NULL means
// no selection and takes a branch-free path that is byte-identical to
// ABI 23.
enum {
  QA_PRE_BLEND_SRC_OVER = 0,  // plain colour: the stamp kernel's srcOver
  QA_PRE_BLEND_ERASE = 1,     // eraser / 소거: the stamp kernel's dstOut
  QA_PRE_BLEND_STROKE = 2,    // every other blend (mode = QA_STROKE_BLEND_*)
};

// Pixels of masked stroke staged per pass. Rows longer than this are
// blended in chunks, so any tile size works with a fixed 4KB of stack.
#define QA_PRE_BLEND_CHUNK 1024

static inline int32_t qa_mask_alpha(int32_t alpha, const uint8_t* mask,
                                    int32_t index) {
  if (mask == NULL) {
    return alpha;
  }
  const int32_t m = mask[index];
  if (m == 255) {
    return alpha;
  }
  if (m == 0 || alpha == 0) {
    return 0;
  }
  // Skia's SkMulDiv255Round — the same rounding the lift's soft masks and
  // every premultiply in this engine use.
  const int32_t product = alpha * m + 128;
  return (product + (product >> 8)) >> 8;
}

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  int32_t kind;
  int32_t mode;
  uint8_t* changed_out;
} qa_pre_blend_context;

// The stroke buffer masked into a scratch row, so the blend kernels below
// can stay exactly the code the commit runs. Returns the row to blend.
static const uint8_t* qa_masked_stroke_row(
    const uint8_t* stroke_row,
    const uint8_t* mask_row,
    int32_t count,
    uint8_t* scratch) {
  if (mask_row == NULL) {
    return stroke_row;
  }
  for (int32_t i = 0; i < count; i += 1) {
    const uint8_t* s = stroke_row + (ptrdiff_t)i * 4;
    uint8_t* d = scratch + (ptrdiff_t)i * 4;
    d[0] = s[0];
    d[1] = s[1];
    d[2] = s[2];
    d[3] = (uint8_t)qa_mask_alpha(s[3], mask_row, i);
  }
  return scratch;
}

static void qa_pre_blend_item(int32_t item_index, void* context) {
  const qa_pre_blend_context* batch = (const qa_pre_blend_context*)context;
  const qa_tile_span* span = &batch->tiles[item_index];
  const int32_t tile_size = batch->tile_size;
  uint8_t* tile = span->tile_pixels;

  // ONE PASS PER ROW: stage the cel's bytes, blend the stroke into them,
  // premultiply into the upload buffer - all while the row is still in
  // L1. The three steps used to be three sweeps of the WHOLE tile, so a
  // 256px tile (256KB) crossed the cache three times; per row it is 1KB
  // and stays resident from the stage to the premultiply.
  //
  // WHAT THIS IS AND IS NOT, measured - do not re-derive it:
  // on a 20-core desktop this is NOT faster. An 8-pair A/B said 15%,
  // and the benchmark's own control (the dab-blend time, code neither
  // arm touches) had moved 6% the same way - two builds from different
  // source dirs shift function layout and with it the i-cache behaviour
  // of code that did not change. Reversing which arm ran first collapsed
  // the rest. Net: inside noise.
  //
  // It is here for the devices that could not be measured. The whole
  // benefit is reuse distance, so it grows as the cache shrinks: a
  // desktop L2 already holds much of a 256KB tile, a tablet's does not.
  // That is a MECHANISM, not a measurement - if a device profile ever
  // shows the pre-blend cold, this is the shape that should pay off, and
  // if it never does, nothing here is lost.
  //
  // Byte-identical by construction: every pixel sees the same three
  // operations in the same order, and no pixel reads another's result
  // (parity-pinned both engines).
  const int32_t row_bytes = tile_size * 4;
  const int32_t left = span->span_left - span->tile_left;
  const int32_t right = span->span_right_exclusive - span->tile_left;
  const int32_t top = span->span_top - span->tile_top;
  const int32_t bottom = span->span_bottom_exclusive - span->tile_top;
  const int32_t count = right - left;
  const int32_t blending = (count > 0 && span->stroke_pixels != NULL) ? 1 : 0;
  // Masking rewrites alpha, so it needs a row of scratch. Fixed stack
  // chunk rather than an allocation: the pool runs this on several
  // threads and must never touch the heap here. Unmasked spans skip the
  // copy entirely (the scratch stays untouched).
  uint8_t masked_row[QA_PRE_BLEND_CHUNK * 4];
  const int32_t chunk =
      count > QA_PRE_BLEND_CHUNK ? QA_PRE_BLEND_CHUNK : count;
  int32_t changed = 0;

  for (int32_t y = 0; y < tile_size; y += 1) {
    uint8_t* row = tile + (ptrdiff_t)y * row_bytes;

    // 1. Stage the cel's bytes (or emptiness) as the blend destination.
    if (span->base_pixels != NULL) {
      memcpy(row, span->base_pixels + (ptrdiff_t)y * row_bytes,
             (size_t)row_bytes);
    } else {
      memset(row, 0, (size_t)row_bytes);
    }

    // 2. Blend the stroke in place, through the SAME kernels the pen-up
    // commit uses. Rows outside the span keep the staged base.
    if (blending && y >= top && y < bottom) {
      for (int32_t x0 = left; x0 < right; x0 += chunk) {
        const int32_t n = (right - x0) < chunk ? (right - x0) : chunk;
        const ptrdiff_t offset = ((ptrdiff_t)y * tile_size + x0);
        uint8_t* tile_row = tile + offset * 4;
        const uint8_t* stroke_row = span->stroke_pixels + offset * 4;
        const uint8_t* mask_row =
            span->mask_pixels == NULL ? NULL : span->mask_pixels + offset;
        const uint8_t* src =
            qa_masked_stroke_row(stroke_row, mask_row, n, masked_row);
        int32_t row_changed;
        if (batch->kind == QA_PRE_BLEND_STROKE) {
          row_changed = qa_stroke_blend_row(tile_row, src, n, batch->mode);
        } else {
          row_changed = qa_stamp_blend_row(
              tile_row, src, n, 1.0,
              batch->kind == QA_PRE_BLEND_ERASE ? 1 : 0);
        }
        if (row_changed) {
          changed = 1;
        }
      }
    }

    // 3. Premultiply straight into the upload buffer.
    if (span->premul_out != NULL) {
      qa_premultiply_rgba_copy(span->premul_out + (ptrdiff_t)y * row_bytes,
                               row, tile_size);
    }
  }
  batch->changed_out[item_index] = (uint8_t)changed;
}

// Stages, blends and premultiplies MANY overlay tiles in one call, fanned
// across the worker pool. Tiles are disjoint and every pixel's math is
// independent, so the result is byte-identical regardless of worker count
// — and identical to running the ABI 23 per-tile sequence.
QA_EXPORT void qa_pre_blend_tiles(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    int32_t kind,
    int32_t mode,
    uint8_t* changed_out) {
  qa_pre_blend_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.kind = kind;
  context.mode = mode;
  context.changed_out = changed_out;
  qa_pool_run(qa_pre_blend_item, &context, tile_count);
}

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  int32_t* bounds_out;
} qa_alpha_bounds_context;

static void qa_alpha_bounds_item(int32_t item_index, void* context) {
  const qa_alpha_bounds_context* batch =
      (const qa_alpha_bounds_context*)context;
  qa_tile_alpha_bounds(batch->tiles[item_index].tile_pixels, batch->tile_size,
                       batch->bounds_out + (ptrdiff_t)item_index * 4);
}

// Scans MANY tiles' alpha bounds in one call, fanned across the pool.
// Only tile_pixels of each span is consumed (the scan is whole-tile).
QA_EXPORT void qa_alpha_bounds_tiles(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    int32_t* bounds_out) {
  qa_alpha_bounds_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.bounds_out = bounds_out;
  qa_pool_run(qa_alpha_bounds_item, &context, tile_count);
}

// ---------------------------------------------------------------------------
// Parallel flood fill (R22-E3): wave-parallel connected growth.
//
// A sequential stepper grows the region pixel by pixel; at 64MP it was
// the app's dominant fill term (↩️`qa_flood_fill_step`, R18 A-2b — unbound
// since this engine replaced it, deleted with F-416). This engine keeps
// the lazy-compose protocol with the Dart driver (uncomposed
// pixels come back as candidates) but grows the region one compose-tile
// WAVE at a time: every tile with pending seeds floods LOCALLY (scan-
// line + the SSE2 tolerance spans, no composed checks inside a tile) in
// parallel across the worker pool; tiles write only their own filled
// pixels and their own outgoing edge-crossing buffers, so there is no
// shared-write anywhere in the parallel phase. A serial routing phase
// moves crossings into neighbor pending lists (composed) or the
// caller's candidate buffer (uncomposed), then the next wave runs.
//
// Determinism: the final filled set is "the seed's connected component
// of within-tolerance pixels" - a SET, independent of tile visit order
// and worker count, so the mask and bounds are byte-identical to the
// sequential reference (the randomized parity suite pins this against
// the permanent Dart oracle).
//
// Buffer bounds (why nothing can overflow): a pixel fills exactly once
// per fill, and only edge pixels emit crossings - so a tile's outgoing
// buffer per edge is capped by the edge length, and a tile's pending
// intake is capped by its own perimeter (from neighbors and from the
// driver's candidate re-seeds, which are exactly edge crossings) plus
// the original seed. Local stacks are capped by the per-tile run count
// (checkerboard worst case = tile_size^2/2). Every cap is enforced with
// an error flag anyway; any failure returns -1 and the caller redoes
// the fill on the sequential path from clean state.

#if defined(_MSC_VER)
#define QA_THREAD_LOCAL __declspec(thread)
#else
#define QA_THREAD_LOCAL __thread
#endif

enum { QA_WAVE_LEFT = 0, QA_WAVE_RIGHT = 1, QA_WAVE_UP = 2, QA_WAVE_DOWN = 3 };

typedef struct {
  int32_t px0, py0, px1, py1; // Inclusive pixel bounds of the tile.
  int32_t min_x, max_x, min_y, max_y; // Filled bounds inside this tile.
  int32_t pending_count;
  int32_t pending_taken;
  int32_t out_count[4];
  int32_t out_routed[4];
  uint8_t in_wave;
  uint8_t queued; // On the new-pending list for the next wave scan.
  uint8_t error;
} qa_wave_tile;

static struct {
  int32_t tile_capacity; // Allocated tile slots.
  int32_t pending_capacity_per_tile;
  int32_t out_capacity_per_edge;
  qa_wave_tile* tiles;
  int32_t* pending;   // tile_capacity * pending_capacity_per_tile
  int32_t* outgoing;  // tile_capacity * 4 * out_capacity_per_edge
  int32_t* wave_list; // tile ids in the current wave
  int32_t* queue_list; // tile ids with new pending (next wave scan)
} g_wave;

// Shared per-call view for the parallel job (read-only except the
// per-tile-owned fields documented above).
static struct {
  const uint8_t* rgb;
  uint8_t* filled;
  int32_t width;
  int32_t height;
  uint32_t seed;
  int32_t tolerance;
} g_wave_job;

// Worker-local scanline stack, lazily allocated per thread and kept.
#define QA_WAVE_LOCAL_STACK (1 << 17)
static QA_THREAD_LOCAL int32_t* g_wave_local_stack;

static int qa_wave_arena_ensure(int32_t tile_count, int32_t tile_size) {
  // Intake per tile per call: driver re-seeds (<= perimeter) + their
  // routed cross-tile crossings + neighbor wave crossings (<= 4 edges).
  const int32_t pending_cap = 16 * tile_size + 64;
  const int32_t out_cap = tile_size;
  if (g_wave.tile_capacity >= tile_count &&
      g_wave.pending_capacity_per_tile >= pending_cap &&
      g_wave.out_capacity_per_edge >= out_cap) {
    return 1;
  }
  free(g_wave.tiles);
  free(g_wave.pending);
  free(g_wave.outgoing);
  free(g_wave.wave_list);
  free(g_wave.queue_list);
  g_wave.tiles = (qa_wave_tile*)malloc(sizeof(qa_wave_tile) * tile_count);
  g_wave.pending =
      (int32_t*)malloc(sizeof(int32_t) * (size_t)tile_count * pending_cap);
  g_wave.outgoing =
      (int32_t*)malloc(sizeof(int32_t) * (size_t)tile_count * 4 * out_cap);
  g_wave.wave_list = (int32_t*)malloc(sizeof(int32_t) * tile_count);
  g_wave.queue_list = (int32_t*)malloc(sizeof(int32_t) * tile_count);
  if (g_wave.tiles == NULL || g_wave.pending == NULL ||
      g_wave.outgoing == NULL || g_wave.wave_list == NULL ||
      g_wave.queue_list == NULL) {
    free(g_wave.tiles);
    free(g_wave.pending);
    free(g_wave.outgoing);
    free(g_wave.wave_list);
    free(g_wave.queue_list);
    memset(&g_wave, 0, sizeof(g_wave));
    return 0;
  }
  g_wave.tile_capacity = tile_count;
  g_wave.pending_capacity_per_tile = pending_cap;
  g_wave.out_capacity_per_edge = out_cap;
  return 1;
}

static inline int32_t* qa_wave_pending_of(int32_t tile) {
  return g_wave.pending + (size_t)tile * g_wave.pending_capacity_per_tile;
}

static inline int32_t* qa_wave_out_of(int32_t tile, int edge) {
  return g_wave.outgoing +
         ((size_t)tile * 4 + edge) * g_wave.out_capacity_per_edge;
}

// Emits the crossing NEIGHBOR pixel for a filled edge pixel. Called
// only from the tile that owns (x, y) - single-writer per buffer.
static inline void qa_wave_emit(
    qa_wave_tile* t, int32_t tile_id, int edge, int32_t neighbor_index) {
  if (t->out_count[edge] >= g_wave.out_capacity_per_edge) {
    t->error = 1; // Unreachable by the perimeter bound; belt only.
    return;
  }
  qa_wave_out_of(tile_id, edge)[t->out_count[edge]] = neighbor_index;
  t->out_count[edge] += 1;
}

// Fills one pixel of the tile, with edge-crossing emission. Vector
// fast paths may bypass this ONLY for pixels strictly inside the tile
// (no crossings possible); bounds are tracked at run granularity by
// the caller.
static inline void qa_wave_fill_px(
    qa_wave_tile* t, int32_t tile_id, int32_t x, int32_t y) {
  const int32_t width = g_wave_job.width;
  g_wave_job.filled[(size_t)y * width + x] = 255;
  if (x == t->px0 && x > 0) {
    qa_wave_emit(t, tile_id, QA_WAVE_LEFT, y * width + x - 1);
  }
  if (x == t->px1 && x < width - 1) {
    qa_wave_emit(t, tile_id, QA_WAVE_RIGHT, y * width + x + 1);
  }
  if (y == t->py0 && y > 0) {
    qa_wave_emit(t, tile_id, QA_WAVE_UP, (y - 1) * width + x);
  }
  if (y == t->py1 && y < g_wave_job.height - 1) {
    qa_wave_emit(t, tile_id, QA_WAVE_DOWN, (y + 1) * width + x);
  }
}

// Pool job adapter: item index -> current wave's tile id.
static void qa_wave_flood_wave_item(int32_t item_index, void* context);

// Local scanline flood of ONE tile: consumes the tile's fresh pending
// seeds, never reads outside [px0..px1]x[py0..py1]. Runs inside one
// pool worker; everything it writes is tile-owned.
static void qa_wave_flood_tile(int32_t tile_id, void* context) {
  (void)context;
  qa_wave_tile* t = &g_wave.tiles[tile_id];
  const uint8_t* rgb = g_wave_job.rgb;
  uint8_t* filled = g_wave_job.filled;
  const int32_t width = g_wave_job.width;
  const uint32_t seed = g_wave_job.seed;
  const int32_t tolerance = g_wave_job.tolerance;
#ifdef QA_FLOOD_SIMD
  const qa_vec4 seed4 = qa_vec4_splat(seed);
  const qa_vec4 tol4 = qa_vec4_splat(qa_tol_lanes(tolerance));
#endif

  if (g_wave_local_stack == NULL) {
    g_wave_local_stack =
        (int32_t*)malloc(sizeof(int32_t) * QA_WAVE_LOCAL_STACK);
    if (g_wave_local_stack == NULL) {
      t->error = 1;
      return;
    }
  }
  int32_t* stack = g_wave_local_stack;
  int32_t stack_size = 0;

  const int32_t* pending = qa_wave_pending_of(tile_id);
  const int32_t pending_end = t->pending_count;
  for (int32_t i = t->pending_taken; i < pending_end; i += 1) {
    const int32_t p = pending[i];
    if (filled[p] == 0) {
      if (!qa_tol_ok1(
              rgb + ((ptrdiff_t)p << 2), seed, tolerance)) {
        continue;
      }
      const int32_t x = p % width;
      const int32_t y = p / width;
      qa_wave_fill_px(t, tile_id, x, y);
      if (x < t->min_x) t->min_x = x;
      if (x > t->max_x) t->max_x = x;
      if (y < t->min_y) t->min_y = y;
      if (y > t->max_y) t->max_y = y;
    }
    if (stack_size >= QA_WAVE_LOCAL_STACK) {
      t->error = 1;
      return;
    }
    stack[stack_size] = p;
    stack_size += 1;
  }
  t->pending_taken = pending_end;

  while (stack_size > 0) {
    stack_size -= 1;
    const int32_t index = stack[stack_size];
    const int32_t y = index / width;
    const int32_t row_start = y * width;

    // Expand the run left/right WITHIN the tile (SSE2 on the interior;
    // scalar owns edge pixels so crossings always emit).
    int32_t left = index - row_start;
    {
      int32_t x = left - 1;
#ifdef QA_FLOOD_SIMD
      if (y > t->py0 && y < t->py1) {
        while (x - 3 > t->px0) {
          uint32_t f4;
          memcpy(&f4, filled + row_start + x - 3, 4);
          if (f4 != 0) {
            break;
          }
          if (qa_tol_ok4(
                  rgb + ((ptrdiff_t)(row_start + x - 3) << 2), seed4, tol4) !=
              0xF) {
            break;
          }
          memset(filled + row_start + x - 3, 255, 4);
          x -= 4;
        }
      }
#endif
      while (x >= t->px0) {
        const int32_t p = row_start + x;
        if (filled[p] != 0 ||
            !qa_tol_ok1(
                rgb + ((ptrdiff_t)p << 2), seed,
                tolerance)) {
          break;
        }
        qa_wave_fill_px(t, tile_id, x, y);
        x -= 1;
      }
      left = x + 1;
    }
    int32_t right = index - row_start;
    {
      int32_t x = right + 1;
#ifdef QA_FLOOD_SIMD
      if (y > t->py0 && y < t->py1) {
        while (x + 3 < t->px1) {
          uint32_t f4;
          memcpy(&f4, filled + row_start + x, 4);
          if (f4 != 0) {
            break;
          }
          if (qa_tol_ok4(
                  rgb + ((ptrdiff_t)(row_start + x) << 2), seed4, tol4) !=
              0xF) {
            break;
          }
          memset(filled + row_start + x, 255, 4);
          x += 4;
        }
      }
#endif
      while (x <= t->px1) {
        const int32_t p = row_start + x;
        if (filled[p] != 0 ||
            !qa_tol_ok1(
                rgb + ((ptrdiff_t)p << 2), seed,
                tolerance)) {
          break;
        }
        qa_wave_fill_px(t, tile_id, x, y);
        x += 1;
      }
      right = x - 1;
    }
    if (left < t->min_x) t->min_x = left;
    if (right > t->max_x) t->max_x = right;
    if (y < t->min_y) t->min_y = y;
    if (y > t->max_y) t->max_y = y;

    // Seed the rows above/below WITHIN the tile (crossings to the rows
    // outside were already emitted when the edge-row pixels filled).
    for (int32_t direction = 0; direction < 2; direction += 1) {
      const int32_t neighbor_y = direction == 0 ? y - 1 : y + 1;
      if (neighbor_y < t->py0 || neighbor_y > t->py1) {
        continue;
      }
      const int32_t neighbor_row = neighbor_y * width;
      int32_t run_open = 0;
      for (int32_t x = left; x <= right; x += 1) {
        const int32_t p = neighbor_row + x;
        if (filled[p] == 0 &&
            qa_tol_ok1(
                rgb + ((ptrdiff_t)p << 2), seed,
                tolerance)) {
          if (!run_open) {
            qa_wave_fill_px(t, tile_id, x, neighbor_y);
            if (stack_size >= QA_WAVE_LOCAL_STACK) {
              t->error = 1;
              return;
            }
            stack[stack_size] = p;
            stack_size += 1;
            run_open = 1;
          }
        } else {
          run_open = 0;
        }
      }
    }
  }
}

static void qa_wave_flood_wave_item(int32_t item_index, void* context) {
  (void)context;
  qa_wave_flood_tile(g_wave.wave_list[item_index], NULL);
}

// qa_flood_fill_wave's round, run by the caller that holds the arena.
static int32_t qa_flood_fill_wave_owned(
    const uint8_t* rgb,
    uint8_t* filled,
    const uint8_t* composed,
    int32_t width,
    int32_t height,
    int32_t compose_tile_shift,
    int32_t tiles_x,
    uint32_t seed,
    int32_t tolerance,
    int32_t* stack,
    int32_t* stack_size,
    int32_t* candidates,
    int32_t candidates_capacity,
    int32_t* bounds) {
  const int32_t tile_size = 1 << compose_tile_shift;
  const int32_t tiles_y = (height + tile_size - 1) >> compose_tile_shift;
  const int32_t tile_count = tiles_x * tiles_y;
  if (!qa_wave_arena_ensure(tile_count, tile_size)) {
    return -1;
  }

  // Per-call reset of tile bookkeeping (geometry + counters).
  for (int32_t ty = 0; ty < tiles_y; ty += 1) {
    for (int32_t tx = 0; tx < tiles_x; tx += 1) {
      qa_wave_tile* t = &g_wave.tiles[ty * tiles_x + tx];
      t->px0 = tx << compose_tile_shift;
      t->py0 = ty << compose_tile_shift;
      t->px1 = t->px0 + tile_size - 1;
      if (t->px1 > width - 1) t->px1 = width - 1;
      t->py1 = t->py0 + tile_size - 1;
      if (t->py1 > height - 1) t->py1 = height - 1;
      t->min_x = width;
      t->max_x = -1;
      t->min_y = height;
      t->max_y = -1;
      t->pending_count = 0;
      t->pending_taken = 0;
      t->out_count[0] = t->out_count[1] = t->out_count[2] = t->out_count[3] =
          0;
      t->out_routed[0] = t->out_routed[1] = t->out_routed[2] =
          t->out_routed[3] = 0;
      t->in_wave = 0;
      t->queued = 0;
      t->error = 0;
    }
  }

  int32_t candidate_count = 0;
  int32_t queue_count = 0;

  // Route one pixel to its tile's pending list (composed) or to the
  // candidate buffer (uncomposed). Serial phases only.
#define QA_WAVE_ROUTE(pixel_index)                                          \
  do {                                                                      \
    const int32_t rp_ = (pixel_index);                                      \
    const int32_t rx_ = rp_ % width;                                        \
    const int32_t ry_ = rp_ / width;                                        \
    const int32_t rt_ = (ry_ >> compose_tile_shift) * tiles_x +             \
                        (rx_ >> compose_tile_shift);                        \
    if (composed[rt_] == 0) {                                               \
      if (candidate_count >= candidates_capacity) {                         \
        return -1;                                                          \
      }                                                                     \
      candidates[candidate_count] = rp_;                                    \
      candidate_count += 1;                                                 \
    } else {                                                                \
      qa_wave_tile* rtile_ = &g_wave.tiles[rt_];                            \
      if (rtile_->pending_count >= g_wave.pending_capacity_per_tile) {      \
        return -1;                                                          \
      }                                                                     \
      qa_wave_pending_of(rt_)[rtile_->pending_count] = rp_;                 \
      rtile_->pending_count += 1;                                           \
      if (!rtile_->queued) {                                                \
        rtile_->queued = 1;                                                 \
        g_wave.queue_list[queue_count] = rt_;                               \
        queue_count += 1;                                                   \
      }                                                                     \
    }                                                                       \
  } while (0)

  // Distribute the driver's seeds. Seeds the DRIVER filled (the
  // original seed and re-seeded candidates) never went through the
  // engine's fill-time crossing emission, so a driver-filled seed
  // sitting on a tile edge routes its cross-tile 4-neighbors here
  // directly (serial phase; in-tile neighbors are covered by the
  // seed's own expansion).
  const int32_t tile_mask = tile_size - 1;
  for (int32_t i = 0; i < *stack_size; i += 1) {
    const int32_t p = stack[i];
    QA_WAVE_ROUTE(p);
    if (filled[p] != 0) {
      const int32_t x = p % width;
      const int32_t y = p / width;
      if ((x & tile_mask) == 0 && x > 0) {
        QA_WAVE_ROUTE(p - 1);
      }
      if ((x & tile_mask) == tile_mask && x < width - 1) {
        QA_WAVE_ROUTE(p + 1);
      }
      if ((y & tile_mask) == 0 && y > 0) {
        QA_WAVE_ROUTE(p - width);
      }
      if ((y & tile_mask) == tile_mask && y < height - 1) {
        QA_WAVE_ROUTE(p + width);
      }
    }
  }
  *stack_size = 0;

  g_wave_job.rgb = rgb;
  g_wave_job.filled = filled;
  g_wave_job.width = width;
  g_wave_job.height = height;
  g_wave_job.seed = seed;
  g_wave_job.tolerance = tolerance;

  while (queue_count > 0) {
    // Wave = every queued tile (all are composed by routing).
    int32_t wave_count = 0;
    for (int32_t i = 0; i < queue_count; i += 1) {
      const int32_t tile_id = g_wave.queue_list[i];
      qa_wave_tile* t = &g_wave.tiles[tile_id];
      t->queued = 0;
      if (t->pending_taken < t->pending_count) {
        g_wave.wave_list[wave_count] = tile_id;
        wave_count += 1;
      }
    }
    queue_count = 0;
    if (wave_count == 0) {
      break;
    }

    // Parallel local floods (tile-owned writes only).
    if (wave_count == 1) {
      qa_wave_flood_tile(g_wave.wave_list[0], NULL);
    } else {
      qa_pool_run(qa_wave_flood_wave_item, NULL, wave_count);
    }

    // Serial routing of the new crossings.
    for (int32_t i = 0; i < wave_count; i += 1) {
      const int32_t tile_id = g_wave.wave_list[i];
      qa_wave_tile* t = &g_wave.tiles[tile_id];
      if (t->error) {
        return -1;
      }
      for (int edge = 0; edge < 4; edge += 1) {
        const int32_t* out = qa_wave_out_of(tile_id, edge);
        for (int32_t j = t->out_routed[edge]; j < t->out_count[edge];
             j += 1) {
          QA_WAVE_ROUTE(out[j]);
        }
        t->out_routed[edge] = t->out_count[edge];
      }
    }
  }
#undef QA_WAVE_ROUTE

  // Merge per-tile bounds.
  int32_t min_x = bounds[0];
  int32_t max_x = bounds[1];
  int32_t min_y = bounds[2];
  int32_t max_y = bounds[3];
  for (int32_t i = 0; i < tile_count; i += 1) {
    const qa_wave_tile* t = &g_wave.tiles[i];
    if (t->max_x < 0) {
      continue;
    }
    if (t->min_x < min_x) min_x = t->min_x;
    if (t->max_x > max_x) max_x = t->max_x;
    if (t->min_y < min_y) min_y = t->min_y;
    if (t->max_y > max_y) max_y = t->max_y;
  }
  bounds[0] = min_x;
  bounds[1] = max_x;
  bounds[2] = min_y;
  bounds[3] = max_y;
  return candidate_count;
}

// The arena (g_wave, g_wave_job) is one for the process, like the pool:
// one fill at a time holds it, and another finds the round failed (card
// clip-import-hangs-on-three-samples, 2026-10-23).
static qa_claim_flag g_wave_owned;

// One full lazy-protocol round: floods EVERYTHING reachable through
// currently-composed tiles (wave-parallel), returns crossings into
// uncomposed tiles as candidates (same contract as the sequential
// stepper: the driver composes them, re-seeds the matches, re-enters).
// stack in: the driver's seeds; out: always fully consumed (0).
// Returns the candidate count, or -1 on any allocation/bound failure or
// while another fill holds the arena - the caller redoes the fill on the
// sequential path from clean state.
QA_EXPORT int32_t qa_flood_fill_wave(
    const uint8_t* rgb,
    uint8_t* filled,
    const uint8_t* composed,
    int32_t width,
    int32_t height,
    int32_t compose_tile_shift,
    int32_t tiles_x,
    uint32_t seed,
    int32_t tolerance,
    int32_t* stack,
    int32_t* stack_size,
    int32_t* candidates,
    int32_t candidates_capacity,
    int32_t* bounds) {
  if (!qa_claim(&g_wave_owned)) {
    return -1;
  }
  const int32_t candidate_count = qa_flood_fill_wave_owned(
      rgb, filled, composed, width, height, compose_tile_shift, tiles_x,
      seed, tolerance, stack, stack_size, candidates,
      candidates_capacity, bounds);
  qa_release(&g_wave_owned);
  return candidate_count;
}

// --- Tile allocator (R20-E1) -----------------------------------------------
//
// Exact-size free-list recycler for tile pixel buffers. Tiles churn hard:
// every commit ADOPTS its scratch buffers as finished tiles (R19-Z), so
// buffers leave the acquire/release cycle and only come back when the GC
// finalizes old tiles - with plain malloc that meant ~1024 fresh mallocs
// per full-canvas 8K fill. Freed tile blocks now park on per-size free
// lists and are handed straight back to the next allocation.
//
// qa_tile_free doubles as the Dart NativeFinalizer callback, which runs
// on GC threads - all pool state is mutex-guarded.

#include <stdlib.h>

#if defined(_WIN32)
static SRWLOCK g_tile_pool_lock = SRWLOCK_INIT;
#define QA_TILE_LOCK() AcquireSRWLockExclusive(&g_tile_pool_lock)
#define QA_TILE_UNLOCK() ReleaseSRWLockExclusive(&g_tile_pool_lock)
#else
#include <pthread.h>
static pthread_mutex_t g_tile_pool_lock = PTHREAD_MUTEX_INITIALIZER;
#define QA_TILE_LOCK() pthread_mutex_lock(&g_tile_pool_lock)
#define QA_TILE_UNLOCK() pthread_mutex_unlock(&g_tile_pool_lock)
#endif

typedef struct qa_tile_block {
  struct qa_tile_block* next;  // free-list link (meaningful only while free)
  int64_t size;                // user-visible byte length
} qa_tile_block;  // 16-byte header keeps the user data 16-byte aligned

#define QA_TILE_BUCKETS 8
// Total bytes allowed to park across all buckets: one full 8K frame of
// tiles (256MB) plus headroom for a previous frame still draining.
#define QA_TILE_POOL_BYTE_CAP (512ll * 1024 * 1024)

static int64_t g_tile_bucket_sizes[QA_TILE_BUCKETS];
static qa_tile_block* g_tile_bucket_heads[QA_TILE_BUCKETS];
static int64_t g_tile_pool_cached_bytes = 0;
// The cap in force. The define above is where it starts; the memory tab's
// allowance moves it through qa_tile_pool_set_byte_cap (ABI 36).
static int64_t g_tile_pool_byte_cap = QA_TILE_POOL_BYTE_CAP;

QA_EXPORT void* qa_tile_alloc(int64_t size) {
  if (size <= 0) {
    return NULL;
  }
  QA_TILE_LOCK();
  for (int i = 0; i < QA_TILE_BUCKETS; i += 1) {
    if (g_tile_bucket_sizes[i] == size && g_tile_bucket_heads[i] != NULL) {
      qa_tile_block* block = g_tile_bucket_heads[i];
      g_tile_bucket_heads[i] = block->next;
      g_tile_pool_cached_bytes -= size;
      QA_TILE_UNLOCK();
      return (void*)(block + 1);
    }
  }
  QA_TILE_UNLOCK();
  qa_tile_block* block =
      (qa_tile_block*)malloc(sizeof(qa_tile_block) + (size_t)size);
  if (block == NULL) {
    return NULL;
  }
  block->next = NULL;
  block->size = size;
  return (void*)(block + 1);
}

// Parks the block for reuse, or frees it past the byte cap. The signature
// is exactly Dart's NativeFinalizerFunction: tile finalizers call this
// directly. Only pointers returned by qa_tile_alloc may be passed.
QA_EXPORT void qa_tile_free(void* pixels) {
  if (pixels == NULL) {
    return;
  }
  qa_tile_block* block = ((qa_tile_block*)pixels) - 1;
  const int64_t size = block->size;
  QA_TILE_LOCK();
  if (g_tile_pool_cached_bytes + size <= g_tile_pool_byte_cap) {
    int slot = -1;
    for (int i = 0; i < QA_TILE_BUCKETS; i += 1) {
      if (g_tile_bucket_sizes[i] == size) {
        slot = i;
        break;
      }
    }
    if (slot < 0) {
      // Claim an idle bucket for this size (empty lists can be re-keyed).
      for (int i = 0; i < QA_TILE_BUCKETS; i += 1) {
        if (g_tile_bucket_heads[i] == NULL) {
          g_tile_bucket_sizes[i] = size;
          slot = i;
          break;
        }
      }
    }
    if (slot >= 0) {
      block->next = g_tile_bucket_heads[slot];
      g_tile_bucket_heads[slot] = block;
      g_tile_pool_cached_bytes += size;
      QA_TILE_UNLOCK();
      return;
    }
  }
  QA_TILE_UNLOCK();
  free(block);
}

QA_EXPORT int64_t qa_tile_pool_cached_bytes(void) {
  QA_TILE_LOCK();
  const int64_t bytes = g_tile_pool_cached_bytes;
  QA_TILE_UNLOCK();
  return bytes;
}

// Releases every parked block: on a memory warning, and in tests.
QA_EXPORT void qa_tile_pool_trim(void) {
  QA_TILE_LOCK();
  for (int i = 0; i < QA_TILE_BUCKETS; i += 1) {
    qa_tile_block* block = g_tile_bucket_heads[i];
    while (block != NULL) {
      qa_tile_block* next = block->next;
      free(block);
      block = next;
    }
    g_tile_bucket_heads[i] = NULL;
    g_tile_bucket_sizes[i] = 0;
  }
  g_tile_pool_cached_bytes = 0;
  QA_TILE_UNLOCK();
}

// Sets the cap (ABI 36), releasing parked blocks until what is parked fits
// under it - a lowered cap must not wait for the next free to take effect.
QA_EXPORT void qa_tile_pool_set_byte_cap(int64_t bytes) {
  QA_TILE_LOCK();
  g_tile_pool_byte_cap = bytes < 0 ? 0 : bytes;
  for (int i = 0; i < QA_TILE_BUCKETS; i += 1) {
    while (g_tile_bucket_heads[i] != NULL &&
           g_tile_pool_cached_bytes > g_tile_pool_byte_cap) {
      qa_tile_block* block = g_tile_bucket_heads[i];
      g_tile_bucket_heads[i] = block->next;
      g_tile_pool_cached_bytes -= block->size;
      free(block);
    }
    if (g_tile_bucket_heads[i] == NULL) {
      g_tile_bucket_sizes[i] = 0;
    }
  }
  QA_TILE_UNLOCK();
}

// ---------------------------------------------------------------------------
// Grid tile rasterizer (UI-R18 O7 / R18-T T1): the timeline frame grids
// pre-raster their cell strips into RGBA tiles OFF the UI thread. The op
// stream is a flat int32 word list - deterministic INTEGER rasterization
// (byte-rounded source-over, the fill-compose arithmetic), so the output
// bytes are pinned against the Dart reference implementation by parity
// tests and identical on every platform/worker-count.
//
// OP colors pack as memory-order RGBA words: r | g<<8 | b<<16 | a<<24,
// STRAIGHT (non-premultiplied) alpha. The background word is written
// VERBATIM (pass 0 for a fully transparent tile); accumulating
// source-over from transparent black produces PREMULTIPLIED output
// bytes - the image upload's contract - so tiles composite pixel-true
// over any panel background.
//
// Op stream layout (int32 words, count validated - a truncated op makes
// the call return negative without touching remaining pixels):
//   QA_GRID_OP_FILL_RECT (1): x, y, w, h, rgba            = 6 words
//   QA_GRID_OP_HLINE     (2): x, y, length, thickness, rgba = 6 words
//   QA_GRID_OP_VLINE     (3): x, y, length, thickness, rgba = 6 words
//   QA_GRID_OP_GLYPH     (4): dest_x, dest_y, atlas_x, atlas_y,
//                             w, h, rgba                  = 8 words
// Glyph coverage reads the A8 atlas and scales the color's alpha per
// pixel. Every op clips to the tile (and the glyph also to the atlas);
// fully off-tile ops are no-ops, never errors.

enum {
  QA_GRID_OP_FILL_RECT = 1,
  QA_GRID_OP_HLINE = 2,
  QA_GRID_OP_VLINE = 3,
  QA_GRID_OP_GLYPH = 4,
  // The rounded-rect fill (T2: the cell BLOCK chrome - block start/end
  // corners round, so the tile path needs analytic-AA corners to match the
  // Skia painter's look):
  //   QA_GRID_OP_RRECT_FILL   (5): x_q8, y_q8, w_q8, h_q8, radius_q8,
  //                                corner_mask, rgba         = 8 words
  // Every _q8 field is 24.8 fixed point (pixels * 256): cell rects are
  // FRACTIONAL at fractional zooms, so the whole geometry rides
  // sub-pixel. corner_mask bit0=TL, bit1=TR, bit2=BL, bit3=BR (unset
  // corners stay square). AA coverage comes from the rounded-box SDF
  // with float sqrt - IEEE correctly-rounded, so bytes stay identical
  // across platforms.
  QA_GRID_OP_RRECT_FILL = 5,
  // The rounded-rect RING (I-129, 2026-10-25: an EMPTY block's outline,
  // the export Cels tab's hollow block on the timeline's blocks):
  //   QA_GRID_OP_RRECT_RING   (6): x_q8, y_q8, w_q8, h_q8, radius_q8,
  //                                corner_mask, line_q8, open_mask,
  //                                rgba                      = 10 words
  // The RRECT_FILL coverage of the box less that of the box line_q8 in
  // from each side, its corners line_q8 tighter. open_mask bit0=left,
  // bit1=top, bit2=right, bit3=bottom names the sides it leaves OPEN: a
  // block a tile's span cuts runs on into the next tile, which must not
  // see a seam there.
  // <- 6 was the per-cell block border's STROKE once: D32/D38 (2026-08-18)
  // made that border transparent for good, and it left the Dart writer,
  // the Dart reference and this engine together with the substrate
  // rewrite of 2026-09-24.
  QA_GRID_OP_RRECT_RING = 6,
};

static inline void qa_grid_blend_span(
    uint8_t* dst,
    int32_t count,
    int32_t r,
    int32_t g,
    int32_t b,
    int32_t a) {
  if (a >= 255) {
    for (int32_t i = 0; i < count; i += 1) {
      dst[0] = (uint8_t)r;
      dst[1] = (uint8_t)g;
      dst[2] = (uint8_t)b;
      dst[3] = 255;
      dst += 4;
    }
    return;
  }
  const int32_t inv = 255 - a;
  for (int32_t i = 0; i < count; i += 1) {
    dst[0] = (uint8_t)((r * a + dst[0] * inv + 127) / 255);
    dst[1] = (uint8_t)((g * a + dst[1] * inv + 127) / 255);
    dst[2] = (uint8_t)((b * a + dst[2] * inv + 127) / 255);
    dst[3] = (uint8_t)(255 - ((255 - dst[3]) * inv + 127) / 255);
    dst += 4;
  }
}

static void qa_grid_blend_rect(
    uint8_t* pixels,
    int32_t tile_width,
    int32_t tile_height,
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h,
    uint32_t rgba) {
  const int32_t a = (int32_t)(rgba >> 24) & 0xFF;
  if (a == 0 || w <= 0 || h <= 0) {
    return;
  }
  int32_t left = x < 0 ? 0 : x;
  int32_t top = y < 0 ? 0 : y;
  int32_t right = x + w;
  int32_t bottom = y + h;
  if (right > tile_width) right = tile_width;
  if (bottom > tile_height) bottom = tile_height;
  if (left >= right || top >= bottom) {
    return;
  }
  const int32_t r = (int32_t)rgba & 0xFF;
  const int32_t g = (int32_t)(rgba >> 8) & 0xFF;
  const int32_t b = (int32_t)(rgba >> 16) & 0xFF;
  for (int32_t row = top; row < bottom; row += 1) {
    qa_grid_blend_span(
        pixels + (((ptrdiff_t)row * tile_width + left) << 2),
        right - left, r, g, b, a);
  }
}

// Signed distance of the pixel center to a rounded box with PER-CORNER
// radii (0 = square corner). The quadrant of the pixel picks its corner
// radius. DOUBLE math throughout: the Dart reference computes with
// doubles, and +,-,*,/,sqrt are IEEE correctly rounded in both - so the
// two sides stay byte-identical (a float sqrtf would round differently).
static inline double qa_grid_rrect_distance(
    double cx,
    double cy,
    double center_x,
    double center_y,
    double half_w,
    double half_h,
    double radius_tl,
    double radius_tr,
    double radius_bl,
    double radius_br) {
  const double rx = cx - center_x;
  const double ry = cy - center_y;
  double r;
  if (rx < 0.0) {
    r = ry < 0.0 ? radius_tl : radius_bl;
  } else {
    r = ry < 0.0 ? radius_tr : radius_br;
  }
  const double ax = (rx < 0.0 ? -rx : rx) - (half_w - r);
  const double ay = (ry < 0.0 ? -ry : ry) - (half_h - r);
  const double mx = ax > 0.0 ? ax : 0.0;
  const double my = ay > 0.0 ? ay : 0.0;
  const double outside = sqrt(mx * mx + my * my);
  const double inside_axis = ax > ay ? ax : ay;
  const double inside = inside_axis < 0.0 ? inside_axis : 0.0;
  return outside + inside - r;
}

// A rounded box's coverage field: the box, its centre and halves, and each
// corner's radius (0 = square) - RRECT_FILL's box, and both of a ring's.
typedef struct {
  double left;
  double top;
  double width;
  double height;
  double center_x;
  double center_y;
  double half_w;
  double half_h;
  double radius_tl;
  double radius_tr;
  double radius_bl;
  double radius_br;
} qa_grid_rrect_field;

// The box (x, y, w, h) with [radius] on the corners [corner_mask] picks,
// held to what the box can hold.
static qa_grid_rrect_field qa_grid_rrect_field_of(
    double x,
    double y,
    double w,
    double h,
    double radius,
    int32_t corner_mask) {
  qa_grid_rrect_field field;
  field.left = x;
  field.top = y;
  field.width = w;
  field.height = h;
  field.half_w = w * 0.5;
  field.half_h = h * 0.5;
  field.center_x = x + field.half_w;
  field.center_y = y + field.half_h;
  const double max_radius =
      field.half_w < field.half_h ? field.half_w : field.half_h;
  if (radius > max_radius) {
    radius = max_radius;
  }
  field.radius_tl = (corner_mask & 1) != 0 ? radius : 0.0;
  field.radius_tr = (corner_mask & 2) != 0 ? radius : 0.0;
  field.radius_bl = (corner_mask & 4) != 0 ? radius : 0.0;
  field.radius_br = (corner_mask & 8) != 0 ? radius : 0.0;
  return field;
}

// The box an RRECT_FILL or RRECT_RING op at [op] states: its x_q8, y_q8,
// w_q8, h_q8, radius_q8 and corner_mask words.
static qa_grid_rrect_field qa_grid_rrect_field_at(const int32_t* op) {
  return qa_grid_rrect_field_of(
      (double)op[1] / 256.0, (double)op[2] / 256.0, (double)op[3] / 256.0,
      (double)op[4] / 256.0, (double)op[5] / 256.0, op[6]);
}

// A ring's inner corner: its outer corner [line] tighter, never below
// square nor past what the inner box can hold.
static inline double qa_grid_ring_inner_radius(
    double outer,
    double line,
    double max_radius) {
  double radius = outer - line;
  if (radius < 0.0) {
    radius = 0.0;
  }
  if (radius > max_radius) {
    radius = max_radius;
  }
  return radius;
}

// The box a ring of [outer] leaves unpainted: [line] in from each side it
// strokes and [line] + 2 past each side [open_mask] leaves open, its
// corners [line] tighter.
static qa_grid_rrect_field qa_grid_ring_inner_field(
    const qa_grid_rrect_field* outer,
    double line,
    int32_t open_mask) {
  const double past = line + 2.0;
  const double left = outer->left + ((open_mask & 1) != 0 ? -past : line);
  const double top = outer->top + ((open_mask & 2) != 0 ? -past : line);
  const double right =
      outer->left + outer->width - ((open_mask & 4) != 0 ? -past : line);
  const double bottom =
      outer->top + outer->height - ((open_mask & 8) != 0 ? -past : line);
  qa_grid_rrect_field field;
  field.left = left;
  field.top = top;
  field.width = right - left;
  field.height = bottom - top;
  field.half_w = field.width * 0.5;
  field.half_h = field.height * 0.5;
  field.center_x = left + field.half_w;
  field.center_y = top + field.half_h;
  const double max_radius =
      field.half_w < field.half_h ? field.half_w : field.half_h;
  field.radius_tl = qa_grid_ring_inner_radius(outer->radius_tl, line,
                                              max_radius);
  field.radius_tr = qa_grid_ring_inner_radius(outer->radius_tr, line,
                                              max_radius);
  field.radius_bl = qa_grid_ring_inner_radius(outer->radius_bl, line,
                                              max_radius);
  field.radius_br = qa_grid_ring_inner_radius(outer->radius_br, line,
                                              max_radius);
  return field;
}

// How much of the pixel centred at (cx, cy) [field] covers: analytic-AA
// 0.5 - d from the rounded-box SDF, held to [0, 1].
static inline double qa_grid_rrect_coverage(
    const qa_grid_rrect_field* field,
    double cx,
    double cy) {
  const double coverage = 0.5 - qa_grid_rrect_distance(
      cx, cy, field->center_x, field->center_y, field->half_w,
      field->half_h, field->radius_tl, field->radius_tr, field->radius_bl,
      field->radius_br);
  return coverage <= 0.0 ? 0.0 : coverage > 1.0 ? 1.0 : coverage;
}

// The RRECT_FILL and RRECT_RING raster loop: [outer]'s coverage less
// [inner]'s (NULL for none), blended source-over per pixel.
static void qa_grid_blend_rrect_band(
    uint8_t* pixels,
    int32_t tile_width,
    int32_t tile_height,
    const qa_grid_rrect_field* outer,
    const qa_grid_rrect_field* inner,
    uint32_t rgba) {
  const int32_t color_a = (int32_t)(rgba >> 24) & 0xFF;
  if (color_a == 0 || outer->width <= 0.0 || outer->height <= 0.0) {
    return;
  }
  if (inner != NULL && (inner->half_w <= 0.0 || inner->half_h <= 0.0)) {
    inner = NULL;
  }
  int32_t left = (int32_t)(outer->left - 1.0);
  int32_t top = (int32_t)(outer->top - 1.0);
  int32_t right = (int32_t)(outer->left + outer->width + 2.0);
  int32_t bottom = (int32_t)(outer->top + outer->height + 2.0);
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (right > tile_width) right = tile_width;
  if (bottom > tile_height) bottom = tile_height;

  const int32_t r = (int32_t)rgba & 0xFF;
  const int32_t g = (int32_t)(rgba >> 8) & 0xFF;
  const int32_t b = (int32_t)(rgba >> 16) & 0xFF;
  for (int32_t py = top; py < bottom; py += 1) {
    uint8_t* dst = pixels + (((ptrdiff_t)py * tile_width + left) << 2);
    for (int32_t px = left; px < right; px += 1) {
      const double cx = (double)px + 0.5;
      const double cy = (double)py + 0.5;
      double coverage = qa_grid_rrect_coverage(outer, cx, cy);
      if (coverage > 0.0 && inner != NULL) {
        coverage -= qa_grid_rrect_coverage(inner, cx, cy);
      }
      if (coverage > 0.0) {
        const int32_t a = (int32_t)(coverage * (double)color_a + 0.5);
        qa_grid_blend_span(dst, 1, r, g, b, a);
      }
      dst += 4;
    }
  }
}

QA_EXPORT int32_t qa_grid_raster_tile(
    uint8_t* pixels,
    int32_t tile_width,
    int32_t tile_height,
    uint32_t background_rgba,
    const int32_t* ops,
    int32_t op_word_count,
    const uint8_t* atlas,
    int32_t atlas_width,
    int32_t atlas_height) {
  if (pixels == NULL || tile_width <= 0 || tile_height <= 0) {
    return -1;
  }
  // Background fill VERBATIM (T2: 0 = fully transparent). Source-over
  // accumulation from transparent black yields PREMULTIPLIED bytes
  // natively (src.rgb*a + dst.rgb*(1-a)), which is exactly what the
  // image upload expects (the fill overlay's premultiply contract) - so
  // tiles composite pixel-true over ANY panel background.
  {
    const uint32_t bg = background_rgba;
    uint32_t* dst = (uint32_t*)pixels;
    const ptrdiff_t count = (ptrdiff_t)tile_width * tile_height;
    for (ptrdiff_t i = 0; i < count; i += 1) {
      dst[i] = bg;
    }
  }
  if (ops == NULL || op_word_count <= 0) {
    return 0;
  }

  int32_t cursor = 0;
  while (cursor < op_word_count) {
    const int32_t op = ops[cursor];
    switch (op) {
      case QA_GRID_OP_FILL_RECT: {
        if (cursor + 6 > op_word_count) return -2;
        qa_grid_blend_rect(
            pixels, tile_width, tile_height,
            ops[cursor + 1], ops[cursor + 2], ops[cursor + 3],
            ops[cursor + 4], (uint32_t)ops[cursor + 5]);
        cursor += 6;
        break;
      }
      case QA_GRID_OP_HLINE: {
        if (cursor + 6 > op_word_count) return -2;
        qa_grid_blend_rect(
            pixels, tile_width, tile_height,
            ops[cursor + 1], ops[cursor + 2], ops[cursor + 3],
            ops[cursor + 4], (uint32_t)ops[cursor + 5]);
        cursor += 6;
        break;
      }
      case QA_GRID_OP_VLINE: {
        if (cursor + 6 > op_word_count) return -2;
        qa_grid_blend_rect(
            pixels, tile_width, tile_height,
            ops[cursor + 1], ops[cursor + 2], ops[cursor + 4],
            ops[cursor + 3], (uint32_t)ops[cursor + 5]);
        cursor += 6;
        break;
      }
      case QA_GRID_OP_RRECT_FILL: {
        if (cursor + 8 > op_word_count) return -2;
        const qa_grid_rrect_field box = qa_grid_rrect_field_at(ops + cursor);
        qa_grid_blend_rrect_band(
            pixels, tile_width, tile_height, &box, NULL,
            (uint32_t)ops[cursor + 7]);
        cursor += 8;
        break;
      }
      case QA_GRID_OP_RRECT_RING: {
        if (cursor + 10 > op_word_count) return -2;
        const double line = (double)ops[cursor + 7] / 256.0;
        if (line > 0.0) {
          const qa_grid_rrect_field box = qa_grid_rrect_field_at(ops + cursor);
          const qa_grid_rrect_field hole =
              qa_grid_ring_inner_field(&box, line, ops[cursor + 8]);
          qa_grid_blend_rrect_band(
              pixels, tile_width, tile_height, &box, &hole,
              (uint32_t)ops[cursor + 9]);
        }
        cursor += 10;
        break;
      }
      case QA_GRID_OP_GLYPH: {
        if (cursor + 8 > op_word_count) return -2;
        if (atlas == NULL) return -3;
        const int32_t dest_x = ops[cursor + 1];
        const int32_t dest_y = ops[cursor + 2];
        const int32_t atlas_x = ops[cursor + 3];
        const int32_t atlas_y = ops[cursor + 4];
        const int32_t w = ops[cursor + 5];
        const int32_t h = ops[cursor + 6];
        const uint32_t rgba = (uint32_t)ops[cursor + 7];
        const int32_t color_a = (int32_t)(rgba >> 24) & 0xFF;
        const int32_t r = (int32_t)rgba & 0xFF;
        const int32_t g = (int32_t)(rgba >> 8) & 0xFF;
        const int32_t b = (int32_t)(rgba >> 16) & 0xFF;
        for (int32_t row = 0; row < h; row += 1) {
          const int32_t ty = dest_y + row;
          const int32_t ay = atlas_y + row;
          if (ty < 0 || ty >= tile_height || ay < 0 || ay >= atlas_height) {
            continue;
          }
          for (int32_t col = 0; col < w; col += 1) {
            const int32_t tx = dest_x + col;
            const int32_t ax = atlas_x + col;
            if (tx < 0 || tx >= tile_width || ax < 0 || ax >= atlas_width) {
              continue;
            }
            const int32_t coverage =
                atlas[(ptrdiff_t)ay * atlas_width + ax];
            if (coverage == 0 || color_a == 0) {
              continue;
            }
            const int32_t a = (color_a * coverage + 127) / 255;
            qa_grid_blend_span(
                pixels + (((ptrdiff_t)ty * tile_width + tx) << 2),
                1, r, g, b, a);
          }
        }
        cursor += 8;
        break;
      }
      default:
        return -4;
    }
  }
  return 0;
}

// ---------------------------------------------------------------------
// Audio mixer (audio program 2B).
//
// The mixer does NOT "play clips" - it BUILDS a mix. For any sample range
// [S, S+N) it pulls those exact samples out of every overlapping clip,
// applies gain and fades, and sums. There is no "start the clip" moment,
// so a clip's start accuracy is +/-1 sample no matter how far into the
// movie it sits, and the platform player's 50-200ms start latency (which
// the old path shipped uncompensated, once per cut) stops existing.
//
// Realtime contract: no allocation, no I/O, no locks, no Dart. Everything
// this needs is passed in. A sample outside a source's available window
// contributes SILENCE rather than waiting - the audio callback can never
// block, and keeping the device fed is the caller's job (the streaming
// reader thread lands with the device stage).
//
// Positions are SAMPLES (per channel), never "frames": in this codebase a
// frame is a picture. ProjectFrameRate.frameToSample is what converts.
// ---------------------------------------------------------------------

// One scheduled clip on the timeline. Layout: doubles, then int64s, then
// an even number of int32s - natural alignment, no implicit padding on any
// supported ABI (the loader cross-checks qa_audio_clip_sizeof).
//
// AUDIO-PRO R1 additions: pan arrives as PRECOMPUTED per-channel factors
// (the equal-power cos/sin runs once in Dart - a libm trig call here could
// differ from Dart's by an ulp and break byte parity; sqrt in the fade
// curve is safe because IEEE 754 requires it correctly rounded), the fade
// curve selects the ramp shape, and the volume envelope references a
// shared key array by offset/count (variable-length data cannot live in a
// fixed struct).
typedef struct {
  double gain;
  double pan_left;           // factor for output channel 0 (stereo out)
  double pan_right;          // factor for output channel 1 (stereo out)
  int64_t start_sample;      // timeline position, inclusive
  int64_t end_sample;        // timeline position, exclusive
  int64_t source_offset;     // sample index into the source at start_sample
  int64_t fade_in_samples;   // 0 = none
  int64_t fade_out_samples;  // 0 = none
  int32_t source_index;
  int32_t fade_curve;        // 0 = linear, 1 = equal-power (sqrt ramp)
  int32_t envelope_offset;   // into the shared envelope key array
  int32_t envelope_count;    // 0 = unity envelope
} qa_audio_clip;

// One volume-envelope point: at [sample] (clip-local, from the clip's
// start) the envelope passes [gain]. Between points the value
// interpolates linearly; before the first and after the last it holds.
typedef struct {
  int64_t sample;
  double gain;
} qa_audio_envelope_key;

// A block of decoded samples, interleaved by channel.
//
// [source_start] is the source-sample index that samples[0] holds, which
// is what lets a STREAMED clip present a sliding window through the exact
// same struct a fully-resident one uses: residency is a policy the mixer
// never sees.
typedef struct {
  int64_t source_start;
  int64_t length;  // samples per channel available from source_start
  int32_t channels;
  int32_t reserved;
  const float* samples;
} qa_audio_source;

QA_EXPORT int32_t qa_audio_clip_sizeof(void) {
  return (int32_t)sizeof(qa_audio_clip);
}

QA_EXPORT int32_t qa_audio_source_sizeof(void) {
  return (int32_t)sizeof(qa_audio_source);
}

QA_EXPORT int32_t qa_audio_envelope_key_sizeof(void) {
  return (int32_t)sizeof(qa_audio_envelope_key);
}

// The clip's volume envelope at one timeline position - the same shape the
// Dart path has always used (linear ramps anchored to the clip's own start
// and end).
//
// Deliberately NOT clamped to [0, 1]. The old preview path clamped because
// a platform player's volume tops out at 1.0, while EXPORT applied gain
// exactly - so a clip boosted past unity sounded different in preview than
// in the file. A mix bus has no such ceiling: gain applies exactly here and
// clipping belongs to the output stage, which is where
// qa_audio_bus_to_int16 does it.
// The fade ramp's shape (AUDIO-PRO R1): linear, or the equal-power sqrt
// curve (sum of SQUARES constant across a crossfade, so overlapped fades
// hold loudness instead of dipping). sqrt, not sin, on purpose: IEEE 754
// requires sqrt correctly rounded, so C and Dart produce the same bits.
static double qa_audio_fade_ramp(double ramp, int32_t curve) {
  const double clamped = ramp < 0.0 ? 0.0 : ramp;
  return curve == 1 ? sqrt(clamped) : clamped;
}

// The clip's volume envelope at [position] (clip-local samples): keyed
// gains, linear between keys, held past the ends. Empty = unity. Linear
// scan - envelopes carry a handful of keys, and the arithmetic mirrors
// the Dart reference expression for expression.
static double qa_audio_envelope_at(const qa_audio_envelope_key* keys,
                                   int32_t count,
                                   int64_t position) {
  if (keys == NULL || count <= 0) {
    return 1.0;
  }
  if (position <= keys[0].sample) {
    return keys[0].gain;
  }
  if (position >= keys[count - 1].sample) {
    return keys[count - 1].gain;
  }
  for (int32_t index = 0; index < count - 1; index += 1) {
    const qa_audio_envelope_key* a = &keys[index];
    const qa_audio_envelope_key* b = &keys[index + 1];
    if (position < b->sample) {
      const double span = (double)(b->sample - a->sample);
      if (span <= 0.0) {
        return b->gain;
      }
      const double t = (double)(position - a->sample) / span;
      return a->gain + (b->gain - a->gain) * t;
    }
  }
  return keys[count - 1].gain;
}

static double qa_audio_clip_volume(const qa_audio_clip* clip,
                                   const qa_audio_envelope_key* envelope_keys,
                                   int32_t envelope_key_count,
                                   int64_t position_sample) {
  double volume = clip->gain;
  const int64_t position = position_sample - clip->start_sample;
  if (clip->envelope_count > 0 && envelope_keys != NULL &&
      clip->envelope_offset >= 0 &&
      clip->envelope_offset + clip->envelope_count <= envelope_key_count) {
    volume *= qa_audio_envelope_at(&envelope_keys[clip->envelope_offset],
                                   clip->envelope_count, position);
  }
  if (clip->fade_in_samples > 0 && position < clip->fade_in_samples) {
    const double ramp = (double)position / (double)clip->fade_in_samples;
    volume *= qa_audio_fade_ramp(ramp, clip->fade_curve);
  }
  const int64_t remaining = clip->end_sample - position_sample;
  if (clip->fade_out_samples > 0 && remaining < clip->fade_out_samples) {
    const double ramp = (double)remaining / (double)clip->fade_out_samples;
    volume *= qa_audio_fade_ramp(ramp, clip->fade_curve);
  }
  return volume;
}

// Which source channel feeds output channel [out_channel]: a mono source
// feeds every output channel (a mono SE is heard from both speakers, and
// duplicating it in memory to say so would waste half the RAM animation
// projects spend on sound), and anything wider maps straight across,
// holding the last channel if the output is wider than the source.
static int32_t qa_audio_source_channel(int32_t source_channels,
                                       int32_t out_channel) {
  if (source_channels <= 1) {
    return 0;
  }
  return out_channel < source_channels ? out_channel : source_channels - 1;
}

// Mixes [sample_count] samples starting at timeline sample [start_sample]
// into [out], an interleaved DOUBLE bus of sample_count * out_channels.
//
// The bus is double, not float, on purpose. Pro Tools sums in 64-bit float
// for the same reason: narrowing after every clip would round dozens of
// times per sample in an SE-heavy scene. It also makes the Dart reference
// bit-identical for free - Dart has only 64-bit doubles, so a float bus
// would round in C at points Dart cannot reproduce.
QA_EXPORT void qa_audio_mix(
    const qa_audio_clip* clips,
    int32_t clip_count,
    const qa_audio_source* sources,
    int32_t source_count,
    const qa_audio_envelope_key* envelope_keys,
    int32_t envelope_key_count,
    int64_t start_sample,
    int32_t sample_count,
    int32_t out_channels,
    double* out) {
  if (out == NULL || sample_count <= 0 || out_channels <= 0) {
    return;
  }
  const size_t total = (size_t)sample_count * (size_t)out_channels;
  memset(out, 0, total * sizeof(double));
  if (clips == NULL || sources == NULL || clip_count <= 0 || source_count <= 0) {
    return;
  }

  const int64_t block_end = start_sample + sample_count;
  for (int32_t index = 0; index < clip_count; index += 1) {
    const qa_audio_clip* clip = &clips[index];
    if (clip->source_index < 0 || clip->source_index >= source_count) {
      continue;
    }
    const qa_audio_source* source = &sources[clip->source_index];
    if (source->samples == NULL || source->channels <= 0 ||
        source->length <= 0) {
      continue;
    }

    int64_t from = clip->start_sample > start_sample ? clip->start_sample
                                                     : start_sample;
    int64_t to = clip->end_sample < block_end ? clip->end_sample : block_end;
    for (int64_t position = from; position < to; position += 1) {
      const int64_t source_index =
          clip->source_offset + (position - clip->start_sample);
      const int64_t offset = source_index - source->source_start;
      if (offset < 0 || offset >= source->length) {
        continue;  // Outside the available window: silence, never a wait.
      }
      const double volume = qa_audio_clip_volume(clip, envelope_keys,
                                                 envelope_key_count, position);
      const float* frame = &source->samples[offset * source->channels];
      double* destination =
          &out[(size_t)(position - start_sample) * (size_t)out_channels];
      for (int32_t channel = 0; channel < out_channels; channel += 1) {
        const int32_t source_channel =
            qa_audio_source_channel(source->channels, channel);
        // Pan factors apply on a STEREO bus only (the factors are per
        // output side); any other geometry passes through untouched.
        // Multiplication order mirrors the Dart reference exactly.
        const double factor =
            out_channels == 2
                ? (channel == 0 ? clip->pan_left : clip->pan_right)
                : 1.0;
        destination[channel] +=
            (double)frame[source_channel] * volume * factor;
      }
    }
  }
}

// Output stage: the mix bus to the device's sample format.
QA_EXPORT void qa_audio_bus_to_float(const double* bus,
                                     int32_t count,
                                     float* out) {
  if (bus == NULL || out == NULL) {
    return;
  }
  for (int32_t index = 0; index < count; index += 1) {
    out[index] = (float)bus[index];
  }
}

// Clipping lives HERE, not in the mix: the bus is allowed past unity (that
// is what headroom is), and only the conversion to a fixed-point device
// format has to decide what to do about it. llround matches Dart's
// double.round() - both round half away from zero.
//
// Scaling by 32768 (not 32767) is what makes the whole chain lossless at
// unity gain: a decoder hands us raw/32768 (dr_wav multiplies by the
// literal 0.000030517578125f), so multiplying back by 32768 returns the
// SAME int16 the file held. -32768 survives too, which the 32767
// convention cannot represent. Only +1.0 needs the clamp, since 32768
// does not fit an int16.
QA_EXPORT void qa_audio_bus_to_int16(const double* bus,
                                     int32_t count,
                                     int16_t* out) {
  if (bus == NULL || out == NULL) {
    return;
  }
  for (int32_t index = 0; index < count; index += 1) {
    double value = bus[index];
    if (value > 1.0) {
      value = 1.0;
    } else if (value < -1.0) {
      value = -1.0;
    }
    long long scaled = llround(value * 32768.0);
    if (scaled > 32767) {
      scaled = 32767;
    }
    out[index] = (int16_t)scaled;
  }
}

// ---------------------------------------------------------------------
// Sample-rate conversion (audio program 2B) - the C twin of
// lib/src/services/audio/audio_resampler_reference.dart.
//
// Kaiser-windowed sinc, run in polyphase form. LINEAR PHASE, and the
// constant group delay is cancelled in the INDEX ARITHMETIC rather than by
// trimming afterwards: at these filter lengths the delay exceeds a frame
// at 24fps, so an uncompensated conform would put every resampled clip a
// frame late - the exact defect this program exists to remove.
//
// Every expression here mirrors the Dart line for line, including the
// Bessel series' termination, because the parity suite compares the two
// bit for bit. Arithmetic is double throughout for the same reason.
//
// Not realtime: conforming happens once at import.
// ---------------------------------------------------------------------

static int64_t qa_audio_gcd(int64_t a, int64_t b) {
  int64_t x = a < 0 ? -a : a;
  int64_t y = b < 0 ? -b : b;
  while (y != 0) {
    const int64_t t = x % y;
    x = y;
    y = t;
  }
  return x;
}

// Modified Bessel function of the first kind, order 0 - the Kaiser
// window's kernel. FIXED termination (relative epsilon, hard cap) so both
// sides run the identical number of terms; a loop that stopped "when it
// looks converged" would be a parity hazard.
static double qa_audio_bessel_i0(double x) {
  const double half = x / 2.0;
  double term = 1.0;
  double sum = 1.0;
  for (int32_t k = 1; k <= 64; k += 1) {
    const double ratio = half / (double)k;
    term *= ratio * ratio;
    sum += term;
    if (term < sum * 1e-16) {
      break;
    }
  }
  return sum;
}

static double qa_audio_kaiser_beta(double stopband_db) {
  if (stopband_db > 50.0) {
    return 0.1102 * (stopband_db - 8.7);
  }
  if (stopband_db >= 21.0) {
    return 0.5842 * pow(stopband_db - 21.0, 0.4) +
           0.07886 * (stopband_db - 21.0);
  }
  return 0.0;
}

static double qa_audio_sinc(double x) {
  if (x == 0.0) {
    return 1.0;
  }
  const double pix = 3.14159265358979323846 * x;
  return sin(pix) / pix;
}

QA_EXPORT int32_t qa_audio_resample_taps(int32_t input_rate,
                                         int32_t output_rate,
                                         double stopband_db,
                                         double bandwidth) {
  if (input_rate <= 0 || output_rate <= 0 || input_rate == output_rate) {
    return 0;
  }
  const int64_t divisor = qa_audio_gcd(input_rate, output_rate);
  const int64_t interpolation = output_rate / divisor;
  const int64_t decimation = input_rate / divisor;
  const int64_t larger = interpolation > decimation ? interpolation : decimation;

  const double nyquist = 0.5 / (double)larger;
  const double transition = nyquist - nyquist * bandwidth;
  int64_t taps;
  if (transition <= 0.0) {
    taps = 131071;
  } else {
    taps = (int64_t)ceil((stopband_db - 8.0) /
                         (2.285 * 2.0 * 3.14159265358979323846 * transition));
  }
  if (taps < 15) {
    taps = 15;
  }
  if (taps > 131071) {
    taps = 131071;
  }
  if (taps % 2 == 0) {
    taps += 1;
  }
  return (int32_t)taps;
}

// 🚨★★★**ONE LOOP, WHOLE OR A PIECE AT A TIME** (user 2026-10-10, board
// long-sound-conform-memory-Q1: 「지금 한다 — 전 플랫폼」). A long sound is
// conformed as the decoder hands it back, so the filter is fed a piece at a
// time — and an output frame reads the inputs it reads either way: the same
// taps in the same order, so a conversion fed in pieces writes the whole
// conversion's samples, bit for bit. qa_audio_resample is that loop over
// input that has all arrived; ⛔a second loop for the pieces would be the
// copy that drifts.

/// What a conversion between two rates runs: its polyphase geometry and
/// the prototype's taps.
typedef struct {
  int64_t interpolation;
  int64_t decimation;
  int64_t taps;
  int64_t half_length;
  double* kernel;
} qa_audio_resample_design;

/// The design for input_rate -> output_rate into [design], or 0 on bad
/// geometry. Equal rates are bad geometry here: the caller skips the whole
/// path and keeps the input bit-exact, which is the common case.
static int qa_audio_resample_design_make(int32_t input_rate,
                                         int32_t output_rate,
                                         double stopband_db,
                                         double bandwidth,
                                         qa_audio_resample_design* design) {
  if (input_rate <= 0 || output_rate <= 0 || input_rate == output_rate) {
    return 0;
  }
  const int64_t divisor = qa_audio_gcd(input_rate, output_rate);
  const int64_t interpolation = output_rate / divisor;
  const int64_t decimation = input_rate / divisor;
  const int64_t larger = interpolation > decimation ? interpolation : decimation;

  const double nyquist = 0.5 / (double)larger;
  const double passband_edge = nyquist * bandwidth;
  const double cutoff = (passband_edge + nyquist) / 2.0;
  const double beta = qa_audio_kaiser_beta(stopband_db);
  const int64_t taps =
      qa_audio_resample_taps(input_rate, output_rate, stopband_db, bandwidth);
  if (taps <= 0) {
    return 0;
  }

  double* kernel = (double*)malloc((size_t)taps * sizeof(double));
  if (kernel == NULL) {
    return 0;
  }
  {
    const double center = (double)(taps - 1) / 2.0;
    const double denominator = qa_audio_bessel_i0(beta);
    for (int64_t index = 0; index < taps; index += 1) {
      const double offset = (double)index - center;
      const double ratio = offset / center;
      const double inside = 1.0 - ratio * ratio;
      const double window =
          inside <= 0.0 ? 0.0
                        : qa_audio_bessel_i0(beta * sqrt(inside)) / denominator;
      kernel[index] = 2.0 * cutoff * qa_audio_sinc(2.0 * cutoff * offset) *
                      window * (double)interpolation;
    }
  }
  design->interpolation = interpolation;
  design->decimation = decimation;
  design->taps = taps;
  design->half_length = (taps - 1) / 2;
  design->kernel = kernel;
  return 1;
}

/// One past the last output frame [design] can write from [total] input
/// frames: every one there is once the input has [ended], and before that
/// only those whose every input has arrived.
static int64_t qa_audio_resample_ready_end(
    const qa_audio_resample_design* design, int64_t total, int ended) {
  const int64_t limit = total * design->interpolation / design->decimation;
  if (ended) {
    return limit;
  }
  // An output reads back from its base frame, (frame * M + half) / L, so it
  // is complete once that frame has arrived: frame * M + half < total * L.
  const int64_t reach = total * design->interpolation - design->half_length;
  const int64_t complete =
      reach <= 0 ? 0 : (reach + design->decimation - 1) / design->decimation;
  return complete < limit ? complete : limit;
}

/// Writes [count] output frames from frame [from] into [out], reading the
/// input frames [first, total) — the sound's frames from [first] on, [total]
/// of them so far — out of [held].
///
/// ⚠️What the caller promises: every input those outputs read from [first]
/// on is held, and while more input may come, none reads past [total]
/// (qa_audio_resample_ready_end). An input past the end is skipped, which is
/// right only at the sound's end.
static void qa_audio_resample_run(const qa_audio_resample_design* design,
                                  int32_t channels,
                                  const float* held,
                                  int64_t first,
                                  int64_t total,
                                  int64_t from,
                                  int64_t count,
                                  float* out) {
  const int64_t interpolation = design->interpolation;
  const int64_t taps = design->taps;
  const double* kernel = design->kernel;
  for (int64_t at = 0; at < count; at += 1) {
    // + half_length centres the filter on the output instant: the delay
    // compensation, applied here so it never has to be a whole number of
    // output samples.
    const int64_t position =
        (from + at) * design->decimation + design->half_length;
    const int64_t phase = position % interpolation;
    const int64_t base = position / interpolation;

    for (int32_t channel = 0; channel < channels; channel += 1) {
      double sum = 0.0;
      int64_t tap = phase;
      int64_t source = base;
      while (tap < taps && source >= first) {
        if (source < total) {
          sum += kernel[tap] *
                 (double)held[(source - first) * channels + channel];
        }
        tap += interpolation;
        source -= 1;
      }
      out[at * channels + channel] = (float)sum;
    }
  }
}

// Resamples interleaved [samples] from input_rate to output_rate into
// [out], which the caller sizes with qa_audio_resample_frames.
//
// Returns the number of output frames written, or 0 on bad geometry. Equal
// rates are NOT handled here - the caller skips the whole path and keeps
// the input bit-exact, which is the common case.
QA_EXPORT int64_t qa_audio_resample(
    const float* samples,
    int64_t input_frames,
    int32_t channels,
    int32_t input_rate,
    int32_t output_rate,
    double stopband_db,
    double bandwidth,
    float* out) {
  qa_audio_resample_design design;
  if (samples == NULL || out == NULL || channels <= 0 || input_frames <= 0 ||
      !qa_audio_resample_design_make(input_rate, output_rate, stopband_db,
                                     bandwidth, &design)) {
    return 0;
  }
  const int64_t output_frames =
      qa_audio_resample_ready_end(&design, input_frames, 1);
  qa_audio_resample_run(&design, channels, samples, 0, input_frames, 0,
                        output_frames, out);
  free(design.kernel);
  return output_frames;
}

/// A conversion fed a piece at a time: the design, and the input the
/// outputs still to come read.
typedef struct {
  qa_audio_resample_design design;
  int32_t channels;
  /// Input frames [first, first + held_frames), interleaved.
  float* held;
  int64_t first;
  int64_t held_frames;
  int64_t held_capacity;
  /// The next output frame.
  int64_t next;
  int ended;
} qa_audio_resampler;

/// A conversion of [channels] from input_rate to output_rate, fed a piece at
/// a time — NULL on bad geometry, equal rates among it (see
/// qa_audio_resample). qa_audio_resampler_close lets it go.
QA_EXPORT qa_audio_resampler* qa_audio_resampler_open(int32_t channels,
                                                      int32_t input_rate,
                                                      int32_t output_rate,
                                                      double stopband_db,
                                                      double bandwidth) {
  if (channels <= 0) {
    return NULL;
  }
  qa_audio_resampler* resampler =
      (qa_audio_resampler*)calloc(1, sizeof(qa_audio_resampler));
  if (resampler == NULL) {
    return NULL;
  }
  if (!qa_audio_resample_design_make(input_rate, output_rate, stopband_db,
                                     bandwidth, &resampler->design)) {
    free(resampler);
    return NULL;
  }
  resampler->channels = channels;
  return resampler;
}

/// Lets go of the held input no output still to come reads: output frame f
/// reads back to input (f * M + half - taps) / L + 1.
static void qa_audio_resampler_let_go(qa_audio_resampler* resampler) {
  const qa_audio_resample_design* design = &resampler->design;
  const int64_t reach = resampler->next * design->decimation +
                        design->half_length - design->taps +
                        design->interpolation;
  const int64_t lowest = reach <= 0 ? 0 : reach / design->interpolation;
  int64_t drop = lowest - resampler->first;
  if (drop > resampler->held_frames) {
    drop = resampler->held_frames;
  }
  if (drop <= 0) {
    return;
  }
  const int64_t channels = resampler->channels;
  memmove(resampler->held, resampler->held + drop * channels,
          (size_t)((resampler->held_frames - drop) * channels) *
              sizeof(float));
  resampler->held_frames -= drop;
  resampler->first += drop;
}

/// Hands [frames] more frames of input to [resampler]. 0 when the memory ran
/// out, or after qa_audio_resampler_end.
QA_EXPORT int32_t qa_audio_resampler_push(qa_audio_resampler* resampler,
                                          const float* samples,
                                          int64_t frames) {
  if (resampler == NULL || resampler->ended || frames < 0 ||
      (frames > 0 && samples == NULL)) {
    return 0;
  }
  qa_audio_resampler_let_go(resampler);
  const int64_t channels = resampler->channels;
  const int64_t wanted = resampler->held_frames + frames;
  if (wanted > resampler->held_capacity) {
    int64_t capacity =
        resampler->held_capacity == 0 ? 4096 : resampler->held_capacity;
    while (capacity < wanted) {
      capacity *= 2;
    }
    float* grown = (float*)realloc(
        resampler->held, (size_t)(capacity * channels) * sizeof(float));
    if (grown == NULL) {
      return 0;
    }
    resampler->held = grown;
    resampler->held_capacity = capacity;
  }
  if (frames > 0) {
    memcpy(resampler->held + resampler->held_frames * channels, samples,
           (size_t)(frames * channels) * sizeof(float));
  }
  resampler->held_frames = wanted;
  return 1;
}

/// Says no more input comes: the outputs that read past the end are ready.
QA_EXPORT void qa_audio_resampler_end(qa_audio_resampler* resampler) {
  if (resampler != NULL) {
    resampler->ended = 1;
  }
}

/// Input frames [resampler] holds now — for the tests that tell a
/// conversion that lets go of its input from one that keeps the whole sound.
QA_EXPORT int64_t qa_audio_resampler_held(
    const qa_audio_resampler* resampler) {
  return resampler == NULL ? 0 : resampler->held_frames;
}

/// How many output frames qa_audio_resampler_pull can write now.
QA_EXPORT int64_t qa_audio_resampler_ready(
    const qa_audio_resampler* resampler) {
  if (resampler == NULL) {
    return 0;
  }
  const int64_t end = qa_audio_resample_ready_end(
      &resampler->design, resampler->first + resampler->held_frames,
      resampler->ended);
  return end > resampler->next ? end - resampler->next : 0;
}

/// Writes up to [capacity] of the ready output frames into [out], and
/// answers how many.
QA_EXPORT int64_t qa_audio_resampler_pull(qa_audio_resampler* resampler,
                                          float* out,
                                          int64_t capacity) {
  if (resampler == NULL || out == NULL || capacity <= 0) {
    return 0;
  }
  int64_t count = qa_audio_resampler_ready(resampler);
  if (count > capacity) {
    count = capacity;
  }
  qa_audio_resample_run(&resampler->design, resampler->channels,
                        resampler->held, resampler->first,
                        resampler->first + resampler->held_frames,
                        resampler->next, count, out);
  resampler->next += count;
  return count;
}

QA_EXPORT void qa_audio_resampler_close(qa_audio_resampler* resampler) {
  if (resampler == NULL) {
    return;
  }
  free(resampler->held);
  free(resampler->design.kernel);
  free(resampler);
}

// How many frames qa_audio_resample will write - the caller's allocation
// size, computed the same way so the two can never disagree.
QA_EXPORT int64_t qa_audio_resample_frames(int64_t input_frames,
                                           int32_t input_rate,
                                           int32_t output_rate) {
  if (input_frames <= 0 || input_rate <= 0 || output_rate <= 0) {
    return 0;
  }
  if (input_rate == output_rate) {
    return input_frames;
  }
  const int64_t divisor = qa_audio_gcd(input_rate, output_rate);
  const int64_t interpolation = output_rate / divisor;
  const int64_t decimation = input_rate / divisor;
  return input_frames * interpolation / decimation;
}

// ---------------------------------------------------------------------------
// Image resample (ABI 25). Mirrors lib/src/services/resample/
// resample_kernel.dart byte for byte - see that file for WHY the kernel is
// shaped this way; this one only has to agree with it.
//
// Every expression below is written in the same order as the Dart, because
// "the same maths" is not the contract - the same rounding of the same
// intermediate values is. -ffp-contract=off keeps the compiler from fusing
// a multiply-add and rounding once where Dart rounds twice; that flag has
// to be present in BOTH the CMake flags and the Apple podspec, and a build
// that loses it fails the parity suite on Apple silicon only.
//
// Pixels are straight-alpha RGBA8 read four bytes at a time as one word:
// on the little-endian targets the app ships to that is A<<24|B<<16|G<<8|R,
// matching the Dart shifts.

#define QA_RESAMPLE_MODE_BLEND 0
#define QA_RESAMPLE_MODE_PICK 1
#define QA_RESAMPLE_VOTE_SLOTS 16
// Mirrors kResampleRadiusCeiling in resample_kernel.dart - see there for
// why. Blend's, now that Pick has no radius. Must change in both files or
// the parity suite fails.
#define QA_RESAMPLE_RADIUS_CEILING 16.0
// Mirrors kResampleRefineLimit - how far a TIED Pick vote may refine, per
// axis, and the stride of the subsample offset table below. One doubling,
// not two: a second DOES change pixels, but the ones it changes are almost
// all axis-aligned, and those no longer reach the sampler at all - they go
// down the exact-coverage path, where there is no quantisation to refine
// away. See the Dart for the measurement.
#define QA_RESAMPLE_REFINE_LIMIT 16
// Mirrors kResampleIndexLimit: past 2^53 a double cannot name consecutive
// integers, llround() is undefined and Dart's round() saturates, so both
// kernels answer "outside" before rounding rather than after.
#define QA_RESAMPLE_INDEX_LIMIT 9007199254740992.0
// Rows per pooled item. Bands are independent by construction (each writes
// only its own destination rows and reads only the source), so the split
// cannot change a byte - the Dart suite pins that with a banded run.
#define QA_RESAMPLE_BAND_ROWS 16

// How much of the destination pixel's preimage a source pixel covers along
// one axis: the preimage spans centre +/- half, a source pixel spans
// source +/- 0.5, and the weight is the length they share. Mirrors
// `_coverage` in resample_kernel.dart, and like it is used ONLY where the
// preimage is an axis-aligned rectangle, where the product of the two
// lengths is the shared area rather than an estimate of it. The operand
// ORDER matters for parity: Dart evaluates max(source - 0.5, centre - half)
// and this must compare the same two values in the same order.
static double qa_resample_coverage(int64_t source, double centre,
                                   double half) {
  const double source_low = (double)source - 0.5;
  const double source_high = (double)source + 0.5;
  const double pre_low = centre - half;
  const double pre_high = centre + half;
  const double low = source_low > pre_low ? source_low : pre_low;
  const double high = source_high < pre_high ? source_high : pre_high;
  return high - low;
}

// Mirrors resampleSamplesPerAxis: how many subsamples one destination axis
// is cut into, from the SQUARED source-space length of that axis's step.
// The rule is ceil(2*sqrt(squared_step)) clamped to 8..16, written as a
// comparison chain against the squared thresholds so that no sqrt and no
// cast to an integer appear - see the Dart for why that matters. NaN fails
// every `<=` here exactly as it does in Dart, and lands on the ceiling.
static int32_t qa_resample_samples_per_axis(double squared_step) {
  if (squared_step <= 16.0) return 8;
  if (squared_step <= 20.25) return 9;
  if (squared_step <= 25.0) return 10;
  if (squared_step <= 30.25) return 11;
  if (squared_step <= 36.0) return 12;
  if (squared_step <= 42.25) return 13;
  if (squared_step <= 49.0) return 14;
  if (squared_step <= 56.25) return 15;
  return 16;
}

typedef struct {
  const uint32_t* src;
  int32_t src_width;
  int32_t src_height;
  uint32_t* dst;
  int32_t dst_width;
  int32_t dst_height;
  double a, b, c, d, e, f, g, h, i;
  int32_t is_affine;
  int32_t is_integer_translation;
  double radius_floor;
  int32_t mode;
  // Where this destination buffer sits inside the FULL output rect the
  // transform was built for. Zero means "the buffer is the whole rect",
  // which is every caller that does not clip.
  //
  // A window keeps the whole rect's pixel GRID: destination pixel (x, y)
  // of the buffer is absolute pixel (x + clip_x, y + clip_y), and the
  // matrix is the one the whole rect would use. That is what makes a
  // window bit-identical to the same window of the whole — the source
  // position below comes out of the same multiply-add on the same
  // operands, rather than out of an origin folded into `c` (equal in
  // arithmetic, not in doubles, and a position sitting exactly on a pixel
  // boundary rounds the other way).
  int32_t clip_x;
  int32_t clip_y;
} qa_resample_context;

static void qa_resample_rows(
    const qa_resample_context* ctx, int32_t row_start, int32_t row_end) {
  const uint32_t* src = ctx->src;
  uint32_t* dst = ctx->dst;
  const int32_t src_width = ctx->src_width;
  const int32_t src_height = ctx->src_height;
  const int32_t dst_width = ctx->dst_width;

  // Whole-pixel translation: copy the overlapping rectangle verbatim. The
  // gather would agree numerically; callers rely on "the same bytes".
  if (ctx->is_integer_translation) {
    // 64-bit throughout, because Dart's int is: narrowing to int32 here
    // would wrap a translation past 2^31 into a SMALL offset and copy real
    // pixels where the reference copies nothing.
    const int64_t shift_x = -llround(ctx->c);
    const int64_t shift_y = -llround(ctx->f);
    for (int32_t y = row_start; y < row_end; y += 1) {
      const int64_t source_y = (int64_t)y + ctx->clip_y - shift_y;
      uint32_t* row = dst + (ptrdiff_t)y * dst_width;
      if (source_y < 0 || source_y >= src_height) {
        for (int32_t x = 0; x < dst_width; x += 1) {
          row[x] = 0u;
        }
        continue;
      }
      const uint32_t* source_row = src + (ptrdiff_t)source_y * src_width;
      for (int32_t x = 0; x < dst_width; x += 1) {
        const int64_t source_x = (int64_t)x + ctx->clip_x - shift_x;
        row[x] = (source_x < 0 || source_x >= src_width)
                     ? 0u
                     : source_row[source_x];
      }
    }
    return;
  }

  const int is_pick = ctx->mode == QA_RESAMPLE_MODE_PICK;

  const double floor_radius = ctx->radius_floor;
  double extent_x = fabs(ctx->a) + fabs(ctx->b);
  double extent_y = fabs(ctx->d) + fabs(ctx->e);
  double radius_x = extent_x;
  double radius_y = extent_y;
  if (radius_x < floor_radius) radius_x = floor_radius;
  if (radius_y < floor_radius) radius_y = floor_radius;
  if (radius_x > QA_RESAMPLE_RADIUS_CEILING)
    radius_x = QA_RESAMPLE_RADIUS_CEILING;
  if (radius_y > QA_RESAMPLE_RADIUS_CEILING)
    radius_y = QA_RESAMPLE_RADIUS_CEILING;

  // The squared source-space length of one destination step along each
  // axis - the columns of the same Jacobian, and the only thing that sets
  // Pick's sample rate.
  double step_x_squared = ctx->a * ctx->a + ctx->d * ctx->d;
  double step_y_squared = ctx->b * ctx->b + ctx->e * ctx->e;

  // Pick's EXACT path. When both destination steps land on the axes - `b`
  // and `d` zero (no rotation or a half turn), or `a` and `e` zero (a
  // quarter turn, axes swapped) - the preimage is an axis-aligned
  // rectangle, and then the separable coverage product is not an estimate
  // of the shared area, it IS the shared area. See the Dart reference for
  // why that distinction is worth a branch: counting samples quantises,
  // leaving a band of coverages just over half that come back tied, and an
  // axis-aligned line loses all of itself at once there.
  const int pick_exact =
      is_pick && ctx->is_affine &&
      ((ctx->b == 0.0 && ctx->d == 0.0) || (ctx->a == 0.0 && ctx->e == 0.0)) &&
      extent_x > 0.0 && extent_y > 0.0 &&
      extent_x <= QA_RESAMPLE_RADIUS_CEILING &&
      extent_y <= QA_RESAMPLE_RADIUS_CEILING;

  uint32_t keys[QA_RESAMPLE_VOTE_SLOTS];
  // One table for both of Pick's gathers: the supersampler adds 1.0 per
  // landing, which a double counts exactly far past the 1024 it can reach.
  double weights[QA_RESAMPLE_VOTE_SLOTS];
  // Where the subsamples land, so an eviction recount re-reads a scratch
  // array instead of re-running the inverse map.
  uint32_t landings[QA_RESAMPLE_REFINE_LIMIT * QA_RESAMPLE_REFINE_LIMIT];
  // Subsample centres for every count either axis can take. Built once per
  // band rather than per pixel, and by the SAME expression as the Dart -
  // `(s + 0.5) / n`, not a multiply by a reciprocal, because those two do
  // not round alike.
  static const int32_t offset_stride = QA_RESAMPLE_REFINE_LIMIT;
  double offsets[(QA_RESAMPLE_REFINE_LIMIT + 1) * QA_RESAMPLE_REFINE_LIMIT];
  if (is_pick && !pick_exact) {
    for (int32_t n = 1; n <= QA_RESAMPLE_REFINE_LIMIT; n += 1) {
      for (int32_t s = 0; s < n; s += 1) {
        offsets[n * offset_stride + s] = ((double)s + 0.5) / (double)n;
      }
    }
  }

  for (int32_t y = row_start; y < row_end; y += 1) {
    // The ABSOLUTE destination row, formed once in the integer domain so
    // every reader below keeps the two-term double sum it had. Adding the
    // clip in doubles instead would make these three-term sums, and this
    // kernel's parity with the Dart reference is expression identity, not
    // value identity - see the -ffp-contract note at the top of the file.
    const int64_t absolute_y = (int64_t)y + ctx->clip_y;
    const double centre_of_y = (double)absolute_y + 0.5;
    uint32_t* row = dst + (ptrdiff_t)y * dst_width;
    for (int32_t x = 0; x < dst_width; x += 1) {
      const int64_t absolute_x = (int64_t)x + ctx->clip_x;
      const double centre_of_x = (double)absolute_x + 0.5;

      double u;
      double v;
      if (ctx->is_affine) {
        u = ctx->a * centre_of_x + ctx->b * centre_of_y + ctx->c - 0.5;
        v = ctx->d * centre_of_x + ctx->e * centre_of_y + ctx->f - 0.5;
      } else {
        const double w = ctx->g * centre_of_x + ctx->h * centre_of_y + ctx->i;
        if (w == 0.0) {
          row[x] = 0u;
          continue;
        }
        const double inverse_w = 1.0 / w;
        const double projected_u =
            (ctx->a * centre_of_x + ctx->b * centre_of_y + ctx->c) * inverse_w;
        const double projected_v =
            (ctx->d * centre_of_x + ctx->e * centre_of_y + ctx->f) * inverse_w;
        u = projected_u - 0.5;
        v = projected_v - 0.5;
        const double dudx = (ctx->a - projected_u * ctx->g) * inverse_w;
        const double dudy = (ctx->b - projected_u * ctx->h) * inverse_w;
        const double dvdx = (ctx->d - projected_v * ctx->g) * inverse_w;
        const double dvdy = (ctx->e - projected_v * ctx->h) * inverse_w;
        extent_x = fabs(dudx) + fabs(dudy);
        extent_y = fabs(dvdx) + fabs(dvdy);
        // Per-pixel, from the per-pixel Jacobian - taking these from the
        // matrix entries would describe a pixel somewhere else entirely.
        step_x_squared = dudx * dudx + dvdx * dvdx;
        step_y_squared = dudy * dudy + dvdy * dvdy;
        radius_x = extent_x;
        radius_y = extent_y;
        if (radius_x < floor_radius) radius_x = floor_radius;
        if (radius_y < floor_radius) radius_y = floor_radius;
        if (radius_x > QA_RESAMPLE_RADIUS_CEILING)
          radius_x = QA_RESAMPLE_RADIUS_CEILING;
        if (radius_y > QA_RESAMPLE_RADIUS_CEILING)
          radius_y = QA_RESAMPLE_RADIUS_CEILING;
      }

      // A degenerate map puts u, v or a radius outside the finite doubles,
      // where llround() and ceil() are undefined - on arm64 the latter
      // saturates to INT32_MAX and the gather becomes an unbreakable loop.
      // Both kernels declare the pixel outside instead.
      if (!isfinite(u) || !isfinite(v) || !isfinite(radius_x) ||
          !isfinite(radius_y)) {
        row[x] = 0u;
        continue;
      }

      const int64_t centre_x = llround(u);
      const int64_t centre_y = llround(v);

      const int32_t samples_x = (is_pick && !pick_exact)
                                    ? qa_resample_samples_per_axis(
                                          step_x_squared)
                                    : 0;
      const int32_t samples_y = (is_pick && !pick_exact)
                                    ? qa_resample_samples_per_axis(
                                          step_y_squared)
                                    : 0;

      // The exact path's half-widths. NO floor is applied: a floor above
      // the true extent claims the preimage reaches further than it does.
      const double half_x = extent_x * 0.5;
      const double half_y = extent_y * 0.5;
      const int32_t exact_rad_x =
          pick_exact ? (int32_t)ceil(half_x + 0.5) : 0;
      const int32_t exact_rad_y =
          pick_exact ? (int32_t)ceil(half_y + 0.5) : 0;

      // The window for the flat-support probe. For Blend and for exact
      // Pick it IS the gather window. For the supersampler it is derived -
      // see the Dart reference - and the derivation holds only while the
      // preimage really is the parallelogram the extents describe, so the
      // supersampler does not probe a homography at all. The cell count is
      // compared as a double because a large reduction overflows an int32
      // on the way to the comparison.
      int run_flat = 1;
      int32_t flat_rad_x;
      int32_t flat_rad_y;
      if (pick_exact) {
        flat_rad_x = exact_rad_x;
        flat_rad_y = exact_rad_y;
      } else if (is_pick) {
        const double span_x = floor(extent_x * 0.5 + 1.0);
        const double span_y = floor(extent_y * 0.5 + 1.0);
        run_flat = ctx->is_affine &&
                   (2.0 * span_x + 1.0) * (2.0 * span_y + 1.0) <=
                       (double)samples_x * (double)samples_y;
        flat_rad_x = run_flat ? (int32_t)span_x : 0;
        flat_rad_y = run_flat ? (int32_t)span_y : 0;
      } else {
        flat_rad_x = (int32_t)ceil(radius_x);
        flat_rad_y = (int32_t)ceil(radius_y);
      }

      // Flat support: when every source pixel in reach holds the same word
      // both modes must return that word. Cheap on line art, where most of
      // a frame is one colour.
      if (run_flat) {
        uint32_t flat_token = 0u;
        int flat = 1;
        int seen_any = 0;
        for (int32_t dy = -flat_rad_y; dy <= flat_rad_y && flat; dy += 1) {
          const int64_t source_y = centre_y + dy;
          const int row_inside = source_y >= 0 && source_y < src_height;
          const uint32_t* source_row =
              row_inside ? src + (ptrdiff_t)source_y * src_width : NULL;
          for (int32_t dx = -flat_rad_x; dx <= flat_rad_x; dx += 1) {
            const int64_t source_x = centre_x + dx;
            const uint32_t token =
                (!row_inside || source_x < 0 || source_x >= src_width)
                    ? 0u
                    : source_row[source_x];
            if (!seen_any) {
              flat_token = token;
              seen_any = 1;
            } else if (token != flat_token) {
              flat = 0;
              break;
            }
          }
        }
        if (flat) {
          row[x] = flat_token;
          continue;
        }
      }

      if (pick_exact) {
        // Exact area, gathered rather than sampled: each tap's weight is
        // the length its source pixel shares with the preimage along x
        // times the same along y, and because the preimage is an
        // axis-aligned rectangle here that product IS the shared area. No
        // quantisation, so no tie band. A surviving tie is real and goes
        // to the token met first - see the Dart reference for the two
        // tie-breaks that were built, measured and reverted.
        int32_t slots = 0;
        int evicted = 0;
        for (int32_t dy = -exact_rad_y; dy <= exact_rad_y; dy += 1) {
          const int64_t source_y = centre_y + dy;
          const double weight_y = qa_resample_coverage(source_y, v, half_y);
          if (weight_y <= 0.0) continue;
          const int row_inside = source_y >= 0 && source_y < src_height;
          const uint32_t* source_row =
              row_inside ? src + (ptrdiff_t)source_y * src_width : NULL;
          for (int32_t dx = -exact_rad_x; dx <= exact_rad_x; dx += 1) {
            const int64_t source_x = centre_x + dx;
            const double weight_x = qa_resample_coverage(source_x, u, half_x);
            if (weight_x <= 0.0) continue;
            const uint32_t token =
                (!row_inside || source_x < 0 || source_x >= src_width)
                    ? 0u
                    : source_row[source_x];
            const double weight = weight_x * weight_y;
            int32_t slot = -1;
            for (int32_t s = 0; s < slots; s += 1) {
              if (keys[s] == token) {
                slot = s;
                break;
              }
            }
            if (slot >= 0) {
              weights[slot] += weight;
            } else if (slots < QA_RESAMPLE_VOTE_SLOTS) {
              keys[slots] = token;
              weights[slots] = weight;
              slots += 1;
            } else {
              int32_t lightest = 0;
              for (int32_t s = 1; s < QA_RESAMPLE_VOTE_SLOTS; s += 1) {
                if (weights[s] < weights[lightest]) lightest = s;
              }
              keys[lightest] = token;
              weights[lightest] += weight;
              evicted = 1;
            }
          }
        }
        if (slots == 0) {
          row[x] = 0u;
          continue;
        }
        if (evicted) {
          for (int32_t s = 0; s < slots; s += 1) {
            weights[s] = 0.0;
          }
          for (int32_t dy = -exact_rad_y; dy <= exact_rad_y; dy += 1) {
            const int64_t source_y = centre_y + dy;
            const double weight_y = qa_resample_coverage(source_y, v, half_y);
            if (weight_y <= 0.0) continue;
            const int row_inside = source_y >= 0 && source_y < src_height;
            const uint32_t* source_row =
                row_inside ? src + (ptrdiff_t)source_y * src_width : NULL;
            for (int32_t dx = -exact_rad_x; dx <= exact_rad_x; dx += 1) {
              const int64_t source_x = centre_x + dx;
              const double weight_x =
                  qa_resample_coverage(source_x, u, half_x);
              if (weight_x <= 0.0) continue;
              const uint32_t token =
                  (!row_inside || source_x < 0 || source_x >= src_width)
                      ? 0u
                      : source_row[source_x];
              for (int32_t s = 0; s < slots; s += 1) {
                if (keys[s] == token) {
                  weights[s] += weight_x * weight_y;
                  break;
                }
              }
            }
          }
        }
        int32_t best = 0;
        for (int32_t s = 1; s < slots; s += 1) {
          if (weights[s] > weights[best]) best = s;
        }
        row[x] = keys[best];
        continue;
      }

      if (is_pick) {
        // Sample, count, and if the count came back TIED, sample again at
        // twice the rate. A tie is nearly always the grid's fault rather
        // than the geometry's; only tied pixels pay for the refinement,
        // and a tie that survives the cap falls through to the token met
        // first - not because it is an exact half (traced, they were
        // 55/45). See the Dart reference.
        int32_t nx = samples_x;
        int32_t ny = samples_y;
        int32_t slots = 0;
        int32_t best = 0;
        for (;;) {
          const int32_t base_x = nx * offset_stride;
          const int32_t base_y = ny * offset_stride;
          int32_t votes = 0;
          for (int32_t sy = 0; sy < ny; sy += 1) {
            const double sample_y = (double)absolute_y + offsets[base_y + sy];
            for (int32_t sx = 0; sx < nx; sx += 1) {
              const double sample_x =
                  (double)absolute_x + offsets[base_x + sx];
              double sample_u;
              double sample_v;
              if (ctx->is_affine) {
                sample_u =
                    ctx->a * sample_x + ctx->b * sample_y + ctx->c - 0.5;
                sample_v =
                    ctx->d * sample_x + ctx->e * sample_y + ctx->f - 0.5;
              } else {
                const double sample_w =
                    ctx->g * sample_x + ctx->h * sample_y + ctx->i;
                if (sample_w == 0.0) continue;
                sample_u =
                    (ctx->a * sample_x + ctx->b * sample_y + ctx->c) / sample_w -
                    0.5;
                sample_v =
                    (ctx->d * sample_x + ctx->e * sample_y + ctx->f) / sample_w -
                    0.5;
              }
              if (!isfinite(sample_u) || !isfinite(sample_v)) continue;
              if (fabs(sample_u) >= QA_RESAMPLE_INDEX_LIMIT ||
                  fabs(sample_v) >= QA_RESAMPLE_INDEX_LIMIT) {
                landings[votes] = 0u;
                votes += 1;
                continue;
              }
              const int64_t source_x = llround(sample_u);
              const int64_t source_y = llround(sample_v);
              landings[votes] =
                  (source_x < 0 || source_x >= src_width || source_y < 0 ||
                   source_y >= src_height)
                      ? 0u
                      : src[(ptrdiff_t)source_y * src_width + source_x];
              votes += 1;
            }
          }

          slots = 0;
          int evicted = 0;
          for (int32_t s = 0; s < votes; s += 1) {
            const uint32_t token = landings[s];
            int32_t slot = -1;
            for (int32_t k = 0; k < slots; k += 1) {
              if (keys[k] == token) {
                slot = k;
                break;
              }
            }
            if (slot >= 0) {
              weights[slot] += 1.0;
            } else if (slots < QA_RESAMPLE_VOTE_SLOTS) {
              keys[slots] = token;
              weights[slots] = 1.0;
              slots += 1;
            } else {
              // The weakest slot yields its key and keeps its count, so a
              // token can only be evicted while it holds less than a
              // sixteenth of the samples. Lowest index on a tie.
              int32_t lightest = 0;
              for (int32_t k = 1; k < QA_RESAMPLE_VOTE_SLOTS; k += 1) {
                if (weights[k] < weights[lightest]) lightest = k;
              }
              keys[lightest] = token;
              weights[lightest] += 1.0;
              evicted = 1;
            }
          }
          if (slots == 0) {
            break;
          }
          if (evicted) {
            // An inherited count over-estimates its new owner; recount the
            // survivors exactly. Gated on the eviction, so an ordinary
            // preimage never pays for it.
            for (int32_t s = 0; s < slots; s += 1) {
              weights[s] = 0.0;
            }
            for (int32_t s = 0; s < votes; s += 1) {
              const uint32_t token = landings[s];
              for (int32_t k = 0; k < slots; k += 1) {
                if (keys[k] == token) {
                  weights[k] += 1.0;
                  break;
                }
              }
            }
          }
          best = 0;
          for (int32_t s = 1; s < slots; s += 1) {
            if (weights[s] > weights[best]) best = s;
          }
          int tied = 0;
          for (int32_t s = 0; s < slots; s += 1) {
            if (s != best && weights[s] == weights[best]) {
              tied = 1;
              break;
            }
          }
          if (!tied || (nx >= QA_RESAMPLE_REFINE_LIMIT &&
                        ny >= QA_RESAMPLE_REFINE_LIMIT)) {
            break;
          }
          nx = nx * 2 < QA_RESAMPLE_REFINE_LIMIT ? nx * 2
                                                 : QA_RESAMPLE_REFINE_LIMIT;
          ny = ny * 2 < QA_RESAMPLE_REFINE_LIMIT ? ny * 2
                                                 : QA_RESAMPLE_REFINE_LIMIT;
        }
        if (slots == 0) {
          // Every subsample was degenerate - a homography pole through this
          // pixel, or a matrix that maps it nowhere finite.
          row[x] = 0u;
          continue;
        }
        row[x] = keys[best];
        continue;
      }

      const int32_t rad_x = flat_rad_x;
      const int32_t rad_y = flat_rad_y;

      double acc_red = 0.0;
      double acc_green = 0.0;
      double acc_blue = 0.0;
      double acc_alpha = 0.0;
      double weight_sum = 0.0;
      for (int32_t dy = -rad_y; dy <= rad_y; dy += 1) {
        const int64_t source_y = centre_y + dy;
        const double weight_y = 1.0 - fabs((double)source_y - v) / radius_y;
        if (weight_y <= 0.0) continue;
        const int row_inside = source_y >= 0 && source_y < src_height;
        const uint32_t* source_row =
            row_inside ? src + (ptrdiff_t)source_y * src_width : NULL;
        for (int32_t dx = -rad_x; dx <= rad_x; dx += 1) {
          const int64_t source_x = centre_x + dx;
          const double weight_x = 1.0 - fabs((double)source_x - u) / radius_x;
          if (weight_x <= 0.0) continue;
          const uint32_t token =
              (!row_inside || source_x < 0 || source_x >= src_width)
                  ? 0u
                  : source_row[source_x];
          const double weight = weight_x * weight_y;
          const double alpha = (double)((token >> 24) & 0xFFu);
          const double colour_weight = weight * alpha;
          acc_red += (double)(token & 0xFFu) * colour_weight;
          acc_green += (double)((token >> 8) & 0xFFu) * colour_weight;
          acc_blue += (double)((token >> 16) & 0xFFu) * colour_weight;
          acc_alpha += alpha * weight;
          weight_sum += weight;
        }
      }
      if (weight_sum <= 0.0 || acc_alpha <= 0.0) {
        row[x] = 0u;
        continue;
      }
      int64_t out_alpha = llround(acc_alpha / weight_sum);
      if (out_alpha < 0) out_alpha = 0;
      if (out_alpha > 255) out_alpha = 255;
      if (out_alpha == 0) {
        row[x] = 0u;
        continue;
      }
      int64_t out_red = llround(acc_red / acc_alpha);
      int64_t out_green = llround(acc_green / acc_alpha);
      int64_t out_blue = llround(acc_blue / acc_alpha);
      if (out_red < 0) out_red = 0;
      if (out_red > 255) out_red = 255;
      if (out_green < 0) out_green = 0;
      if (out_green > 255) out_green = 255;
      if (out_blue < 0) out_blue = 0;
      if (out_blue > 255) out_blue = 255;
      row[x] = ((uint32_t)out_alpha << 24) | ((uint32_t)out_blue << 16) |
               ((uint32_t)out_green << 8) | (uint32_t)out_red;
    }
  }
}

static void qa_resample_item(int32_t item_index, void* context) {
  const qa_resample_context* ctx = (const qa_resample_context*)context;
  const int32_t row_start = item_index * QA_RESAMPLE_BAND_ROWS;
  int32_t row_end = row_start + QA_RESAMPLE_BAND_ROWS;
  if (row_end > ctx->dst_height) {
    row_end = ctx->dst_height;
  }
  qa_resample_rows(ctx, row_start, row_end);
}

// Resamples src into dst through the destination-to-source map `inverse`
// (9 doubles, row-major, homogeneous row last). mode 0 = tent mean, 1 =
// area argmax - measured exactly when the preimage is an axis-aligned
// rectangle, supersampled otherwise. `radius_floor` is Blend's; Pick has
// no radius and ignores it. Returns 0 ok, negative on bad arguments.
QA_EXPORT int32_t qa_resample_rgba(
    const uint8_t* src,
    int32_t src_width,
    int32_t src_height,
    uint8_t* dst,
    int32_t dst_width,
    int32_t dst_height,
    const double* inverse,
    double radius_floor,
    int32_t mode,
    int32_t clip_x,
    int32_t clip_y) {
  if (src == NULL || dst == NULL || inverse == NULL) {
    return -1;
  }
  if (src_width <= 0 || src_height <= 0 || dst_width <= 0 || dst_height <= 0) {
    return -2;
  }
  if (mode != QA_RESAMPLE_MODE_BLEND && mode != QA_RESAMPLE_MODE_PICK) {
    return -3;
  }
  if (radius_floor < 1.0) {
    return -4;
  }

  qa_resample_context ctx;
  ctx.src = (const uint32_t*)src;
  ctx.src_width = src_width;
  ctx.src_height = src_height;
  ctx.dst = (uint32_t*)dst;
  ctx.dst_width = dst_width;
  ctx.dst_height = dst_height;
  ctx.a = inverse[0];
  ctx.b = inverse[1];
  ctx.c = inverse[2];
  ctx.d = inverse[3];
  ctx.e = inverse[4];
  ctx.f = inverse[5];
  ctx.g = inverse[6];
  ctx.h = inverse[7];
  ctx.i = inverse[8];
  ctx.radius_floor = radius_floor;
  ctx.mode = mode;
  ctx.clip_x = clip_x;
  ctx.clip_y = clip_y;
  ctx.is_affine = (ctx.g == 0.0 && ctx.h == 0.0 && ctx.i == 1.0) ? 1 : 0;
  // "Is a whole number" via trunc(), not llround(): llround is undefined
  // past the int64 range, where Dart's roundToDouble() is simply the
  // identity. trunc() answers the same question for every finite double
  // and gives the same answer as Dart for every value the short circuit
  // can accept.
  ctx.is_integer_translation =
      (ctx.is_affine && ctx.a == 1.0 && ctx.b == 0.0 && ctx.d == 0.0 &&
       ctx.e == 1.0 && isfinite(ctx.c) && isfinite(ctx.f) &&
       ctx.c == trunc(ctx.c) && ctx.f == trunc(ctx.f))
          ? 1
          : 0;

  const int32_t band_count =
      (dst_height + QA_RESAMPLE_BAND_ROWS - 1) / QA_RESAMPLE_BAND_ROWS;
  qa_pool_run(qa_resample_item, &ctx, band_count);
  return 0;
}

// The device's physical RAM in bytes; 0 when the platform refuses to
// answer. The hot cel budget scales from this instead of assuming a
// desktop-class machine (a 3GB tablet was being asked to hold 1.5GB of
// hot cels).
QA_EXPORT int64_t qa_physical_memory_bytes(void) {
#if defined(_WIN32)
  MEMORYSTATUSEX status;
  status.dwLength = sizeof(status);
  if (GlobalMemoryStatusEx(&status)) {
    return (int64_t)status.ullTotalPhys;
  }
  return 0;
#elif defined(__APPLE__)
  int64_t bytes = 0;
  size_t length = sizeof(bytes);
  int mib[2] = {CTL_HW, HW_MEMSIZE};
  if (sysctl(mib, 2, &bytes, &length, NULL, 0) == 0) {
    return bytes;
  }
  return 0;
#else
  struct sysinfo info;
  if (sysinfo(&info) == 0) {
    return (int64_t)info.totalram * (int64_t)info.mem_unit;
  }
  return 0;
#endif
}

// What THIS PROCESS is holding right now, in bytes; 0 when the platform
// will not say.
//
// ONE QUESTION, ANSWERED BY EVERY PLATFORM IN ITS OWN WORDS: the bytes
// that belong to this process alone and come back when it exits. That is
// the number each OS puts next to the app in its own task manager -- Task
// Manager's "Memory" column, Activity Monitor's "Memory", the number a
// jetsam report calls `rpages x pageSize`. The user asked for the panel to
// show that same number (2026-09-10), so all three arms answer it.
//
// The Apple arm has been here since v29. Windows and Linux used to return
// 0 with a note that a per-process API would add a link dependency to a
// file that deliberately has none. It does not: kernel32 exports
// K32GetProcessMemoryInfo, so Windows needs GetProcAddress and no import
// library, and Linux reads a file.
//
// Physical RAM (qa_physical_memory_bytes above) answers a different
// question and had been standing in for this one.
QA_EXPORT int64_t qa_process_footprint_bytes(void) {
#if defined(__APPLE__)
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) ==
      KERN_SUCCESS) {
    return (int64_t)info.phys_footprint;
  }
  return 0;
#elif defined(_WIN32)
  // PROCESS_MEMORY_COUNTERS_EX2 (Windows 10 1809+) carries
  // PrivateWorkingSetSize: the RESIDENT bytes no other process shares,
  // which is what Task Manager's "Memory" column shows. The struct is
  // declared here rather than included because psapi.h only grew it in
  // newer SDKs, and this file compiles against whatever the platform
  // hands it.
  //
  // NOT PrivateUsage from the smaller EX struct: that is private COMMIT,
  // which on this app reads 237MB where the working set reads 139MB
  // (measured 2026-09-10). They are two different questions, so an older
  // Windows gets 0 -- "not measured here" -- rather than a number that
  // quietly means something else.
  typedef struct {
    DWORD cb;
    DWORD PageFaultCount;
    SIZE_T PeakWorkingSetSize;
    SIZE_T WorkingSetSize;
    SIZE_T QuotaPeakPagedPoolUsage;
    SIZE_T QuotaPagedPoolUsage;
    SIZE_T QuotaPeakNonPagedPoolUsage;
    SIZE_T QuotaNonPagedPoolUsage;
    SIZE_T PagefileUsage;
    SIZE_T PeakPagefileUsage;
    SIZE_T PrivateUsage;
    SIZE_T PrivateWorkingSetSize;
    ULONG64 SharedCommitUsage;
  } qa_pmc_ex2;
  typedef BOOL(WINAPI * qa_get_pmi)(HANDLE, void *, DWORD);
  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  qa_get_pmi get_process_memory_info =
      kernel32 == NULL ? NULL
                       : (qa_get_pmi)(void *)GetProcAddress(
                             kernel32, "K32GetProcessMemoryInfo");
  if (get_process_memory_info != NULL) {
    qa_pmc_ex2 counters;
    memset(&counters, 0, sizeof(counters));
    counters.cb = (DWORD)sizeof(counters);
    if (get_process_memory_info(GetCurrentProcess(), &counters,
                                (DWORD)sizeof(counters))) {
      return (int64_t)counters.PrivateWorkingSetSize;
    }
  }
  return 0;
#else
  // Linux and Android: /proc/self/smaps_rollup is the kernel's own sum
  // over every mapping (4.14+), so this is one small read instead of a
  // walk of /proc/self/smaps. Private_Clean + Private_Dirty is the same
  // quantity the other two arms return -- pages no other process shares.
  FILE *rollup = fopen("/proc/self/smaps_rollup", "r");
  if (rollup == NULL) {
    return 0;
  }
  char line[256];
  int64_t private_kb = 0;
  int found = 0;
  while (fgets(line, (int)sizeof(line), rollup) != NULL) {
    long long value = 0;
    if (sscanf(line, "Private_Clean: %lld kB", &value) == 1 ||
        sscanf(line, "Private_Dirty: %lld kB", &value) == 1) {
      private_kb += (int64_t)value;
      found = 1;
    }
  }
  fclose(rollup);
  return found ? private_kb * 1024 : 0;
#endif
}

// How much more this process may take before the OS stops it; 0 when the
// platform will not say.
//
// On iOS this is the real ceiling - os_proc_available_memory answers what
// is left of the app's own allowance, which is not the device's free RAM
// and not a fraction of its total. Elsewhere the closest honest answer is
// the machine's free memory.
QA_EXPORT int64_t qa_available_memory_bytes(void) {
#if defined(__APPLE__) && TARGET_OS_IPHONE
  return (int64_t)os_proc_available_memory();
#elif defined(_WIN32)
  MEMORYSTATUSEX status;
  status.dwLength = sizeof(status);
  if (GlobalMemoryStatusEx(&status)) {
    return (int64_t)status.ullAvailPhys;
  }
  return 0;
#elif defined(__APPLE__)
  return 0;
#else
  struct sysinfo info;
  if (sysinfo(&info) == 0) {
    return (int64_t)info.freeram * (int64_t)info.mem_unit;
  }
  return 0;
#endif
}

// What the OS lets THIS APP hold, all in: what it holds now plus what it may
// still take - the ceiling a jetsam decision is made against. 0 where the OS
// gives an app no limit of its own: a desktop's free memory
// (qa_available_memory_bytes there) is the machine's, not this app's.
// C-ipad-crash (ABI 36): the automatic allowance is half of this where it
// exists and half the RAM where it does not.
QA_EXPORT int64_t qa_app_memory_limit_bytes(void) {
#if defined(__APPLE__) && TARGET_OS_IPHONE
  return qa_process_footprint_bytes() + (int64_t)os_proc_available_memory();
#else
  return 0;
#endif
}

// ---------------------------------------------------------------------------
// Cel pixel pass (ABI 33): 색 변환 and 픽셀 비우기 over a cel's tiles.
//
// Mirrors the per-pixel loop of lib/src/services/cel_pixel_overwrite.dart.
// That Dart loop STAYS — it is the reference, and it is what runs with no
// engine — and `cel_pixel_pass_parity_test.dart` drives both over the same
// fixtures and compares bytes.
//
// ⛔ONE TILE PER CALL, deliberately. The batched shape every other tile
// kernel here uses (qa_tile_span[] + qa_pool_run) cannot be used as-is:
// this pass writes its ORIGINALS into one stream shared by every tile, in
// walk order, and a tile's slot in that stream is the sum of the counts
// before it — which is not known until those tiles have run. 510 calls on
// a 4K cel cost tens of microseconds against a pass that costs hundreds of
// milliseconds, and per-call keeps both the caller's ONE scratch buffer and
// the lazy copy below.

typedef struct {
  // 3 for colour, 1 for alpha.
  int32_t byte_count;
  // Where channel byte i sits in the RGBA quad: base + i * stride.
  // colour = (0, 1) -> 0, 1, 2 · alpha = (3, 0) -> 3.
  //
  // ⚠️TWO NUMBERS RATHER THAN A CHANNEL ENUM, so the C never has to know
  // what a channel IS. `CelPixelChannel.byteOffset` stays the one law and
  // this reads it; a third channel added there needs no edit here.
  int32_t byte_offset_base;
  int32_t byte_offset_stride;
  // 1 = every masked pixel takes part (the alpha rule); 0 = only pixels
  // that carry ink (the colour rule, alpha > 0). Same reasoning as
  // `celPixelParticipates`: an alpha write destroys "was there ink here",
  // so undo must record the empty pixels too.
  int32_t takes_empty_pixels;
  // The colour selector, or has_selector = 0. ⛔It reads R, G and B and
  // NEVER alpha — that purity is what lets undo re-ask the same question
  // of the same bytes and walk the same pixels.
  int32_t has_selector;
  int32_t selector_red;
  int32_t selector_green;
  int32_t selector_blue;
  int32_t selector_tolerance;
  int32_t selector_keeps_matches;
  // 1 = undo: `incoming` is the flat originals stream indexed by the
  // GLOBAL walk index, and coverage does not blend — the recipe already
  // holds what the pixel was, so putting it back is a plain assignment.
  int32_t is_undo;
  // Pixels per tile side — one number for every tile of a pass.
  int32_t tile_size;
  // Undo only: how many entries [incoming] holds, and how far apart they
  // sit. A recipe laid flat steps byte_count per touched pixel; a UNIFORM
  // recipe is one value stepped 0, so the case that matters most — line art
  // is flat, and every recolour after the first leaves it flat — is never
  // laid out at all.
  int32_t incoming_count;
  int32_t incoming_step;
  // 2치화 (ABI 50): 0 = off. Otherwise a channel byte at or above it takes
  // the incoming byte and one below it takes 0 — alpha at or over the cut
  // goes opaque, the rest empty. ⛔It shapes the VALUE written, never
  // whether a pixel takes part: that reads R, G and B only, so the undo
  // walks the same pixels after the alpha has changed. Forward only — an
  // undo assigns its recipe, and is sent 0 (the Dart side asserts it).
  int32_t threshold;
} qa_cel_pixel_spec;

QA_EXPORT int32_t qa_cel_pixel_spec_sizeof(void) {
  return (int32_t)sizeof(qa_cel_pixel_spec);
}

// `older + (incoming - older) * coverage / 255`, the integer mul-div-255
// idiom — byte-for-byte the Dart `_blend`.
static uint8_t qa_cel_pixel_blend(int32_t older, int32_t incoming,
                                  int32_t coverage) {
  const int32_t scaled =
      incoming * coverage + older * (255 - coverage) + 128;
  return (uint8_t)((scaled + (scaled >> 8)) >> 8);
}

static int32_t qa_cel_pixel_participates(const qa_cel_pixel_spec* spec,
                                         int32_t alpha, int32_t mask_value,
                                         int32_t red, int32_t green,
                                         int32_t blue) {
  if (mask_value == 0) {
    return 0;
  }
  if (spec->has_selector) {
    const int32_t tolerance = spec->selector_tolerance;
    const int32_t dr = red > spec->selector_red ? red - spec->selector_red
                                                : spec->selector_red - red;
    const int32_t dg = green > spec->selector_green
                           ? green - spec->selector_green
                           : spec->selector_green - green;
    const int32_t db = blue > spec->selector_blue ? blue - spec->selector_blue
                                                  : spec->selector_blue - blue;
    const int32_t matches =
        (dr <= tolerance && dg <= tolerance && db <= tolerance) ? 1 : 0;
    // `matches != keepsMatches` — CelColorKey.erases, exactly.
    return matches != spec->selector_keeps_matches ? 1 : 0;
  }
  return spec->takes_empty_pixels ? 1 : (alpha > 0 ? 1 : 0);
}

// Runs the pass over ONE tile. Returns 1 when anything was written, 0 when
// nothing was, and -1 when an undo walk reaches past the end of its stream.
//
// [in_pixels] is the tile's own bytes and is never written; [out_pixels] is
// a caller-owned scratch of the same size that receives a COPY at the first
// pixel that actually changes and the writes after it. A tile the walk
// crosses but never writes returns 0 and the caller keeps the original tile
// object — the copy-on-write law of `rewriteTileLazily`, in C.
//
// [mask] is tile-local coverage or NULL for full coverage.
// [incoming] is `byte_count` bytes going forward; on undo it is the recipe,
// read at `index * incoming_step` for global walk index `index` and
// `incoming_count` entries long (see the spec).
// [start_index] is the global walk index this tile starts at.
// [run_values_out] / [run_lengths_out] receive this tile's ORIGINALS as runs
// — consecutive touched pixels whose channel bytes are equal share one entry
// — or are NULL when no recipe is wanted. A run never spans two tiles here;
// the recipe builder joins them across tiles, so this only has to be exact,
// not maximal.
// [counts_out] receives { touched pixels, runs }.
//
// 🚨RUNS, NOT FLAT BYTES — that is what makes this pass worth having in C.
// The first version handed the originals back one entry per pixel, and the
// Dart loop feeding them to the recipe builder cost as much as the loop this
// replaced: measured in one process, 21 -> 13 ns/px on flat line art, and no
// gain at all on 4K. A flat cel is one run per tile.
//
// A recipe shorter than the walk it replays was built over some other
// surface, and the Dart reference refuses it too; here the alternative is
// reading whatever memory follows the stream.
QA_EXPORT int32_t qa_cel_pixel_pass_tile(const uint8_t* in_pixels,
                                         uint8_t* out_pixels,
                                         const uint8_t* mask,
                                         const qa_cel_pixel_spec* spec,
                                         const uint8_t* incoming,
                                         int64_t start_index,
                                         uint8_t* run_values_out,
                                         int32_t* run_lengths_out,
                                         int32_t* counts_out) {
  const int32_t pixel_count = spec->tile_size * spec->tile_size;
  const int32_t bytes = spec->byte_count;
  const int32_t base = spec->byte_offset_base;
  const int32_t stride = spec->byte_offset_stride;
  const int64_t incoming_count = spec->incoming_count;
  const ptrdiff_t incoming_step = spec->incoming_step;
  const int32_t threshold = spec->threshold;
  int32_t copied = 0;
  int32_t runs = 0;
  int64_t index = start_index;

  for (int32_t pixel = 0; pixel < pixel_count; pixel += 1) {
    const int32_t mask_value = mask != NULL ? mask[pixel] : 255;
    const ptrdiff_t offset = (ptrdiff_t)pixel * 4;
    if (!qa_cel_pixel_participates(spec, in_pixels[offset + 3], mask_value,
                                   in_pixels[offset], in_pixels[offset + 1],
                                   in_pixels[offset + 2])) {
      continue;
    }
    if (spec->is_undo && index >= incoming_count) {
      counts_out[0] = (int32_t)(index - start_index);
      counts_out[1] = runs;
      return -1;
    }
    if (!copied) {
      memcpy(out_pixels, in_pixels, (size_t)pixel_count * 4);
      copied = 1;
    }
    if (run_values_out != NULL) {
      int32_t same = 0;
      if (runs > 0) {
        const uint8_t* last = run_values_out + (ptrdiff_t)(runs - 1) * bytes;
        same = 1;
        for (int32_t byte = 0; byte < bytes; byte += 1) {
          if (last[byte] != in_pixels[offset + base + (ptrdiff_t)byte * stride]) {
            same = 0;
            break;
          }
        }
      }
      if (same) {
        run_lengths_out[runs - 1] += 1;
      } else {
        uint8_t* next = run_values_out + (ptrdiff_t)runs * bytes;
        for (int32_t byte = 0; byte < bytes; byte += 1) {
          next[byte] = in_pixels[offset + base + (ptrdiff_t)byte * stride];
        }
        run_lengths_out[runs] = 1;
        runs += 1;
      }
    }
    const uint8_t* source =
        spec->is_undo ? incoming + index * incoming_step : incoming;
    for (int32_t byte = 0; byte < bytes; byte += 1) {
      const ptrdiff_t at = offset + base + (ptrdiff_t)byte * stride;
      const uint8_t target =
          threshold > 0 && in_pixels[at] < threshold ? 0 : source[byte];
      // 🚨UNDO WRITES, IT DOES NOT BLEND — the same law the Dart loop's
      // comment states at length: running the recipe through the blend only
      // converges toward the original and never reaches it.
      out_pixels[at] = (spec->is_undo || mask_value == 255)
                           ? target
                           : qa_cel_pixel_blend(in_pixels[at], target,
                                                mask_value);
    }
    index += 1;
  }

  counts_out[0] = (int32_t)(index - start_index);
  counts_out[1] = runs;
  return copied;
}

// Engine ABI version - ONE number for this whole binary, and the Dart
// loader refuses a mismatched one.
//
// The changelog and the bump checklist live in the single place Dart
// reads this from: lib/src/native/qa_engine_abi.dart. Bumping here
// without bumping there fails qa_engine_abi_test.dart, which compares the
// literal below against kQaEngineAbiVersion and needs no binary to do it.
// v25: qa_resample_rgba - the shared image resampler (tent mean / coverage
// argmax) behind the transform tool, FX transforms, import fit and screen
// minification.
// v26: qa_resample_rgba gained clip_x/clip_y - where the destination
// buffer sits inside the full output rect, so a caller can compute one
// window of it bit-identically. Zero is the whole rect.
// v27: qa_video_decode_* - the export path's mirror (qa_video_decode.c).
// v28: qa_physical_memory_bytes - the device's RAM, for the hot cel
// budget.
// v29: qa_process_footprint_bytes / qa_available_memory_bytes - what this
// process is actually holding, and what the OS will still let it take.
// v31: qa_dab_spec gains aa_contrast + QA_DAB_FLAG_AA_THRESHOLD (brush edge).
// v32: qa_dab_spec gains dual_density + dual_one_minus_density.
// v33: qa_dab_spec's `reserved` int32 becomes dual_composite_mode - how the
// dual mask COMBINES with the coverage under it, through the same
// QA_STROKE_BLEND_* ids and the same qa_stroke_blend_channel table the
// stroke kernel reads. Multiply is the default and keeps its own line, so
// every brush that ever shipped draws byte-identically. Same slot, same
// size: sizeof does not move.
// v34: qa_cel_pixel_spec + qa_cel_pixel_pass_tile - the 색 변환 / 픽셀
// 비우기 pass over one tile, lazy copy included. One tile per call: the
// originals stream is shared across tiles in walk order, so a batched,
// pooled form would need every tile's count before any could start.
// Originals come back as RUNS, and an undo reads its recipe at a step
// (0 for a uniform one) - the flat-bytes shape left a Dart call per pixel on
// each side of the kernel. Changed inside this version, before it landed.
// v35: the video decoder's document became a HANDLE. `qa_video_decode_open`
// and `_open_range` answer one (0 is still failure), `_info`, `_frame` and
// `_close` take it, and `qa_video_decode_close_all` closes the lot. One
// native document meant a ~111ms re-open per switch, and a movie kept as a
// reference put three callers in the room at once — the canvas where it is
// shown, the playback warmer ahead of it, and export walking the cut.
// v36: qa_tile_pool_set_byte_cap + qa_app_memory_limit_bytes - the memory
// tab's allowance reaches the parked tile blocks (C-ipad-crash).
// v37: qa_media_span_* - ONE reader of a medium stored in a span, plain or
// framed, for every decoder and for Dart. `qa_video_decode_open_span`
// replaces `_open_range` and takes `framed`; `qa_video_decode_framed_
// supported` says whether this device can be fed a framed span;
// `qa_audio_decode_span` replaces `_range`, and `qa_audio_decode_memory` is
// gone with the in-memory origin it served.
// v38: qa_dab_blend_batch replaces qa_dab_blend_tiles - a call carries
// every dab it has (specs, and a clip each), the tiles they cover once, and
// the kernel cuts those tiles into row bands, each applying every dab that
// reaches it in order. One wake of the pool a call instead of one a dab.
// v39: qa_dab_spec gains tip_row_ink - each tip mask row's first and last
// inked column - and an unrotated tip's row visits only the pixels whose
// texels can hold ink (qa_tip_row_reach). Sizeof moves.
// v40: qa_tile_span gains tile_wide - the stroke tile's 16-bit plane - and
// qa_dab_blend_tile takes it: a dab reads what is under it from the plane
// and writes both planes (qa_dab_store). Sizeof moves.
// v41: qa_dab_spec gains evening - the table a dab lays its share of one
// stamp per tenth of its size through (qa_dab_even) - and the laid alpha
// reads it in qa_dab_source_alpha and the pair path. Sizeof moves.
// v42: qa_audio_decode_span_window - a window of a sound's frames, and only
// those held.
// v43: qa_audio_stream_open/_read/_close - a sound opened once and read on,
// every decoder through one door - and qa_audio_resampler_* - the resampler
// fed a piece at a time, through the loop qa_audio_resample runs.
// v44: qa_display_vblank / qa_display_wait_until_us - the compositor's
// vblank and a wait that ends on a microsecond, for a clock's frame to be
// handed to the GPU where it lands on the vblank it claimed.
// v45: qa_display_compose_every_vblank - the compositor kept composing on
// every vblank while a clock runs, so a picture handed over between two
// vblanks is taken at the second of them however idle the desktop is.
// v46: qa_premultiply_rgba_rows - the premultiplied copy between two row
// strides, so a block of tiles becomes one picture with one call a tile.
// v47: qa_audio_capture_clock / qa_audio_capture_frames - the capture's own
// clock line, so a take is placed by what the microphone had taken in when
// its anchor was heard.
// v48: qa_audio_buffer_new / _retain / _release / _holds, and a set_schedule
// that names buffers - the device's PCM is made once in C memory, and a
// schedule copies none of it.
// v49: qa_key_rgba - a row's colour keys over straight pixels in place,
// from tables the Dart definition makes, so a keyed cel is shown at C speed.
// v50: qa_audio_device_play gains lead_samples - a run started that much
// silence ahead of its first sample, so that sample is heard as its first
// picture is shown.
// v51: the stroke kernel's mode ids 13-25 - seven separable blends Photoshop
// and Clip Studio add (linear burn ... divide), which the dual mask reads
// too, and six that mix the three channels (qa_stroke_blend_triple). An
// older engine would take an id it does not know for exclusion.
// v52: qa_cel_pixel_spec gains threshold - 2치화: a byte under it is written
// 0 and the rest the incoming byte, forward only. Sizeof moves.
// v53: QA_DAB_FLAG_TEXTURE_HEIGHT - the paper's height cuts a dab's
// coverage (F-451). An older engine would multiply it.
// v54: the fill raster is premultiplied RGBA over nothing - no paper -
// and every flood takes its seed as one packed RGBA pixel, the coverage
// a lane like the colours (F-416). qa_fill_paper_rect becomes
// qa_fill_clear_rect; qa_fill_compose_batch loses the paper.
// v55: qa_audio_device_play returns the run it starts (it returned 1), and
// qa_audio_device_stop_run silences unless another run holds the device -
// a player's end stops only its own sound.
// v56: qa_dab_spec drops hard_radius and edge_span for an analytic round
// tip's profile - round_scale, round_reach, round_inner and the tables
// round_coverage and round_pile - and QA_DAB_FLAG_EDGE_HELD: a round tip is
// its profile read along its radius (qa_round_profile_at), and its edge does
// not pile (qa_dab_source_alpha's ceiling). Sizeof moves.
// v57: qa_dab_spec gains round_row_length: a small circle's round tables
// are square, what each pixel's whole square covers (qa_round_square_at),
// so a dot lays the same ink wherever it lies. Sizeof moves.
// v58: qa_blur_dab and qa_blur_result_tile - the blur brush (I-75): a dab
// rewrites the picture under it, read through a qa_blur_tile table.
// v59: qa_key_rgba gains originals, and its keeps bitmask is restores - a
// key gives back what its run erased of what it names (AE's Keep Colors,
// I-132-Q2) instead of erasing what it does not name.
// v60: the second tip is a second stroke - QA_DAB_FLAG_SECOND dabs pile on
// qa_tile_span's new tile_second plane, and qa_dab_blend_batch takes the
// view's dual_mode and dual_density and rebuilds the bytes of a span that
// carries it from both planes (qa_dual_view_rows). qa_dab_spec drops the
// per-dab dual mask - dual_density, dual_one_minus_density, dual_size,
// dual_composite_mode and its lattices. Sizeof moves, both structs.
QA_EXPORT int32_t qa_engine_abi_version(void) { return 61; }
