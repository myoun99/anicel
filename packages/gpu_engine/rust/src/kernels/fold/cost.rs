//! What a folded tile costs (F-610, 2026-11-19): a measurement, no test —
//! it asserts nothing, prints what it timed, and no run of the suite takes
//! it. By name, in release, on the machine asked about:
//!
//! `cargo test --release -p gpu_engine --lib -- --ignored --nocapture what_a_folded_tile_costs`
//!
//! It times, for tiles of each kind of picture, the same rows read from
//! the tiles as they are and from the tiles folded — a row copied, a row
//! posed (four pixels read for one) and eight rows over one another —, and
//! the fold itself. `FOLD_COST_TILES` is how many tiles a row holds (1024
//! unless said).

use std::time::{Duration, Instant};

use super::tests::{kernels, page, placed, tile_of};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Rig, mix, rig, row, with_map};
use crate::kernels::composite::{
    GRANULE_BYTES, NO_EDGE, Plan, Step, TILE, TILE_BYTES, TileAt, TileSet, WHOLE,
};
use crate::kernels::shared::{ResampleMap, ResampleMode, room, words_buffer};

/// How many times a row is timed; the middle one is what is said.
const TIMES: usize = 15;
/// How long a row is run before it is timed: a device's clock comes up
/// under load, and the first runs are slower than the rest.
const WARM: Duration = Duration::from_millis(400);
/// The tiles of a kind made apart; a row's are these over and over.
const APART: u32 = 16;

/// A kind of picture: of a hundred blocks, how many hold each count of
/// colours — from, to, of a hundred.
struct Kind {
    name: &'static str,
    blocks: &'static [(u32, u32, u32)],
}

/// 🔬The two pictures' are what was counted in the user's line art and
/// S5_BA cut 352 (2026-11-19, their pictures' tiles): of a hundred blocks,
/// those of one colour, of 2, of 3–4, of 5–16, of 17–47 and of more.
const KINDS: [Kind; 5] = [
    Kind { name: "one colour", blocks: &[(1, 1, 100)] },
    Kind { name: "16 colours a block", blocks: &[(16, 16, 100)] },
    Kind { name: "40 in 100 as they are", blocks: &[(64, 64, 40), (1, 1, 60)] },
    Kind {
        name: "line art",
        blocks: &[(1, 1, 49), (2, 2, 3), (3, 4, 5), (5, 16, 24), (17, 47, 18), (64, 64, 1)],
    },
    Kind {
        name: "painted",
        blocks: &[(1, 1, 30), (2, 2, 3), (3, 4, 5), (5, 16, 17), (17, 47, 33), (64, 64, 12)],
    },
];

impl Kind {
    /// The colours of block `block` of the kind's tile `seed`.
    fn count(&self, seed: u32, block: u32) -> u32 {
        let drawn = mix(seed.wrapping_mul(0x9e37_79b9) ^ block);
        let mut of_a_hundred = drawn % 100;
        for &(from, to, share) in self.blocks {
            if of_a_hundred < share {
                return from + (drawn >> 8) % (to - from + 1);
            }
            of_a_hundred -= share;
        }
        unreachable!("the shares are a hundred")
    }
}

/// The middle of [`TIMES`] timings of each of `runs` and the GPU's work
/// after it, in milliseconds — taken turn about, so what drifts drifts
/// under them all, after runs nobody times ([`WARM`]).
fn timed<const N: usize>(mut runs: [&mut dyn FnMut(); N]) -> [f64; N] {
    let engine = rig().engine;
    let once = |run: &mut dyn FnMut()| {
        let started = Instant::now();
        run();
        engine.wait().expect("wait for the GPU");
        started.elapsed().as_secs_f64() * 1e3
    };
    let warming = Instant::now();
    while warming.elapsed() < WARM {
        runs.iter_mut().for_each(|run| {
            once(run);
        });
    }
    let mut times = [(); N].map(|()| Vec::with_capacity(TIMES));
    for _ in 0..TIMES {
        for (run, times) in runs.iter_mut().zip(&mut times) {
            times.push(once(run));
        }
    }
    times.map(|mut times| {
        times.sort_by(f64::total_cmp);
        times[TIMES / 2]
    })
}

/// A row of `places`, a column each, and `rows` of them: each the row
/// before it turned by an eighth of its tiles, so no two read the same
/// tile under one output tile.
fn sets(places: &[TileAt], rows: usize) -> Vec<TileSet> {
    (0..rows)
        .map(|turn| {
            let mut tiles: Vec<Option<TileAt>> = places.iter().copied().map(Some).collect();
            tiles.rotate_left(turn * places.len() / 8);
            TileSet { x0: 0, y0: 0, columns: places.len() as u32, rows: 1, tiles }
        })
        .collect()
}

