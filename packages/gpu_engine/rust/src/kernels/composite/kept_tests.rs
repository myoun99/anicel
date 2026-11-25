//! A kept picture read back on a real GPU: what the tests of the screen
//! (screen_tests.rs) and of one tile for the same input
//! (made_of_tests.rs) hold a picture's tiles to.

use super::Kept;
use crate::device::Engine;
use crate::kernels::composite::TileAt;
use crate::kernels::composite::tests::rig;
use crate::kernels::fold::Fold;
use crate::kernels::pool::folded_tests::{numbered, told, told_within};
use crate::kernels::pool::{Pictures, told_by};
use std::time::Duration;

/// A kept picture's tiles, read back one after another, row after row:
/// each as the pool it is kept in holds it, whatever it lies as.
pub(crate) fn kept_bytes(kept: &Kept) -> Vec<u8> {
    kept_bytes_on(rig().engine, kept)
}

/// [`kept_bytes`] of a picture kept on `engine`.
pub(crate) fn kept_bytes_on(engine: &Engine, kept: &Kept) -> Vec<u8> {
    let places: Vec<TileAt> = kept.places().collect();
    kept.pictures.read(engine, &places).expect("read the tiles back")
}

/// How many of the tiles named at `names` lie off their slots in
/// `pictures`: folded, or moved whole to a page of folded tiles.
pub(crate) fn moved(pictures: &Pictures, names: &[TileAt]) -> usize {
    names.iter().filter(|&&at| pictures.lies(at) != at).count()
}

/// How long a rest's folds may take before a test says they never ended.
/// A batch behind another, each step a job of the engine's thread behind
/// every other test's — the binary's tests share one engine —, so the
/// whole of a rest is several of the waits one telling is given
/// (`told_within`, 120 s).
/// 🔬2026-11-21, a land's release gate beside two wide test runs: every
/// test of the binary ran past a minute (1,716 s the run), and two rests
/// of 15 tiles passed 120 s — both green in debug an hour before.
pub(crate) const A_REST_S_FOLDS: Duration = Duration::from_secs(600);

/// The hand rests on `pictures` ([`Pictures::rests`]): the number its
/// rest is told by once its folds are through ([`rested`]).
pub(crate) fn resting(engine: &Engine, pictures: &Pictures) -> u64 {
    let number = numbered();
    pictures.rests(engine, told_by(told, number));
    number
}

/// What the rest told by `number` told once its folds were through —
/// whether the pictures were weighed again —, none where they are not
/// through within [`A_REST_S_FOLDS`].
pub(crate) fn rested(number: u64) -> Option<bool> {
    told_within(number, A_REST_S_FOLDS)
}

/// The hand rests on `engine`, its fold's kernels compiled: `pictures`'
/// tiles folded a batch behind another till none is next, the last told
/// and settled, and the pictures weighed again.
pub(crate) fn rested_on(engine: &Engine, pictures: &Pictures) {
    engine.on_thread(|| Fold::new(engine)).expect("the fold's kernels");
    let told = rested(resting(engine, pictures));
    assert_eq!(told, Some(true), "the rest's folds never ended, or ended unweighed");
}
