//! The export's C ABI (screen-on-the-engine 2c, gpu-export-path ①): the
//! conversions a frame takes before its readback, each its own call and
//! each pass compiled where it is first asked, and what each put read out
//! (저장 23:17): mapped once, then copied row by row straight into wherever
//! its writer takes it — an encoder's planes, a codec's packed buffer, a
//! PNG's rows without their padding — with no copy between.
//!
//! A frame is a run's output tiles (`Composited`) or a frame as the screen
//! shows it ([`gpu_engine_export_shown`], ①⑴); each conversion has a call
//! for either, and one law.

#[cfg(test)]
mod tests;

use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64, Ordering};

use super::{
    Clear, Cover, Frame, Lay, Nv12, Nv12Shape, Opaque, OverGround, Picture, PngFilter, Shown, Source,
};
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::Composited;
use crate::kernels::shared::Counted;
use crate::platform::Surface;

/// The export's passes, each compiled where it is first asked: a still
/// asks no NV12, a movie no PNG.
pub struct Export {
    nv12: Nv12,
    over_ground: OverGround,
    clear: Clear,
    opaque: Opaque,
    png: PngFilter,
    lay: Lay,
}

/// What a pass put: its buffer, the bytes of it its writer takes, and —
/// once [`gpu_engine_readout_map`] has — their copy the CPU maps.
pub struct Readout {
    out: wgpu::Buffer,
    bytes: u64,
    /// How its wait ended, once one has: the buffer the CPU maps — or why
    /// there is none, kept of a wait its caller did not stay for
    /// ([`gpu_engine_readout_map_then`]), which has no one to fail to.
    mapped: Option<Result<wgpu::Buffer, String>>,
    _counted: Counted,
}

/// The bytes of the buffer every readout alive was made of — what a pass
/// put, or a pool gathered its tiles into —, counted where one is made and
/// freed ([`gpu_engine_readout_live_bytes`]). A readout is one read's:
/// what is still counted once the read is over was never freed.
static READOUT_BYTES: AtomicU64 = AtomicU64::new(0);

/// A readout handed to the engine's thread for the length of a wait its
/// caller did not stay for ([`Readout::map_then`]).
struct Waited(*mut Readout);

// SAFETY: nothing else has the readout till its wait has ended
// ([`Readout::map_then`]'s contract).
unsafe impl Send for Waited {}

impl Waited {
    /// # Safety
    /// The readout is live, and nothing else has it.
    unsafe fn end(self, ended: Result<wgpu::Buffer, String>) {
        // SAFETY: see the function's contract.
        unsafe { (*self.0).mapped = Some(ended) };
    }
}

/// The readout of what a pass put — `bytes` of `out` its writer takes —,
/// or null where it put nothing (see the last error). A pool's tiles on
/// their way back are one too (`gpu_engine_pool_readout`).
pub(crate) fn readout(out: Option<wgpu::Buffer>, bytes: u64) -> *mut Readout {
    out.map_or(std::ptr::null_mut(), |out| {
        let _counted = Counted::among(&READOUT_BYTES, out.size());
        Box::into_raw(Box::new(Readout { out, bytes, mapped: None, _counted }))
    })
}

/// The export's passes, none compiled yet.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_export_new() -> *mut Export {
    Box::into_raw(Box::new(Export {
        nv12: Nv12::new(),
        over_ground: OverGround::new(),
        clear: Clear::new(),
        opaque: Opaque::new(),
        png: PngFilter::new(),
        lay: Lay::new(),
    }))
}

/// # Safety
/// `export` came from `gpu_engine_export_new`, and its engine is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_free(export: *mut Export) {
    if !export.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(export) });
    }
}

/// Compiles the lay pass for the frames the export makes and for frames
/// shown on surfaces laid `bgra` or not — on the thread that asks, which an
/// app keeps off the one its frames are built on — so no lay compiles where
/// it is first asked.
///
/// # Safety
/// Both are live, `export` on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_warm(export: *const Export, engine: *const Engine, bgra: bool) {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    export.lay.warm(engine, bgra);
}

