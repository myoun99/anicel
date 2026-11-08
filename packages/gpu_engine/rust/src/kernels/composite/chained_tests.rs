//! Effect chains a plan names, on a real GPU: a chained row or buffer lays
//! what its chain puts as a row, each checked against the chain run by
//! hand and laid so. What a chain puts is checked against its kernels' own
//! hands in kernels/chain. A buffer closed as a row, run first as a chained
//! one is, likewise.

use std::sync::OnceLock;

use super::tests::{
    Pool, chained, contrast, keyed, masked_row, matrixed, mixed, pose, rig, row, texel, with_map,
};
use super::{Budget, NO_EDGE, Over, Plan, Step, TileSet, WHOLE, check_depth};
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, PLUS, SCREEN};
use crate::kernels::chain::tests::lens;
use crate::kernels::chain::{Chain, Chained, MapTiles, Op, laid_as, tiles_of};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Edge, Way};
use crate::kernels::effects::blur::iris::Focus;
use crate::kernels::effects::blur::lens::{BlurMap, MapChannel};
use crate::kernels::effects::{MATRIX_WORDS, matrix_words};
use crate::kernels::mask::Mask;
use crate::kernels::mask::tests::masked;
use crate::kernels::shared::ResampleMap;
use crate::testing::read_buffer;

/// The output: two by two tiles from the origin.
const TILES: [(i32, i32); 4] = [(0, 0), (1, 0), (0, 1), (1, 1)];

/// Where a chain runs: wider than the output and left of it, so a chain
/// run over the output's tiles, or counted from the wrong corner, puts
/// elsewhere.
const RECT: TileRect = TileRect {
    x0: -1,
    y0: 0,
    columns: 3,
    rows: 2,
};

/// Taller than [`RECT`] and above it, for a chain that is not its.
const TALL: TileRect = TileRect {
    x0: 0,
    y0: -1,
    columns: 2,
    rows: 3,
};

/// The executor's chain: the one it compiles where a plan first names one.
fn chain() -> &'static Chain {
    let rig = rig();
    rig.composite.chain.get_or_init(|| Chain::new(rig.engine))
}

/// The one colour matrix here — matrix 0 of every plan —, made once so a
/// plan can borrow it.
fn matrix() -> &'static [u32; MATRIX_WORDS] {
    static MATRIX: OnceLock<[u32; MATRIX_WORDS]> = OnceLock::new();
    MATRIX.get_or_init(|| matrix_words(&contrast()).expect("a matrix in range"))
}

/// A Gaussian of `sigmas` reaching `reaches` over the whole of `rect`'s
/// tiles, nothing past them.
fn gaussian(rect: TileRect, sigmas: (f64, f64), reaches: (u32, u32)) -> Op<'static> {
    let whole = rect.pixels();
    Op::Gaussian(Blur {
        across: Way { sigma: sigmas.0, reach: reaches.0 },
        down: Way { sigma: sigmas.1, reach: reaches.1 },
        picture: whole,
        edge: Edge::Nothing,
        puts: whole,
    })
}

/// A blur, then a colour matrix between it and the final paint.
fn blurred() -> Vec<Op<'static>> {
    vec![gaussian(RECT, (1.0, 0.7), (3, 2)), Op::Matrix(*matrix())]
}

/// A blur along the rows alone.
fn across() -> Vec<Op<'static>> {
    vec![gaussian(RECT, (1.7, 0.0), (5, 0))]
}

/// A blur down the columns alone, over [`TALL`].
fn down() -> Vec<Op<'static>> {
    vec![gaussian(TALL, (0.0, 1.3), (0, 4))]
}

/// A buffer's close at `opacity` in `mode`, through matrix `matrix` if any.
fn close(opacity: u32, mode: u32, matrix: Option<usize>) -> Step {
    Step::Close {
        opacity,
        mode,
        matrix,
        chain: None,
    }
}

/// The pages and tile sets the plans here lay, and the sets a chain run by
/// hand adds.
struct Laying {
    pages: Vec<wgpu::Buffer>,
    sets: Vec<TileSet>,
}

