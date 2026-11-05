//! The row composite — 2단계's executor, round E1 (gpu-canonical-store):
//! a plan of rows, folders and clipping groups, composited on the GPU into
//! output tiles in the blend family's one integer formula. Every route that
//! composites rows — the editing screen, a frame's picture, a panel, an
//! export — is to run this one executor, so what is shown while working and
//! what comes out cannot differ.
//!
//! The plan is the composite tree flattened into steps, bottom to top
//! ([`Step`]); the tree itself stays the app's (composite_tree.dart). E1
//! takes the five node kinds that close per pixel: a row in any pose R1
//! takes (a whole-pixel move being its copy), a folder's buffer, a row over
//! its backdrop (its own mode), a clipping group and its base made opaque.
//! A row's colour keys run on its stored pixels, before R1 poses them.
//! The other effects, adjustments and a cel number's letters (drawn by the
//! engine's glyph path, then a row here) come in later rounds.
//!
//! The pages a pass can bind are few — `max_storage_buffers_per_shader_stage`
//! less the plan and the work buffer, 2 where GLES reports 4 — so a plan is
//! cut into passes, each binding the pages of its run of rows. A copied row
//! whose tiles lie on several pages becomes one step per page: a pixel
//! reads one tile of it, so exactly one of them lays it. Any other pose
//! reads around where a pixel lands, so its row is one step binding every
//! page it reaches; one reaching more than a pass binds waits for the
//! round that lays a row first. A pass holds a window of the stack in its
//! registers, [`DEPTH`] levels at most, so a tree nested deeper is cut
//! where it leaves the window. Between passes the stack is kept on the
//! 16-bit scale as it was, so the cuts change no value.

// ⏳Nothing outside the tests calls it until the app's bridge round
// (gpu-canonical-store 14:49 — the app connects after the bridges land).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::effects::KEY_WGSL;
use crate::kernels::shared::{ISQRT_WGSL, RESAMPLE_WGSL, ResampleMap, TILE_WGSL, WIDE_WGSL};

/// A tile's side in pixels (1a ①).
pub(crate) const TILE: u32 = 128;
/// A tile's pixels — and its words, one RGBA8 pixel to a word.
pub(crate) const TILE_TEXELS: u64 = (TILE * TILE) as u64;
/// The most stack levels a pass holds in its registers — composite.wgsl's
/// DEPTH. Folders and clips nest deeper by cutting passes where the walk
/// leaves the levels a pass holds; the rest wait in the work buffer.
pub(crate) const DEPTH: usize = 8;
/// The most pages one pass binds, whatever the device allows: each is a
/// case of composite.wgsl's `page_word`.
const MOST_PAGES: usize = 16;
const STEP_WORDS: usize = 12;
const NO_TILE: u32 = u32::MAX;
/// A page a pass binds none of, in its table of pages.
const NO_PAGE: u32 = u32::MAX;
/// The plan and the work buffer: the storage buffers a pass binds besides
/// its pages.
const OWN_BUFFERS: u32 = 2;

/// Where a stored tile is: a page of the pool, a slot in it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct TileAt {
    pub(crate) page: u16,
    pub(crate) slot: u16,
}

/// A row's picture on the canvas's tile grid: the tiles of the rectangle
/// whose top-left tile is column `x0`, row `y0`, row by row. `None` is a
/// tile with nothing on it.
pub(crate) struct TileSet {
    pub(crate) x0: i32,
    pub(crate) y0: i32,
    pub(crate) columns: u32,
    pub(crate) rows: u32,
    pub(crate) tiles: Vec<Option<TileAt>>,
}

impl TileSet {
    fn at(&self, column: i32, row: i32) -> Option<TileAt> {
        let (c, r) = (column - self.x0, row - self.y0);
        if c < 0 || r < 0 || c as u32 >= self.columns || r as u32 >= self.rows {
            return None;
        }
        self.tiles[(r as u32 * self.columns + c as u32) as usize]
    }

