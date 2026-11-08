//! A frame grid's tile, drawn from the op stream the grids write — the
//! words the C rasterizer `qa_grid_raster_tile` reads today
//! (timeline_grid_tile_ops.dart has them) — over an A8 atlas of the
//! letters, in `grid.wgsl`.
//!
//! What the stream says is the C rasterizer's, but for the rounded rects:
//! their field is taken in q9 integers with `isqrt_round`, not in doubles
//! with the C library's square root, so an edge pixel may differ from an
//! old build's by a step — the same on every device, which is the point.

pub(crate) mod abi;
#[cfg(test)]
mod tests;

use std::time::Instant;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::letters::words::WordCover;
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, PREMULTIPLY_WGSL, encode_on, flat, pipeline, storage_format, whole,
};
use crate::kernels::timeline::LAID_WGSL;

const FILL_RECT: i32 = 1;
const HLINE: i32 = 2;
const VLINE: i32 = 3;
const GLYPH: i32 = 4;
const RRECT_FILL: i32 = 5;
const RRECT_RING: i32 = 6;

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

/// A frame grid's tile as the engine keeps it: what the pass draws, stored
/// premultiplied, for the view's screen to lay (grid-on-the-engine ⓑ, 관제
/// 2026-11-08 16:42) — never read back for the app to raise again (관제
/// 11-05 14:02).
pub(crate) struct GridPicture {
    pub(crate) texture: wgpu::Texture,
}

impl GridPicture {
    /// A clear picture `width` × `height` pixels — None, with the last
    /// error, for a side of none or past what the device makes.
    pub(crate) fn new(engine: &Engine, width: u32, height: u32) -> Option<Self> {
        let most = engine.device.limits().max_texture_dimension_2d;
        if width == 0 || height == 0 || width > most || height > most {
            return fail(format!("a grid tile {width} × {height}: a side is 1 to {most} pixels"));
        }
        let texture = engine.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("grid tile"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            // Drawn by the pass, laid by the screen, read for a fingerprint.
            usage: wgpu::TextureUsages::STORAGE_BINDING
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        Some(Self { texture })
    }
}

/// The atlas a stream's letters are read from: each of `words` with its
/// top-left at its place, nothing where none lies — None for no word, and
/// None with the last error for an atlas past what the device makes.
pub(crate) fn atlas_of(engine: &Engine, words: &[(&WordCover, [u32; 2])]) -> Option<Option<wgpu::Texture>> {
    if words.is_empty() {
        return Some(None);
    }
    let ends: Option<Vec<[u32; 2]>> = words
        .iter()
        .map(|(word, [x, y])| Some([x.checked_add(word.width)?, y.checked_add(word.height)?]))
        .collect();
    let Some(ends) = ends else {
        return fail(format!("a word laid in a letters' atlas past its {}th pixel", u32::MAX));
    };
    let width = ends.iter().map(|[x, _]| *x).max().unwrap_or(0);
    let height = ends.iter().map(|[_, y]| *y).max().unwrap_or(0);
    let most = engine.device.limits().max_texture_dimension_2d;
    if width == 0 || height == 0 || width > most || height > most {
        return fail(format!("a letters' atlas {width} × {height}: a side is 1 to {most} pixels"));
    }
    let mut bytes = vec![0u8; width as usize * height as usize];
    for (word, [x, y]) in words {
        for (row, line) in word.bytes.chunks_exact(word.width as usize).enumerate() {
            let at = (*y as usize + row) * width as usize + *x as usize;
            bytes[at..at + line.len()].copy_from_slice(line);
        }
    }
    let size = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    let texture = engine.device.create_texture(&wgpu::TextureDescriptor {
        label: Some("grid atlas"),
        size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::R8Uint,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    engine.queue.write_texture(
        texture.as_image_copy(),
        &bytes,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(width),
            rows_per_image: Some(height),
        },
        size,
    );
    Some(Some(texture))
}

/// A frame grid's tile pass, one pipeline per texture format it has been
/// run on.
pub(crate) struct GridTile {
    params: wgpu::Buffer,
    /// What the atlas binding holds for a stream with no letters.
    no_atlas: wgpu::Texture,
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
        _ => None,
    }
}

/// Why `ops` cannot be drawn, if it cannot: an op the stream does not
/// have, one cut short, a letter with no atlas, a place or length past
/// [`MOST_REACH`], or a corner below square or past [`MOST_RADIUS_Q9`].
///
/// ⚠️Mine: a stream the C rasterizer would stop part-way through is refused
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
        at += words;
    }
    None
}

impl GridTile {
    pub(crate) fn new(engine: &Engine) -> Self {
        let params = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("grid params"),
            size: 32,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let no_atlas = engine.device.create_texture(&wgpu::TextureDescriptor {
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
            params,
            no_atlas,
            pipelines: Vec::new(),
        }
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
            &[ISQRT_WGSL, BLEND_WGSL, LAID_WGSL, PREMULTIPLY_WGSL, &body],
            "grid",
        );
        self.pipelines.push((format, pipeline.clone()));
        Some(pipeline)
    }

    /// Draws `ops` into `tile` over `background` (an RGBA word), the
    /// letters from `atlas` (an `R8Uint` texture of coverages), and waits
    /// for the GPU. Returns the wall time from submit to completion, in
    /// nanoseconds; None, with the last error, for a stream it refuses.
    pub(crate) fn run(
        &mut self,
        engine: &Engine,
        tile: &wgpu::Texture,
        background: u32,
        ops: &[i32],
        atlas: Option<&wgpu::Texture>,
    ) -> Option<u64> {
        if let Some(fault) = fault_in(ops, atlas.is_some()) {
            return fail(fault);
        }
        let pipeline = self.pipeline(engine, tile.format())?;
        let atlas = atlas.unwrap_or(&self.no_atlas);
        let params: Vec<u8> = [
            tile.width(),
            tile.height(),
            background,
            ops.len() as u32,
            atlas.width(),
            atlas.height(),
            0,
            0,
        ]
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect();
        engine.queue.write_buffer(&self.params, 0, &params);
        // A binding holds at least a word: an empty stream binds one it
        // never reads.
        let words: Vec<u8> = if ops.is_empty() { &[0][..] } else { ops }
            .iter()
            .flat_map(|word| word.to_le_bytes())
            .collect();
        let stream = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("grid ops"),
                contents: &words,
                usage: wgpu::BufferUsages::STORAGE,
            });
        let atlas_view = atlas.create_view(&wgpu::TextureViewDescriptor::default());
        let tile_view = tile.create_view(&wgpu::TextureViewDescriptor::default());
        let mut bound = whole(&[(0, &self.params), (1, &stream)]);
        bound.push(wgpu::BindGroupEntry {
            binding: 2,
            resource: wgpu::BindingResource::TextureView(&atlas_view),
        });
        bound.push(wgpu::BindGroupEntry {
            binding: 3,
            resource: wgpu::BindingResource::TextureView(&tile_view),
        });
        let groups = flat((tile.width().div_ceil(8), tile.height().div_ceil(8)));
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encode_on(
            engine,
            &mut encoder,
            &[Encoded {
                pipeline: &pipeline,
                bound,
                groups,
            }],
        );
        let start = Instant::now();
        engine.queue.submit([encoder.finish()]);
        engine.wait()?;
        Some(start.elapsed().as_nanos() as u64)
    }
}