/// The picture of `width` × `height` from the top-left texel of
/// `surface` — a frame as the screen shows it, premultiplied — copied on
/// the GPU for the conversions of a frame shown (`gpu_engine_export_shown_*`):
/// what the canvas shows is what a file is made of, and nothing crosses to
/// the CPU before a writer's bytes. Null on failure; see the last error.
///
/// # Safety
/// Both are live, `surface` made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown(
    engine: *const Engine,
    surface: *const Surface,
    width: u32,
    height: u32,
) -> *mut Shown {
    // SAFETY: see the function's contract.
    let (engine, surface) = unsafe { (&*engine, &*surface) };
    Shown::of(engine, &surface.texture, Picture { width, height })
        .map_or(std::ptr::null_mut(), |shown| Box::into_raw(Box::new(shown)))
}

/// # Safety
/// `shown` came from `gpu_engine_export_shown`, and its engine is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_free(shown: *mut Shown) {
    if !shown.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(shown) });
    }
}

/// A `width` × `height` frame the export makes, laid with `ground` —
/// straight RGBA8, red the low byte; an alpha of 0 leaves it clear — for
/// pictures to be laid over (`gpu_engine_export_lay`): its last picture,
/// which the conversions read as they read a frame shown. Null on failure;
/// see the last error.
///
/// # Safety
/// Both are live, `export` on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_blank(
    export: *const Export,
    engine: *const Engine,
    width: u32,
    height: u32,
    ground: u32,
) -> *mut Shown {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    Shown::blank(engine, Picture { width, height })
        .and_then(|frame| {
            export.lay.run(engine, &frame, Source::Solid(ground), 255, None, None)?;
            Some(frame)
        })
        .map_or(std::ptr::null_mut(), |frame| Box::into_raw(Box::new(frame)))
}

/// The `length` bytes at `bytes`: none where it is null.
///
/// # Safety
/// `bytes` holds `length` bytes where it is not null.
unsafe fn held_bytes<'a>(bytes: *const u8, length: usize) -> &'a [u8] {
    if bytes.is_null() {
        return &[];
    }
    // SAFETY: see the function's contract.
    unsafe { std::slice::from_raw_parts(bytes, length) }
}

/// The `length` bytes at `rgba` — `width` × `height` premultiplied pixels,
/// four bytes each, red first, row after row — copied to the GPU as a
/// picture to lay over a frame (`gpu_engine_export_lay`): what the app
/// rasters of what it draws over one. Null on failure — `length` not the
/// picture's bytes among them; see the last error.
///
/// # Safety
/// `engine` is live; `rgba` holds `length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_upload(
    engine: *const Engine,
    rgba: *const u8,
    length: usize,
    width: u32,
    height: u32,
) -> *mut Shown {
    // SAFETY: see the function's contract.
    let (engine, rgba) = unsafe { (&*engine, held_bytes(rgba, length)) };
    Shown::uploaded(engine, rgba, Picture { width, height })
        .map_or(std::ptr::null_mut(), |frame| Box::into_raw(Box::new(frame)))
}

/// The `length` bytes at `alpha` — a byte for each of `width` × `height`
/// pixels, row after row: how much of what is laid each takes — copied to
/// the GPU as a frame's cover (`gpu_engine_export_lay`). Null on failure —
/// `length` not the frame's pixels among them; see the last error.
///
/// # Safety
/// `engine` is live; `alpha` holds `length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_cover(
    engine: *const Engine,
    alpha: *const u8,
    length: usize,
    width: u32,
    height: u32,
) -> *mut Cover {
    // SAFETY: see the function's contract.
    let (engine, alpha) = unsafe { (&*engine, held_bytes(alpha, length)) };
    Cover::of(engine, alpha, Picture { width, height })
        .map_or(std::ptr::null_mut(), |cover| Box::into_raw(Box::new(cover)))
}

/// # Safety
/// `cover` came from `gpu_engine_export_cover`, and its engine is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_cover_free(cover: *mut Cover) {
    if !cover.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(cover) });
    }
}

