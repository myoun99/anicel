//! Straight rgba8888 bytes premultiplied into a block of their own, four
//! pixels a step (connection round; the C was qa_engine.c's premultiply,
//! R18 A-2a · R19-Z): what a tile's picture uploads
//! (`BitmapTileImageCache.premultipliedTileUpload`). The rounding is Skia's
//! SkMulDiv255Round, so an upload rounds as what Skia rasterizes from the
//! straight colours.
//!
//! 🚨A COPY, AND KNOWN TO BE ONE (관제 2026-11-13, connection-round-
//! checklist). The app's `premultiplyRgbaInPlace`
//! (lib/src/core/rgba_premultiply.dart) is this formula in Dart: the same
//! algorithm written twice (CLAUDE.md, absolute rule 1). Board card
//! `the-premultiply-is-spelled-twice-on-the-cpu` makes them one — the Dart
//! loop goes and its callers ask here. Till then this one stands for what it
//! costs: 🔬a 128 px tile staged — block, copy, free — in 8 µs here (the
//! C's 8 µs the same hour), where the Dart law on the tile lifted into a
//! list takes 63–69 µs; at 256 px, 38–44 µs against 358–407 (main PC,
//! 2026-11-13, test/services/premultiply_kernel_benchmark_test.dart). A
//! tile whose bytes are in RAM pays nothing else for its picture but the
//! upload. ↩️관제's first word was the Dart law alone and no CPU copy in the
//! engine (2026-11-07), the cost to be measured; that is the measure. The
//! two are held to the same bytes meanwhile, over every colour at every
//! alpha (test/ui/canvas/a_tile_upload_is_the_apps_premultiply_test.dart).
//!
//! ⚠️Not a kernel's formula kept for the CPU (kernels/mod.rs forbids that,
//! as the tests' oracle too): these bytes never reach the engine — Flutter
//! draws the picture they upload to. The kernels spell the rounding in
//! `premultiply8` (kernels/shared/premultiply.wgsl), and the app's law is
//! pinned to their ledger (`surface/premultiply`,
//! test/core/the_small_shared_laws_test.dart).
//!
//! FOUR PIXELS A STEP where the build has the SIMD (2026-10-12, the C): a
//! tile's premultiply was ~14% of the UI thread while playback made the
//! camera view's pictures (board playback-plays-the-screen-material), one
//! byte at a time behind a branch per pixel. The formula needs no branch —
//! alpha 255 gives the byte back and alpha 0 gives 0, whatever the colour —
//! so the fast paths were only that, and every lane takes the same steps:
//! the product and its 128 fit sixteen bits (65,153 at most), and so does
//! the rounding added to it (65,407), so the bytes are the scalar's. SSE2 is
//! baseline on x86-64 and NEON on aarch64, so neither asks the CPU what it
//! has; any other target takes the pixels one at a time.
//!
//! ⛔Not spread across threads (lane tile-pictures-in-one-call, 10-12, not
//! landed — over the worker pool the C's brush kernels had till ABI 80): a
//! run of tiles staged in one pooled call was never faster where it was
//! measured, the call waits for every worker it woke, and the composes that
//! give way between pictures took the one staging block from each other —
//! one make on a loaded machine staged its 72 runs 945 times.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[cfg(test)]
mod tests;

/// One pixel: each colour byte `round(value * alpha / 255)`
/// (SkMulDiv255Round), the alpha as it is.
#[inline(always)]
fn one(straight: [u8; 4]) -> [u8; 4] {
    let alpha = u32::from(straight[3]);
    let scaled = |value: u8| {
        let product = u32::from(value) * alpha + 128;
        ((product + (product >> 8)) >> 8) as u8
    };
    [scaled(straight[0]), scaled(straight[1]), scaled(straight[2]), straight[3]]
}

/// Four pixels: the sixteen bytes at `src` premultiplied into the sixteen
/// at `dst`.
///
/// # Safety
/// `src` and `dst` each hold sixteen bytes. They may be the same sixteen.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
unsafe fn four(dst: *mut u8, src: *const u8) {
    use std::arch::x86_64::{
        __m128i, _mm_add_epi16, _mm_and_si128, _mm_andnot_si128, _mm_loadu_si128,
        _mm_mullo_epi16, _mm_or_si128, _mm_packus_epi16, _mm_set1_epi16, _mm_set1_epi32,
        _mm_setzero_si128, _mm_shufflehi_epi16, _mm_shufflelo_epi16, _mm_srli_epi16,
        _mm_storeu_si128, _mm_unpackhi_epi8, _mm_unpacklo_epi8,
    };
    /// A pixel's alpha word in each of its four words.
    const ALPHA: i32 = 0b11_11_11_11;
    // SAFETY: SSE2 is every x86-64's; the load and the store are unaligned,
    // of the sixteen bytes the caller holds.
    unsafe {
        let zero = _mm_setzero_si128();
        let half = _mm_set1_epi16(128);
        let alpha_bytes = _mm_set1_epi32(0xFF00_0000_u32 as i32);
        let px = _mm_loadu_si128(src.cast::<__m128i>());
        let mut lo = _mm_unpacklo_epi8(px, zero);
        let mut hi = _mm_unpackhi_epi8(px, zero);
        let alpha_lo = _mm_shufflehi_epi16::<ALPHA>(_mm_shufflelo_epi16::<ALPHA>(lo));
        let alpha_hi = _mm_shufflehi_epi16::<ALPHA>(_mm_shufflelo_epi16::<ALPHA>(hi));
        lo = _mm_add_epi16(_mm_mullo_epi16(lo, alpha_lo), half);
        hi = _mm_add_epi16(_mm_mullo_epi16(hi, alpha_hi), half);
        lo = _mm_srli_epi16::<8>(_mm_add_epi16(lo, _mm_srli_epi16::<8>(lo)));
        hi = _mm_srli_epi16::<8>(_mm_add_epi16(hi, _mm_srli_epi16::<8>(hi)));
        let colour = _mm_packus_epi16(lo, hi);
        let premultiplied =
            _mm_or_si128(_mm_and_si128(px, alpha_bytes), _mm_andnot_si128(alpha_bytes, colour));
        _mm_storeu_si128(dst.cast::<__m128i>(), premultiplied);
    }
}

