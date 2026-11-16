//! The app's colour law for movies: BT.601, studio range, 4:2:0 — what a
//! picture the app drew becomes as YCbCr when it writes a movie — and how
//! every movie's YCbCr becomes a picture: by the matrix and the range the
//! movie names ([`Sums`]), this law's for the app's own. The writing side
//! is the GPU engine's NV12 pass (`gpu_engine`
//! `kernels/export/nv12.wgsl`), the reading side is here ([`rgba_of`]), and
//! both are held to the same sums worked out by hand, so the matrix one
//! side writes is the matrix the other reads. ↩️Both directions were here
//! till 2026-11-15 — the writing one as `from_rgba`, the pass's twin on the
//! CPU (board trimmed-movie-decodes-to-nv12-Q2: 「지운다 — 테스트도 엔진의
//! NV12 로 옮긴다」).
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
//! YCbCr the app made itself: the GPU engine's NV12 pass, for every writer
//! (gpu-export-path ⑶; the Android writer always converted by hand, and
//! this module did it on the CPU till 2026-11-15). ↩️Media Foundation's writer kept its
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

/// The integer sums a movie's YCbCr becomes RGB by ([`rgba_of`]), eight
/// bits of fraction each: its luma less `black`, times `luma`, and its
/// chroma less 128, times each weight — red of Cr, green of both, blue of
/// Cb. Which ones are the movie's to say ([`Sums::of`]).
///
/// 🚨★★★**ONE LAW FOR WHAT EVERY OS DECODES** (card movie-frames-come-as-
/// their-yuv-to-the-engine, 2026-11-16). ↩️Each OS converted its own way:
/// Media Foundation's advanced processing made RGB32 by its own matrix,
/// Apple's reader 32BGRA by Apple's, and Android these sums' BT.601 alone,
/// whatever the movie named. Every decoder now hands its 4:2:0 as it is,
/// and the RGB is made here, by what the movie names.
///
/// Each row is worked out of its matrix's two weights (H.273's Kr and Kb)
/// and its range, and rounded — `colour/tests.rs` works every one out
/// again. BT.601's studio row is the inverse of the GPU engine's NV12 pass
/// (`kernels/export/nv12.wgsl`): the app's own law for the movies it
/// writes, which it reads back by these.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sums {
    pub black: i32,
    pub luma: i32,
    pub red_cr: i32,
    pub green_cb: i32,
    pub green_cr: i32,
    pub blue_cb: i32,
}

const fn sums(black: i32, luma: i32, red_cr: i32, green_cb: i32, green_cr: i32, blue_cb: i32) -> Sums {
    Sums { black, luma, red_cr, green_cb, green_cr, blue_cb }
}

/// BT.601's sums, studio range and then full.
pub const BT601: [Sums; 2] = [sums(16, 298, 409, -100, -208, 516), sums(0, 256, 359, -88, -183, 454)];

/// BT.709's sums, studio range and then full.
pub const BT709: [Sums; 2] = [sums(16, 298, 459, -55, -136, 541), sums(0, 256, 403, -48, -120, 475)];

/// Every matrix a platform's table names (`colour/media_foundation.rs`,
/// `media_format.rs`; Apple's asks the OS), by its H.273 code point.
pub const MATRICES: [(u8, [Sums; 2]); 5] = [
    (1, BT709),
    // BT.470 System B/G's and SMPTE 170M's: BT.601's, weight for weight.
    (5, BT601),
    (6, BT601),
    // SMPTE 240M.
    (7, [sums(16, 298, 459, -66, -139, 532), sums(0, 256, 403, -58, -122, 467)]),
    // BT.2020's, of non-constant luminance.
    (9, [sums(16, 298, 430, -48, -167, 548), sums(0, 256, 377, -42, -146, 482)]),
];

impl Sums {
    /// The sums of a movie whose pictures are `colours`, `stored` its
    /// pictures' size as its decoder hands them.
    ///
    /// 🗣️★★**A MOVIE THAT NAMES NO MATRIX IS READ BY ITS SIZE** (유저 11-16,
    /// movie-frames-come-as-their-yuv-to-the-engine-Q1 (가): 「추천대로 가
    /// 로 해도 문제없어」): BT.709 where it is 1280 wide or more, or more than
    /// 576 tall — HD — and BT.601 under that. 🔬Media Foundation read a
    /// 1920×1080 movie that had lost its names as BT.709 (main PC,
    /// 2026-11-14 — this module's head). ⚠️A matrix it names that no
    /// platform table knows (YCgCo, BT.2020's constant luminance…) is read
    /// by its size too — mine, 2026-11-16: only Apple's OS hands a name for
    /// one, and these sums can make nothing else of it.
    ///
    /// A range it does not name is studio: H.264's and H.265's
    /// `video_full_range_flag` is 0 where a stream leaves it out.
    pub fn of(colours: Colours, (width, height): (usize, usize)) -> Sums {
        let named = MATRICES.iter().find(|(code, _)| *code == colours.matrix).map(|(_, sums)| sums);
        let matrix = named.unwrap_or(if width >= 1280 || height > 576 { &BT709 } else { &BT601 });
        matrix[usize::from(colours.range == 1)]
    }
}

