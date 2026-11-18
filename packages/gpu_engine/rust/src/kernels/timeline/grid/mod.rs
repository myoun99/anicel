//! A frame grid's tile, drawn from the op stream the grids write
//! (timeline_grid_tile_ops.dart has the words) over an A8 atlas of the
//! letters, in `grid.wgsl` — the one place the stream is drawn, and so
//! what it says.
//!
//! ↩️The C rasterizer `qa_grid_raster_tile` drew it until
//! grid-on-the-engine ⑥. What the stream said was the C's, but for the
//! rounded rects: their field is taken here in q9 integers with
//! `isqrt_round`, not in doubles with the C library's square root, so an
//! edge pixel may differ from an old build's by a step — the same on every
//! device, which is the point.

pub(crate) mod abi;
pub(crate) mod lay;
#[cfg(test)]
mod tests;


use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::Work;
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, WIDE_WGSL, aligned, encode_on, fits, flat, pipeline, range,
    storage_format,
};
use crate::kernels::timeline::LAID_WGSL;

const FILL_RECT: i32 = 1;
const HLINE: i32 = 2;
const VLINE: i32 = 3;
const GLYPH: i32 = 4;
const RRECT_FILL: i32 = 5;
const RRECT_RING: i32 = 6;
const GRIP: i32 = 7;

/// The largest corner a rounded rect may wear, in q9 (64 pixels), once
/// held to what its box can hold.
///
/// ⚠️Mine (gpu-int-spec-timeline, 관제 15:42): the field's sum of squares
/// must stay in a u32, which this keeps it to (`grid.wgsl`'s cut). The
/// grids' corners are far inside it — a block's 6 logical pixels at the
/// largest ratio the app meets, 36 — and a stream past it is refused, not
/// drawn with a smaller corner: a corner cut quietly is a picture changed
/// with nobody told. The writer is to refuse to write one first
/// (`TimelineGridTileOpWriter.rrectFill` · `rrectRing`, at the bridge).
pub(crate) const MOST_RADIUS_Q9: i32 = 1 << 15;

/// The longest side a grip's box may have, in q9 (8192 pixels): half a
/// pixel times its far side's length must stay in an i32 — the bound past
/// which `grid.wgsl`'s `grip_coverage` reads a pixel as all in or all out
/// before it divides.
///
/// ⚠️Mine (F-604, 2026-11-17): a grip's box is half a block's paper across
/// — on the X-sheet half a column, a hundred device pixels and more at a
/// high ratio — and one past this is refused rather than drawn wrapped, as
/// a corner past [`MOST_RADIUS_Q9`] is (`TimelineGridTileOpWriter.grip`
/// refuses first).
pub(crate) const MOST_GRIP_SIDE_Q9: i32 = 1 << 22;

/// A frame grid's tile as the engine keeps it: what the pass draws, stored
/// straight (grid.wgsl says why), for the view's screen to lay
/// ([`lay::GridLay`]; grid-on-the-engine ⓑ, 관제 2026-11-08 16:42) — never
/// read back for the app to raise again (관제 11-05 14:02).
pub(crate) struct GridPicture {
    pub(crate) texture: wgpu::Texture,
}

impl GridPicture {
    /// What every tile's picture is made in: what the app's tile pass is
    /// compiled for before a tile is drawn ([`GridTile::for_pictures`]).
    pub(crate) const FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