/// What lays `steps` over a row of `places` on `pages`, once a call.
fn laying<'a>(
    pages: &'a [wgpu::Buffer],
    places: &[TileAt],
    steps: &'a [Step],
) -> impl FnMut() + 'a {
    let Rig { engine, composite } = rig();
    let sets = sets(places, steps.len());
    let tiles: Vec<(i32, i32)> = (0..places.len() as i32).map(|column| (column, 0)).collect();
    move || {
        let plan = Plan {
            pages,
            sets: &sets,
            keys: &[],
            matrices: &[],
            chains: &[],
            steps,
            mask: None,
            stamps: None,
        };
        composite.run(engine, &plan, &tiles, NO_EDGE, composite.widest()).expect("composite");
    }
}

#[test]
#[ignore = "a measurement: by name, in release, with --ignored --nocapture"]
fn what_a_folded_tile_costs() {
    let engine = rig().engine;
    let asked = std::env::var("FOLD_COST_TILES").ok().and_then(|tiles| tiles.parse().ok());
    let count = asked.unwrap_or(1024).min((room(engine) / TILE_BYTES) as usize).min(1024);
    let info = engine.adapter.get_info();
    println!("fold cost: {} ({:?}, {:?}), {count} tiles a row", info.name, info.backend, info.device_type);
    let compiling = Instant::now();
    let fold = &kernels().fold;
    println!("fold cost: the fold and its readers compiled in {:.0} ms", compiling.elapsed().as_secs_f64() * 1e3);
    let half = [1.0, 0.0, 0.5, 0.0, 1.0, 0.5, 0.0, 0.0, 1.0];
    let half = ResampleMap::new(half, 1.0, ResampleMode::Blend, TILE, TILE).unwrap();
    let copied = [row(0, (0, 0), WHOLE, NORMAL)];
    let posed = [with_map(0, half, WHOLE, NORMAL)];
    let over: Vec<Step> = (0..8).map(|set| row(set, (0, 0), WHOLE / 2, NORMAL)).collect();
    // The first kind once before anything is said: the device's clock comes
    // up over its first seconds of work, past what a row's own warming is.
    for (said, kind) in [false].into_iter().chain([true; KINDS.len()]).zip(KINDS.iter().take(1).chain(&KINDS)) {
        let apart: Vec<Vec<u32>> =
            (0..APART).map(|seed| tile_of(seed, |block| kind.count(seed, block))).collect();
        let words: Vec<u32> = (0..count).flat_map(|at| apart[at % apart.len()].iter().copied()).collect();
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
        let as_they_are = words_buffer(engine, "tiles as they are", &words, usage);
        drop(words);
        let pages = vec![as_they_are, page(engine, "tiles folded", count as u64 * TILE_BYTES / 2)];
        let places: Vec<TileAt> = (0..count as u16).map(|slot| TileAt { page: 0, slot }).collect();
        let [folding] = timed([&mut || {
            fold.folded(engine, &pages, &places).expect("fold");
        }]);
        let folded = fold.folded(engine, &pages, &places).expect("fold");
        // A tile that stays as it is is read where it is.
        let put = placed(&pages, &folded, 1);
        let kept: Vec<TileAt> = put.iter().zip(&places).map(|(folded, &at)| folded.unwrap_or(at)).collect();
        let granules: u64 = (0..count).filter_map(|at| folded.granules(at)).map(u64::from).sum();
        let stay = put.iter().filter(|at| at.is_none()).count();
        let (before, after) = (count as u64 * TILE_BYTES, granules * GRANULE_BYTES + stay as u64 * TILE_BYTES);
        let say = |line: String| {
            if said {
                println!("fold cost: {:<22} {line}", kind.name);
            }
        };
        say(format!(
            "{} of {count} tiles fold, {:.1} -> {:.1} MB ({:.2}x), folded in {:.3} ms a tile",
            count - stay,
            before as f64 / 1048576.0,
            after as f64 / 1048576.0,
            before as f64 / after as f64,
            folding / count as f64,
        ));
        for (name, steps) in [("copied", &copied[..]), ("posed", &posed[..]), ("8 rows over", &over[..])] {
            let (mut as_it_is, mut kept_folded) = (laying(&pages, &places, steps), laying(&pages, &kept, steps));
            let [as_it_is, kept_folded] = timed([&mut as_it_is, &mut kept_folded]);
            say(format!(
                "{name:<12} as they are {as_it_is:8.2} ms, folded {kept_folded:8.2} ms ({:.2}x)",
                kept_folded / as_it_is,
            ));
        }
    }
}
