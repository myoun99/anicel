//! A mask cut by another as the app asks for it: two planes it made, the
//! cut kept as a third and read back — held to what the cut is by hand,
//! pixel by pixel, never to a CPU copy of the pass (`kernels/mod.rs`).

use std::sync::OnceLock;

use super::super::abi::{SelectionMasks, gpu_engine_selection_mask_cut, gpu_engine_selection_masks_new};
use crate::device::Engine;
use crate::kernels::composite::abi::{
    MaskPlane, gpu_engine_mask_free, gpu_engine_mask_new, gpu_engine_mask_read,
};
use crate::testing::{first_engine, last_error};

struct Rig {
    engine: &'static Engine,
    masks: &'static SelectionMasks,
}

/// One device and one compile for every test here.
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        // SAFETY: the engine lives for the process; the kernels are never
        // freed.
        let masks = unsafe { &*gpu_engine_selection_masks_new(engine) };
        Rig { engine, masks }
    })
}

/// The plane of `rows` — a row of bytes each — whose top-left pixel is
/// `at`, as the app makes one.
fn made(at: (i32, i32), rows: &[&[u8]]) -> *mut MaskPlane {
    let (width, height) = (rows[0].len() as u32, rows.len() as u32);
    let bytes: Vec<u8> = rows.concat();
    // SAFETY: the engine is live and `bytes` holds width × height.
    let plane = unsafe { gpu_engine_mask_new(rig().engine, bytes.as_ptr(), at.0, at.1, width, height) };
    assert!(!plane.is_null(), "{}", last_error());
    plane
}

/// `mask` cut by `by`, read back a row at a time over `width`; both freed.
fn cut(mask: *mut MaskPlane, by: *mut MaskPlane, width: usize, height: usize) -> Vec<Vec<u8>> {
    let Rig { engine, masks } = rig();
    // SAFETY: every plane was made on `engine`, the kernels too.
    let put = unsafe { gpu_engine_selection_mask_cut(*masks, *engine, mask, by) };
    assert!(!put.is_null(), "{}", last_error());
    let mut bytes = vec![7u8; width * height];
    // SAFETY: `bytes` holds what it is said to.
    let read = unsafe { gpu_engine_mask_read(*engine, put, bytes.as_mut_ptr(), bytes.len()) };
    assert!(read, "{}", last_error());
    // SAFETY: each was made by the engine and is freed once.
    unsafe {
        gpu_engine_mask_free(put);
        gpu_engine_mask_free(mask);
        gpu_engine_mask_free(by);
    }
    bytes.chunks(width).map(<[u8]>::to_vec).collect()
}

/// A range of six pixels across from the canvas's origin under a selection
/// from (1, 1), four across and two down: whole where both take any of the
/// pixel — 1 and 3 as much as 255 —, nothing where either takes none, nor
/// past the selection's box, left, right or above it.
#[test]
fn a_mask_cut_by_another_is_whole_where_both_take_any_of_the_pixel() {
    let mask = made(
        (0, 0),
        &[&[255, 1, 0, 128, 255, 7], &[0, 255, 255, 255, 0, 255], &[9, 9, 9, 9, 9, 9]],
    );
    let by = made((1, 1), &[&[255, 0, 1, 255], &[3, 3, 0, 3]]);
    assert_eq!(
        cut(mask, by, 6, 3),
        [vec![0, 0, 0, 0, 0, 0], vec![0, 255, 0, 255, 0, 0], vec![0, 255, 255, 0, 255, 0]],
    );
}

/// Both left of and above the canvas's origin, the selection further: it
/// is read where it lies, its last column over the range's first and its
/// last row over the range's first.
#[test]
fn a_cut_reads_the_other_where_it_lies_left_of_and_above_the_origin() {
    let mask = made((-7, -3), &[&[200; 5], &[200; 5]]);
    let by = made((-9, -4), &[&[255; 3], &[255; 3]]);
    assert_eq!(cut(mask, by, 5, 2), [vec![255, 0, 0, 0, 0], vec![0; 5]]);
}

/// A selection that meets none of the range cuts all of it — and the cut
/// keeps the range's box, which a read of another size is refused.
#[test]
fn a_cut_keeps_the_box_of_what_it_cuts() {
    let Rig { engine, masks } = rig();
    let mask = made((0, 0), &[&[255; 3]]);
    let by = made((40, 40), &[&[255; 2]]);
    // SAFETY: every plane was made on `engine`, the kernels too.
    let put = unsafe { gpu_engine_selection_mask_cut(*masks, *engine, mask, by) };
    assert!(!put.is_null(), "{}", last_error());
    let mut wrong = vec![0u8; 4];
    // SAFETY: `wrong` holds what it is said to.
    let read = unsafe { gpu_engine_mask_read(*engine, put, wrong.as_mut_ptr(), wrong.len()) };
    assert!(!read);
    assert!(last_error().contains("are not a mask"), "{}", last_error());
    // SAFETY: each was made by the engine and is freed once.
    unsafe {
        gpu_engine_mask_free(put);
        gpu_engine_mask_free(mask);
        gpu_engine_mask_free(by);
    }
    assert_eq!(cut(made((0, 0), &[&[255; 3]]), made((40, 40), &[&[255; 2]]), 3, 1), [vec![0; 3]]);
}
