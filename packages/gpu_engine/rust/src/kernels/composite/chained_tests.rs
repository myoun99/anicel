//! Effect chains a plan names, on a real GPU: a chained row or buffer lays
//! what its chain puts as a row, each checked against the chain run by
//! hand and laid so. What a chain puts is checked against its kernels' own
//! hands in kernels/chain.

use std::sync::OnceLock;

use super::tests::{Pool, contrast, keyed, masked_row, matrixed, pose, rig, row, texel, with_map};
use super::{BufferChain, Budget, NO_EDGE, Plan, Step, TileSet, WHOLE, check_depth};
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, PLUS, SCREEN};
use crate::kernels::chain::{Chain, Chained, Op, laid_as, tiles_of};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::Edge;
use crate::kernels::effects::{MATRIX_WORDS, matrix_words};
use crate::kernels::mask::Mask;
use crate::kernels::mask::tests::masked;
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

/// A blur, then a colour matrix between it and the final paint.
fn blurred() -> Vec<Op<'static>> {
    let blur = Op::Gaussian {
        radius: (3, 2),
        edge: Edge::Nothing,
    };
    vec![blur, Op::Matrix(*matrix())]
}

/// A blur along the rows alone.
fn across() -> Vec<Op<'static>> {
    let radius = (5, 0);
    vec![Op::Gaussian { radius, edge: Edge::Nothing }]
}

/// A blur down the columns alone.
fn down() -> Vec<Op<'static>> {
    let radius = (0, 4);
    vec![Op::Gaussian { radius, edge: Edge::Nothing }]
}

/// `step` through effect chain `at` — a close's whole.
fn chained(step: Step, at: usize) -> Step {
    mixed(step, at, WHOLE)
}

/// `step` through effect chain `at`, a close's at `mix`.
fn mixed(mut step: Step, at: usize, mix: u32) -> Step {
    match &mut step {
        Step::Row { chain, .. } => *chain = Some(at),
        Step::Close { chain, .. } => *chain = Some(BufferChain { chain: at, mix }),
        _ => unreachable!("only a row or a close runs a chain"),
    }
    step
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

    /// `steps` through `chains` over [`TILES`] within `budget`, under `mask`
    /// if any: the output's bytes, or `None` where the plan was refused.
    fn composited(
        &self,
        chains: &[Chained],
        steps: &[Step],
        mask: Option<&Mask>,
        budget: Budget,
    ) -> Option<Vec<u8>> {
        let rig = rig();
        let plan = self.plan(chains, steps, mask);
        let done = rig.composite.run(rig.engine, &plan, &TILES, NO_EDGE, budget)?;
        Some(read_buffer(rig.engine, &done.out))
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