    /// The tiles of the set under the pixels `[left, top, right, bottom)`,
    /// or all of them for `None`.
    fn under(&self, pixels: Option<[i64; 4]>) -> impl Iterator<Item = TileAt> + '_ {
        let side = i64::from(TILE);
        // In tiles, ends excluded.
        let first = (i64::from(self.x0), i64::from(self.y0));
        let end = (first.0 + i64::from(self.columns), first.1 + i64::from(self.rows));
        let [left, top, right, bottom] = match pixels {
            None => [first.0, first.1, end.0, end.1],
            Some([l, t, r, b]) => [
                l.div_euclid(side).max(first.0),
                t.div_euclid(side).max(first.1),
                (r.saturating_sub(1).div_euclid(side) + 1).min(end.0),
                (b.saturating_sub(1).div_euclid(side) + 1).min(end.1),
            ],
        };
        (top..bottom)
            .flat_map(move |row| (left..right).map(move |column| (column, row)))
            .filter_map(|(column, row)| self.at(column as i32, row as i32))
    }
}

/// A row's colour keys: its runs, `KeyRun::words` each, in the chain's
/// order. They are walked on the row's stored pixels before R1 poses them,
/// as the app keys a cel before it is placed (캔버스 베이스,
/// gpu-canonical-store 11-05 18:24), every run against the pixel's stored
/// alpha.
pub(crate) struct KeyChain {
    pub(crate) runs: Vec<Vec<u32>>,
}

/// One step of a plan, bottom to top. An opacity is on the 16-bit scale
/// (65535 is whole); a mode is blend.wgsl's id.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Step {
    /// Tile set `set`, keyed by chain `keys` if any, posed by `map` —
    /// canvas pixel to the row's own — laid at `opacity` in `mode`.
    Row {
        set: usize,
        keys: Option<usize>,
        map: ResampleMap,
        opacity: u32,
        mode: u32,
    },
    /// Opens a transparent buffer: a folder's, a clip's base or its scope.
    Open,
    /// Opens a buffer holding the one under it with its alpha made whole —
    /// a clip's scope whose rows blend with the base (CompositeOpaque).
    OpenOpaque,
    /// Closes a buffer onto the one under it at `opacity` in `mode`.
    Close { opacity: u32, mode: u32 },
    /// Closes a clip's scope onto its base by the base's alpha (srcATop).
    CloseAtop,
}

/// What one pass may take: pages to bind, output tiles — as many as the
/// work buffer, stack and all, fits in one binding — and stack levels to
/// hold, 2 (a buffer and the one it closes onto) to [`DEPTH`].
#[derive(Clone, Copy, Debug)]
pub(crate) struct Budget {
    pub(crate) pages: usize,
    pub(crate) tiles: usize,
    pub(crate) levels: usize,
}

/// What a run left: every output tile's pixels, straight RGBA8, tile after
/// tile in the order asked, and how many passes it took.
pub(crate) struct Composited {
    pub(crate) out: wgpu::Buffer,
    pub(crate) passes: usize,
}

/// A step as the GPU reads it, and the pages it lays a row from — one for a
/// copied row's step, every one it reaches for any other pose.
struct Laid {
    step: Step,
    pages: Vec<u16>,
}

/// A run of steps one pass takes: the pages it binds, in binding order,
/// the lowest stack level it holds, and the depth it starts at.
struct Batch {
    begin: usize,
    end: usize,
    base: usize,
    depth_in: usize,
    depth_out: usize,
    pages: Vec<u16>,
}

/// The composite pass, compiled once for as many pages as the device lets
/// a pass bind.
pub(crate) struct Composite {
    pipeline: wgpu::ComputePipeline,
    pages_per_pass: usize,
    /// Bound where a pass has fewer pages than the pipeline has bindings.
    blank: wgpu::Buffer,
}