/// What a frame the export made holds (`gpu_engine_export_blank`), to read
/// back: its premultiplied RGBA, red first, row after row with nothing
/// between. Null on failure; see the last error.
///
/// # Safety
/// `frame` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_read(frame: *const Shown) -> *mut Readout {
    // SAFETY: see the function's contract.
    let frame = unsafe { &*frame };
    frame.laid_rows().map_or(std::ptr::null_mut(), |(rows, bytes)| readout(Some(rows), bytes))
}

/// The pixels `within` names — [left, top, right, bottom), four of them —
/// or none where it is null.
///
/// # Safety
/// `within` holds four where it is not null.
unsafe fn edges(within: *const i32) -> Option<[i32; 4]> {
    // SAFETY: see the function's contract.
    unsafe { within.cast::<[i32; 4]>().as_ref() }.copied()
}

/// Lays `source`, its top-left at (`x`, `y`) of `onto`, over `onto` at
/// `opacity` — a byte, 255 as it is — each pixel taking of it what `cover`
/// says, or all of it where `cover` is null — only within the pixels
/// `within` names, [left, top, right, bottom), where it is not null — and
/// submits the work. `onto` is a frame the export made
/// (`gpu_engine_export_blank`). False on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`, but `cover` and `within`, which
/// may be null; `within` holds four where it is not.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_lay(
    export: *const Export,
    engine: *const Engine,
    onto: *const Shown,
    source: *const Shown,
    x: i32,
    y: i32,
    opacity: u8,
    cover: *const Cover,
    within: *const i32,
) -> bool {
    // SAFETY: see the function's contract.
    let (export, engine, onto, frame) = unsafe { (&*export, &*engine, &*onto, &*source) };
    // SAFETY: see the function's contract.
    let (cover, within) = unsafe { (cover.as_ref(), edges(within)) };
    export.lay.run(engine, onto, Source::Frame { frame, x, y }, opacity, cover, within).is_some()
}

/// [`gpu_engine_export_lay`] of one colour over the whole of `onto` —
/// straight RGBA8, red the low byte.
///
/// # Safety
/// Every pointer is live, made on `engine`, but `cover` and `within`, which
/// may be null; `within` holds four where it is not.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_lay_colour(
    export: *const Export,
    engine: *const Engine,
    onto: *const Shown,
    colour: u32,
    opacity: u8,
    cover: *const Cover,
    within: *const i32,
) -> bool {
    // SAFETY: see the function's contract.
    let (export, engine, onto) = unsafe { (&*export, &*engine, &*onto) };
    // SAFETY: see the function's contract.
    let (cover, within) = unsafe { (cover.as_ref(), edges(within)) };
    export.lay.run(engine, onto, Source::Solid(colour), opacity, cover, within).is_some()
}

/// A run's output tiles, as the conversions read them.
///
/// # Safety
/// `frame` is live.
unsafe fn tiles<'a>(frame: *const Composited) -> Frame<'a> {
    // SAFETY: see the function's contract.
    Frame::Tiles(unsafe { &(*frame).out })
}

/// A frame shown, as the conversions read it.
///
/// # Safety
/// `frame` is live.
unsafe fn shown<'a>(frame: *const Shown) -> Frame<'a> {
    // SAFETY: see the function's contract.
    Frame::Shown(unsafe { &*frame })
}

/// Converts the picture in `frame` into the encoder's NV12 frame of
/// `shape`: the picture's width and height, the frame's (even, at least
/// the picture's — the writer's, as it opened its encoder) and the bytes
/// from one row to the next (a multiple of 4, at least the frame's width):
/// `height` Y rows, then `height / 2` CbCr rows, `nv12.wgsl`'s law. Null
/// on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`; `shape` holds five words.
unsafe fn nv12(export: *const Export, engine: *const Engine, frame: Frame, shape: *const u32) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine, [src_width, src_height, width, height, y_stride]) =
        unsafe { (&*export, &*engine, *shape.cast::<[u32; 5]>()) };
    let shape = Nv12Shape { src_width, src_height, width, height, y_stride };
    readout(export.nv12.run(engine, frame, shape), shape.bytes())
}

