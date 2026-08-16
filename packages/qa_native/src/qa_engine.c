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
#include <sys/sysctl.h>
#include <sys/types.h>
#else
#include <sys/sysinfo.h>
#endif

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
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

    int64_t out_r;
    int64_t out_g;
    int64_t out_b;
    int64_t out_a;
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
        out_a = llround(out_alpha * 255.0);
        if (out_a < 0) out_a = 0;
        if (out_a > 255) out_a = 255;
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
        out_r = llround(((double)src[0] * source_alpha +
                         (double)dest_r * destination_alpha *
                             inverse_source_alpha) /
                        out_alpha);
        out_g = llround(((double)src[1] * source_alpha +
                         (double)dest_g * destination_alpha *
                             inverse_source_alpha) /
                        out_alpha);
        out_b = llround(((double)src[2] * source_alpha +
                         (double)dest_b * destination_alpha *
                             inverse_source_alpha) /
                        out_alpha);
        out_a = llround(out_alpha * 255.0);
        if (out_r < 0) out_r = 0;
        if (out_r > 255) out_r = 255;
        if (out_g < 0) out_g = 0;
        if (out_g > 255) out_g = 255;
        if (out_b < 0) out_b = 0;
        if (out_b > 255) out_b = 255;
        if (out_a < 0) out_a = 0;
        if (out_a > 255) out_a = 255;
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
  QA_DAB_FLAG_ROTATED_RECT = 8,
  QA_DAB_FLAG_TIP_UNROTATED = 16,
};