impl Composite {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let limit = engine.device.limits().max_storage_buffers_per_shader_stage;
        if limit <= OWN_BUFFERS {
            return fail(format!("{limit} storage buffers a stage leave no page to bind"));
        }
        let pages_per_pass = ((limit - OWN_BUFFERS) as usize).min(MOST_PAGES);
        let bindings: String = (0..pages_per_pass)
            .map(|k| {
                format!(
                    "@group(0) @binding({}) var<storage, read> page{k}: array<u32>;\n",
                    k + OWN_BUFFERS as usize + 1
                )
            })
            .collect();
        let reads: String = (0..pages_per_pass)
            .map(|k| format!("case {k}u: {{\n      return page{k}[index];\n    }}\n    "))
            .collect();
        let body = include_str!("composite.wgsl")
            .replace("//__PAGES__", &bindings)
            .replace("//__READS__", &reads);
        let source = [
            ISQRT_WGSL,
            BLEND_WGSL,
            WIDE_WGSL,
            RESAMPLE_WGSL,
            TILE_WGSL,
            KEY_WGSL,
            &body,
        ]
        .join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("composite"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("composite"),
                layout: None,
                module: &module,
                entry_point: Some("composite"),
                compilation_options: Default::default(),
                cache: None,
            });
        let blank = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite blank page"),
            size: 16,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        Some(Self {
            pipeline,
            pages_per_pass,
            blank,
        })
    }

    /// All this device lets a pass take.
    pub(crate) fn widest(&self) -> Budget {
        Budget {
            pages: self.pages_per_pass,
            tiles: usize::MAX,
            levels: DEPTH,
        }
    }

    /// Composites `steps` over the output `tiles` (canvas tile columns and
    /// rows) and submits the work; the caller waits. `pages` is the pool,
    /// `sets` the rows' tile sets, `keys` their key chains. A `budget` under
    /// [`Composite::widest`] cuts the run where a smaller device would.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        pages: &[wgpu::Buffer],
        sets: &[TileSet],
        keys: &[KeyChain],
        steps: &[Step],
        tiles: &[(i32, i32)],
        budget: Budget,
    ) -> Option<Composited> {
        let pages_per_pass = budget.pages;
        if pages_per_pass == 0 || pages_per_pass > self.pages_per_pass {
            return fail(format!(
                "{pages_per_pass} pages a pass; this device binds 1 to {}",
                self.pages_per_pass
            ));
        }
        if !(2..=DEPTH).contains(&budget.levels) {
            return fail(format!("{} stack levels a pass; one holds 2 to {DEPTH}", budget.levels));
        }
        check_depth(steps, sets.len(), keys.len())?;
        let laid = lay(steps, sets, tiles, pages.len())?;
        let batches = cut(&laid, pages_per_pass, budget.levels)?;
        let encoded = encode(&laid, &batches, sets, keys, tiles, pages.len());
        let plan = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("composite plan"),
                contents: &encoded.words,
                usage: wgpu::BufferUsages::STORAGE,
            });
        // The stack is kept between passes only; one pass keeps none.
        let kept = batches[..batches.len() - 1]
            .iter()
            .map(|batch| batch.depth_out as u64 + 1)
            .max()
            .unwrap_or(0);
        let per_tile = (kept * 2 + 1) * TILE_TEXELS * 4;
        let limits = engine.device.limits();
        let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
        let chunk = (room / per_tile)
            .min(u64::from(limits.max_compute_workgroups_per_dimension))
            .min(budget.tiles as u64)
            .min(tiles.len().max(1) as u64) as usize;
        if chunk == 0 {
            return fail(format!("one tile's work ({per_tile} bytes) exceeds a binding"));
        }
        let work = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite work"),
            size: chunk as u64 * per_tile,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite out"),
            size: (tiles.len().max(1) as u64) * TILE_TEXELS * 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let layout = self.pipeline.get_bind_group_layout(0);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let mut passes = 0;
        for (first_tile, chunk_tiles) in (0..tiles.len())
            .step_by(chunk)
            .map(|first| (first, (tiles.len() - first).min(chunk)))
        {
            let out_at = kept * 2 * TILE_TEXELS * chunk_tiles as u64;
            for (index, batch) in batches.iter().enumerate() {
                let words = [
                    (batch.begin) as u32,
                    batch.end as u32,
                    batch.depth_in as u32,
                    u32::from(index == 0),
                    u32::from(index == batches.len() - 1),
                    encoded.tiles_at + 2 * first_tile as u32,
                    chunk_tiles as u32,
                    out_at as u32,
                    encoded.tables_at + (index * pages.len()) as u32,
                    batch.base as u32,
                ];
                let uniform = engine
                    .device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: Some("composite pass"),
                        contents: &le_bytes(&words),
                        usage: wgpu::BufferUsages::UNIFORM,
                    });
                let mut entries = vec![
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: uniform.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: plan.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: work.as_entire_binding(),
                    },
                ];
                for k in 0..self.pages_per_pass {
                    let page = match batch.pages.get(k) {
                        Some(&page) => &pages[usize::from(page)],
                        None => &self.blank,
                    };
                    entries.push(wgpu::BindGroupEntry {
                        binding: k as u32 + OWN_BUFFERS + 1,
                        resource: page.as_entire_binding(),
                    });
                }
                let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("composite"),
                    layout: &layout,
                    entries: &entries,
                });
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
                pass.set_pipeline(&self.pipeline);
                pass.set_bind_group(0, &bind_group, &[]);
                pass.dispatch_workgroups(TILE / 16, TILE / 16, chunk_tiles as u32);
                passes += 1;
            }
            encoder.copy_buffer_to_buffer(
                &work,
                out_at * 4,
                &out,
                first_tile as u64 * TILE_TEXELS * 4,
                chunk_tiles as u64 * TILE_TEXELS * 4,
            );
        }
        engine.queue.submit([encoder.finish()]);
        Some(Composited { out, passes })
    }
}

