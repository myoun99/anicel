//! The effect chain on a real GPU: each op as its kernel or the executor's
//! row puts it, the ops one after another, and the rectangle a chain runs
//! over — checked against the executor's and the matrix's own hands, never
//! against a CPU copy of a kernel (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{Chain, ChainRead, MapTiles, Op, Stored, each_pixel, laid_as, picture_bytes, reaching, tiles_of};
use crate::kernels::composite::tests::{
    KEY_GREEN, KEY_RED, Pool, contrast, half, key_run, keyed_by_hand, pixel_at, rig as composite_rig,
    spotted, texel,
};
use crate::device::Engine;
use crate::kernels::composite::{Composite, KeyChain, Lent, TILE, TILE_TEXELS, TileAt};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Edge, Way};
use crate::kernels::effects::blur::iris::{Focus, Iris};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, Light, MapChannel};
use crate::kernels::effects::blur::line::LinePass;
use crate::kernels::effects::matrix_tests::{each, graded};
use crate::kernels::effects::matrix_words;
use crate::kernels::shared::le_words;
use crate::testing::{a_device_of_its_own, read_buffer};

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
    tiles_on(composite_rig().engine, pixel)
}

/// [`tiles`], on `engine`.
fn tiles_on(engine: &Engine, pixel: impl Fn(i32, i32) -> u32) -> wgpu::Buffer {
    let mut pool = Pool::default();
    pool.drawn(pixel, (RECT.x0, RECT.y0), (RECT.columns, RECT.rows), |_, _| Some(0));
    pool.upload(engine).swap_remove(0)
}

/// `tiles` through `ops`, held as the chain put them — a spare of the
/// tests' engine, the next run's to write over once let go of —, or
/// `None` where the chain refused them.
fn chained(tiles: wgpu::Buffer, ops: &[Op]) -> Option<Lent> {
    chained_over(tiles, Stored { pages: &[], sets: &[] }, ops)
}

/// [`chained`], the ops reading `stored` beside the tiles.
fn chained_over(tiles: wgpu::Buffer, stored: Stored, ops: &[Op]) -> Option<Lent> {
    let rig = composite_rig();
    chain().run(rig.engine, &rig.composite, stored, Lent::alone(tiles), RECT, ops)
}

/// The tiles over `rect` holding `pixels` at `picture`, clear elsewhere:
/// a plug-in's picture as a chain lays it, made here by hand — what the
/// device's tiled run of a plug-in is checked against (plugin/tests.rs).
pub(crate) fn put_over(engine: &Engine, rect: TileRect, picture: [i32; 4], pixels: &[u8]) -> Option<wgpu::Buffer> {
    if pixels.len() != picture_bytes(picture) {
        return crate::fail(format!("{} bytes put over {picture:?}", pixels.len()));
    }
    let mut tiles = vec![0u8; (rect.columns * rect.rows) as usize * TILE_TEXELS as usize * 4];
    each_pixel(picture, rect, |at, tile| {
        tiles[tile..tile + 4].copy_from_slice(&pixels[at..at + 4]);
    });
    Some(engine.filled(
        "chain put",
        &tiles,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
    ))
}

/// Every pixel of [`RECT`], row by row of the canvas.
fn pixels() -> impl Iterator<Item = (i32, i32)> {
    let side = TILE as i32;
    (0..2 * side).flat_map(move |y| (-side..2 * side).map(move |x| (x, y)))
}

