//! The effect chain on a real GPU: each op as its kernel or the executor's
//! row puts it, the ops one after another, and the rectangle a chain runs
//! over — checked against the executor's and the matrix's own hands, never
//! against a CPU copy of a kernel (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{Chain, Op, laid_as, reaching, tiles_of};
use crate::kernels::composite::tests::{
    KEY_GREEN, KEY_RED, Pool, contrast, half, key_run, keyed_by_hand, pixel_at, rig as composite_rig,
    spotted, texel,
};
use crate::kernels::composite::{KeyChain, TILE, TileAt};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::Edge;
use crate::kernels::effects::blur::iris::{Focus, Iris};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, Light, MapChannel};
use crate::kernels::effects::blur::line::LinePass;
use crate::kernels::effects::matrix_tests::{each, graded};
use crate::kernels::effects::matrix_words;
use crate::testing::read_buffer;

/// The chain's blurs, compiled once on the executor's device for every
/// test here (blend's tests have why).
fn chain() -> &'static Chain {
    static CHAIN: OnceLock<Chain> = OnceLock::new();
    CHAIN.get_or_init(|| Chain::new(composite_rig().engine))
}

/// Wider than tall and left of the origin, so a tile counted by the wrong
/// side or from the wrong corner lands elsewhere.
const RECT: TileRect = TileRect {
    x0: -1,
    y0: 0,
    columns: 3,
    rows: 2,
};

/// [`RECT`]'s tiles, row by row.
const TILES: [(i32, i32); 6] = [(-1, 0), (0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)];

/// [`RECT`]'s tiles holding `pixel`, as a chain reads them: the store's
/// page of them, tile after tile row by row.
fn tiles(pixel: impl Fn(i32, i32) -> u32) -> wgpu::Buffer {
    let mut pool = Pool::default();
    pool.drawn(pixel, (RECT.x0, RECT.y0), (RECT.columns, RECT.rows), |_, _| Some(0));
    pool.upload(composite_rig().engine).swap_remove(0)
}

/// `tiles` through `ops`, or `None` where the chain refused them.
fn chained(tiles: wgpu::Buffer, ops: &[Op]) -> Option<wgpu::Buffer> {
    let rig = composite_rig();
    chain().run(rig.engine, &rig.composite, tiles, RECT, ops)
}

/// Every pixel of [`RECT`], row by row of the canvas.
fn pixels() -> impl Iterator<Item = (i32, i32)> {
    let side = TILE as i32;
    (0..2 * side).flat_map(move |y| (-side..2 * side).map(move |x| (x, y)))
}

/// What `out` holds over [`RECT`], A<<24|B<<16|G<<8|R, in [`pixels`]'
/// order.
fn held(out: &wgpu::Buffer) -> Vec<u32> {
    let bytes = read_buffer(composite_rig().engine, out);
    pixels()
        .map(|(x, y)| u32::from_le_bytes(pixel_at(&bytes, &TILES, x, y)))
        .collect()
}

/// Asserts `got` is `want`, naming the first pixel where it is not.
fn assert_same(got: &[u32], want: &[u32]) {
    if let Some(i) = (0..want.len()).find(|&i| got[i] != want[i]) {
        let (x, y) = pixels().nth(i).expect("a pixel of the rectangle");
        panic!("({x}, {y}) holds {:#010x}, not {:#010x}", got[i], want[i]);
    }
}

/// A square, standing square — its turns by square roots alone.
fn square() -> Iris {
    let half = 0.5f64.sqrt();
    Iris {
        sides: 4,
        roundness: 0.0,
        aspect: 1.0,
        turn: [1.0, 0.0],
        half_side: [half, half],
        side: [0.0, 1.0],
    }
}

/// A lens blur 3 pixels out, nothing past its picture — so the picture an op
/// names is the one it blurs over (a paper repeated hid it, mutant c08).
fn lens() -> Lens {
    Lens {
        iris: square(),
        radius: 3.0,
        fringe: 0.0,
        light: Light::STORED,
        paper: None,
    }
}

/// The pixels of [`RECT`], [left, top, right, bottom).
const PICTURE: [i32; 4] = [-128, 0, 256, 256];

/// Tile k of a chain's rectangle is slot k of its page, the rectangle's
/// tiles taken row by row — as a blur lays them, and the store a row's.
#[test]
fn a_chain_s_tiles_lie_row_by_row() {
    assert_eq!(tiles_of(RECT), TILES);
    let set = laid_as(RECT, 3);
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (-1, 0, 3, 2));
    let slots: Vec<_> = (0..6).map(|slot| Some(TileAt { page: 3, slot })).collect();
    assert_eq!(set.tiles, slots);
}

/// A colour matrix lays what the executor's row lays through it: every
/// stored pixel through the matrix, and nothing where that leaves no alpha.
#[test]
fn a_colour_matrix_is_the_executor_s_row_through_it() {
    let picture = |x, y| texel(91, x, y);
    let words = matrix_words(&contrast()).expect("a matrix in range");
    let out = chained(tiles(picture), &[Op::Matrix(words)]).expect("chain");
    let stored: Vec<u32> = pixels().map(|(x, y)| picture(x, y)).collect();
    let want: Vec<u32> = each(contrast(), &stored)
        .into_iter()
        .map(|word| if word >> 24 == 0 { 0 } else { word })
        .collect();
    assert_same(&held(&out), &want);
}