    /// A clear picture `width` × `height` pixels — None, with the last
    /// error, for a side of none or past what the device makes.
    pub(crate) fn new(engine: &Engine, width: u32, height: u32) -> Option<Self> {
        let most = engine.device().limits().max_texture_dimension_2d;
        if width == 0 || height == 0 || width > most || height > most {
            return fail(format!("a grid tile {width} × {height}: a side is 1 to {most} pixels"));
        }
        let texture = engine.device().create_texture(&wgpu::TextureDescriptor {
            label: Some("grid tile"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: Self::FORMAT,
            // Drawn by the pass, laid by the screen, read for a fingerprint.
            usage: wgpu::TextureUsages::STORAGE_BINDING
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        Some(Self { texture })
    }
}

/// How far across and down the letters' atlas is ([`GridTile::put_letters`]):
/// one R8 square a grid pass holds for as long as it is, its words put on
/// it once each and read by every tile drawn after.
///
/// ⏳Mine (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q2,
/// 유저 2026-11-15 「(라)」 — the engine holds the atlas for the session,
/// not one a tile): never grown, so its 4 MiB is all it ever holds (관제
/// 06:1x: a kept byte that grows grows unseen). The app's ledger starts it
/// over when it fills, its batch drawn first. ↩️Each tile brought an atlas
/// of its own words, made and uploaded with it (`atlas_of`): 🔬with its
/// stream's buffer and its submit, 2.1 ms of a cold tile's 3.3 on the main
/// PC (measure-cold-tiles, 11-15).
pub(crate) const ATLAS_SIDE: u32 = 2048;

/// Letters a batch puts on the atlas before it draws: `bytes`, a coverage
/// a pixel row by row, over `at` — [x, y, width, height].
#[derive(Clone, Copy)]
pub(crate) struct Put<'a> {
    pub(crate) at: [u32; 4],
    pub(crate) bytes: &'a [u8],
}

/// A tile a batch draws: `ops` into `tile` over `background` (an RGBA
/// word).
pub(crate) struct Drawn<'a> {
    pub(crate) tile: &'a wgpu::Texture,
    pub(crate) background: u32,
    pub(crate) ops: &'a [i32],
}

/// A frame grid's tile pass, one pipeline per texture format: compiled
/// where the pass first runs on one, or ahead of it for a tile's picture
/// ([`GridTile::for_pictures`]).
pub(crate) struct GridTile {
    /// The longest side of a picture the device makes, read as the pass is
    /// made: what a batch asks its pictures within, where it asks them.
    most_side: u32,
    /// What the atlas binding holds where no letters were put yet.
    no_atlas: wgpu::Texture,
    atlas: Option<wgpu::Texture>,
    /// The plane a batch's words and streams lie on, a part a tile.
    work: Work,
    pipelines: Vec<(wgpu::TextureFormat, wgpu::ComputePipeline)>,
}

/// How far an op's places and lengths may reach either way: 2^28 — a
/// rect's pixels, a rounded rect's q8, a million pixels. Doubled to q9,
/// summed and pushed out by a ring's open side, they stay inside an i32.
///
/// ⚠️Mine, as [`MOST_RADIUS_Q9`] is: a tile is a few hundred pixels, and a
/// word past this is refused rather than drawn wrapped.
pub(crate) const MOST_REACH: i32 = 1 << 28;

/// An op's length in words and which of them are places and lengths —
/// None for no grid op.
fn shape_of(op: i32) -> Option<(usize, &'static [usize])> {
    match op {
        FILL_RECT | HLINE | VLINE => Some((6, &[1, 2, 3, 4])),
        GLYPH => Some((8, &[1, 2, 3, 4, 5, 6])),
        // x, y, w, h and the radius — and a ring's line.
        RRECT_FILL => Some((8, &[1, 2, 3, 4, 5])),
        RRECT_RING => Some((10, &[1, 2, 3, 4, 5, 7])),
        // x, y, w, h, the paper's corner and its bleed.
        GRIP => Some((9, &[1, 2, 3, 4, 5, 6])),
        _ => None,
    }
}

/// Why `ops` cannot be drawn, if it cannot: an op the stream does not
/// have, one cut short, a letter with no atlas, a place or length past
/// [`MOST_REACH`], or a corner below square or past [`MOST_RADIUS_Q9`].
///
/// ⚠️Mine: a stream the C rasterizer stopped part-way through is refused
/// whole here — a pass cannot stop at an op — so nothing of it is drawn.
fn fault_in(ops: &[i32], has_atlas: bool) -> Option<String> {
    let mut at = 0;
    while at < ops.len() {
        let op = ops[at];
        let Some((words, reaches)) = shape_of(op) else {
            return Some(format!("op {op} at word {at} is no grid op"));
        };
        if at + words > ops.len() {
            return Some(format!("op {op} at word {at} is cut short"));
        }
        if op == GLYPH && !has_atlas {
            return Some(format!("the letter at word {at} has no atlas"));
        }
        let far = MOST_REACH.unsigned_abs();
        if reaches.iter().any(|&word| ops[at + word].unsigned_abs() >= far) {
            return Some(format!("op {op} at word {at} reaches too far"));
        }
        if matches!(op, RRECT_FILL | RRECT_RING) {
            if ops[at + 5] < 0 {
                return Some(format!("the corner at word {at} is below square"));
            }
            let corner = (2 * ops[at + 5]).min(ops[at + 3]).min(ops[at + 4]);
            if corner > MOST_RADIUS_Q9 {
                return Some(format!("the corner at word {at} is past 64 pixels"));
            }
        }
        if op == GRIP {
            if let Some(fault) = grip_fault(&ops[at..at + words]) {
                return Some(format!("the grip at word {at} {fault}"));
            }
        }
        at += words;
    }
    None
}

/// Why a GRIP op's `words` cannot be drawn, if they cannot: a side past
/// [`MOST_GRIP_SIDE_Q9`], a corner below square or past [`MOST_RADIUS_Q9`],
/// a bleed below none, or a corner that is not one of the box's four.
fn grip_fault(words: &[i32]) -> Option<&'static str> {
    if 2 * words[3] >= MOST_GRIP_SIDE_Q9 || 2 * words[4] >= MOST_GRIP_SIDE_Q9 {
        return Some("is 8192 pixels or more across");
    }
    if words[5] < 0 {
        return Some("has a corner below square");
    }
    if 2 * words[5] > MOST_RADIUS_Q9 {
        return Some("has a corner past 64 pixels");
    }
    if words[6] < 0 {
        return Some("bleeds less than nothing");
    }
    if !matches!(words[7], 1 | 2 | 4 | 8) {
        return Some("names no one corner");
    }
    None
}

