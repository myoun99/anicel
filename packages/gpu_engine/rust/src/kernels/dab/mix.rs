//! A mixing brush's colours on the GPU (밑바탕 혼색 — the law beside
//! `BrushGroundColorMixer`; board
//! `the-mixing-brush-reads-a-whole-tile-back-for-its-ground`, 11-17):
//! `mix.wgsl` reads the ground under each step's dab and moves the
//! reservoir, in the stroke's order, and puts what each step lays in the
//! pile's records before the pile reads them.
//!
//! ↩️Till 11-17 the app read the ground itself, an 8×8 grid of the cel's
//! pixels a dab: a tile the engine had made was read back whole the first
//! time a dab met it — a wait for all the GPU had been handed, the stroke's
//! own dabs among it, mid-stroke —, and kept on the CPU besides. The ground
//! is the GPU's, so reading it is the GPU's (🗣️유저: 「cpu로하는거 최대한
//! 전부 gpu로 · 진짜 cpu가 빠를수밖에 없는거만 cpu로」).
//!
//! The ground is the cel as the stroke began: a step's points are found
//! here, as the app found them; the cel's tiles they are on are copied as
//! the executor copies a row whole (`Composite::copied` — the blur brush
//! reads the cel so); the pile's records are coloured by the step each
//! names. A stroke's book — the reservoir and the colour each step laid —
//! is kept on the GPU from pile to pile and read once, at pen-up
//! ([`Book::read`]), where the app bakes the colours into the dabs it keeps.

#[cfg(test)]
#[path = "mix_tests.rs"]
mod tests;

use std::collections::HashMap;

use super::TILE;
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{Composite, TILE_TEXELS, TileAt, TileSet};
use crate::kernels::shared::{Encoded, encode, le_words, pipeline, whole, words_buffer};

/// A step's points: a grid of GRID × GRID across its dab's circle, a lane
/// each (mix.wgsl's 64).
const GRID: usize = 8;
const LANES: usize = GRID * GRID;
/// mix.wgsl's MIX_NONE: a point out of its circle, or on no tile of the cel.
const NONE: u32 = u32::MAX;
/// mix.wgsl's head, step and book words.
const HEAD_WORDS: usize = 4;
const STEP_WORDS: usize = 10 + LANES;
const BOOK_LOG: usize = 8;

/// A dab of a mixing brush as the app resolved it (`BrushDabMix`): where it
/// reads the ground — `centre`, `radius` —, its drawing colour and what its
/// curves and dice made of the brush's paint.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Step {
    pub(crate) centre: [f64; 2],
    pub(crate) radius: f64,
    /// Red, green, blue, alpha, from the low byte.
    pub(crate) colour: [u8; 4],
    /// A loaded brush's refill toward the drawing colour, the share of it
    /// laid over what it carries, and its thickness.
    pub(crate) refill: f64,
    pub(crate) laid: f64,
    pub(crate) density: f64,
    /// A dry brush's pickup.
    pub(crate) take: f64,
    /// The share of a whole stamp it is, and what a whole one lifts.
    pub(crate) share: f64,
    pub(crate) pick: f64,
    /// A brush with no paint of its own (`paintAmount` 0).
    pub(crate) dry: bool,
}

/// What a step's points are: the canvas pixel each in its circle is on —
/// `None` for one out of it, in lane order —, as `sampleBitmapSurfaceGround`
/// found them on the CPU.
fn points_of(step: &Step) -> [Option<(i32, i32)>; LANES] {
    let mut points = [None; LANES];
    let radius = step.radius;
    if radius <= 0.0 || !radius.is_finite() {
        return points;
    }
    let [x, y] = step.centre;
    let spacing = radius * 2.0 / GRID as f64;
    for (lane, point) in points.iter_mut().enumerate() {
        let (row, column) = ((lane / GRID) as f64, (lane % GRID) as f64);
        let across = x - radius + spacing * (column + 0.5);
        let down = y - radius + spacing * (row + 0.5);
        let (dx, dy) = (across - x, down - y);
        if dx * dx + dy * dy <= radius * radius {
            *point = Some((across.floor() as i32, down.floor() as i32));
        }
    }
    points
}

/// The tile `pixel` is on.
fn tile_of((x, y): (i32, i32)) -> (i32, i32) {
    (x.div_euclid(TILE), y.div_euclid(TILE))
}

/// The tiles of the canvas `steps`' points are on, each once, in the order
/// met: the ones the app finds the cel's for.
pub(crate) fn ground_of(steps: &[Step]) -> Vec<(i32, i32)> {
    let mut met = Vec::new();
    for step in steps {
        for tile in points_of(step).into_iter().flatten().map(tile_of) {
            if !met.contains(&tile) {
                met.push(tile);
            }
        }
    }
    met
}

/// The kernel.
pub(crate) struct Mixes {
    pipeline: wgpu::ComputePipeline,
}