/// [`nv12`] of a run's output tiles for the picture, asked row by row from
/// its top-left tile.
///
/// # Safety
/// Every pointer is live, made on `engine`; `shape` holds five words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_nv12(
    export: *const Export,
    engine: *const Engine,
    frame: *const Composited,
    shape: *const u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { nv12(export, engine, tiles(frame), shape) }
}

/// [`nv12`] of a frame shown.
///
/// # Safety
/// Every pointer is live, made on `engine`; `shape` holds five words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_nv12(
    export: *const Export,
    engine: *const Engine,
    frame: *const Shown,
    shape: *const u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { nv12(export, engine, shown(frame), shape) }
}

/// Lays the picture of `picture` in `frame` over `ground` — red, green and
/// blue, red the low byte — its alpha cut at `cut` where a GIF cuts it (-1
/// for none: its shades; 0 is a GIF with no clear colour), into three bytes
/// a pixel, row after row with nothing between: width × height × 3 bytes.
/// Null on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`.
unsafe fn over_ground(
    export: *const Export,
    engine: *const Engine,
    frame: Frame,
    picture: Picture,
    ground: u32,
    cut: i32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    let [red, green, blue, _] = ground.to_le_bytes();
    let cut = match cut {
        -1 => None,
        0..=255 => Some(cut as u8),
        _ => {
            fail::<()>(format!("a cut is an alpha or -1, not {cut}"));
            return std::ptr::null_mut();
        }
    };
    let out = export.over_ground.run(engine, frame, picture, [red, green, blue], cut);
    readout(out, picture.rgb_bytes())
}

/// [`over_ground`] of a run's output tiles.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_over_ground(
    export: *const Export,
    engine: *const Engine,
    frame: *const Composited,
    width: u32,
    height: u32,
    ground: u32,
    cut: i32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { over_ground(export, engine, tiles(frame), Picture { width, height }, ground, cut) }
}

/// [`over_ground`] of a frame shown.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_over_ground(
    export: *const Export,
    engine: *const Engine,
    frame: *const Shown,
    width: u32,
    height: u32,
    ground: u32,
    cut: i32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { over_ground(export, engine, shown(frame), Picture { width, height }, ground, cut) }
}

/// Marks the pixels of `picture` in `frame` whose alpha is under `cut`:
/// pixel i is bit i % 8 of byte i / 8, low bit first, row after row with
/// nothing between — ⌈width × height / 32⌉ × 4 bytes. Null on failure;
/// see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`.
unsafe fn clear(export: *const Export, engine: *const Engine, frame: Frame, picture: Picture, cut: u8) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    readout(export.clear.run(engine, frame, picture, cut), picture.clear_bytes())
}

/// [`clear`] of a run's output tiles.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_clear(
    export: *const Export,
    engine: *const Engine,
    frame: *const Composited,
    width: u32,
    height: u32,
    cut: u8,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { clear(export, engine, tiles(frame), Picture { width, height }, cut) }
}

/// [`clear`] of a frame shown.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_clear(
    export: *const Export,
    engine: *const Engine,
    frame: *const Shown,
    width: u32,
    height: u32,
    cut: u8,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { clear(export, engine, shown(frame), Picture { width, height }, cut) }
}

/// Asks whether every pixel of `picture` in `frame` is opaque: four bytes,
/// one little-endian word, 255 when every pixel is and less when one is
/// not. Null on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`.
unsafe fn opaque(export: *const Export, engine: *const Engine, frame: Frame, picture: Picture) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    readout(export.opaque.run(engine, frame, picture), 4)
}

/// [`opaque`] of a run's output tiles.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_opaque(
    export: *const Export,
    engine: *const Engine,
    frame: *const Composited,
    width: u32,
    height: u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { opaque(export, engine, tiles(frame), Picture { width, height }) }
}

/// [`opaque`] of a frame shown.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_opaque(
    export: *const Export,
    engine: *const Engine,
    frame: *const Shown,
    width: u32,
    height: u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { opaque(export, engine, shown(frame), Picture { width, height }) }
}

