//! A kept picture read back on a real GPU: what the tests of the screen
//! (screen_tests.rs) and of one tile for the same input
//! (made_of_tests.rs) hold a picture's tiles to.

use super::Kept;
use crate::kernels::composite::tests::rig;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::pool::gather;

/// A kept picture's tiles, read back off the pages it names one after
/// another, row after row: each where the pool it is kept in placed it.
pub(crate) fn kept_bytes(kept: &Kept) -> Vec<u8> {
    let engine = rig().engine;
    let places: Vec<TileAt> = kept.places().collect();
    let mut bytes = vec![0; places.len() * TILE_BYTES as usize];
    let out = engine.readback(bytes.len() as u64);
    gather(engine, &kept.pages, &places, &out);
    engine.mapped_into(&out, &mut bytes).expect("read the tiles back");
    bytes
}