/// A stroke's mixing: the steps handed and not yet run, the ground tiles
/// they read, and the book.
#[derive(Default)]
pub(crate) struct Mixing {
    steps: Vec<Step>,
    ground: Vec<(i32, i32)>,
    book: Book,
}

impl Mixing {
    /// Hands `steps`, `first` the first's place in the stroke's chain — the
    /// next after those already run —, to be run with the next pile; gives
    /// the ground tiles they read ([`ground_of`]).
    pub(crate) fn hand(&mut self, steps: &[Step], first: u32) -> Option<&[(i32, i32)]> {
        if first != self.book.steps {
            return fail(format!(
                "mixing steps from {first}, where the stroke has run {}",
                self.book.steps
            ));
        }
        self.steps = steps.to_vec();
        self.ground = ground_of(steps);
        Some(&self.ground)
    }

    /// Whether steps are waiting to run.
    pub(crate) fn waits(&self) -> bool {
        !self.steps.is_empty()
    }

    /// Lets the stroke's book go to its start, for the next stroke; the
    /// buffer stays.
    pub(crate) fn clear(&mut self, encoder: &mut wgpu::CommandEncoder) {
        self.steps.clear();
        self.ground.clear();
        self.book.clear(encoder);
    }

    /// The colour each of the stroke's first `count` steps laid, ARGB.
    pub(crate) fn read(&self, engine: &Engine, count: usize) -> Option<Vec<u32>> {
        self.book.read(engine, count)
    }
}

/// The reservoir as the last step left it, and the colour each step laid,
/// on the GPU (mix.wgsl's book).
#[derive(Default)]
struct Book {
    buffer: Option<wgpu::Buffer>,
    /// The steps its log has room for.
    room: usize,
    /// How many steps have run.
    steps: u32,
}

impl Book {
    /// Room for `steps` in the log, the steps logged kept.
    fn grow(&mut self, engine: &Engine, steps: usize) -> &wgpu::Buffer {
        if self.buffer.is_none() || steps > self.room {
            let room = steps.max(2 * self.room).max(1024);
            let grown = engine.device().create_buffer(&wgpu::BufferDescriptor {
                label: Some("mixing book"),
                size: ((BOOK_LOG + room) * 4) as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            let mut encoder = engine.device().create_command_encoder(&Default::default());
            match &self.buffer {
                Some(old) => encoder.copy_buffer_to_buffer(old, 0, &grown, 0, old.size()),
                None => encoder.clear_buffer(&grown, 0, Some((BOOK_LOG * 4) as u64)),
            }
            engine.queue.submit([encoder.finish()]);
            self.buffer = Some(grown);
            self.room = room;
        }
        self.buffer.as_ref().expect("a book")
    }

    fn clear(&mut self, encoder: &mut wgpu::CommandEncoder) {
        if let Some(buffer) = &self.buffer {
            encoder.clear_buffer(buffer, 0, Some((BOOK_LOG * 4) as u64));
        }
        self.steps = 0;
    }

    fn read(&self, engine: &Engine, count: usize) -> Option<Vec<u32>> {
        if count > self.steps as usize {
            return fail(format!("{count} steps' colours, of {} run", self.steps));
        }
        let Some(buffer) = &self.buffer.as_ref().filter(|_| count > 0) else {
            return Some(Vec::new());
        };
        let words = BOOK_LOG + count;
        let staged = engine.staged(buffer, (words * 4) as u64);
        let mut bytes = vec![0; words * 4];
        engine.mapped_into(&staged, &mut bytes)?;
        Some(le_words(&bytes)[BOOK_LOG..].to_vec())
    }
}

/// A pile's mixing: the stroke's kernel and steps, the ground they read,
/// and which of the pile's dabs — by their index — take which step's
/// colour.
pub(crate) struct MixRun<'a> {
    pub(crate) mixes: &'a Mixes,
    pub(crate) mixing: &'a mut Mixing,
    pub(crate) ground: Ground<'a>,
    pub(crate) colours: &'a [(usize, u32)],
}

/// The ground a run reads: the cel's tiles, `under` the stroke's handed
/// ground tile at each, on the pool's `pages`, copied by `executor`.
pub(crate) struct Ground<'a> {
    pub(crate) executor: &'a Composite,
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) under: &'a [Option<TileAt>],
}

