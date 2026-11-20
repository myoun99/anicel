//! A kept picture read back on a real GPU: what the tests of the screen
//! (screen_tests.rs) and of one tile for the same input
//! (made_of_tests.rs) hold a picture's tiles to.

use super::Kept;
use crate::device::Engine;
use crate::kernels::composite::TileAt;
use crate::kernels::composite::tests::rig;
use crate::kernels::fold::Fold;
use crate::kernels::pool::Pictures;
use std::time::Duration;

/// A kept picture's tiles, read back one after another, row after row:
/// each as the pool it is kept in holds it, whatever it lies as.
pub(crate) fn kept_bytes(kept: &Kept) -> Vec<u8> {
    let places: Vec<TileAt> = kept.places().collect();
    kept.pictures.read(rig().engine, &places).expect("read the tiles back")
}

/// How many of the tiles named at `names` lie off their slots in
/// `pictures`: folded, or moved whole to a page of folded tiles.
pub(crate) fn moved(pictures: &Pictures, names: &[TileAt]) -> usize {
    names.iter().filter(|&&at| pictures.lies(at) != at).count()
}

/// The hand rests on `engine`, its fold's kernels compiled: `pictures`'
/// tiles folded a batch behind another till none is next, the last told
/// and settled.
pub(crate) fn rested_on(engine: &Engine, pictures: &Pictures) {
    engine.on_thread(|| Fold::new(engine)).expect("the fold's kernels");
    pictures.rests(engine);
    assert!(pictures.rested_within(Duration::from_secs(120)), "the rest's folds never ended");
}