impl Laying {
    /// Row n of `rows` — its origin and size in tiles — on page n, its
    /// pixels [`texel`]'s of seed 81 + n.
    fn new(rows: &[((i32, i32), (u32, u32))]) -> Self {
        let mut pool = Pool::default();
        let sets = (0..rows.len())
            .map(|n| {
                let (origin, size) = rows[n];
                let pixel = move |x, y| texel(81 + n as u32, x, y);
                pool.drawn(pixel, origin, size, |_, _| Some(n as u16))
            })
            .collect();
        Self {
            pages: pool.upload(rig().engine),
            sets,
        }
    }

    /// The plan laying `steps` through `chains`, under `mask` if any.
    fn plan<'a>(
        &'a self,
        chains: &'a [Chained<'a>],
        steps: &'a [Step],
        mask: Option<&'a Mask<'a>>,
    ) -> Plan<'a> {
        Plan {
            pages: &self.pages,
            sets: &self.sets,
            keys: &[],
            matrices: std::slice::from_ref(matrix()),
            chains,
            steps,
            mask,
        }
    }

    /// `steps` through `chains` over the output `tiles` within `budget`,
    /// under `mask` if any: the output's bytes, or `None` where the plan was
    /// refused.
    fn over(
        &self,
        tiles: &[(i32, i32)],
        (chains, steps): (&[Chained], &[Step]),
        mask: Option<&Mask>,
        budget: Budget,
    ) -> Option<Vec<u8>> {
        let rig = rig();
        let plan = self.plan(chains, steps, mask);
        let done = rig.composite.run(rig.engine, &plan, tiles, NO_EDGE, budget)?;
        Some(read_buffer(rig.engine, &done.out))
    }

    /// [`Laying::over`] [`TILES`].
    fn composited(
        &self,
        chains: &[Chained],
        steps: &[Step],
        mask: Option<&Mask>,
        budget: Budget,
    ) -> Option<Vec<u8>> {
        self.over(&TILES, (chains, steps), mask, budget)
    }

    /// [`Laying::composited`] at all the device lets a pass take.
    fn widest(&self, chains: &[Chained], steps: &[Step], mask: Option<&Mask>) -> Vec<u8> {
        let budget = rig().composite.widest();
        self.composited(chains, steps, mask, budget).expect("composite")
    }

    /// `tiles` over `rect` laid as a tile set of their own on a page of
    /// their own: that set.
    fn laid(&mut self, tiles: wgpu::Buffer, rect: TileRect) -> usize {
        self.sets.push(laid_as(rect, self.pages.len() as u16));
        self.pages.push(tiles);
        self.sets.len() - 1
    }

    /// `tiles` — over `rect` — through `ops`, [`Laying::laid`].
    fn through(&mut self, tiles: wgpu::Buffer, rect: TileRect, ops: &[Op]) -> usize {
        let rig = rig();
        let put = chain().run(rig.engine, &rig.composite, tiles, rect, ops).expect("chain");
        self.laid(put, rect)
    }

    /// `steps` composited alone over `rect`, with no edge: the tiles.
    fn alone(&self, steps: &[Step], rect: TileRect) -> wgpu::Buffer {
        let rig = rig();
        let plan = self.plan(&[], steps, None);
        let widest = rig.composite.widest();
        let done = rig.composite.run(rig.engine, &plan, &tiles_of(rect), NO_EDGE, widest);
        done.expect("composite").out
    }

    /// Set `set`'s tiles over `rect`, as they are stored, through `ops`, by
    /// hand: the set they are laid as.
    fn row_by_hand(&mut self, set: usize, rect: TileRect, ops: &[Op]) -> usize {
        let Self { pages, sets } = &*self;
        let (rig, read) = (rig(), tiles_of(rect));
        let widest = rig.composite.widest();
        let copied = rig.composite.copied(rig.engine, pages, &sets[set], &read, widest);
        self.through(copied.expect("copy").out, rect, ops)
    }

    /// `steps` composited alone over `rect`, with no edge, through `ops`, by
    /// hand: the set they are laid as.
    fn buffer_by_hand(&mut self, steps: &[Step], rect: TileRect, ops: &[Op]) -> usize {
        let tiles = self.alone(steps, rect);
        self.through(tiles, rect, ops)
    }
}