fn le_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

/// Fails unless every buffer the steps open is closed, none is closed that
/// was not opened, and every row names a tile set and a key chain there
/// are.
fn check_depth(steps: &[Step], sets: usize, chains: usize) -> Option<()> {
    let mut depth = 0usize;
    for (index, step) in steps.iter().enumerate() {
        match *step {
            Step::Row { set, .. } if set >= sets => {
                return fail(format!("step {index} lays tile set {set} of {sets}"));
            }
            Step::Row {
                keys: Some(chain), ..
            } if chain >= chains => {
                return fail(format!("step {index} keys by chain {chain} of {chains}"));
            }
            Step::Row { .. } => {}
            Step::Open | Step::OpenOpaque => depth += 1,
            Step::Close { .. } | Step::CloseAtop if depth == 0 => {
                return fail(format!("step {index} closes a buffer that is not open"));
            }
            Step::Close { .. } | Step::CloseAtop => depth -= 1,
        }
    }
    if depth != 0 {
        return fail(format!("{depth} buffers are left open"));
    }
    Some(())
}

/// `steps` as the GPU takes them: a row with the pages of the tiles its
/// pose reads for the output tiles — a copied row once for each page, any
/// other pose once for them all — and not at all where it reads none.
fn lay(
    steps: &[Step],
    sets: &[TileSet],
    tiles: &[(i32, i32)],
    page_count: usize,
) -> Option<Vec<Laid>> {
    let side = i64::from(TILE);
    let mut laid = Vec::new();
    for step in steps {
        let Step::Row { set, map, .. } = *step else {
            laid.push(Laid {
                step: *step,
                pages: Vec::new(),
            });
            continue;
        };
        let mut pages: Vec<u16> = Vec::new();
        for &(column, row) in tiles {
            let (x0, y0) = (i64::from(column) * side, i64::from(row) * side);
            for at in sets[set].under(map.reads(x0, y0, x0 + side, y0 + side)) {
                if usize::from(at.page) >= page_count {
                    return fail(format!("tile set {set} names page {}", at.page));
                }
                if !pages.contains(&at.page) {
                    pages.push(at.page);
                }
            }
        }
        pages.sort_unstable();
        if map.is_copy() {
            laid.extend(pages.into_iter().map(|page| Laid {
                step: *step,
                pages: vec![page],
            }));
        } else if !pages.is_empty() {
            laid.push(Laid { step: *step, pages });
        }
    }
    Some(laid)
}

/// `laid` cut into passes, in order. A pass ends where the next step would
/// bind more than `pages_per_pass` pages, or reach outside the `levels`
/// stack levels it holds — opening past the top, or closing onto a level
/// under its base. The next pass then holds the levels around the depth
/// there. None where one step reads more pages than a pass binds.
fn cut(laid: &[Laid], pages_per_pass: usize, levels: usize) -> Option<Vec<Batch>> {
    let mut batches = Vec::new();
    let mut batch = Batch {
        begin: 0,
        end: 0,
        base: 0,
        depth_in: 0,
        depth_out: 0,
        pages: Vec::new(),
    };
    let mut depth = 0usize;
    for (index, each) in laid.iter().enumerate() {
        if each.pages.len() > pages_per_pass {
            return fail(format!(
                "a row reads {} pages at once; a pass binds {pages_per_pass}",
                each.pages.len()
            ));
        }
        let fresh = each.pages.iter().filter(|page| !batch.pages.contains(page)).count();
        // The levels the step reads and writes, lowest and highest.
        let (low, high) = match each.step {
            Step::Open | Step::OpenOpaque => (depth, depth + 1),
            Step::Close { .. } | Step::CloseAtop => (depth - 1, depth),
            Step::Row { .. } => (depth, depth),
        };
        let outside = low < batch.base || high >= batch.base + levels;
        if batch.pages.len() + fresh > pages_per_pass || outside {
            // Half the levels under the depth, but never so low that `high`
            // is past the top. Half is at least one, so `low` is held too.
            let base = if outside {
                depth
                    .saturating_sub(levels / 2)
                    .max((high + 1).saturating_sub(levels))
            } else {
                batch.base
            };
            batch.end = index;
            batch.depth_out = depth;
            let next = Batch {
                begin: index,
                end: index,
                base,
                depth_in: depth,
                depth_out: depth,
                pages: Vec::new(),
            };
            batches.push(std::mem::replace(&mut batch, next));
        }
        for &page in &each.pages {
            if !batch.pages.contains(&page) {
                batch.pages.push(page);
            }
        }
        match each.step {
            Step::Open | Step::OpenOpaque => depth += 1,
            Step::Close { .. } | Step::CloseAtop => depth -= 1,
            Step::Row { .. } => {}
        }
    }
    batch.end = laid.len();
    batch.depth_out = depth;
    batches.push(batch);
    Some(batches)
}