/// A run of keys keys every pixel it reads against that pixel's alpha, in
/// each of the executor's runs it is held in — two here, as a run of more
/// keys than one of them holds is.
#[test]
fn a_key_run_keys_what_it_reads() {
    let picture = |x, y| spotted(92, x, y);
    let keys = KeyChain {
        runs: vec![key_run(KEY_RED, false, half), key_run(KEY_GREEN, false, half)],
    };
    let out = chained(tiles(picture), &[Op::Keys(keys)]).expect("chain");
    let keyed = |pixel| keyed_by_hand(keyed_by_hand(pixel, KEY_RED, half), KEY_GREEN, half);
    let want: Vec<u32> = pixels().map(|(x, y)| keyed(picture(x, y))).collect();
    assert_same(&held(&out), &want);
}

/// Each blur of a chain is its kernel's, run on the chain's rectangle with
/// the op's own settings — a Gaussian's two radii each its way, a lens
/// through its map. Each case is told from a near one, so a setting lost on
/// the way could not pass.
#[test]
fn each_blur_of_a_chain_is_its_kernel_s() {
    let engine = composite_rig().engine;
    let picture = |x, y| texel(93, x, y);
    let blurred = |op: Op| held(&chained(tiles(picture), &[op]).expect("chain"));

    let edge = Edge::Repeat([-90, 20, 180, 230]);
    let gaussian = |radius| {
        let out = chain().gaussian.run(engine, &tiles(picture), RECT, radius, edge);
        held(&out.expect("blur"))
    };
    assert_same(&blurred(Op::Gaussian { radius: (3, 2), edge }), &gaussian((3, 2)));
    assert_ne!(gaussian((3, 2)), gaussian((2, 3)));
    let unrepeated = Op::Gaussian {
        radius: (3, 2),
        edge: Edge::Nothing,
    };
    assert_ne!(blurred(unrepeated), gaussian((3, 2)));

    let plate = [-100, 10, 200, 240];
    let passes = vec![LinePass::along([1.5, 0.5], 7)];
    let line = chain().line.run(engine, &tiles(picture), RECT, plate, &passes);
    assert_same(&blurred(Op::Line { plate, passes }), &held(&line.expect("blur")));

    let map_tiles = tiles(|x, y| texel(94, x, y));
    let map = BlurMap {
        tiles: &map_tiles,
        channel: MapChannel::Red,
        focus: Focus {
            focal: 0.0,
            inverts: false,
        },
    };
    let by_lens = |map| {
        let out = chain().lens.run(engine, &tiles(picture), RECT, PICTURE, &lens(), map);
        held(&out.expect("blur"))
    };
    let mapped = Op::Lens {
        picture: PICTURE,
        lens: lens(),
        map: Some(map),
    };
    assert_same(&blurred(mapped), &by_lens(Some(map)));
    assert_ne!(by_lens(Some(map)), by_lens(None));
}

/// A chain's ops run one after another, each on what the one before put —
/// so the chain is its ops chained one at a time, and not them in another
/// order.
#[test]
fn a_chain_runs_its_ops_one_after_another() {
    let picture = |x, y| spotted(95, x, y);
    let map_tiles = tiles(|x, y| texel(96, x, y));
    let ops = || {
        let tint = matrix_words(&graded(0.5, 40.0)).expect("a matrix in range");
        vec![
            Op::Keys(KeyChain {
                runs: vec![key_run(KEY_RED, false, half)],
            }),
            Op::Matrix(matrix_words(&contrast()).expect("a matrix in range")),
            Op::Gaussian {
                radius: (3, 2),
                edge: Edge::Nothing,
            },
            Op::Line {
                plate: [-100, 10, 200, 240],
                passes: vec![LinePass::along([1.5, 0.5], 7)],
            },
            Op::Lens {
                picture: PICTURE,
                lens: lens(),
                map: Some(BlurMap {
                    tiles: &map_tiles,
                    channel: MapChannel::Luminance,
                    focus: Focus {
                        focal: 128.0,
                        inverts: true,
                    },
                }),
            },
            Op::Matrix(tint),
        ]
    };
    let whole = held(&chained(tiles(picture), &ops()).expect("chain"));

    let mut put = tiles(picture);
    for op in &ops() {
        put = chained(put, std::slice::from_ref(op)).expect("chain");
    }
    assert_same(&whole, &held(&put));

    let mut turned = ops();
    turned.reverse();
    assert_ne!(whole, held(&chained(tiles(picture), &turned).expect("chain")));
}

/// A chain of no op is no chain: a plan leaves it out.
#[test]
fn a_chain_of_no_op_is_refused() {
    assert!(chained(tiles(|_, _| 0), &[]).is_none());
}

/// A chain runs over its output's tiles grown by whole tiles, as many each
/// way as its reach takes: none for none, one for up to a tile's side, two
/// past it.
#[test]
fn a_chain_runs_over_whole_tiles_as_far_as_it_reaches() {
    let out = [(2, -1), (4, 0)];
    let rect = |reach| reaching(&out, reach).map(|rect| (rect.x0, rect.y0, rect.columns, rect.rows));
    assert_eq!(rect(0), Some((2, -1, 3, 2)));
    assert_eq!(rect(1), Some((1, -2, 5, 4)));
    assert_eq!(rect(TILE), Some((1, -2, 5, 4)));
    assert_eq!(rect(TILE + 1), Some((0, -3, 7, 6)));
    assert!(reaching(&[], 5).is_none());
}
