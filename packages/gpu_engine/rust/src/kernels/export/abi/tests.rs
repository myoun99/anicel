//! The export's C ABI on a real GPU: each call puts what its pass puts run
//! in Rust, its readout holds the bytes its writer takes, the rows copy
//! reads them where it is asked, and what is refused says why.

use super::*;
use crate::kernels::export::tests::{Rig, frame, mixed, rig};
use crate::testing::{last_error, read_buffer};

/// 37 x 21: no side a tile's or a word's, so a width put for a height, or
/// a pixel's bytes for a row's, reads other pixels.
const WIDTH: u32 = 37;
const HEIGHT: u32 = 21;

/// One export for every test here, as the app keeps one.
fn export() -> &'static Export {
    static EXPORT: OnceLock<Export> = OnceLock::new();
    // SAFETY: a new export is boxed, and its box is let go of here.
    EXPORT.get_or_init(|| *unsafe { Box::from_raw(gpu_engine_export_new()) })
}

/// A run's output tiles for a picture of any colours and alphas.
fn ran() -> Composited {
    Composited { out: frame(WIDTH, HEIGHT, mixed(11)), passes: 0 }
}

/// All the bytes of `readout`, mapped and copied out as one row; the
/// readout is freed.
fn read_out(readout: *mut Readout) -> Vec<u8> {
    assert!(!readout.is_null(), "{}", last_error());
    let engine = rig().engine;
    // SAFETY: `readout` is live.
    let bytes = unsafe { gpu_engine_readout_bytes(readout) };
    let mut out = vec![0; bytes as usize];
    // SAFETY: `readout` is live, made on `engine`; `out` holds its bytes.
    unsafe {
        assert!(gpu_engine_readout_map(engine, readout), "{}", last_error());
        assert!(gpu_engine_readout_rows(readout, 0, bytes, bytes, 1, out.as_mut_ptr(), bytes), "{}", last_error());
        gpu_engine_readout_free(readout);
    }
    out
}

/// The first `bytes` a pass put, run in Rust.
fn put(out: Option<wgpu::Buffer>, bytes: u64) -> Vec<u8> {
    let mut read = read_buffer(rig().engine, &out.expect("the pass runs"));
    read.truncate(bytes as usize);
    read
}

fn picture() -> Picture {
    Picture { width: WIDTH, height: HEIGHT }
}

// ---- Each call is its pass ----

// The five words in the order the call names them: picture, frame, rows —
// each other than the rest, so two put in each other's place is a frame the
// picture does not fit, or other rows.
#[test]
fn nv12_puts_the_frame_its_five_words_shape() {
    let (frame, Rig { engine, nv12, .. }) = (ran(), rig());
    let words = [WIDTH, HEIGHT, 38, 22, 44];
    // SAFETY: all are live, made on `engine`; `words` holds five.
    let readout = unsafe { gpu_engine_export_nv12(export(), *engine, &frame, words.as_ptr()) };
    let shape = Nv12Shape { src_width: WIDTH, src_height: HEIGHT, width: 38, height: 22, y_stride: 44 };
    let bytes = read_out(readout);
    assert_eq!(bytes.len(), 44 * 22 * 3 / 2);
    assert_eq!(bytes, put(nv12.run(engine, &frame.out, shape), shape.bytes()));
}

// Red is the ground's low byte and blue its third; the fourth is no colour.
#[test]
fn over_ground_lays_the_ground_red_first() {
    let (frame, Rig { engine, over_ground, .. }) = (ran(), rig());
    let want = put(over_ground.run(engine, &frame.out, picture(), [0x32, 0x64, 0xc8], None), picture().rgb_bytes());
    assert_eq!(want.len(), (WIDTH * HEIGHT * 3) as usize, "three bytes a pixel, nothing between rows");
    for ground in [0x00c8_6432, 0xffc8_6432] {
        // SAFETY: all are live, made on `engine`.
        let readout = unsafe { gpu_engine_export_over_ground(export(), *engine, &frame, WIDTH, HEIGHT, ground, -1) };
        assert_eq!(read_out(readout), want, "{ground:#x}");
    }
}

// -1 is no cut, its shades; 0 a cut no alpha is under; each other alpha
// its own.
#[test]
fn over_ground_cuts_where_it_is_asked() {
    let (frame, Rig { engine, over_ground, .. }) = (ran(), rig());
    for (cut, as_run) in [(-1, None), (0, Some(0)), (200, Some(200)), (255, Some(255))] {
        let want = put(over_ground.run(engine, &frame.out, picture(), [9, 99, 199], as_run), picture().rgb_bytes());
        // SAFETY: all are live, made on `engine`.
        let readout = unsafe { gpu_engine_export_over_ground(export(), *engine, &frame, WIDTH, HEIGHT, 0xc7_6309, cut) };
        assert_eq!(read_out(readout), want, "cut {cut}");
    }
}

