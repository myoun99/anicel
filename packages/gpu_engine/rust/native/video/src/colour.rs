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
//! that conversion, for every writer. ↩️Media Foundation's writer kept its
//! own until 2026-11-14 — its writer and reader agreed with each other
//! within 3 — and takes this law's NV12 since, which its reader reads as
//! closely (`export/windows.rs`).
//!
//! 🚨★★**WHAT A WRITER SAYS ITS PICTURES ARE: THE SAME FOUR NAMES FROM EVERY
//! WRITER** (2026-11-14, board the-apple-writer-tags-bt709-transfer-on-a-
//! video) — BT.601's matrix, studio range, SMPTE C's primaries and BT.709's
//! transfer. The transfer is the one curve every writer can name: Apple's
//! settings and Android's formats offer no sRGB one. The bytes are the
//! canvas's own values all the same: this law's own reader reads them back
//! as they are, and so does Media Foundation's, the primaries named right.
//! 🔬WHAT BROKE, ONE CAUSE ON TWO MACHINES (2026-11-14, `tests/decode.rs`):
//! Windows' writer named the primaries SMPTE_C, which its muxer writes as
//! 8 — generic film. On Surface (Intel) its reader then came back 16
//! brighter in the darks wherever BT.709's transfer was named beside
//! them, converting from those primaries; on the main PC (NVIDIA RTX
//! 4080) it let the whole colour description go, whatever the transfer,
//! and read a 1920×1080 movie as BT.709's matrix — green +13. Named
//! SMPTE170M (6), the four read back within 3 on both, the reader asked
//! nothing. ↩️So Windows' writer named sRGB's transfer for a day — which
//! hid the first and not the second. Android's writer names them
//! too since that day (it had named none — an HD movie it wrote read as
//! BT.709 on Windows); ⚠️no device read one back where this was measured.
//!
//! 🗣️★★★**A PIECE CUT FROM A MOVIE IS NOT WRITTEN IN THIS LAW — IT KEEPS
//! THE MOVIE'S OWN** (유저 2026-11-14, board trimmed-movie-decodes-to-nv12-Q1:
//! 「원본의 색을 그대로 따라 쓴다」). This law is how the app makes YCbCr
//! of a picture it drew; a trimmed piece has YCbCr already. Its decoder
//! hands the movie's 4:2:0 as it is ([`nv12_of`]) and says what the movie
//! calls it ([`Colours`]); its writer lays those bytes and names those
//! colours, and names nothing the movie did not. No sum either way.
//! ⚠️So a piece's writer takes no RGBA (`export`): RGBA becomes YCbCr in
//! this law only, which is not what the piece says it holds.

/// What a movie says its pictures are, in the code points every container
/// and bitstream spell them in (ITU-T H.273 — an MP4's `colr`, H.264's
/// VUI): the colour primaries, the transfer curve and the YCbCr matrix, and
/// the range — 0 studio, 1 full. [`UNSPECIFIED`] is said of any the movie
/// does not name — H.273's own 2 for the first three, and the same 2 for
/// the range, which H.273 has no word for. Each platform keeps one table
/// of its own names against these numbers (Apple asks the OS's own).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Colours {
    pub primaries: u8,
    pub transfer: u8,
    pub matrix: u8,
    pub range: u8,
}

/// What [`Colours`] holds for anything a movie does not name.
pub const UNSPECIFIED: u8 = 2;

impl Colours {
    /// This law's four: SMPTE C's primaries (SMPTE 170M, 6), BT.709's
    /// transfer (1), BT.601's matrix (SMPTE 170M, 6), studio range (0).
    pub const LAW: Colours = Colours { primaries: 6, transfer: 1, matrix: 6, range: 0 };

    /// What a movie that names nothing says.
    pub const NONE: Colours =
        Colours { primaries: UNSPECIFIED, transfer: UNSPECIFIED, matrix: UNSPECIFIED, range: UNSPECIFIED };
}

/// Each of `named`'s pairs — a platform's name and the code point it is —
/// read one way: the code point `name` is, or [`UNSPECIFIED`] where the
/// platform says nothing the table knows. One table a platform and an
/// attribute serves both ways ([`name_of`]), so what a reader understands
/// and what a writer names cannot drift apart.
pub fn code_of<T: PartialEq>(named: &[(T, u8)], name: Option<T>) -> u8 {
    name.and_then(|name| named.iter().find(|(known, _)| *known == name)).map_or(UNSPECIFIED, |&(_, code)| code)
}

/// The platform's name for `code` in `named` — none for [`UNSPECIFIED`],
/// or for a code point the platform has no name for: nothing is written
/// then, as a movie that names nothing names nothing.
pub fn name_of<T: Copy>(named: &[(T, u8)], code: u8) -> Option<T> {
    named.iter().find(|&&(_, known)| known == code && code != UNSPECIFIED).map(|&(name, _)| name)
}

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

/// Where a decoder's 4:2:0 frame lies, to be read — what [`Planes`] is to
/// be written: `y` rows `y_stride` apart, and the chroma sample for 2×2
/// pixels at `row * chroma_stride + column * chroma_step` past `cb` (and
/// past `cr`) in `chroma`. Apple hands its two planes apart; Media
/// Foundation and MediaCodec one buffer ([`Decoded::in_one_buffer`]).
pub struct Decoded<'a> {
    pub y: &'a [u8],
    pub y_stride: usize,
    pub chroma: &'a [u8],
    pub cb: usize,
    pub cr: usize,
    pub chroma_stride: usize,
    pub chroma_step: usize,
}