// Field order/types MUST match the Dart QaDabSpecStruct exactly; the
// loader cross-checks qa_dab_spec_sizeof() against Dart's sizeOf<>().
// Layout: doubles, then an even number of int32s, then pointers - natural
// alignment with no implicit padding on every supported ABI.
typedef struct {
  double center_x;
  double center_y;
  double radius;
  double hard_radius;
  double edge_span;
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
  int32_t source_r;
  int32_t source_g;
  int32_t source_b;
  int32_t flags;
  int32_t region_left;
  int32_t region_top;
  int32_t tip_size;
  int32_t dual_size;
  int32_t tex_size;
  int32_t reserved;
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
  // Dual-brush tiled mask lattices (wrapped texel pairs).
  const double* dual_alpha;
  const int32_t* dual_u_texel0;
  const int32_t* dual_u_texel1;
  const double* dual_u_fraction;
  const double* dual_u_one_minus;
  const int32_t* dual_v_texel0;
  const int32_t* dual_v_texel1;
  const double* dual_v_fraction;
  const double* dual_v_one_minus;
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
static int32_t qa_round_byte(double value) {
  int64_t rounded = llround(value);
  if (rounded < 0) return 0;
  if (rounded > 255) return 255;
  return (int32_t)rounded;
}

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

// sampleBrushTipMaskCoverageLattice: unrotated tip through axis lattices.
static double qa_sample_tip_lattice(
    const qa_dab_spec* s,
    int32_t u_index,
    int32_t v_index) {
  const int32_t size = s->tip_size;
  const double* alpha = s->tip_alpha;
  const int32_t x0 = s->tip_u_texel0[u_index];
  const int32_t y0 = s->tip_v_texel0[v_index];
  const int32_t x1 = x0 + 1;
  const int32_t y1 = y0 + 1;
  const double fraction_x = s->tip_u_fraction[u_index];
  const double one_minus_fraction_x = s->tip_u_one_minus[u_index];
  const int x0_in = x0 >= 0 && x0 < size;
  const int x1_in = x1 >= 0 && x1 < size;

  double top = 0.0;
  if (y0 >= 0 && y0 < size) {
    const int32_t row = y0 * size;
    top = (x0_in ? alpha[row + x0] : 0.0) * one_minus_fraction_x +
          (x1_in ? alpha[row + x1] : 0.0) * fraction_x;
  }
  double bottom = 0.0;
  if (y1 >= 0 && y1 < size) {
    const int32_t row = y1 * size;
    bottom = (x0_in ? alpha[row + x0] : 0.0) * one_minus_fraction_x +
             (x1_in ? alpha[row + x1] : 0.0) * fraction_x;
  }
  return qa_clamp01(
      top * s->tip_v_one_minus[v_index] + bottom * s->tip_v_fraction[v_index]);
}

// sampleBrushTipMaskTiledCoverageLattice: tiled mask (dual / texture)
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

// Blends one dab into one tile over the given canvas-space spans. Pixel
// visit set and math are identical to the Dart loop (which walks rows
// outermost; per-dab each pixel is touched exactly once either way).
// Returns nonzero when any destination byte changed.
QA_EXPORT int32_t qa_dab_blend_tile(
    uint8_t* tile_pixels,
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
  const int is_rotated_rect = (flags & QA_DAB_FLAG_ROTATED_RECT) != 0;
  const int unrotated_tip = (flags & QA_DAB_FLAG_TIP_UNROTATED) != 0;
  const int has_tip = s->tip_alpha != NULL;
  const int has_dual = s->dual_alpha != NULL;
  const int has_tex = s->tex_alpha != NULL;
  int32_t changed = 0;

  for (int32_t y = span_top; y < span_bottom_exclusive; y += 1) {
    const int32_t v_index = y - s->region_top;
    if (has_tip && unrotated_tip && s->tip_v_in_range[v_index] == 0) {
      continue;
    }
    const double dy = (double)y + 0.5 - s->center_y;
    const double dy_squared = dy * dy;
    const int32_t local_row_offset = (y - tile_top) * tile_size;

    for (int32_t x = span_left; x < span_right_exclusive; x += 1) {
      double coverage;
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
        if (distance > s->radius) {
          continue;
        }
        if (distance <= s->hard_radius || s->edge_span <= 0.0) {
          coverage = 1.0;
        } else {
          coverage =
              qa_clamp01(1.0 - ((distance - s->hard_radius) / s->edge_span));
        }
        if (coverage <= 0.0) {
          continue;
        }
      } else {
        if (is_rotated_rect) {
          const double dx = (double)x + 0.5 - s->center_x;
          const double tip_u = dx * s->tip_cos - dy * s->tip_sin;
          const double tip_v = dx * s->tip_sin + dy * s->tip_cos;
          if (fabs(tip_u) > s->radius || fabs(tip_v) > s->minor_radius) {
            continue;
          }
        }
        coverage = 1.0;
      }

      if (has_dual) {
        coverage *= qa_sample_tiled_lattice(
            s->dual_alpha, s->dual_size, s->dual_u_texel0, s->dual_u_texel1,
            s->dual_u_fraction, s->dual_u_one_minus, s->dual_v_texel0,
            s->dual_v_texel1, s->dual_v_fraction, s->dual_v_one_minus,
            x - s->region_left, v_index);
        if (coverage <= 0.0) {
          continue;
        }
      }
      if (has_tex) {
        const double texture_sample = qa_sample_tiled_lattice(
            s->tex_alpha, s->tex_size, s->tex_u_texel0, s->tex_u_texel1,
            s->tex_u_fraction, s->tex_u_one_minus, s->tex_v_texel0,
            s->tex_v_texel1, s->tex_v_fraction, s->tex_v_one_minus,
            x - s->region_left, v_index);
        coverage *= s->texture_one_minus_density +
                    s->texture_density * texture_sample;
        if (coverage <= 0.0) {
          continue;
        }
      }

      const double effective_opacity = s->dab_opacity * coverage;
      if (effective_opacity == 0.0) {
        continue;
      }
      const double source_alpha =
          s->source_alpha_norm * effective_opacity * s->dab_flow;

      uint8_t* pixel =
          tile_pixels + (ptrdiff_t)(local_row_offset + (x - tile_left)) * 4;
      const uint8_t dest_r = pixel[0];
      const uint8_t dest_g = pixel[1];
      const uint8_t dest_b = pixel[2];
      const uint8_t dest_a = pixel[3];
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
          out_r = qa_round_byte(
              ((double)s->source_r * source_alpha +
               (double)dest_r * destination_alpha * inverse_source_alpha) /
              out_alpha);
          out_g = qa_round_byte(
              ((double)s->source_g * source_alpha +
               (double)dest_g * destination_alpha * inverse_source_alpha) /
              out_alpha);
          out_b = qa_round_byte(
              ((double)s->source_b * source_alpha +
               (double)dest_b * destination_alpha * inverse_source_alpha) /
              out_alpha);
          out_a = qa_round_byte(out_alpha * 255.0);
        }
      }

      if ((uint8_t)out_r != dest_r || (uint8_t)out_g != dest_g ||
          (uint8_t)out_b != dest_b || (uint8_t)out_a != dest_a) {
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

// ---------------------------------------------------------------------------
// Alpha premultiply (R18 A-2a): the display upload path's per-tile
// conversion (BitmapTileImageCache.premultipliedTilePixels) - straight
// alpha to premultiplied with Skia's own SkMulDiv255Round so uploads
// round identically to Skia's rasterization. Pure integer math, ported
// verbatim from the Dart reference.
QA_EXPORT void qa_premultiply_rgba(uint8_t* pixels, int32_t pixel_count) {
  for (int32_t i = 0; i < pixel_count; i += 1) {
    uint8_t* p = pixels + (ptrdiff_t)i * 4;
    const int32_t alpha = p[3];
    if (alpha == 255) {
      continue;
    }
    if (alpha == 0) {
      p[0] = 0;
      p[1] = 0;
      p[2] = 0;
      continue;
    }
    // SkMulDiv255Round: round(value * alpha / 255) for bytes.
    int32_t product = p[0] * alpha + 128;
    p[0] = (uint8_t)((product + (product >> 8)) >> 8);
    product = p[1] * alpha + 128;
    p[1] = (uint8_t)((product + (product >> 8)) >> 8);
    product = p[2] * alpha + 128;
    p[2] = (uint8_t)((product + (product >> 8)) >> 8);
  }
}

// Fused copy + premultiply (R19-Z): reads straight-alpha [src], writes
// premultiplied bytes into [dst] in one pass - the decode-start path
// used to pay a copy AND an in-place premultiply. Same SkMulDiv255Round
// math as qa_premultiply_rgba (byte-identical output by construction).
QA_EXPORT void qa_premultiply_rgba_copy(
    uint8_t* dst,
    const uint8_t* src,
    int32_t pixel_count) {
  for (int32_t i = 0; i < pixel_count; i += 1) {
    const uint8_t* s = src + (ptrdiff_t)i * 4;
    uint8_t* d = dst + (ptrdiff_t)i * 4;
    const int32_t alpha = s[3];
    if (alpha == 255) {
      d[0] = s[0];
      d[1] = s[1];
      d[2] = s[2];
      d[3] = 255;
      continue;
    }
    if (alpha == 0) {
      d[0] = 0;
      d[1] = 0;
      d[2] = 0;
      d[3] = 0;
      continue;
    }
    int32_t product = s[0] * alpha + 128;
    d[0] = (uint8_t)((product + (product >> 8)) >> 8);
    product = s[1] * alpha + 128;
    d[1] = (uint8_t)((product + (product >> 8)) >> 8);
    product = s[2] * alpha + 128;
    d[2] = (uint8_t)((product + (product >> 8)) >> 8);
    d[3] = (uint8_t)alpha;
  }
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

// ---------------------------------------------------------------------------
// Flood fill, frontier-stepped (R18 A-2b; RGBX + SSE2 R22-D).
//
// R22-D: the fill raster is RGBX - 4 bytes per pixel, X always 0 (the
// paper fill writes whole words and the compose never touches byte 3).
// One pixel is one 32-bit word and four pixels fill an SSE2 register,
// so the span loops below test 4 px per step; scalar tails keep every
// DECISION byte-identical to the Dart reference (which stays scalar
// RGBX - the parity suite pins identical filled sets).

#if defined(_M_X64) || defined(__x86_64__) || defined(__SSE2__) || \
    (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#define QA_FLOOD_SSE2 1
#include <emmintrin.h>
typedef __m128i qa_vec4;
static inline qa_vec4 qa_vec4_splat(uint32_t word) {
  return _mm_set1_epi32((int32_t)word);
}
#elif defined(__aarch64__)
// R28 NEON port: the ARM mirror of the SSE2 compare - same saturating
// abs-diff (vabd), same X-lane mask, same <= tol semantics, so the
// decisions stay byte-identical (the permanent Dart oracle pins them
// on-device). aarch64 only (vaddvq); 32-bit ARM keeps the scalar path.
#define QA_FLOOD_NEON 1
#include <arm_neon.h>
typedef uint8x16_t qa_vec4;
static inline qa_vec4 qa_vec4_splat(uint32_t word) {
  return vreinterpretq_u8_u32(vdupq_n_u32(word));
}
#endif

#if defined(QA_FLOOD_SSE2) || defined(QA_FLOOD_NEON)
#define QA_FLOOD_SIMD 1
#endif

// One-pixel tolerance test against the seed color (RGBX layout).
static inline int qa_tol_ok1(
    const uint8_t* px,
    int32_t seed_r,
    int32_t seed_g,
    int32_t seed_b,
    int32_t tolerance) {
  const int32_t dr = (int32_t)px[0] - seed_r;
  const int32_t dg = (int32_t)px[1] - seed_g;
  const int32_t db = (int32_t)px[2] - seed_b;
  return dr <= tolerance && -dr <= tolerance && dg <= tolerance &&
         -dg <= tolerance && db <= tolerance && -db <= tolerance;
}

#if defined(QA_FLOOD_SSE2)
// Bit i (0..3) set = pixel i of the 16-byte RGBX block is within
// tolerance of the seed on R, G and B. The X lane is MASKED OUT of the
// abs-diff, so the test matches the scalar compare under ANY X bytes -
// no hidden "X must be 0" contract. The per-byte |p-seed| <= tol via
// saturating unsigned abs-diff is exact for the integer compare above.
static inline int qa_tol_ok4(const uint8_t* rgbx, qa_vec4 seed4, qa_vec4 tol4) {
  const __m128i p = _mm_loadu_si128((const __m128i*)rgbx);
  const __m128i d = _mm_and_si128(
      _mm_or_si128(_mm_subs_epu8(p, seed4), _mm_subs_epu8(seed4, p)),
      _mm_set1_epi32(0x00FFFFFF));
  const __m128i ok8 =
      _mm_cmpeq_epi8(_mm_subs_epu8(d, tol4), _mm_setzero_si128());
  const __m128i ok32 = _mm_cmpeq_epi32(ok8, _mm_set1_epi32(-1));
  return _mm_movemask_ps(_mm_castsi128_ps(ok32));
}
#elif defined(QA_FLOOD_NEON)
static inline int qa_tol_ok4(const uint8_t* rgbx, qa_vec4 seed4, qa_vec4 tol4) {
  const uint8x16_t p = vld1q_u8(rgbx);
  const uint8x16_t xmask = vreinterpretq_u8_u32(vdupq_n_u32(0x00FFFFFFu));
  const uint8x16_t d = vandq_u8(vabdq_u8(p, seed4), xmask);
  const uint8x16_t ok8 = vcleq_u8(d, tol4);
  const uint32x4_t ok32 =
      vceqq_u32(vreinterpretq_u32_u8(ok8), vdupq_n_u32(0xFFFFFFFFu));
  const uint32x4_t weights = {1u, 2u, 4u, 8u};
  return (int)vaddvq_u32(vandq_u32(ok32, weights));
}
#endif

// EXACT port of the Dart scanline flood (floodFillRegion): expand each
// popped run left/right, seed the rows above/below once per contiguous
// matching run. The Dart original composes raster tiles LAZILY through a
// callback; C cannot call back into Dart, so composition is stepped
// instead: pixels that fall in a not-yet-composed 2^shift tile are
// reported as CANDIDATES and treated as run boundaries. The Dart driver
// composes those tiles, re-tests the candidates (filled[] dedupes), and
// re-enters with them as fresh seeds. A scanline flood fills the whole
// connected tolerance-region from any seed inside it, so the final
// filled set is identical to the single-pass reference - the parity
// suite pins it.
//
// Guards keep every early return BETWEEN runs (never mid-run): before a
// pop, the call returns if the candidate buffer could not absorb a
// whole worst-case run (~4*width) or the stack could not absorb its
// pushes (~width). The driver then composes / grows and re-enters with
// the stack state intact (it lives in caller-owned native memory).
//
// Returns the number of candidate pixel indices written.
QA_EXPORT int32_t qa_flood_fill_step(
    const uint8_t* rgb,
    uint8_t* filled,
    const uint8_t* composed,
    int32_t width,
    int32_t height,
    int32_t compose_tile_shift,
    int32_t tiles_x,
    int32_t seed_r,
    int32_t seed_g,
    int32_t seed_b,
    int32_t tolerance,
    int32_t* stack,
    int32_t* stack_size,
    int32_t stack_capacity,
    int32_t* candidates,
    int32_t candidates_capacity,
    int32_t* bounds) {
  int32_t candidate_count = 0;
  const int32_t candidate_margin = 4 * width + 16;
  const int32_t stack_margin = width + 4;
  int32_t min_x = bounds[0];
  int32_t max_x = bounds[1];
  int32_t min_y = bounds[2];
  int32_t max_y = bounds[3];
#ifdef QA_FLOOD_SIMD
  const qa_vec4 seed4 = qa_vec4_splat(
      (uint32_t)seed_r | ((uint32_t)seed_g << 8) |
      ((uint32_t)seed_b << 16));
  const qa_vec4 tol4 = qa_vec4_splat(
      (uint32_t)tolerance | ((uint32_t)tolerance << 8) |
      ((uint32_t)tolerance << 16));
#endif

  while (*stack_size > 0) {
    if (candidate_count + candidate_margin > candidates_capacity ||
        *stack_size + stack_margin > stack_capacity) {
      break;
    }
    *stack_size -= 1;
    const int32_t index = stack[*stack_size];
    const int32_t y = index / width;
    const int32_t row_start = y * width;
    const int32_t tile_row = (y >> compose_tile_shift) * tiles_x;

    // Expand the scanline run left and right; an uncomposed tile is a
    // candidate + run boundary (the driver re-seeds it after compose).
    // Scans run per compose-tile SEGMENT (composed[] is constant inside
    // one), 4 px per SSE2 step with a scalar tail owning every edge
    // decision - identical stop points to the plain loop.
    int32_t left = index - row_start;
    for (;;) {
      if (left <= 0 || filled[row_start + left - 1] != 0) {
        break;
      }
      const int32_t px = left - 1;
      if (composed[tile_row + (px >> compose_tile_shift)] == 0) {
        candidates[candidate_count] = row_start + px;
        candidate_count += 1;
        break;
      }
      const int32_t seg_start = (px >> compose_tile_shift)
                                << compose_tile_shift;
      int32_t x = px;
      int32_t stop = 0;
#ifdef QA_FLOOD_SIMD
      while (x - 3 >= seg_start) {
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
#endif
      while (x >= seg_start) {
        const int32_t p = row_start + x;
        if (filled[p] != 0 ||
            !qa_tol_ok1(
                rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
                tolerance)) {
          stop = 1;
          break;
        }
        filled[p] = 255;
        x -= 1;
      }
      left = x + 1;
      if (stop) {
        break;
      }
    }
    int32_t right = index - row_start;
    for (;;) {
      if (right >= width - 1 || filled[row_start + right + 1] != 0) {
        break;
      }
      const int32_t px = right + 1;
      if (composed[tile_row + (px >> compose_tile_shift)] == 0) {
        candidates[candidate_count] = row_start + px;
        candidate_count += 1;
        break;
      }
      int32_t seg_end =
          ((((px >> compose_tile_shift) + 1) << compose_tile_shift)) - 1;
      if (seg_end > width - 1) {
        seg_end = width - 1;
      }
      int32_t x = px;
      int32_t stop = 0;
#ifdef QA_FLOOD_SIMD
      while (x + 3 <= seg_end) {
        uint32_t f4;
        memcpy(&f4, filled + row_start + x, 4);
        if (f4 != 0) {
          break;
        }
        if (qa_tol_ok4(rgb + ((ptrdiff_t)(row_start + x) << 2), seed4, tol4) !=
            0xF) {
          break;
        }
        memset(filled + row_start + x, 255, 4);
        x += 4;
      }
#endif
      while (x <= seg_end) {
        const int32_t p = row_start + x;
        if (filled[p] != 0 ||
            !qa_tol_ok1(
                rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
                tolerance)) {
          stop = 1;
          break;
        }
        filled[p] = 255;
        x += 1;
      }
      right = x - 1;
      if (stop) {
        break;
      }
    }
    if (left < min_x) min_x = left;
    if (right > max_x) max_x = right;
    if (y < min_y) min_y = y;
    if (y > max_y) max_y = y;

    // Seed the rows above and below across the run - ONE seed per
    // contiguous matching run; uncomposed pixels are candidates and
    // close the current run exactly like a non-match. The composed
    // check hoists per segment; the SSE2 block computes a 4-px match
    // mask (unfilled AND within tolerance) and a scalar walk over the
    // bits runs the run_open state machine - decision-identical to the
    // plain loop.
    for (int32_t direction = 0; direction < 2; direction += 1) {
      const int32_t neighbor_y = direction == 0 ? y - 1 : y + 1;
      if (neighbor_y < 0 || neighbor_y >= height) {
        continue;
      }
      const int32_t neighbor_row = neighbor_y * width;
      const int32_t neighbor_tile_row =
          (neighbor_y >> compose_tile_shift) * tiles_x;
      int32_t run_open = 0;
      int32_t x = left;
      while (x <= right) {
        if (composed[neighbor_tile_row + (x >> compose_tile_shift)] == 0) {
          candidates[candidate_count] = neighbor_row + x;
          candidate_count += 1;
          run_open = 0;
          x += 1;
          continue;
        }
        int32_t seg_end =
            ((((x >> compose_tile_shift) + 1) << compose_tile_shift)) - 1;
        if (seg_end > right) {
          seg_end = right;
        }
#ifdef QA_FLOOD_SIMD
        while (x + 3 <= seg_end) {
          const int32_t p0 = neighbor_row + x;
          uint32_t f4;
          memcpy(&f4, filled + p0, 4);
          int32_t match =
              qa_tol_ok4(rgb + ((ptrdiff_t)p0 << 2), seed4, tol4);
          // Clear match bits for already-filled pixels (they close a
          // run exactly like a non-match in the reference loop).
          if (f4 != 0) {
            if (f4 & 0xFFu) match &= ~1;
            if (f4 & 0xFF00u) match &= ~2;
            if (f4 & 0xFF0000u) match &= ~4;
            if (f4 & 0xFF000000u) match &= ~8;
          }
          if (match == 0) {
            run_open = 0;
            x += 4;
            continue;
          }
          for (int32_t i = 0; i < 4; i += 1) {
            if (match & (1 << i)) {
              if (!run_open) {
                const int32_t p = p0 + i;
                filled[p] = 255;
                stack[*stack_size] = p;
                *stack_size += 1;
                run_open = 1;
              }
            } else {
              run_open = 0;
            }
          }
          x += 4;
        }
#endif
        while (x <= seg_end) {
          const int32_t p = neighbor_row + x;
          if (filled[p] == 0 &&
              qa_tol_ok1(
                  rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
                  tolerance)) {
            if (!run_open) {
              filled[p] = 255;
              stack[*stack_size] = p;
              *stack_size += 1;
              run_open = 1;
            }
          } else {
            run_open = 0;
          }
          x += 1;
        }
      }
    }
  }

  bounds[0] = min_x;
  bounds[1] = max_x;
  bounds[2] = min_y;
  bounds[3] = max_y;
  return candidate_count;
}

// ---------------------------------------------------------------------------
// Fill raster compose (R18 A-2c): LazyCanvasRasterRgb's per-tile compose
// ported verbatim - the clean-run lab showed the lazy compose (paper
// fill + integer source-over of layer tiles onto the RGB raster) is
// most of what remains inside the fill.flood probe now that the flood
// itself is native.

// Fills a raster rect with the paper color (RGBX, 4 bytes per pixel;
// X writes 0 for determinism - the SIMD tolerance compare masks the X
// lane out, so nothing depends on it).
QA_EXPORT void qa_fill_paper_rect(
    uint8_t* rgb,
    int32_t raster_width,
    int32_t left,
    int32_t top,
    int32_t right_exclusive,
    int32_t bottom_exclusive,
    int32_t paper_r,
    int32_t paper_g,
    int32_t paper_b) {
  const uint32_t paper = (uint32_t)paper_r | ((uint32_t)paper_g << 8) |
                         ((uint32_t)paper_b << 16);
  for (int32_t y = top; y < bottom_exclusive; y += 1) {
    uint32_t* dst =
        (uint32_t*)(rgb + (((ptrdiff_t)y * raster_width + left) << 2));
    for (int32_t x = left; x < right_exclusive; x += 1) {
      *dst = paper;
      dst += 1;
    }
  }
}

// Integer source-over of one RGBA surface-tile clip onto the RGBX
// raster (byte-rounded, exactly the Dart loop: effective =
// (a*o+127)/255 etc.). The X byte stays untouched (0 from the paper
// fill).
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
      // llround for byte identity.
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
            const int64_t rounded =
                llround((double)(center * 3 + (sum - center)) / 7.0);
            dst_row[x] = (uint8_t)rounded;
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
// 256px tile through per-tile serial FFI calls (paper rect + one call
// per intersecting layer tile). One batch call now fans compose TILES
// across the worker pool; within one tile the paper fill and the layer
// blends run sequentially in order (source-over order IS the bytes),
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

// One compose TILE of a batch: paper-fill its rect, then run its slice
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

static struct {
  uint8_t* rgb;
  int32_t raster_width;
  int32_t paper_r, paper_g, paper_b;
  const qa_compose_tile_item* items;
  const qa_compose_blend* blends;
} g_compose_job;

static void qa_compose_batch_item(int32_t item_index, void* context) {
  (void)context;
  const qa_compose_tile_item* item = &g_compose_job.items[item_index];
  qa_fill_paper_rect(
      g_compose_job.rgb, g_compose_job.raster_width, item->tile_left,
      item->tile_top, item->tile_right_exclusive, item->tile_bottom_exclusive,
      g_compose_job.paper_r, g_compose_job.paper_g, g_compose_job.paper_b);
  for (int32_t i = 0; i < item->blend_count; i += 1) {
    const qa_compose_blend* blend =
        &g_compose_job.blends[item->first_blend + i];
    qa_fill_compose_tile(
        g_compose_job.rgb, g_compose_job.raster_width, blend->tile_pixels,
        blend->tile_size, blend->base_x, blend->base_y, blend->clip_left,
        blend->clip_top, blend->clip_right_exclusive,
        blend->clip_bottom_exclusive, blend->opacity_int);
  }
}

QA_EXPORT void qa_fill_compose_batch(
    uint8_t* rgb,
    int32_t raster_width,
    int32_t paper_r,
    int32_t paper_g,
    int32_t paper_b,
    const qa_compose_tile_item* items,
    int32_t item_count,
    const qa_compose_blend* blends) {
  g_compose_job.rgb = rgb;
  g_compose_job.raster_width = raster_width;
  g_compose_job.paper_r = paper_r;
  g_compose_job.paper_g = paper_g;
  g_compose_job.paper_b = paper_b;
  g_compose_job.items = items;
  g_compose_job.blends = blends;
  qa_pool_run(qa_compose_batch_item, NULL, item_count);
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
    int32_t seed_r,
    int32_t seed_g,
    int32_t seed_b,
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
  // Full-canvas tolerance mask, 4 px per step (RGBX) - at 8K this pass
  // alone walks 132MB.
  const qa_vec4 seed4 = qa_vec4_splat(
      (uint32_t)seed_r | ((uint32_t)seed_g << 8) |
      ((uint32_t)seed_b << 16));
  const qa_vec4 tol4 = qa_vec4_splat(
      (uint32_t)tolerance | ((uint32_t)tolerance << 8) |
      ((uint32_t)tolerance << 16));
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
                      rgb + (i << 2), seed_r, seed_g, seed_b, tolerance)
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

// Runs job_fn(0..item_count-1, context) across the pool + the caller;
// returns only when every item completed.
static void qa_pool_run(qa_job_fn job_fn, void* context, int32_t item_count) {
  if (item_count <= 0) {
    return;
  }
  qa_pool_init_once();
  if (g_pool.worker_count == 0 || item_count == 1) {
    for (int32_t i = 0; i < item_count; i += 1) {
      job_fn(i, context);
    }
    return;
  }
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

// Runs job_fn(0..item_count-1, context) across the pool + the caller;
// returns only when every item completed.
static void qa_pool_run(qa_job_fn job_fn, void* context, int32_t item_count) {
  if (item_count <= 0) {
    return;
  }
  qa_pool_init_once();
  if (g_pool.worker_count == 0 || item_count == 1) {
    for (int32_t i = 0; i < item_count; i += 1) {
      job_fn(i, context);
    }
    return;
  }
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

// --- Batched generic dab blend -------------------------------------------

typedef struct {
  qa_tile_span* tiles;
  int32_t tile_size;
  const qa_dab_spec* spec;
  uint8_t* changed_out;
} qa_dab_batch_context;

static void qa_dab_batch_item(int32_t item_index, void* context) {
  const qa_dab_batch_context* batch = (const qa_dab_batch_context*)context;
  const qa_tile_span* span = &batch->tiles[item_index];
  batch->changed_out[item_index] = (uint8_t)qa_dab_blend_tile(
      span->tile_pixels, batch->tile_size, span->tile_left, span->tile_top,
      span->span_left, span->span_right_exclusive, span->span_top,
      span->span_bottom_exclusive, batch->spec);
}

// Blends one dab into MANY tiles in one call, fanned across the pool.
QA_EXPORT void qa_dab_blend_tiles(
    qa_tile_span* tiles,
    int32_t tile_count,
    int32_t tile_size,
    const qa_dab_spec* spec,
    uint8_t* changed_out) {
  qa_dab_batch_context context;
  context.tiles = tiles;
  context.tile_size = tile_size;
  context.spec = spec;
  context.changed_out = changed_out;
  qa_pool_run(qa_dab_batch_item, &context, tile_count);
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

// Mode ids: a fixed FFI contract - the Dart side maps BrushBlendMode
// through `strokeBlendModeNativeId` with EXACTLY these values. color and
// erase never reach this kernel (they ride the ordinary stamp path).
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
};

static inline int32_t qa_stroke_clamp_byte(double value) {
  int64_t rounded = llround(value * 255.0);
  if (rounded < 0) return 0;
  if (rounded > 255) return 255;
  return (int32_t)rounded;
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
    case QA_STROKE_BLEND_EXCLUSION:
    default:
      return cs + cd - 2.0 * cs * cd;
  }
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
        out_r = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_r + ad * (1.0 - as_) * cd_r +
             as_ * ad * qa_stroke_blend_channel(mode, cs_r, cd_r)) /
            ao);
        out_g = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_g + ad * (1.0 - as_) * cd_g +
             as_ * ad * qa_stroke_blend_channel(mode, cs_g, cd_g)) /
            ao);
        out_b = qa_stroke_clamp_byte(
            (as_ * (1.0 - ad) * cs_b + ad * (1.0 - as_) * cd_b +
             as_ * ad * qa_stroke_blend_channel(mode, cs_b, cd_b)) /
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
  QA_PRE_BLEND_STROKE = 2,    // the 13 brush blends (mode = QA_STROKE_BLEND_*)
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
// The sequential stepper (qa_flood_fill_step) grows the region pixel by
// pixel; at 64MP it is the app's dominant fill term. This engine keeps
// the SAME lazy-compose protocol with the Dart driver (uncomposed
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
  int32_t seed_r, seed_g, seed_b, tolerance;
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
  const int32_t seed_r = g_wave_job.seed_r;
  const int32_t seed_g = g_wave_job.seed_g;
  const int32_t seed_b = g_wave_job.seed_b;
  const int32_t tolerance = g_wave_job.tolerance;
#ifdef QA_FLOOD_SIMD
  const qa_vec4 seed4 = qa_vec4_splat(
      (uint32_t)seed_r | ((uint32_t)seed_g << 8) |
      ((uint32_t)seed_b << 16));
  const qa_vec4 tol4 = qa_vec4_splat(
      (uint32_t)tolerance | ((uint32_t)tolerance << 8) |
      ((uint32_t)tolerance << 16));
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
              rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b, tolerance)) {
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
                rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
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
                rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
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
                rgb + ((ptrdiff_t)p << 2), seed_r, seed_g, seed_b,
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

// One full lazy-protocol round: floods EVERYTHING reachable through
// currently-composed tiles (wave-parallel), returns crossings into
// uncomposed tiles as candidates (same contract as the sequential
// stepper: the driver composes them, re-seeds the matches, re-enters).
// stack in: the driver's seeds; out: always fully consumed (0).
// Returns the candidate count, or -1 on any allocation/bound failure -
// the caller redoes the fill on the sequential path from clean state.
QA_EXPORT int32_t qa_flood_fill_wave(
    const uint8_t* rgb,
    uint8_t* filled,
    const uint8_t* composed,
    int32_t width,
    int32_t height,
    int32_t compose_tile_shift,
    int32_t tiles_x,
    int32_t seed_r,
    int32_t seed_g,
    int32_t seed_b,
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
  g_wave_job.seed_r = seed_r;
  g_wave_job.seed_g = seed_g;
  g_wave_job.seed_b = seed_b;
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
  if (g_tile_pool_cached_bytes + size <= QA_TILE_POOL_BYTE_CAP) {
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

// Releases every parked block (diagnostics / tests).
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
  // Rounded-rect ops (T2: the cell BLOCK chrome - block start/end corners
  // round, so the tile path needs analytic-AA corners to match the Skia
  // painter's look):
  //   QA_GRID_OP_RRECT_FILL   (5): x_q8, y_q8, w_q8, h_q8, radius_q8,
  //                                corner_mask, rgba         = 8 words
  //   QA_GRID_OP_RRECT_STROKE (6): x_q8, y_q8, w_q8, h_q8, radius_q8,
  //                                corner_mask, thickness_q8,
  //                                rgba                      = 9 words
  // Every _q8 field is 24.8 fixed point (pixels * 256): cell rects are
  // FRACTIONAL at fractional zooms, so the whole geometry rides
  // sub-pixel. corner_mask bit0=TL, bit1=TR, bit2=BL, bit3=BR (unset
  // corners stay square). AA coverage comes from the rounded-box SDF
  // with float sqrt - IEEE correctly-rounded, so bytes stay identical
  // across platforms.
  QA_GRID_OP_RRECT_FILL = 5,
  QA_GRID_OP_RRECT_STROKE = 6,
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

// Shared raster loop for RRECT_FILL/STROKE: analytic-AA coverage from
// the rounded-box SDF (fill: 0.5 - d; stroke of thickness t centered on
// the boundary: 0.5 - (|d| - t/2)), blended source-over per pixel.
static void qa_grid_blend_rrect(
    uint8_t* pixels,
    int32_t tile_width,
    int32_t tile_height,
    double x,
    double y,
    double w,
    double h,
    double radius,
    int32_t corner_mask,
    double stroke_thickness,  // <= 0 = fill
    uint32_t rgba) {
  const int32_t color_a = (int32_t)(rgba >> 24) & 0xFF;
  if (color_a == 0 || w <= 0.0 || h <= 0.0) {
    return;
  }
  const double half_w = w * 0.5;
  const double half_h = h * 0.5;
  double max_radius = half_w < half_h ? half_w : half_h;
  if (radius > max_radius) {
    radius = max_radius;
  }
  const double radius_tl = (corner_mask & 1) != 0 ? radius : 0.0;
  const double radius_tr = (corner_mask & 2) != 0 ? radius : 0.0;
  const double radius_bl = (corner_mask & 4) != 0 ? radius : 0.0;
  const double radius_br = (corner_mask & 8) != 0 ? radius : 0.0;
  const double center_x = x + half_w;
  const double center_y = y + half_h;
  const double reach = stroke_thickness > 0.0 ? stroke_thickness * 0.5 : 0.0;

  int32_t left = (int32_t)(x - reach - 1.0);
  int32_t top = (int32_t)(y - reach - 1.0);
  int32_t right = (int32_t)(x + w + reach + 2.0);
  int32_t bottom = (int32_t)(y + h + reach + 2.0);
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
      const double d = qa_grid_rrect_distance(
          (double)px + 0.5, (double)py + 0.5, center_x, center_y, half_w,
          half_h, radius_tl, radius_tr, radius_bl, radius_br);
      double coverage;
      if (stroke_thickness > 0.0) {
        const double ad = d < 0.0 ? -d : d;
        coverage = 0.5 - (ad - reach);
      } else {
        coverage = 0.5 - d;
      }
      if (coverage > 0.0) {
        if (coverage > 1.0) {
          coverage = 1.0;
        }
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
        qa_grid_blend_rrect(
            pixels, tile_width, tile_height,
            (double)ops[cursor + 1] / 256.0, (double)ops[cursor + 2] / 256.0,
            (double)ops[cursor + 3] / 256.0, (double)ops[cursor + 4] / 256.0,
            (double)ops[cursor + 5] / 256.0, ops[cursor + 6], 0.0,
            (uint32_t)ops[cursor + 7]);
        cursor += 8;
        break;
      }
      case QA_GRID_OP_RRECT_STROKE: {
        if (cursor + 9 > op_word_count) return -2;
        qa_grid_blend_rrect(
            pixels, tile_width, tile_height,
            (double)ops[cursor + 1] / 256.0, (double)ops[cursor + 2] / 256.0,
            (double)ops[cursor + 3] / 256.0, (double)ops[cursor + 4] / 256.0,
            (double)ops[cursor + 5] / 256.0, ops[cursor + 6],
            (double)ops[cursor + 7] / 256.0, (uint32_t)ops[cursor + 8]);
        cursor += 9;
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
  if (samples == NULL || out == NULL || channels <= 0 || input_frames <= 0 ||
      input_rate <= 0 || output_rate <= 0 || input_rate == output_rate) {
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
  const int64_t half_length = (taps - 1) / 2;

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

  const int64_t output_frames = input_frames * interpolation / decimation;
  for (int64_t frame = 0; frame < output_frames; frame += 1) {
    // + half_length centres the filter on the output instant: the delay
    // compensation, applied here so it never has to be a whole number of
    // output samples.
    const int64_t position = frame * decimation + half_length;
    const int64_t phase = position % interpolation;
    const int64_t base = position / interpolation;

    for (int32_t channel = 0; channel < channels; channel += 1) {
      double sum = 0.0;
      int64_t tap = phase;
      int64_t source = base;
      while (tap < taps && source >= 0) {
        if (source < input_frames) {
          sum += kernel[tap] * (double)samples[source * channels + channel];
        }
        tap += interpolation;
        source -= 1;
      }
      out[frame * channels + channel] = (float)sum;
    }
  }
  free(kernel);
  return output_frames;
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
        // and a tie that survives the cap is a real one and falls through
        // to the token met first. See the Dart reference.
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
QA_EXPORT int32_t qa_engine_abi_version(void) { return 28; }
