//! The app's colour law for movies: BT.601, studio range, 4:2:0 — how a
//! picture becomes YCbCr when this app writes a movie, and how YCbCr becomes
//! a picture where this app converts one back itself. BOTH DIRECTIONS HERE,
//! so the matrix one side writes is the matrix the other side reads.
//!
//! 🚨★★★**THE WRITERS CONVERT, NOT THE OS.** Apple's writer handed its
//! encoder BGRA and let VideoToolbox turn it into YCbCr, and what came back
//! through the Apple reader had lost red in exact proportion to it — 0.9136
//! of itself each way round, which is BT.709 in and BT.601 out. Measured on
//! the Apple runner: red 110 written came back 101, and a piece cut from a
//! take came back 168 where the take showed 185 and 200 was written
//! (2026-09-24, board `trimmed-piece-apple-parity`). Naming BT.601 in the
//! writer's colour properties moved none of those numbers, so the matrix is
//! not the writer's to choose that way — it is chosen by handing the encoder
//! YCbCr made HERE. The Android writer always converted by hand; this is now
//! that conversion, for both. (Media Foundation's writer and reader agree
//! with each other within 3, and keep their own.)

/// A straight-RGBA picture, rows top-down and packed.
pub struct Picture<'a> {
    pub rgba: &'a [u8],
    pub width: usize,
    pub height: usize,
}

/// Where a 4:2:0 frame's planes lie, because every buffer this fills lays
/// them out its own way: `y` rows are `y_stride` bytes apart, and the
/// chroma sample for 2×2 pixels lands at
/// `row * chroma_stride + column * chroma_step` past `cb` (and past `cr`)
/// in `chroma` — `chroma_step` 2 with `cr = cb + 1` for interleaved NV12, 1
/// with two separate planes for I420.
pub struct Planes<'a> {
    pub y: &'a mut [u8],
    pub y_stride: usize,
    pub chroma: &'a mut [u8],
    pub cb: usize,
    pub cr: usize,
    pub chroma_stride: usize,
    pub chroma_step: usize,
}

/// `width`×`height` of 4:2:0 BT.601 studio range from `picture`, which fills
/// the top-left of the frame; the rest is PADDING, painted white (an encoder
/// takes even sizes; the picture may be odd).
///
/// ⚠️Each 2×2 block takes its chroma from its top-left pixel rather than an
/// average: it is what the Android writer always did, and a flat picture —
/// what every test of this reads — is the same either way.
///
/// 🚨★★★TWO SPELLINGS OF ONE CONVERSION, ON PURPOSE (관제 2026-11-12,
/// gpu-export-path ⑶-3 ①). The GPU engine's NV12 pass
/// (`gpu_engine` `kernels/export/nv12.wgsl`) makes these same bytes for an
/// export's frames, and the writers only lay them (`export/nv12.rs`). This
/// one stays for a trimmed movie, re-encoded on a worker that has no GPU
/// engine (`lib/src/services/media/movie_span.dart` `writeMovieSpan`). The
/// pass's tests hold it to this byte for byte (`kernels/export/tests.rs`,
/// this their oracle) — ⛔change one and the other goes with it, or the
/// export and the trimmed movie part colours. It goes when the decoder
/// hands NV12 itself and nothing comes here as RGBA (board
/// `trimmed-movie-decodes-to-nv12`).
pub fn from_rgba(picture: &Picture, width: usize, height: usize, planes: &mut Planes) {
    for y in 0..height {
        for x in 0..width {
            let (r, g, b) = if x < picture.width && y < picture.height {
                let pixel = &picture.rgba[(y * picture.width + x) * 4..];
                (i32::from(pixel[0]), i32::from(pixel[1]), i32::from(pixel[2]))
            } else {
                (255, 255, 255)
            };
            planes.y[y * planes.y_stride + x] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16) as u8;
            if x & 1 == 0 && y & 1 == 0 {
                let at = (y / 2) * planes.chroma_stride + (x / 2) * planes.chroma_step;
                planes.chroma[planes.cb + at] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128) as u8;
                planes.chroma[planes.cr + at] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128) as u8;
            }
        }
    }
}

/// YUV420 → RGBA, BT.601 studio range — the inverse of [`from_rgba`].
///
/// `stride` is BYTES PER LUMA ROW and `slice` the rows between the Y plane
/// and the chroma that follows it. Both are ≥ the picture, and assuming
/// either equals it is the classic way to get a green-striped frame on one
/// vendor's hardware and a correct one on another's. `semi_planar` picks
/// NV12 (interleaved chroma) over planar I420.
///
/// 🚨★★★**IT LIVES IN THE LAW BECAUSE IT IS ARITHMETIC, AND BECAUSE IT WAS
/// NEVER RUN.** It was inside the Android backend, where it compiled on
/// every PR and executed on no machine anybody has — the card
/// `android-decoder-branch-never-runs` is about exactly that gap. Nothing in
/// it touches a platform: it reads bytes and writes bytes, so it can be
/// proven on the bench, round trip included.
///
/// ⛔The picture size comes in as ARGUMENTS. It used to read the decoder's
/// global document, which is what tied a pure calculation to a backend
/// having opened something.
///
/// ⚠️Whether it could: `data` that ends before the last byte its own stride
/// and slice place is refused, not read past — the C read on regardless
/// (2026-11-07, the decoder's move to Rust, where reading past is a panic
/// and a panic across the FFI is the app gone).
#[must_use]
pub fn to_rgba(
    data: &[u8],
    width: usize,
    height: usize,
    stride: usize,
    slice: usize,
    semi_planar: bool,
    rgba: &mut [u8],
) -> bool {
    let cb_at = stride * slice;
    let (cr_at, chroma_stride, chroma_step) =
        if semi_planar { (cb_at + 1, stride, 2) } else { (cb_at + (stride / 2) * (slice / 2), stride / 2, 1) };
    if width == 0 || height == 0 {
        return true;
    }
    let last_luma = (height - 1) * stride + width - 1;
    let last_chroma = cr_at + (height - 1) / 2 * chroma_stride + (width - 1) / 2 * chroma_step;
    if data.len() <= last_luma.max(last_chroma) || rgba.len() < width * height * 4 {
        return false;
    }
    for y in 0..height {
        for x in 0..width {
            let chroma = (y / 2) * chroma_stride + (x / 2) * chroma_step;
            let luma = i32::from(data[y * stride + x]) - 16;
            let cb = i32::from(data[cb_at + chroma]) - 128;
            let cr = i32::from(data[cr_at + chroma]) - 128;
            let r = (298 * luma + 409 * cr + 128) >> 8;
            let g = (298 * luma - 100 * cb - 208 * cr + 128) >> 8;
            let b = (298 * luma + 516 * cb + 128) >> 8;
            let out = &mut rgba[(y * width + x) * 4..][..4];
            out.copy_from_slice(&[r.clamp(0, 255) as u8, g.clamp(0, 255) as u8, b.clamp(0, 255) as u8, 255]);
        }
    }
    true
}

#[cfg(test)]
mod tests;