#[test]
fn over_ground_refuses_a_cut_that_is_no_alpha() {
    let frame = ran();
    for cut in [-2, 256] {
        // SAFETY: all are live, made on `engine`.
        let readout = unsafe { gpu_engine_export_over_ground(export(), rig().engine, &frame, WIDTH, HEIGHT, 0, cut) };
        assert!(readout.is_null(), "cut {cut}");
        assert_eq!(last_error(), format!("a cut is an alpha or -1, not {cut}"));
    }
}

#[test]
fn clear_marks_what_its_pass_marks() {
    let (frame, Rig { engine, clear, .. }) = (ran(), rig());
    let want = put(clear.run(engine, &frame.out, picture(), 131), picture().clear_bytes());
    assert_eq!(want.len(), (WIDTH * HEIGHT).div_ceil(32) as usize * 4);
    // SAFETY: all are live, made on `engine`.
    let readout = unsafe { gpu_engine_export_clear(export(), *engine, &frame, WIDTH, HEIGHT, 131) };
    assert_eq!(read_out(readout), want);
}

// The answer is one word: 255 for a picture all opaque, less for one that
// is not — the run's own pictures, both.
#[test]
fn opaque_answers_in_one_word() {
    let Rig { engine, opaque, .. } = rig();
    for (composited, all) in [(ran(), false), (Composited { out: frame(WIDTH, HEIGHT, |_, _| 0xff12_3456), passes: 0 }, true)] {
        let want = put(opaque.run(engine, &composited.out, picture()), 4);
        // SAFETY: all are live, made on `engine`.
        let readout = unsafe { gpu_engine_export_opaque(export(), *engine, &composited, WIDTH, HEIGHT) };
        let bytes = read_out(readout);
        assert_eq!(bytes, want);
        assert_eq!(u32::from_le_bytes(bytes.try_into().expect("a word")) == 255, all);
    }
}

#[test]
fn png_rgba_filters_what_its_pass_filters() {
    let (frame, Rig { engine, png, .. }) = (ran(), rig());
    let want = put(png.rgba(engine, &frame.out, picture()), picture().png_bytes(4));
    assert_eq!(want.len(), HEIGHT as usize * 152, "37 x 4 + 1 bytes a row, filled out to 152");
    // SAFETY: all are live, made on `engine`.
    let readout = unsafe { gpu_engine_export_png_rgba(export(), *engine, &frame, WIDTH, HEIGHT) };
    assert_eq!(read_out(readout), want);
}

// What over_ground put is the RGB rows' source as it stands on the GPU,
// mapped or not.
#[test]
fn png_rgb_filters_over_grounds_rows() {
    let (frame, Rig { engine, over_ground, png, .. }) = (ran(), rig());
    let rgb = over_ground.run(engine, &frame.out, picture(), [5, 6, 7], None).expect("over ground");
    let want = put(png.rgb(engine, &rgb, picture()), picture().png_bytes(3));
    assert_eq!(want.len(), HEIGHT as usize * 112, "37 x 3 + 1 bytes a row, filled out to 112");
    // SAFETY: all are live, made on `engine`.
    let source = unsafe { gpu_engine_export_over_ground(export(), *engine, &frame, WIDTH, HEIGHT, 0x07_0605, -1) };
    for mapped in [false, true] {
        if mapped {
            // SAFETY: `source` is live, made on `engine`.
            assert!(unsafe { gpu_engine_readout_map(*engine, source) }, "{}", last_error());
        }
        // SAFETY: all are live, made on `engine`.
        let readout = unsafe { gpu_engine_export_png_rgb(export(), *engine, source, WIDTH, HEIGHT) };
        assert_eq!(read_out(readout), want, "mapped {mapped}");
    }
    // SAFETY: `source` is live.
    unsafe { gpu_engine_readout_free(source) };
}

#[test]
fn png_rows_are_their_filters_byte_and_their_own_in_words() {
    for (width, pixel_bytes, row) in [(WIDTH, 4, 152), (WIDTH, 3, 112), (1, 3, 4), (1, 4, 8)] {
        assert_eq!(gpu_engine_export_png_row_bytes(width, pixel_bytes), row, "{width} x {pixel_bytes}");
    }
}

#[test]
fn a_frame_its_pass_refuses_reads_out_nothing() {
    let frame = ran();
    let words = [WIDTH, HEIGHT, 37, 22, 40];
    // SAFETY: all are live, made on `engine`; `words` holds five.
    let readout = unsafe { gpu_engine_export_nv12(export(), rig().engine, &frame, words.as_ptr()) };
    assert!(readout.is_null());
    assert_eq!(last_error(), "an encoder's frame is even and not empty, not 37x22");
}

// ---- The readout ----