/// What `out` holds over [`RECT`], A<<24|B<<16|G<<8|R, in [`pixels`]'
/// order.
fn held(out: &Lent) -> Vec<u32> {
    let bytes = read_buffer(composite_rig().engine, out.buffer());
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
pub(crate) fn lens() -> Lens {
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

/// A Gaussian of sigma `across` reaching 3 and `down` reaching 2, reading
/// the picture inside [`RECT`]'s by `edge` and putting past it.
pub(crate) fn blur(across: f64, down: f64, edge: Edge) -> Blur {
    Blur {
        across: Way { sigma: across, reach: 3 },
        down: Way { sigma: down, reach: 2 },
        picture: [-90, 20, 180, 230],
        edge,
        puts: [-100, 10, 200, 240],
    }
}

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
/// the op's own settings — a Gaussian's two sigmas each its way, a lens
/// through its map. Each case is told from a near one, so a setting lost on
/// the way could not pass.
#[test]
fn each_blur_of_a_chain_is_its_kernel_s() {
    let engine = composite_rig().engine;
    let picture = |x, y| texel(93, x, y);
    let blurred = |op: Op| held(&chained(tiles(picture), &[op]).expect("chain"));

    let gaussian = |blur: Blur| {
        let out = chain().gaussian.run(engine, &tiles(picture), RECT, &blur);
        held(&out.expect("blur"))
    };
    let repeated = blur(1.0, 0.7, Edge::Repeat);
    assert_same(&blurred(Op::Gaussian(repeated)), &gaussian(repeated));
    assert_ne!(gaussian(repeated), gaussian(blur(0.7, 1.0, Edge::Repeat)));
    assert_ne!(blurred(Op::Gaussian(blur(1.0, 0.7, Edge::Nothing))), gaussian(repeated));

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
        map: Some(BlurMap {
            tiles: MapTiles::Laid(map.tiles),
            channel: map.channel,
            focus: map.focus,
        }),
    };
    assert_same(&blurred(mapped), &by_lens(Some(map)));
    assert_ne!(by_lens(Some(map)), by_lens(None));
}

/// What each op puts into buffers taken again — every spare scribbled
/// over, as holding what another run left there — is what it puts into
/// ones made new: a blur zeroes the tiles it puts before its passes and
/// reads its planes only where a pass put them, and a colour step puts
/// every tile whole. On a device of the test's own, whose spares are no
/// other test's.
#[test]
fn each_op_puts_into_buffers_taken_again_what_it_puts_into_new_ones() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let chain = Chain::new(&engine);
    let map_tiles = tiles_on(&engine, |x, y| texel(96, x, y));
    let map = BlurMap {
        tiles: MapTiles::Laid(&map_tiles),
        channel: MapChannel::Luminance,
        focus: Focus {
            focal: 128.0,
            inverts: true,
        },
    };
    let ops = [
        Op::Keys(KeyChain {
            runs: vec![key_run(KEY_RED, false, half)],
        }),
        Op::Matrix(matrix_words(&graded(0.5, 40.0)).expect("a matrix in range")),
        Op::Gaussian(blur(1.0, 0.7, Edge::Nothing)),
        Op::Line {
            plate: [-100, 10, 200, 240],
            passes: vec![LinePass::along([1.5, 0.5], 7), LinePass::along([-0.5, 1.5], 5)],
        },
        // Over a picture inside the rectangle, as the other two put.
        Op::Lens {
            picture: [-100, 10, 200, 240],
            lens: lens(),
            map: Some(map),
        },
        // The map's tiles as a set a plug-in made.
        Op::Put(0),
    ];
    let sets = [laid_as(RECT, 0)];
    let ran = |op: &Op| {
        let tiles = Lent::alone(tiles_on(&engine, |x, y| spotted(95, x, y)));
        let stored = Stored { pages: std::slice::from_ref(&map_tiles), sets: &sets };
        let put = chain.run(&engine, &composite, stored, tiles, RECT, std::slice::from_ref(op));
        let bytes = read_buffer(&engine, put.expect("chain").buffer());
        bytes[..TILES.len() * TILE_TEXELS as usize * 4].to_vec()
    };
    // The buffers each makes, every one a spare: the tiles it puts and,
    // of a blur, the two planes between its passes.
    let buffers = [1, 1, 3, 3, 3, 1];
    for (at, op) in ops.iter().enumerate() {
        engine.spares.let_go();
        let before = engine.spares.made();
        let new = ran(op);
        assert!(new.iter().any(|&byte| byte != 0), "the premise: op {at} puts a picture");
        let made = engine.spares.made();
        assert_eq!(made - before, buffers[at], "each buffer op {at} made is a spare");
        engine.spares.scribble(&engine);
        assert!(ran(op) == new, "op {at}");
        assert_eq!(engine.spares.made(), made, "the premise: op {at} took each of its buffers again");
    }
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
            Op::Gaussian(blur(1.0, 0.7, Edge::Nothing)),
            Op::Line {
                plate: [-100, 10, 200, 240],
                passes: vec![LinePass::along([1.5, 0.5], 7)],
            },
            Op::Lens {
                picture: PICTURE,
                lens: lens(),
                map: Some(BlurMap {
                    tiles: MapTiles::Laid(&map_tiles),
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

    let mut put = Lent::alone(tiles(picture));
    for op in &ops() {
        put = chained(put.buffer().clone(), std::slice::from_ref(op)).expect("chain");
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

/// A map drawn from rows is the executor's to draw before the chain runs
/// (`Composite::chained`): a chain handed one refuses it, and reads it as
/// no map nowhere.
#[test]
fn a_chain_refuses_a_map_still_to_be_drawn() {
    let map = BlurMap {
        tiles: MapTiles::Drawn(&[]),
        channel: MapChannel::Red,
        focus: Focus {
            focal: 0.0,
            inverts: false,
        },
    };
    let op = Op::Lens {
        picture: PICTURE,
        lens: lens(),
        map: Some(map),
    };
    assert!(chained(tiles(|x, y| texel(95, x, y)), &[op]).is_none());
}

/// A plug-in's step reads what the chain had come to: what the op before
/// it put is handed on as it is, and what the host is given of it is those
/// pixels, clear past the tiles the chain ran over.
#[test]
fn a_read_keeps_what_the_chain_came_to_and_hands_it_on() {
    let side = TILE as i32;
    let came_to = |x, y| texel(96, x, y);
    let read = ChainRead::default();
    let op = Op::Read { read: read.clone(), rows: Vec::new() };
    let out = chained(tiles(came_to), &[op]).expect("chain");
    assert_same(&held(&out), &pixels().map(|(x, y)| came_to(x, y)).collect::<Vec<_>>());

    // A pixel left of the chain's rectangle, then pixels of its first two
    // tiles either side of their seam, one row a tile up.
    let (left, right, y) = (-side - 1, -side + 2, side - 1);
    let bytes = read
        .pixels(composite_rig().engine, [left, y, right, y + 1], None)
        .expect("kept");
    let want: Vec<u8> = (left..right)
        .flat_map(|x| if x < -side { 0 } else { came_to(x, y) }.to_le_bytes())
        .collect();
    assert_eq!(bytes, want);
}

/// [`RECT`]'s pixels, as a picture's four edges.
fn whole() -> [i32; 4] {
    let side = TILE as i32;
    [RECT.x0 * side, RECT.y0 * side, (RECT.x0 + RECT.columns as i32) * side, (RECT.y0 + RECT.rows as i32) * side]
}

/// `pixel` where `stands` has a tile of it, clear elsewhere, over
/// [`RECT`] in [`pixels`]' order.
fn where_it_stands(pixel: impl Fn(i32, i32) -> u32, stands: impl Fn(i32, i32) -> bool) -> Vec<u32> {
    let side = TILE as i32;
    pixels()
        .map(|(x, y)| if stands(x.div_euclid(side), y.div_euclid(side)) { pixel(x, y) } else { 0 })
        .collect()
}

/// A read keeps the rows it names — the plan's tile sets, by slot — as
/// they are stored over the chain's rectangle: a low alpha's colour as it
/// is, nothing where a row has no tile, and nothing of a tile past the
/// rectangle.
#[test]
fn a_read_keeps_each_row_it_names_as_it_is_stored() {
    let engine = composite_rig().engine;
    let mut pool = Pool::default();
    // Each row past the rectangle on one side, and short of it elsewhere.
    let first = |column: i32, row: i32| column >= 0 && row == 0;
    let second = |column: i32, row: i32| column == -1 && row == 1;
    let sets = [
        pool.drawn(|x, y| texel(101, x, y), (0, 0), (3, 1), |column, row| first(column, row).then_some(0)),
        pool.drawn(|x, y| texel(102, x, y), (-2, 1), (2, 1), |column, _| (column <= -1).then_some(1)),
    ];
    let pages = pool.upload(engine);
    let read = ChainRead::default();
    // The second set in slot 0: a slot is the set it names, not its place.
    let op = Op::Read { read: read.clone(), rows: vec![1, 0] };
    let came_to = |x, y| texel(103, x, y);
    let out = chained_over(tiles(came_to), Stored { pages: &pages, sets: &sets }, &[op]).expect("chain");
    assert_same(&held(&out), &pixels().map(|(x, y)| came_to(x, y)).collect::<Vec<_>>());

    let row = |slot| le_words(&read.pixels(engine, whole(), Some(slot)).expect("kept"));
    assert_same(&row(0), &where_it_stands(|x, y| texel(102, x, y), second));
    assert_same(&row(1), &where_it_stands(|x, y| texel(101, x, y), |column, row| first(column, row) && column < 2));
    assert!(read.pixels(engine, whole(), Some(2)).is_none());
    assert_eq!(crate::last_error(), "no row 2 of 2");
}

/// What a plug-in made replaces what the op before it put: the tiles of
/// the set it names as they are stored, and nothing past them.
#[test]
fn a_put_lays_the_set_it_names_and_nothing_else() {
    let engine = composite_rig().engine;
    let mut pool = Pool::default();
    let stands = |column: i32, row: i32| (column, row) == (0, 0) || (column, row) == (1, 1);
    let made = |x, y| texel(97, x, y);
    let sets = [pool.drawn(made, (0, 0), (2, 2), |column, row| stands(column, row).then_some(0))];
    let pages = pool.upload(engine);
    let stored = Stored { pages: &pages, sets: &sets };
    let out = chained_over(tiles(|x, y| texel(98, x, y)), stored, &[Op::Put(0)]).expect("chain");
    assert_same(&held(&out), &where_it_stands(made, stands));
}

/// A read or a put of a set the plan has not is refused, by its number.
#[test]
fn a_read_or_a_put_of_a_set_the_plan_has_not_is_refused() {
    let read = ChainRead::default();
    for op in [Op::Put(0), Op::Read { read: read.clone(), rows: vec![0] }] {
        assert!(chained(tiles(|x, y| texel(99, x, y)), &[op]).is_none());
        assert_eq!(crate::last_error(), "no tile set 0 of 0");
    }
    assert!(read.kept().is_none(), "a read refused keeps nothing");
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
