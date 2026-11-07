//! The export's C ABI (screen-on-the-engine 2c, gpu-export-path ①): the
//! conversions a frame a run put takes before its readback, each its own
//! call and each pass compiled where it is first asked, and what each put
//! read out (저장 23:17): mapped once, then copied row by row straight
//! into wherever its writer takes it — an encoder's planes, a codec's
//! packed buffer, a PNG's rows without their padding — with no copy
//! between.

#[cfg(test)]
mod tests;

use std::sync::OnceLock;

use super::{Clear, Nv12, Nv12Shape, Opaque, OverGround, Picture, PngFilter};
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::Composited;

/// The export's passes, each compiled where it is first asked: a still
/// asks no NV12, a movie no PNG.
pub struct Export {
    nv12: OnceLock<Nv12>,
    over_ground: OnceLock<OverGround>,
    clear: OnceLock<Clear>,
    opaque: OnceLock<Opaque>,
    png: OnceLock<PngFilter>,
}

/// What a pass put: its buffer, the bytes of it its writer takes, and —
/// once [`gpu_engine_readout_map`] has — their copy the CPU maps.
pub struct Readout {
    out: wgpu::Buffer,
    bytes: u64,
    mapped: Option<wgpu::Buffer>,
}

/// The readout of what a pass put — `bytes` of `out` its writer takes —,
/// or null where it put nothing (see the last error).
fn readout(out: Option<wgpu::Buffer>, bytes: u64) -> *mut Readout {
    out.map_or(std::ptr::null_mut(), |out| {
        Box::into_raw(Box::new(Readout { out, bytes, mapped: None }))
    })
}

/// The export's passes, none compiled yet.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_export_new() -> *mut Export {
    Box::into_raw(Box::new(Export {
        nv12: OnceLock::new(),
        over_ground: OnceLock::new(),
        clear: OnceLock::new(),
        opaque: OnceLock::new(),
        png: OnceLock::new(),
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

/// Converts the picture in `frame` — a run's output tiles for it, asked
/// row by row from its top-left tile — into the encoder's NV12 frame of
/// `shape`: the picture's width and height, the frame's (even, at least
/// the picture's — the writer's, as it opened its encoder) and the bytes
/// from one row to the next (a multiple of 4, at least the frame's width):
/// `height` Y rows, then `height / 2` CbCr rows, `nv12.wgsl`'s law. Null
/// on failure; see the last error.
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
    let (export, engine, frame, [src_width, src_height, width, height, y_stride]) =
        unsafe { (&*export, &*engine, &*frame, *shape.cast::<[u32; 5]>()) };
    let shape = Nv12Shape { src_width, src_height, width, height, y_stride };
    let pass = export.nv12.get_or_init(|| Nv12::new(engine));
    readout(pass.run(engine, &frame.out, shape), shape.bytes())
}

/// Lays the picture of `width` × `height` in `frame` over `ground` — red,
/// green and blue, red the low byte — its alpha cut at `cut` where a GIF
/// cuts it (-1 for none: its shades; 0 is a GIF with no clear colour), into
/// three bytes a pixel, row after row with nothing between: `width` ×
/// `height` × 3 bytes. Null on failure; see the last error.
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
    let (export, engine, frame) = unsafe { (&*export, &*engine, &*frame) };
    let picture = Picture { width, height };
    let [red, green, blue, _] = ground.to_le_bytes();
    let cut = match cut {
        -1 => None,
        0..=255 => Some(cut as u8),
        _ => {
            fail::<()>(format!("a cut is an alpha or -1, not {cut}"));
            return std::ptr::null_mut();
        }
    };
    let pass = export.over_ground.get_or_init(|| OverGround::new(engine));
    readout(pass.run(engine, &frame.out, picture, [red, green, blue], cut), picture.rgb_bytes())
}

/// Marks the pixels of the picture of `width` × `height` in `frame` whose
/// alpha is under `cut`: pixel i is bit i % 8 of byte i / 8, low bit
/// first, row after row with nothing between — ⌈`width` × `height` / 32⌉
/// × 4 bytes. Null on failure; see the last error.
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
    let (export, engine, frame) = unsafe { (&*export, &*engine, &*frame) };
    let picture = Picture { width, height };
    let pass = export.clear.get_or_init(|| Clear::new(engine));
    readout(pass.run(engine, &frame.out, picture, cut), picture.clear_bytes())
}

/// Asks whether every pixel of the picture of `width` × `height` in
/// `frame` is opaque: four bytes, one little-endian word, 255 when every
/// pixel is and less when one is not. Null on failure; see the last error.
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
    let (export, engine, frame) = unsafe { (&*export, &*engine, &*frame) };
    let pass = export.opaque.get_or_init(|| Opaque::new(engine));
    readout(pass.run(engine, &frame.out, Picture { width, height }), 4)
}

/// Filters the rows of a PNG of the picture of `width` × `height` in
/// `frame`, four bytes a pixel: each row its filter's byte and its own
/// under it, [`gpu_engine_export_png_row_bytes`] from the last. Null on
/// failure; see the last error.
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
    let (export, engine, frame) = unsafe { (&*export, &*engine, &*frame) };
    let picture = Picture { width, height };
    let pass = export.png.get_or_init(|| PngFilter::new(engine));
    readout(pass.rgba(engine, &frame.out, picture), picture.png_bytes(4))
}

/// [`gpu_engine_export_png_rgba`] for a PNG of three bytes a pixel, from
/// `rgb` — what [`gpu_engine_export_over_ground`] put for the same
/// picture, which never crosses to the CPU.
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
    let pass = export.png.get_or_init(|| PngFilter::new(engine));
    readout(pass.rgb(engine, &rgb.out, picture), picture.png_bytes(3))
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
            return Some(());
        }
        // A copy is whole words; each pass's buffer is (its last filled out).
        let staged = engine.staged(&self.out, self.bytes.next_multiple_of(4));
        engine.map(&staged)?;
        self.mapped = Some(staged);
        Some(())
    }

    /// # Safety
    /// `dst` holds (`rows.rows` − 1) × `dst_stride` + `rows.row_bytes`.
    unsafe fn rows(&self, rows: Rows, dst: *mut u8, dst_stride: u64) -> Option<()> {
        let Some(mapped) = &self.mapped else {
            return fail("a readout is mapped before its rows are read");
        };
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