/// `nv12`, a `width`×`height` picture laid as [`nv12_of`] lays one — padded
/// even, its CbCr pairs after its luma, every row the padded width apart —
/// as straight RGBA into `rgba`, by `sums`: every pixel opaque, its 2×2
/// block's chroma its own.
///
/// 🔬A row at a time, the row's chroma spread a pixel apiece first and every
/// pixel written whole: 3.1 ms a 1080p frame on the Surface, where reading
/// each pixel's three through [`Decoded`] took 11.6 and Media Foundation's
/// own conversion about 5 (2026-11-16, release, 72 frames) — the same bytes.
///
/// 🚨★★★**IT LIVES IN THE LAW BECAUSE IT IS ARITHMETIC, AND BECAUSE IT WAS
/// NEVER RUN.** It was inside the Android backend, where it compiled on
/// every PR and executed on no machine anybody has — the card
/// `android-decoder-branch-never-runs` is about exactly that gap. Nothing in
/// it touches a platform: it reads bytes and writes bytes, so it can be
/// proven on the bench. (↩️As `to_rgba`, BT.601 alone, till 2026-11-16.)
///
/// ⛔The picture size comes in as ARGUMENTS. It used to read the decoder's
/// global document, which is what tied a pure calculation to a backend
/// having opened something.
///
/// ⚠️Refused, not read past, where a buffer is short of the picture: the
/// decoder's own buffers are made NV12 first ([`nv12_of`], which refuses
/// one that does not hold its frame — [`Decoded::holds`]), and these two
/// are checked here — `rgba` untouched then.
#[must_use]
pub fn rgba_of(nv12: &[u8], (width, height): (usize, usize), sums: Sums, rgba: &mut [u8]) -> bool {
    if width == 0 || height == 0 {
        return true;
    }
    let (padded, rows) = (width + (width & 1), height + (height & 1));
    if nv12.len() < nv12_bytes(width, height) || rgba.len() < width * height * 4 {
        return false;
    }
    let (luma, chroma) = nv12.split_at(padded * rows);
    let mut spread = vec![0i32; width * 3];
    let (red, rest) = spread.split_at_mut(width);
    let (green, blue) = rest.split_at_mut(width);
    let Sums { black, luma: scale, red_cr, green_cb, green_cr, blue_cb } = sums;
    for (y, out) in rgba.chunks_exact_mut(width * 4).take(height).enumerate() {
        if y % 2 == 0 {
            let pairs = &chroma[(y / 2) * padded..][..padded];
            for (x, ((red, green), blue)) in red.iter_mut().zip(green.iter_mut()).zip(blue.iter_mut()).enumerate() {
                let (cb, cr) = (i32::from(pairs[x & !1]) - 128, i32::from(pairs[x | 1]) - 128);
                *red = red_cr * cr + 128;
                *green = green_cb * cb + green_cr * cr + 128;
                *blue = blue_cb * cb + 128;
            }
        }
        let row = &luma[y * padded..][..width];
        for ((((pixel, &l), &r), &g), &b) in out.chunks_exact_mut(4).zip(row).zip(red.iter()).zip(green.iter()).zip(blue.iter())
        {
            let l = scale * (i32::from(l) - black);
            let word = channel(l + r) | channel(l + g) << 8 | channel(l + b) << 16 | 0xff00_0000;
            pixel.copy_from_slice(&word.to_le_bytes());
        }
    }
    true
}

/// A sum of eight bits of fraction as a channel's byte.
fn channel(sum: i32) -> u32 {
    (sum >> 8).clamp(0, 255) as u32
}

#[cfg(windows)]
pub mod media_foundation;

#[cfg(target_os = "android")]
pub mod media_format;

#[cfg(target_vendor = "apple")]
pub mod core_video;

#[cfg(test)]
pub(crate) mod tests;