/// Filters the rows of a PNG of `picture` in `frame`, four bytes a pixel,
/// straight: each row its filter's byte and its own under it,
/// [`gpu_engine_export_png_row_bytes`] from the last. Null on failure; see
/// the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`.
unsafe fn png_rgba(export: *const Export, engine: *const Engine, frame: Frame, picture: Picture) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine) = unsafe { (&*export, &*engine) };
    readout(export.png.rgba(engine, frame, picture), picture.png_bytes(4))
}

/// [`png_rgba`] of a run's output tiles.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_png_rgba(
    export: *const Export,
    engine: *const Engine,
    frame: *const Composited,
    width: u32,
    height: u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { png_rgba(export, engine, tiles(frame), Picture { width, height }) }
}

/// [`png_rgba`] of a frame shown.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_shown_png_rgba(
    export: *const Export,
    engine: *const Engine,
    frame: *const Shown,
    width: u32,
    height: u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    unsafe { png_rgba(export, engine, shown(frame), Picture { width, height }) }
}

/// [`png_rgba`] for a PNG of three bytes a pixel, from `rgb` — what an
/// over-the-ground call put for the same picture, which never crosses to
/// the CPU.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_export_png_rgb(
    export: *const Export,
    engine: *const Engine,
    rgb: *const Readout,
    width: u32,
    height: u32,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (export, engine, rgb) = unsafe { (&*export, &*engine, &*rgb) };
    let picture = Picture { width, height };
    readout(export.png.rgb(engine, &rgb.out, picture), picture.png_bytes(3))
}

/// Where each row of a PNG's filtered rows starts from the last's, for a
/// picture `width` wide of `pixel_bytes` a pixel: its filter's byte and
/// its own, filled out to a whole word.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_export_png_row_bytes(width: u32, pixel_bytes: u32) -> u64 {
    Picture { width, height: 1 }.png_row_bytes(pixel_bytes)
}

/// The bytes of `readout` its writer takes.
///
/// # Safety
/// `readout` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_readout_bytes(readout: *const Readout) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*readout }.bytes
}

/// Waits for the work behind `readout` and maps its bytes for
/// [`gpu_engine_readout_rows`] — once: a second call finds them mapped.
/// False on failure; see the last error.
///
/// # Safety
/// Both are live, `readout` made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_readout_map(engine: *const Engine, readout: *mut Readout) -> bool {
    // SAFETY: see the function's contract.
    let (engine, readout) = unsafe { (&*engine, &mut *readout) };
    readout.map(engine).is_some()
}

/// [`gpu_engine_readout_map`] with no wait for its caller, who goes on:
/// the engine's thread waits for the work behind `readout`, and calls
/// `then` once its bytes are mapped for [`gpu_engine_readout_rows`] — or
/// are not, which the rows then fail by — with `wait`, the number its
/// caller knows this wait by: one `then` serves every wait of a caller.
/// From that thread; from this one where that thread is gone, or the bytes
/// were mapped already.
///
/// # Safety
/// Both are live, `readout` made on `engine` — and `readout` is asked
/// nothing more, nor freed, till `then` is called. `then` is one any
/// thread may call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_readout_map_then(
    engine: *const Engine,
    readout: *mut Readout,
    then: extern "C" fn(u64),
    wait: u64,
) {
    // SAFETY: see the function's contract.
    let (engine, readout) = unsafe { (&*engine, &mut *readout) };
    // SAFETY: the readout is the caller's to leave alone (the contract).
    unsafe { readout.map_then(engine, move || then(wait)) };
}

/// Copies `rows` rows of `row_bytes` from the mapped bytes of `readout` —
/// the first at `offset`, each `stride` from the last — into `dst`, each
/// `dst_stride` from the last. False where the readout is not mapped or a
/// row reaches past the bytes it holds; see the last error.
///
/// # Safety
/// Both are live; `dst` holds (`rows` − 1) × `dst_stride` + `row_bytes`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_readout_rows(
    readout: *const Readout,
    offset: u64,
    stride: u64,
    row_bytes: u64,
    rows: u64,
    dst: *mut u8,
    dst_stride: u64,
) -> bool {
    // SAFETY: see the function's contract.
    let readout = unsafe { &*readout };
    // SAFETY: `dst` holds the rows (the contract).
    unsafe { readout.rows(Rows { offset, stride, row_bytes, rows }, dst, dst_stride) }.is_some()
}