impl<'a> Decoded<'a> {
    /// One buffer `data`: `slice` Y rows `stride` bytes apart, then the
    /// chroma — side by side on rows as long (NV12, `semi_planar`), or Cb's
    /// plane of half rows and then Cr's (I420).
    ///
    /// `stride` is BYTES PER LUMA ROW and `slice` the rows between the Y
    /// plane and the chroma that follows it. Both are ≥ the picture, and
    /// assuming either equals it is the classic way to get a green-striped
    /// frame on one vendor's hardware and a correct one on another's.
    pub fn in_one_buffer(data: &'a [u8], stride: usize, slice: usize, semi_planar: bool) -> Self {
        let cb = stride * slice;
        let (cr, chroma_stride, chroma_step) =
            if semi_planar { (cb + 1, stride, 2) } else { (cb + (stride / 2) * (slice / 2), stride / 2, 1) };
        Decoded { y: data, y_stride: stride, chroma: data, cb, cr, chroma_stride, chroma_step }
    }

    /// Whether it holds a `width`×`height` frame: its last luma byte and
    /// its last chroma pair are inside it.
    ///
    /// ⚠️Whether it could: a buffer that ends before the last byte its own
    /// stride and slice place is refused, not read past — the C read on
    /// regardless (2026-11-07, the decoder's move to Rust, where reading
    /// past is a panic and a panic across the FFI is the app gone).
    fn holds(&self, width: usize, height: usize) -> bool {
        let last_chroma =
            self.cb.max(self.cr) + (height - 1) / 2 * self.chroma_stride + (width - 1) / 2 * self.chroma_step;
        self.y.len() > (height - 1) * self.y_stride + width - 1 && self.chroma.len() > last_chroma
    }

    /// The Y, Cb and Cr of pixel (`x`, `y`).
    fn at(&self, x: usize, y: usize) -> (u8, u8, u8) {
        let chroma = (y / 2) * self.chroma_stride + (x / 2) * self.chroma_step;
        (self.y[y * self.y_stride + x], self.chroma[self.cb + chroma], self.chroma[self.cr + chroma])
    }
}

/// How many bytes [`nv12_of`] makes of a `width`×`height` picture: NV12 of
/// it padded even, as an encoder takes it.
pub fn nv12_bytes(width: usize, height: usize) -> usize {
    let (width, height) = (width + (width & 1), height + (height & 1));
    width * height * 3 / 2
}

/// `frame`'s `width`×`height` into `out` as it is — no sum, the decoder's
/// own bytes — laid as NV12 padded even ([`nv12_bytes`]): the Y rows, then
/// the CbCr pairs side by side, every row the padded width apart.
///
/// The padding repeats the picture's last column and row: an odd picture's
/// chroma already covers it (a 2×2 block's sample is the decoder's), and
/// a repeated edge is a colour the movie has, in whatever range it is in.
/// False, and `out` untouched, where `frame` does not hold the picture.
#[must_use]
pub fn nv12_of(frame: &Decoded, width: usize, height: usize, out: &mut [u8]) -> bool {
    if width == 0 || height == 0 {
        return true;
    }
    let (padded, rows) = (width + (width & 1), height + (height & 1));
    if !frame.holds(width, height) || out.len() < nv12_bytes(width, height) {
        return false;
    }
    let (luma, chroma) = out.split_at_mut(padded * rows);
    for (y, row) in luma.chunks_exact_mut(padded).enumerate() {
        let from = &frame.y[y.min(height - 1) * frame.y_stride..][..width];
        row[..width].copy_from_slice(from);
        row[width..].fill(from[width - 1]);
    }
    for (y, row) in chroma.chunks_exact_mut(padded).take(rows / 2).enumerate() {
        for (x, pair) in row.chunks_exact_mut(2).enumerate() {
            let (_, cb, cr) = frame.at(x * 2, y * 2);
            pair.copy_from_slice(&[cb, cr]);
        }
    }
    true
}

/// YUV420 → RGBA, BT.601 studio range — the inverse of [`from_rgba`].
///
/// `data` lies as [`Decoded::in_one_buffer`] reads it: `stride` bytes a
/// luma row, `slice` rows to the chroma, `semi_planar` NV12 over I420.
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
/// ⚠️Refused, not read past, where `data` does not hold the frame
/// ([`Decoded::holds`]).
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
    if width == 0 || height == 0 {
        return true;
    }
    let frame = Decoded::in_one_buffer(data, stride, slice, semi_planar);
    if !frame.holds(width, height) || rgba.len() < width * height * 4 {
        return false;
    }
    for y in 0..height {
        for x in 0..width {
            let (luma, cb, cr) = frame.at(x, y);
            let (luma, cb, cr) = (i32::from(luma) - 16, i32::from(cb) - 128, i32::from(cr) - 128);
            let r = (298 * luma + 409 * cr + 128) >> 8;
            let g = (298 * luma - 100 * cb - 208 * cr + 128) >> 8;
            let b = (298 * luma + 516 * cb + 128) >> 8;
            let out = &mut rgba[(y * width + x) * 4..][..4];
            out.copy_from_slice(&[r.clamp(0, 255) as u8, g.clamp(0, 255) as u8, b.clamp(0, 255) as u8, 255]);
        }
    }
    true
}

#[cfg(windows)]
pub mod media_foundation;

#[cfg(target_os = "android")]
pub mod media_format;

#[cfg(target_vendor = "apple")]
pub mod core_video;

#[cfg(test)]
mod tests;