/// The plan buffer's words, where its output tiles start, and where its
/// passes' tables of pages do, one after another.
struct Plan {
    words: Vec<u8>,
    tiles_at: u32,
    tables_at: u32,
}

/// The steps, then each tile set's map, the key chains — an empty list,
/// then each chain's list (how many runs, where each is) and its runs —
/// each row's R1 map, each pass's table of pages — for every page of the
/// pool the binding holding it, or NO_PAGE — and the output tiles.
fn encode(
    laid: &[Laid],
    batches: &[Batch],
    sets: &[TileSet],
    keys: &[KeyChain],
    tiles: &[(i32, i32)],
    page_count: usize,
) -> Plan {
    let mut words: Vec<u32> = Vec::with_capacity(laid.len() * STEP_WORDS);
    let maps_at = (laid.len() * STEP_WORDS) as u32;
    let mut map_at = Vec::with_capacity(sets.len());
    let mut maps: Vec<u32> = Vec::new();
    for set in sets {
        map_at.push(maps_at + maps.len() as u32);
        maps.extend(set.tiles.iter().map(|tile| match tile {
            Some(at) => (u32::from(at.page) << 16) | u32::from(at.slot),
            None => NO_TILE,
        }));
    }
    let chains_at = maps_at + maps.len() as u32;
    // The empty list also keeps the plan from being empty, as a storage
    // binding must hold something.
    let mut chains: Vec<u32> = vec![0];
    let mut chain_at = Vec::with_capacity(keys.len());
    for chain in keys {
        let list_at = chains_at + chains.len() as u32;
        chain_at.push(list_at);
        chains.push(chain.runs.len() as u32);
        let mut run_at = list_at + 1 + chain.runs.len() as u32;
        for run in &chain.runs {
            chains.push(run_at);
            run_at += run.len() as u32;
        }
        for run in &chain.runs {
            chains.extend(run);
        }
    }
    let poses_at = chains_at + chains.len() as u32;
    let mut poses: Vec<u32> = Vec::new();
    for each in laid {
        let step = match each.step {
            Step::Row {
                set,
                keys,
                map,
                opacity,
                mode,
            } => {
                let pose_at = poses_at + poses.len() as u32;
                poses.extend(map.words());
                let pages = || each.pages.iter().copied().map(u32::from);
                let tiles = &sets[set];
                [
                    0,
                    mode,
                    opacity,
                    pages().min().expect("a laid row has its pages"),
                    pages().max().expect("a laid row has its pages"),
                    map_at[set],
                    tiles.x0 as u32,
                    tiles.y0 as u32,
                    tiles.columns,
                    tiles.rows,
                    pose_at,
                    keys.map_or(chains_at, |chain| chain_at[chain]),
                ]
            }
            Step::Open => [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::OpenOpaque => [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::Close { opacity, mode } => [3, mode, opacity, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::CloseAtop => [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        };
        words.extend(step);
    }
    words.extend(maps);
    words.extend(chains);
    words.extend(poses);
    let tables_at = words.len() as u32;
    for batch in batches {
        words.extend((0..page_count).map(|page| {
            batch
                .pages
                .iter()
                .position(|&bound| usize::from(bound) == page)
                .map_or(NO_PAGE, |k| k as u32)
        }));
    }
    let tiles_at = words.len() as u32;
    words.extend(tiles.iter().flat_map(|&(column, row)| [column as u32, row as u32]));
    Plan {
        words: le_bytes(&words),
        tiles_at,
        tables_at,
    }
}