/// Why `put` cannot go on the atlas, if it cannot: a box past its sides,
/// or bytes that are not the box's.
fn put_fault(put: &Put) -> Option<String> {
    let [x, y, width, height] = put.at;
    let inside = |from: u32, side: u32| from.checked_add(side).is_some_and(|to| to <= ATLAS_SIDE);
    if !inside(x, width) || !inside(y, height) {
        return Some(format!("letters {width} × {height} at ({x}, {y}) are past the atlas's {ATLAS_SIDE}"));
    }
    if put.bytes.len() as u64 != u64::from(width) * u64::from(height) {
        return Some(format!("letters {width} × {height} of {} bytes", put.bytes.len()));
    }
    None
}

impl GridTile {
    pub(crate) fn new(engine: &Engine) -> Self {
        let no_atlas = engine.device().create_texture(&wgpu::TextureDescriptor {
            label: Some("grid no atlas"),
            size: wgpu::Extent3d {
                width: 1,
                height: 1,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Uint,
            usage: wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        Self {
            most_side: engine.device().limits().max_texture_dimension_2d,
            no_atlas,
            atlas: None,
            work: Work::default(),
            pipelines: Vec::new(),
        }
    }

    /// The pass with its pipeline for a tile's picture compiled where the
    /// caller is, so that the first tile drawn compiles nothing: the app
    /// makes it off the thread its frames are built on (🗣️관제 2026-11-10
    /// 18:14, gpu-canonical-store ⑦: 「UI 스레드가 직접 하는 커널 컴파일
    /// 0개」 — 🔬the row that first drew a tile waited 0.17 s for it at
    /// launch on the Surface Pro 11, and 1.9–2.2 s where S5 opened).
    pub(crate) fn for_pictures(engine: &Engine) -> Self {
        let mut tile = Self::new(engine);
        tile.pipeline(engine, GridPicture::FORMAT);
        tile
    }

    fn pipeline(
        &mut self,
        engine: &Engine,
        format: wgpu::TextureFormat,
    ) -> Option<wgpu::ComputePipeline> {
        if let Some((_, pipeline)) = self.pipelines.iter().find(|(made, _)| *made == format) {
            return Some(pipeline.clone());
        }
        let Some(token) = storage_format(format) else {
            return fail(format!("the grid pass cannot store to {format:?}"));
        };
        let body = include_str!("grid.wgsl").replace("__FORMAT__", token);
        let pipeline = pipeline(
            engine,
            &[ISQRT_WGSL, BLEND_WGSL, WIDE_WGSL, LAID_WGSL, &body],
            "grid",
        );
        self.pipelines.push((format, pipeline.clone()));
        Some(pipeline)
    }

    /// Puts each of `puts` on the atlas, made here the first time — on the
    /// queue, ahead of what is submitted next. None, with the last error,
    /// for one past the atlas or one whose bytes are not its box's: none is
    /// put then.
    pub(crate) fn put_letters(&mut self, engine: &Engine, puts: &[Put]) -> Option<()> {
        if let Some(fault) = puts.iter().find_map(put_fault) {
            return fail(fault);
        }
        if puts.is_empty() {
            return Some(());
        }
        let atlas = self.atlas.get_or_insert_with(|| {
            engine.device().create_texture(&wgpu::TextureDescriptor {
                label: Some("grid atlas"),
                size: wgpu::Extent3d {
                    width: ATLAS_SIDE,
                    height: ATLAS_SIDE,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::R8Uint,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            })
        });
        for put in puts {
            let [x, y, width, height] = put.at;
            if width == 0 || height == 0 {
                continue;
            }
            engine.queue.write_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: atlas,
                    mip_level: 0,
                    origin: wgpu::Origin3d { x, y, z: 0 },
                    aspect: wgpu::TextureAspect::All,
                },
                put.bytes,
                wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(width),
                    rows_per_image: Some(height),
                },
                wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
            );
        }
        Some(())
    }

    /// The longest side of a picture its device makes ([`GridPicture`]).
    pub(crate) fn most_side(&self) -> u32 {
        self.most_side
    }

    /// The bytes it keeps between its batches: the atlas, and the plane.
    pub(crate) fn kept_bytes(&self) -> u64 {
        let atlas = self.atlas.as_ref().map_or(0, |_| u64::from(ATLAS_SIDE) * u64::from(ATLAS_SIDE));
        atlas + self.work.bytes()
    }

    /// What it keeps between its batches, let go: the next makes its own,
    /// and the atlas holds no letters till they are put again.
    pub(crate) fn let_go_kept(&mut self) {
        self.atlas = None;
        self.work.let_go();
    }

    /// Encodes each of `drawn` on `encoder`, its letters read from the
    /// atlas ([`GridTile::put_letters`]): one compute pass, a dispatch a
    /// tile, each tile's words and stream a part of the one plane the
    /// batch's dispatches share ([`Work`], [`range`]) — the caller submits.
    /// None, with the last error, where the pass refuses any stream or the
    /// batch is past what the device binds: nothing is encoded then.
    ///
    /// ↩️A tile was drawn and submitted alone, its stream on a buffer of
    /// its own (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-
    /// Q2, 유저 2026-11-15 「(라)」: a frame's cold tiles in one submit).
    /// ↩️It waited for the GPU after each tile: 🔬a zoom across S5_BA's cut
    /// 352 draws some 16 tiles a frame, in the row's paint, and the UI
    /// thread's build stood at a median of 11.6 ms a frame of it against
    /// 3.1 with the rows drawing their own cells (main PC, profile, 11-09).
    pub(crate) fn encode(
        &mut self,
        engine: &Engine,
        encoder: &mut wgpu::CommandEncoder,
        drawn: &[Drawn],
    ) -> Option<()> {
        let has_atlas = self.atlas.is_some();
        for (index, tile) in drawn.iter().enumerate() {
            if let Some(fault) = fault_in(tile.ops, has_atlas) {
                return fail(format!("tile {index}: {fault}"));
            }
        }
        if drawn.is_empty() {
            return Some(());
        }
        let align = engine.device().limits().min_storage_buffer_offset_alignment as usize;
        let atlas = self.atlas.as_ref().unwrap_or(&self.no_atlas);
        let mut bytes = Vec::new();
        let mut parts = Vec::with_capacity(drawn.len());
        for tile in drawn {
            let words_at = aligned(&mut bytes, align);
            for value in [
                tile.tile.width(),
                tile.tile.height(),
                tile.background,
                tile.ops.len() as u32,
                atlas.width(),
                atlas.height(),
                0,
                0,
            ] {
                bytes.extend(value.to_le_bytes());
            }
            let stream_at = aligned(&mut bytes, align);
            // A binding holds at least a word: an empty stream binds one
            // it never reads.
            for word in if tile.ops.is_empty() { &[0][..] } else { tile.ops } {
                bytes.extend(word.to_le_bytes());
            }
            parts.push((words_at..stream_at, stream_at..bytes.len() as u64));
        }
        let groups: Vec<(u32, u32)> = drawn
            .iter()
            .map(|tile| (tile.tile.width().div_ceil(8), tile.tile.height().div_ceil(8)))
            .collect();
        fits(engine, &[bytes.len() as u64], groups.iter().copied())?;
        let mut pipelines = Vec::with_capacity(drawn.len());
        for tile in drawn {
            pipelines.push(self.pipeline(engine, tile.tile.format())?);
        }
        let plane = self.work.of(engine, bytes.len() as u64);
        engine.queue.write_buffer(&plane, 0, &bytes);
        let atlas = self.atlas.as_ref().unwrap_or(&self.no_atlas);
        let atlas_view = atlas.create_view(&wgpu::TextureViewDescriptor::default());
        let tile_views: Vec<wgpu::TextureView> = drawn
            .iter()
            .map(|tile| tile.tile.create_view(&wgpu::TextureViewDescriptor::default()))
            .collect();
        let encoded: Vec<Encoded> = parts
            .into_iter()
            .zip(&pipelines)
            .zip(&tile_views)
            .zip(groups)
            .map(|((((words, stream), pipeline), tile_view), groups)| Encoded {
                pipeline,
                bound: vec![
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: range(&plane, words),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: range(&plane, stream),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: wgpu::BindingResource::TextureView(&atlas_view),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: wgpu::BindingResource::TextureView(tile_view),
                    },
                ],
                groups: flat(groups),
            })
            .collect();
        encode_on(engine, encoder, &encoded);
        Some(())
    }

    /// `ops` drawn into `tile` over `background` alone — a batch of one,
    /// submitted.
    #[cfg(test)]
    pub(crate) fn run(&mut self, engine: &Engine, tile: &wgpu::Texture, background: u32, ops: &[i32]) -> Option<()> {
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        self.encode(engine, &mut encoder, &[Drawn { tile, background, ops }])?;
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