// A row's chain runs on its stored tiles over its rectangle, in its own
// space; what it puts is laid as the row was — posed, through its matrix,
// at its opacity in its mode, under the plan's mask.
#[test]
fn a_chained_row_lays_what_its_chain_puts_as_it_was_laid() {
    let mut laying = Laying::new(&[((0, 0), (2, 2)), ((0, 0), (2, 1))]);
    let selection = masked((-20, 10), (300, 200), |x, y| (x ^ y) as u8);
    let mask = Some(selection.mask());
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let posed = |set| matrixed(masked_row(with_map(set, pose("turn"), 50000, MULTIPLY)), 0);
    let chains = [Chained {
        ops: blurred(),
        rect: RECT,
    }];
    let got = laying.widest(&chains, &[base, chained(posed(1), 0)], mask.as_ref());
    assert!(got != laying.widest(&[], &[base, posed(1)], mask.as_ref()), "the chain ran");
    let put = laying.row_by_hand(1, RECT, &blurred());
    assert!(got == laying.widest(&[], &[base, posed(put)], mask.as_ref()));
}

// A buffer's chain runs on its rows composited alone on the canvas over its
// rectangle; what it puts is laid in their place as one row, unposed, at
// the close's opacity, mode and matrix.
#[test]
fn a_chained_buffer_lays_what_its_chain_puts_as_its_close_does() {
    let mut laying = Laying::new(&[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let rows = [row(1, (3, -2), 50000, NORMAL), row(2, (-5, 4), 40000, MULTIPLY)];
    let closing = close(45000, SCREEN, Some(0));
    let chains = [Chained {
        ops: blurred(),
        rect: RECT,
    }];
    let buffer = |close| [base, Step::Open, rows[0], rows[1], close];
    let got = laying.widest(&chains, &buffer(chained(closing, 0)), None);
    assert!(got != laying.widest(&[], &buffer(closing), None), "the chain ran");
    let put = laying.buffer_by_hand(&rows, RECT, &blurred());
    let laid = matrixed(row(put, (0, 0), 45000, SCREEN), 0);
    assert!(got == laying.widest(&[], &[base, laid], None));
}

// An adjustment's chain under a whole mix crossfades its scope with what
// the chain put (composeAdjustmentScope): in one buffer the scope at the
// rest of the mix, the chain's added by plus at the mix through the close's
// matrix, the buffer closed at the close's opacity and mode.
#[test]
fn a_buffer_chained_at_a_mix_crossfades_its_rows_with_what_its_chain_puts() {
    let mut laying = Laying::new(&[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let rows = [row(1, (3, -2), 50000, NORMAL), row(2, (-5, 4), 40000, MULTIPLY)];
    let chains = [Chained {
        ops: blurred(),
        rect: RECT,
    }];
    let buffer = |close| [base, Step::Open, rows[0], rows[1], close];
    let closing = |mix| mixed(close(45000, SCREEN, Some(0)), 0, mix);
    let got = laying.widest(&chains, &buffer(closing(20000)), None);
    assert!(got != laying.widest(&chains, &buffer(closing(WHOLE)), None), "the mix");
    let scope = laying.alone(&rows, RECT);
    let put = laying.through(scope.clone(), RECT, &blurred());
    let read = laying.laid(scope, RECT);
    let crossfade = [
        base,
        Step::Open,
        row(read, (0, 0), WHOLE - 20000, NORMAL),
        matrixed(row(put, (0, 0), 20000, PLUS), 0),
        close(45000, SCREEN, None),
    ];
    assert!(got == laying.widest(&[], &crossfade, None));
}

/// A lens blur over [`RECT`] whose map, read by its luma, is `tiles`.
fn lensed(tiles: MapTiles<'_>) -> Vec<Op<'_>> {
    let map = BlurMap {
        tiles,
        channel: MapChannel::Luminance,
        focus: Focus {
            focal: 128.0,
            inverts: false,
        },
    };
    let picture = RECT.pixels();
    vec![Op::Lens {
        picture,
        lens: lens(),
        map: Some(map),
    }]
}

// A lens blur's map drawn from rows is those rows drawn alone over the
// chain's rectangle as they show by themselves — a chained one through its
// own chain, and with no edge, as far as the rectangle reaches — and a row
// that draws nothing is a map with nothing on it. Seen over the whole
// rectangle, left of the canvas too.
#[test]
fn a_map_drawn_from_rows_is_those_rows_drawn_alone_over_the_rectangle() {
    let mut laying = Laying::new(&[((0, 0), (2, 2)), ((-1, 0), (3, 1)), ((-1, 0), (3, 2))]);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let reader = chained(row(1, (0, 0), WHOLE, NORMAL), 0);
    let map_rows = [chained(row(2, (4, -3), 50000, NORMAL), 1)];
    let nothing: [Step; 0] = [];
    fn reading(rows: &[Step]) -> [Chained<'_>; 2] {
        [
            Chained {
                ops: lensed(MapTiles::Drawn(rows)),
                rect: RECT,
            },
            Chained {
                ops: across(),
                rect: RECT,
            },
        ]
    }
    fn seen(laying: &Laying, chains: &[Chained], steps: &[Step]) -> Vec<u8> {
        let budget = rig().composite.widest();
        laying.over(&tiles_of(RECT), (chains, steps), None, budget).expect("composite")
    }
    let got = seen(&laying, &reading(&map_rows), &[base, reader]);
    let got_nothing = seen(&laying, &reading(&nothing), &[base, reader]);
    assert!(got != got_nothing, "the map");
    let map_put = laying.row_by_hand(2, RECT, &across());
    let map = laying.alone(&[row(map_put, (4, -3), 50000, NORMAL)], RECT);
    let put = laying.row_by_hand(1, RECT, &lensed(MapTiles::Laid(&map)));
    assert!(got == seen(&laying, &[], &[base, row(put, (0, 0), WHOLE, NORMAL)]));
    let blank = laying.alone(&nothing, RECT);
    let put = laying.row_by_hand(1, RECT, &lensed(MapTiles::Laid(&blank)));
    assert!(got_nothing == seen(&laying, &[], &[base, row(put, (0, 0), WHOLE, NORMAL)]));
}

// A map's rows read no map of their own (🗣️I-132-Q22 a — the app takes it
// off them): a plan whose map's rows name one is refused, not drawn a level
// further.
#[test]
fn a_map_s_rows_read_no_map_of_their_own() {
    let laying = Laying::new(&[((0, 0), (2, 2)), ((-1, 0), (3, 1)), ((-1, 0), (3, 2))]);
    let deeper = [row(0, (0, 0), WHOLE, NORMAL)];
    let plain = [row(2, (4, -3), 50000, NORMAL)];
    let reading_one = [chained(row(2, (4, -3), 50000, NORMAL), 1)];
    let chains = |rows| {
        [
            Chained {
                ops: lensed(MapTiles::Drawn(rows)),
                rect: RECT,
            },
            Chained {
                ops: lensed(MapTiles::Drawn(&deeper)),
                rect: RECT,
            },
        ]
    };
    let budget = rig().composite.widest();
    let steps = [chained(row(1, (0, 0), WHOLE, NORMAL), 0)];
    assert!(laying.composited(&chains(&plain), &steps, None, budget).is_some());
    assert!(laying.composited(&chains(&reading_one), &steps, None, budget).is_none());
}

// A folder's rows' chains run before its own, and a folder in it before it:
// what each puts is what the one around it composites — a folder in it
// that runs no chain among them. Cut into passes of one page, one tile and
// two levels, the same.
#[test]
fn chains_run_innermost_first() {
    let mut laying = Laying::new(&[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let inner = row(2, (-3, 0), WHOLE, SCREEN);
    let plain = [
        Step::Open,
        row(1, (-7, 3), 30000, SCREEN),
        close(WHOLE, MULTIPLY, None),
    ];
    let steps = [
        &[base, Step::Open, chained(row(1, (2, 1), 50000, NORMAL), 0)][..],
        &[Step::Open, inner, chained(close(40000, MULTIPLY, None), 2)],
        &plain,
        &[chained(close(50000, NORMAL, Some(0)), 1)],
    ]
    .concat();
    let chains = [
        Chained {
            ops: blurred(),
            rect: RECT,
        },
        Chained {
            ops: across(),
            rect: RECT,
        },
        Chained {
            ops: down(),
            rect: TALL,
        },
    ];
    let got = laying.widest(&chains, &steps, None);
    let narrowest = Budget {
        pages: 1,
        tiles: 1,
        levels: 2,
    };
    let cut = laying.composited(&chains, &steps, None, narrowest);
    assert!(cut.as_ref() == Some(&got), "cut into passes");
    let row_put = laying.row_by_hand(1, RECT, &blurred());
    let inner_put = laying.buffer_by_hand(&[inner], TALL, &down());
    let rows = [
        &[row(row_put, (2, 1), 50000, NORMAL), row(inner_put, (0, 0), 40000, MULTIPLY)][..],
        &plain,
    ]
    .concat();
    let outer_put = laying.buffer_by_hand(&rows, RECT, &across());
    let laid = matrixed(row(outer_put, (0, 0), 50000, NORMAL), 0);
    assert!(got == laying.widest(&[], &[base, laid], None));
}

// A step names an effect chain the plan has, a buffer mixes its chain no
// further than whole, and a row names keys or a chain, not both: both run
// on its stored pixels before its pose, so neither order would be the
// plan's.
#[test]
fn a_plan_names_the_chains_it_has_and_keys_no_chained_row() {
    let a_row = row(0, (0, 0), WHOLE, NORMAL);
    assert!(check_depth(&[chained(a_row, 1)], 1, 0, 0, 2).is_some());
    assert!(check_depth(&[chained(a_row, 1)], 1, 0, 0, 1).is_none());
    let scope = [Step::Open, chained(close(WHOLE, NORMAL, None), 1)];
    assert!(check_depth(&scope, 1, 0, 0, 2).is_some());
    assert!(check_depth(&scope, 1, 0, 0, 1).is_none());
    assert!(check_depth(&[keyed(a_row, 0)], 1, 1, 0, 1).is_some());
    assert!(check_depth(&[chained(keyed(a_row, 0), 0)], 1, 1, 0, 1).is_none());
    let at = |mix| [Step::Open, mixed(close(WHOLE, NORMAL, None), 0, mix)];
    assert!(check_depth(&at(WHOLE), 1, 0, 0, 1).is_some());
    assert!(check_depth(&at(WHOLE + 1), 1, 0, 0, 1).is_none());
}

// A buffer opened on the one under it holds what is under it, which its
// steps alone do not lay: its chain is refused, not run on what they lay.
#[test]
fn a_buffer_opened_on_the_one_under_it_runs_no_chain() {
    let laying = Laying::new(&[((0, 0), (2, 2)), ((0, 0), (2, 1))]);
    let chains = [Chained {
        ops: across(),
        rect: RECT,
    }];
    let budget = rig().composite.widest();
    let scope = |open| [row(0, (0, 0), WHOLE, NORMAL), open, row(1, (0, 0), WHOLE, MULTIPLY)];
    let closed = |open| [&scope(open)[..], &[chained(close(WHOLE, NORMAL, None), 0)]].concat();
    let composited = |open| laying.composited(&chains, &closed(open), None, budget);
    assert!(composited(Step::Open).is_some());
    assert!(composited(Step::OpenOpaque).is_none());
}

/// A buffer closed as the row its picture is, over `over`, posed by `map`,
/// through matrix 0, at 45000 in screen.
fn closed_as_a_row(over: Over, map: ResampleMap) -> Step {
    Step::CloseRow {
        over,
        map,
        matrix: Some(0),
        opacity: 45000,
        mode: SCREEN,
    }
}

/// A row's own tiles: a column of two from the origin. Its picture is
/// wider — a tile past it each way, but right of it two — so what lies
/// outside them is there to be left out, on every side a turn reads past.
const OWN: TileRect = TileRect {
    x0: 0,
    y0: 0,
    columns: 1,
    rows: 2,
};

/// The base, a row's picture over more than [`OWN`] and a float over it.
fn held_over_a_row() -> Laying {
    Laying::new(&[((0, 0), (2, 2)), ((-1, -1), (4, 4)), ((0, 0), (1, 1))])
}

/// The row's picture and what a hand holds over it, in the row's space.
fn held() -> [Step; 2] {
    [row(1, (0, 0), WHOLE, NORMAL), row(2, (37, 21), 50000, MULTIPLY)]
}

// A row with what a hand holds over it is one picture in its own space —
// its rows drawn alone over its tiles there and nothing past them —, laid
// as the row is: posed once, through its matrix, at its opacity in its
// mode. Every way R1 poses, a homography's over all its tiles.
#[test]
fn a_buffer_closed_as_a_row_lays_its_picture_as_the_row() {
    let mut laying = held_over_a_row();
    let base = row(0, (0, 0), WHOLE, NORMAL);
    for name in ["turn", "shrink-pick", "tilt"] {
        let closing = closed_as_a_row(Over::Tiles(OWN), pose(name));
        let got = laying.widest(&[], &[&[base, Step::Open][..], &held(), &[closing]].concat(), None);
        assert!(got != laying.widest(&[], &[base], None), "{name}: it lays");
        let picture = laying.alone(&held(), OWN);
        let put = laying.laid(picture, OWN);
        let laid = matrixed(with_map(put, pose(name), 45000, SCREEN), 0);
        assert!(got == laying.widest(&[], &[base, laid], None), "{name}");
    }
}

// Its chain runs on that picture, over the chain's rectangle, as a row's
// runs on its own, before the pose.
#[test]
fn a_buffer_closed_as_a_row_runs_its_chain_on_its_picture() {
    let mut laying = held_over_a_row();
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let chains = [Chained {
        ops: blurred(),
        rect: RECT,
    }];
    let buffer = |over| [&[base, Step::Open][..], &held(), &[closed_as_a_row(over, pose("turn"))]].concat();
    let got = laying.widest(&chains, &buffer(Over::Chain(0)), None);
    assert!(got != laying.widest(&chains, &buffer(Over::Tiles(RECT)), None), "the chain ran");
    let put = laying.buffer_by_hand(&held(), RECT, &blurred());
    let laid = matrixed(with_map(put, pose("turn"), 45000, SCREEN), 0);
    assert!(got == laying.widest(&[], &[base, laid], None));
}

// Of its tiles, only those its output reads through its pose are drawn: a
// row of more than a page holds shows as the few of them read do, over an
// output of no tiles none, and one moved away from the output lays nothing.
#[test]
fn a_buffer_closed_as_a_row_draws_the_tiles_its_output_reads() {
    let laying = held_over_a_row();
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let buffer = |rect, map| [&[base, Step::Open][..], &held(), &[closed_as_a_row(Over::Tiles(rect), map)]].concat();
    let wide = TileRect {
        x0: -(1 << 16),
        y0: -1,
        columns: 1 << 17,
        rows: 4,
    };
    let picture = TileRect {
        x0: -1,
        y0: -1,
        columns: 4,
        rows: 4,
    };
    let got = laying.widest(&[], &buffer(wide, pose("turn")), None);
    assert!(got == laying.widest(&[], &buffer(picture, pose("turn")), None));
    let budget = rig().composite.widest();
    assert!(laying.over(&[], (&[], &buffer(wide, pose("turn"))), None, budget).is_some());
    // Away one way at a time: moved both ways, the rows it no longer reads
    // would hide columns that ran past those it does.
    for away in [ResampleMap::moved(-10_000, 0), ResampleMap::moved(0, -10_000)] {
        let away = laying.widest(&[], &buffer(picture, away), None);
        assert!(away == laying.widest(&[], &[base], None));
    }
}

// A buffer closed as a row names a matrix and a chain the plan has, and
// closes one that is open; one opened on the one under it, which holds
// what its steps alone do not lay, is refused.
#[test]
fn a_buffer_closed_as_a_row_is_checked_as_a_close() {
    let a_row = row(0, (0, 0), WHOLE, NORMAL);
    let closing = |over| closed_as_a_row(over, pose("turn"));
    let buffer = |over| [Step::Open, a_row, closing(over)];
    assert!(check_depth(&buffer(Over::Tiles(OWN)), 1, 0, 1, 0).is_some());
    assert!(check_depth(&buffer(Over::Tiles(OWN)), 1, 0, 0, 0).is_none());
    assert!(check_depth(&buffer(Over::Chain(1)), 1, 0, 1, 2).is_some());
    assert!(check_depth(&buffer(Over::Chain(1)), 1, 0, 1, 1).is_none());
    assert!(check_depth(&[a_row, closing(Over::Tiles(OWN))], 1, 0, 1, 0).is_none());
    let laying = held_over_a_row();
    let opened = |open| [open, a_row, closing(Over::Tiles(OWN))];
    let budget = rig().composite.widest();
    assert!(laying.composited(&[], &opened(Step::Open), None, budget).is_some());
    assert!(laying.composited(&[], &opened(Step::OpenOpaque), None, budget).is_none());
}