/// Rows of a readout: `rows` of `row_bytes`, the first at `offset` and
/// each `stride` from the last.
#[derive(Clone, Copy)]
struct Rows {
    offset: u64,
    stride: u64,
    row_bytes: u64,
    rows: u64,
}

impl Rows {
    /// Where the last ends, or none past what a byte count holds.
    fn end(&self) -> Option<u64> {
        let Self { offset, stride, row_bytes, rows } = *self;
        match rows.checked_sub(1) {
            None => Some(offset),
            Some(last) => last.checked_mul(stride)?.checked_add(offset)?.checked_add(row_bytes),
        }
    }
}

impl Readout {
    fn map(&mut self, engine: &Engine) -> Option<()> {
        if self.mapped.is_some() {
            return self.mapped().map(|_| ());
        }
        let staged = self.staged(engine);
        engine.map(&staged)?;
        self.mapped = Some(Ok(staged));
        Some(())
    }

    /// [`Self::map`] with no wait for its caller ([`Engine::map_then`]):
    /// `then` is called once the wait has ended, how it did kept for
    /// [`Self::rows`] — at once where one had.
    ///
    /// # Safety
    /// `self` stays where it is, asked nothing, till `then` is called.
    unsafe fn map_then(&mut self, engine: &Engine, then: impl FnOnce() + Send + 'static) {
        if self.mapped.is_some() {
            return then();
        }
        let staged = self.staged(engine);
        let waited = Waited(std::ptr::from_mut(self));
        engine.map_then(staged, move |ended| {
            // SAFETY: the contract — nothing else has it till `then`.
            unsafe { waited.end(ended) };
            then();
        });
    }

    /// The buffer the CPU maps of what the pass put: the pass's own where
    /// it put one — a pool's tiles on their way back
    /// (`gpu_engine_pool_readout`) —, else its copy, submitted. A copy is
    /// whole words; each pass's buffer is (its last filled out).
    fn staged(&self, engine: &Engine) -> wgpu::Buffer {
        if self.out.usage().contains(wgpu::BufferUsages::MAP_READ) {
            return self.out.clone();
        }
        engine.staged(&self.out, self.bytes.next_multiple_of(4))
    }

    /// The buffer mapped; fails by why there is none.
    fn mapped(&self) -> Option<&wgpu::Buffer> {
        match &self.mapped {
            Some(Ok(mapped)) => Some(mapped),
            Some(Err(why)) => fail(why.clone()),
            None => fail("a readout is mapped before its rows are read"),
        }
    }

    /// # Safety
    /// `dst` holds (`rows.rows` − 1) × `dst_stride` + `rows.row_bytes`.
    unsafe fn rows(&self, rows: Rows, dst: *mut u8, dst_stride: u64) -> Option<()> {
        let mapped = self.mapped()?;
        let Rows { offset, stride, row_bytes, rows: count } = rows;
        if rows.end().is_none_or(|end| end > self.bytes) {
            return fail(format!(
                "{count} rows of {row_bytes} from {offset}, {stride} apart, reach past the {} bytes read out",
                self.bytes
            ));
        }
        let view = match mapped.get_mapped_range(..) {
            Ok(view) => view,
            Err(error) => return fail(format!("get_mapped_range: {error}")),
        };
        for row in 0..count {
            let from = (offset + row * stride) as usize;
            let source = &view[from..from + row_bytes as usize];
            // SAFETY: `dst` holds row `row` (the contract).
            unsafe {
                std::ptr::copy_nonoverlapping(source.as_ptr(), dst.add((row * dst_stride) as usize), source.len())
            };
        }
        Some(())
    }
}

/// # Safety
/// `readout` came from one of the export's calls.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_readout_free(readout: *mut Readout) {
    if !readout.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(readout) });
    }
}

/// The bytes of the buffer every readout was made of, made and not yet
/// freed.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_readout_live_bytes() -> u64 {
    READOUT_BYTES.load(Ordering::Relaxed)
}