/// The PNG rows of the run's picture, mapped: 21 rows of 152 bytes.
fn mapped_rows() -> (*mut Readout, Vec<u8>) {
    let (frame, engine) = (ran(), rig().engine);
    // SAFETY: all are live, made on `engine`.
    let whole = read_out(unsafe { gpu_engine_export_png_rgba(export(), engine, &frame, WIDTH, HEIGHT) });
    // SAFETY: all are live, made on `engine`.
    let readout = unsafe { gpu_engine_export_png_rgba(export(), engine, &frame, WIDTH, HEIGHT) };
    // SAFETY: `readout` is live, made on `engine`.
    assert!(unsafe { gpu_engine_readout_map(engine, readout) }, "{}", last_error());
    (readout, whole)
}

// Each of the six numbers its own: the rows a PNG's writer takes without
// their filling, from the second row's second byte, into rows of 150.
#[test]
fn rows_are_copied_from_where_they_are_asked_to_where_they_go() {
    let (readout, whole) = mapped_rows();
    let (offset, stride, row_bytes, rows, dst_stride) = (153, 152, 148, 5, 150);
    let mut dst = vec![0xee; (rows - 1) * dst_stride + row_bytes];
    // SAFETY: `readout` is live and `dst` holds the rows.
    let copied = unsafe {
        gpu_engine_readout_rows(readout, offset as u64, stride as u64, row_bytes as u64, rows as u64, dst.as_mut_ptr(), dst_stride as u64)
    };
    assert!(copied, "{}", last_error());
    for row in 0..rows {
        let (from, to) = (offset + row * stride, row * dst_stride);
        assert_eq!(dst[to..to + row_bytes], whole[from..from + row_bytes], "row {row}");
        if row + 1 < rows {
            assert_eq!(dst[to + row_bytes..to + dst_stride], [0xee, 0xee], "past row {row}");
        }
    }
    // SAFETY: `readout` is live.
    unsafe { gpu_engine_readout_free(readout) };
}

// A second map finds the bytes it mapped, and a second copy reads them
// again.
#[test]
fn a_readout_maps_once() {
    let (readout, whole) = mapped_rows();
    let mut dst = vec![0; whole.len()];
    let bytes = whole.len() as u64;
    for _ in 0..2 {
        // SAFETY: `readout` is live, made on `engine`, and `dst` holds it.
        unsafe {
            assert!(gpu_engine_readout_map(rig().engine, readout), "{}", last_error());
            assert!(gpu_engine_readout_rows(readout, 0, bytes, bytes, 1, dst.as_mut_ptr(), bytes));
        }
        assert_eq!(dst, whole);
    }
    // SAFETY: `readout` is live.
    unsafe { gpu_engine_readout_free(readout) };
}

// The last of 21 rows of 152 ends at the 3,192nd byte, the readout's last;
// a byte more is past it, as is a stride whose rows do not fit a u64.
#[test]
fn rows_past_the_bytes_read_out_are_refused() {
    let (readout, _) = mapped_rows();
    let mut dst = vec![0; 3192];
    let mut rows = |offset, stride, row_bytes, rows| {
        // SAFETY: `readout` is live and `dst` holds any rows it copies.
        unsafe { gpu_engine_readout_rows(readout, offset, stride, row_bytes, rows, dst.as_mut_ptr(), 0) }
    };
    assert!(rows(0, 152, 152, 21), "{}", last_error());
    assert!(rows(3192, 152, 0, 0), "no rows at the end");
    assert!(!rows(1, 152, 152, 21));
    assert_eq!(last_error(), "21 rows of 152 from 1, 152 apart, reach past the 3192 bytes read out");
    assert!(!rows(0, 152, 153, 21), "a row a byte longer");
    assert!(!rows(0, 153, 152, 21), "rows a byte further apart");
    assert!(!rows(0, 152, 152, 22), "a row more");
    assert!(!rows(3193, 152, 0, 0), "no rows past the end");
    assert!(!rows(0, u64::MAX, 1, 2), "a stride past a u64");
    assert!(!rows(0, 1 << 63, 1, 3), "a stride a u64 wraps round to 0");
    assert!(!rows(u64::MAX, 0, 1, 1), "an end past a u64");
    // SAFETY: `readout` is live.
    unsafe { gpu_engine_readout_free(readout) };
}

#[test]
fn rows_are_read_only_once_mapped() {
    let frame = ran();
    // SAFETY: all are live, made on `engine`.
    let readout = unsafe { gpu_engine_export_opaque(export(), rig().engine, &frame, WIDTH, HEIGHT) };
    let mut word = [0u8; 4];
    // SAFETY: `readout` is live and `word` holds its four bytes.
    unsafe {
        assert!(!gpu_engine_readout_rows(readout, 0, 4, 4, 1, word.as_mut_ptr(), 4));
        assert_eq!(last_error(), "a readout is mapped before its rows are read");
        gpu_engine_readout_free(readout);
    }
}

#[test]
fn null_frees_nothing() {
    // SAFETY: null is what each takes for nothing.
    unsafe {
        gpu_engine_export_free(std::ptr::null_mut());
        gpu_engine_readout_free(std::ptr::null_mut());
    }
}