impl Mixes {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self { pipeline: pipeline(engine, &[include_str!("mix.wgsl")], "mix_steps") }
    }

    /// Runs `mixing`'s waiting steps over `ground` and colours the records
    /// of `plan` each names — the place of a record's colour and its step —
    /// for the pile to read: the pile's plan written, its passes not yet
    /// submitted. Submits the work, the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        mixing: &mut Mixing,
        ground: Ground,
        plan: Option<(&wgpu::Buffer, &[(u32, u32)])>,
    ) -> Option<()> {
        let steps = std::mem::take(&mut mixing.steps);
        let tiles = std::mem::take(&mut mixing.ground);
        if ground.under.len() != tiles.len() {
            return fail(format!(
                "mixing told of {} tiles under the {} its steps read",
                ground.under.len(),
                tiles.len()
            ));
        }
        // Handed from the steps run (`Mixing::hand`).
        let first = mixing.book.steps;
        let records = plan.map_or(&[][..], |(_, records)| records);
        let run = first + steps.len() as u32;
        if let Some(&(_, step)) = records.iter().find(|&&(_, step)| step >= run) {
            return fail(format!("a record of step {step}, of {run} run"));
        }
        if steps.is_empty() && records.is_empty() {
            return Some(());
        }
        let (copied, at) = ground_copied(engine, &ground, &tiles)?;
        let words = planned(&steps, first, &at, records);
        let book_steps = first as usize + steps.len();
        let book = mixing.book.grow(engine, book_steps);
        let mix_plan = words_buffer(engine, "mix plan", &words, wgpu::BufferUsages::STORAGE);
        // The pile's plan where it has one; one word else, which nothing
        // reads: no record names a step.
        let none;
        let dab_plan = match plan {
            Some((dab_plan, _)) => dab_plan,
            None => {
                none = words_buffer(engine, "no dab plan", &[0], wgpu::BufferUsages::STORAGE);
                &none
            }
        };
        let bound = whole(&[(0, &mix_plan), (1, dab_plan), (2, &copied), (3, book)]);
        encode(engine, &[Encoded { pipeline: &self.pipeline, bound, groups: (1, 1, 1) }]);
        mixing.book.steps = book_steps as u32;
        Some(())
    }
}

/// The cel's tiles at `tiles`, those it has under them, copied: the
/// buffer, and each tile's index in it by its column and row. One word,
/// which nothing reads, where it has none.
fn ground_copied(
    engine: &Engine,
    ground: &Ground,
    tiles: &[(i32, i32)],
) -> Option<(wgpu::Buffer, HashMap<(i32, i32), u32>)> {
    let held: Vec<((i32, i32), TileAt)> = tiles
        .iter()
        .zip(ground.under)
        .filter_map(|(&tile, under)| under.map(|under| (tile, under)))
        .collect();
    if held.is_empty() {
        let none = words_buffer(engine, "no ground", &[0], wgpu::BufferUsages::STORAGE);
        return Some((none, HashMap::new()));
    }
    let x0 = held.iter().map(|((column, _), _)| *column).min()?;
    let y0 = held.iter().map(|((_, row), _)| *row).min()?;
    let columns = (held.iter().map(|((column, _), _)| *column).max()? - x0 + 1) as u32;
    let rows = (held.iter().map(|((_, row), _)| *row).max()? - y0 + 1) as u32;
    let mut set = TileSet { x0, y0, columns, rows, tiles: vec![None; (columns * rows) as usize] };
    for &((column, row), under) in &held {
        set.tiles[((row - y0) as u32 * columns + (column - x0) as u32) as usize] = Some(under);
    }
    let at: Vec<(i32, i32)> = held.iter().map(|&(tile, _)| tile).collect();
    let executor = ground.executor;
    let copied = executor.copied(engine, ground.pages, &set, &at, executor.widest())?;
    let index = at.iter().enumerate().map(|(index, &tile)| (tile, index as u32)).collect();
    Some((copied.out, index))
}

/// mix.wgsl's plan of `steps`, the first of them `first` in the stroke's
/// chain, their points on the ground tiles `at`, and the `records` they
/// colour.
fn planned(
    steps: &[Step],
    first: u32,
    at: &HashMap<(i32, i32), u32>,
    records: &[(u32, u32)],
) -> Vec<u32> {
    let records_at = HEAD_WORDS + steps.len() * STEP_WORDS;
    let mut words = vec![steps.len() as u32, first, records_at as u32, records.len() as u32];
    for step in steps {
        let [red, green, blue, alpha] = step.colour.map(u32::from);
        let points = points_of(step);
        let float = |value: f64| (value as f32).to_bits();
        words.extend([
            red | green << 8 | blue << 16,
            alpha,
            float(step.refill),
            float(step.laid),
            float(step.density),
            float(step.take),
            float(step.share),
            float(step.pick),
            u32::from(step.dry),
            points.iter().flatten().count() as u32,
        ]);
        words.extend(points.iter().map(|point| {
            point
                .and_then(|pixel| {
                    let index = at.get(&tile_of(pixel))?;
                    let (column, row) = tile_of(pixel);
                    let (x, y) = (pixel.0 - column * TILE, pixel.1 - row * TILE);
                    Some(*index * TILE_TEXELS as u32 + (y * TILE + x) as u32)
                })
                .unwrap_or(NONE)
        }));
    }
    for &(place, step) in records {
        words.extend([place, step]);
    }
    words
}