/// Four pixels: the sixteen bytes at `src` premultiplied into the sixteen
/// at `dst`.
///
/// # Safety
/// `src` and `dst` each hold sixteen bytes. They may be the same sixteen.
#[cfg(target_arch = "aarch64")]
#[inline(always)]
unsafe fn four(dst: *mut u8, src: *const u8) {
    use std::arch::aarch64::{
        vaddq_u16, vbslq_u8, vcombine_u8, vdupq_n_u16, vdupq_n_u32, vget_low_u8, vld1q_u8,
        vmull_high_u8, vmull_u8, vqtbl1q_u8, vreinterpretq_u8_u32, vshrn_n_u16, vshrq_n_u16,
        vst1q_u8,
    };
    /// Where each byte's alpha stands in its sixteen.
    const ALPHA_OF: [u8; 16] = [3, 3, 3, 3, 7, 7, 7, 7, 11, 11, 11, 11, 15, 15, 15, 15];
    // SAFETY: NEON is every aarch64's; the load and the store are of the
    // sixteen bytes the caller holds, and the table's sixteen.
    unsafe {
        let px = vld1q_u8(src);
        let alpha = vqtbl1q_u8(px, vld1q_u8(ALPHA_OF.as_ptr()));
        let half = vdupq_n_u16(128);
        let mut lo = vaddq_u16(vmull_u8(vget_low_u8(px), vget_low_u8(alpha)), half);
        let mut hi = vaddq_u16(vmull_high_u8(px, alpha), half);
        lo = vaddq_u16(lo, vshrq_n_u16::<8>(lo));
        hi = vaddq_u16(hi, vshrq_n_u16::<8>(hi));
        let colour = vcombine_u8(vshrn_n_u16::<8>(lo), vshrn_n_u16::<8>(hi));
        let alpha_bytes = vreinterpretq_u8_u32(vdupq_n_u32(0xFF00_0000));
        vst1q_u8(dst, vbslq_u8(alpha_bytes, px, colour));
    }
}

/// How many of `count` pixels are premultiplied four at a step: all the
/// fours there are where the build has the SIMD, none elsewhere.
///
/// # Safety
/// `src` and `dst` each hold `count * 4` bytes. They may be the same block.
#[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
#[inline(always)]
unsafe fn by_fours(dst: *mut u8, src: *const u8, count: usize) -> usize {
    let fours = count - count % 4;
    for at in (0..fours).step_by(4) {
        // SAFETY: four pixels from `at` are inside the `count` the caller
        // holds.
        unsafe { four(dst.add(at * 4), src.add(at * 4)) };
    }
    fours
}

/// How many of `count` pixels are premultiplied four at a step: none — this
/// build has no SIMD the formula was written for.
///
/// # Safety
/// None asked: nothing is read or written.
#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
#[inline(always)]
unsafe fn by_fours(_dst: *mut u8, _src: *const u8, _count: usize) -> usize {
    0
}

/// Fused copy + premultiply (R19-Z): reads `pixel_count` straight-alpha
/// pixels at `src` and writes them premultiplied at `dst` in one pass — the
/// decode-start path used to pay a copy AND an in-place premultiply.
/// Nothing is written for a count of none or less.
///
/// # Safety
/// `src` and `dst` each hold `pixel_count * 4` bytes. `dst` may be `src`: a
/// step reads its pixels before it writes them.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_premultiply_rgba_copy(dst: *mut u8, src: *const u8, pixel_count: i32) {
    let count = usize::try_from(pixel_count).unwrap_or(0);
    // SAFETY: the caller's `count` pixels, at both.
    let done = unsafe { by_fours(dst, src, count) };
    for at in done..count {
        // SAFETY: pixel `at` is inside the `count` the caller holds; it is
        // read whole into `straight` before any of it is written.
        unsafe {
            let straight = src.add(at * 4).cast::<[u8; 4]>().read_unaligned();
            dst.add(at * 4).cast::<[u8; 4]>().write_unaligned(one(straight));
        }
    }
}
