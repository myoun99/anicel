//! A view's screen of frame grid tiles (grid-on-the-engine ⓑ, 관제
//! 2026-11-08 16:42 · 16:46): the tiles a sheet's rows lay — each its own
//! span's, or the part of another a span stands on while it is rastered
//! (timeline_grid_tile_store.dart `standInFor`) — through R1, the engine's
//! one resampler (resample.wgsl), onto the screen's pixels each covers, the
//! rest of what the screen makes clear, in `lay.wgsl`.

#[cfg(test)]
#[path = "lay_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{
    Encoded, PREMULTIPLY_WGSL, RESAMPLE_WGSL, ResampleMap, ResampleMode, WIDE_WGSL, encode_on,
    fits, flat, land_storage_writes, pipeline, storage_format, whole, words_buffer,
};

use crate::platform::stores;

use super::GridPicture;

/// lay.wgsl's workgroup side.
const GROUP: u32 = 8;

/// A tile laid on a screen: the part `from` of its picture, [left, top,
/// right, bottom) in the picture's pixels, onto the part `onto` of the
/// screen, in the screen's — boxes of doubles, as a row's cells fall.
pub(crate) struct Laid<'a> {
    pub(crate) picture: &'a GridPicture,
    pub(crate) from: [f64; 4],
    pub(crate) onto: [f64; 4],
}

/// The screen pass, its two entries compiled once per format: where it
/// first lays onto one, or ahead of it ([`GridLay::ready`]).
pub(crate) struct GridLay {
    pipelines: Vec<(wgpu::TextureFormat, [wgpu::ComputePipeline; 2])>,
}

impl GridLay {
    pub(crate) fn new() -> Self {
        Self { pipelines: Vec::new() }
    }

    /// Compiles the entries that lay onto a screen of `format` where the
    /// caller is, so that the first screen laid compiles nothing: the app
    /// asks off the thread its frames are built on (🗣️관제 2026-11-10
    /// 18:14, gpu-canonical-store ⑦ — 🔬the two were the first 2.9–3.5 s
    /// of a stopped UI at launch on the Surface Pro 11). Nothing where
    /// this adapter stores to no such screen: none is made there
    /// (`platform::Surface`).
    pub(crate) fn ready(&mut self, engine: &Engine, format: wgpu::TextureFormat) {
        if stores(engine, format) {
            self.pipelines(engine, format);
        }
    }

    /// The clear and the tile entries for `format`.
    fn pipelines(&mut self, engine: &Engine, format: wgpu::TextureFormat) -> Option<[wgpu::ComputePipeline; 2]> {
        if let Some((_, made)) = self.pipelines.iter().find(|(of, _)| *of == format) {
            return Some(made.clone());
        }
        let Some(token) = storage_format(format) else {
            return fail(format!("a grid screen cannot store to {format:?}"));
        };
        let body = include_str!("lay.wgsl").replace("__FORMAT__", token);
        let sources = [WIDE_WGSL, RESAMPLE_WGSL, PREMULTIPLY_WGSL, body.as_str()];
        let made = ["lay_clear", "lay_tile"].map(|entry| pipeline(engine, &sources, entry));
        self.pipelines.push((format, made.clone()));
        Some(made)
    }

    /// The pixels `rect` of `target`, [left, top, right, bottom): clear, and
    /// each of `laid` over the pixels whose centres its `onto` holds, by R1
    /// from its `from` ([`laid_by`]) — where two hold one pixel either may land,
    /// which no row lays —, premultiplied as Flutter reads a surface. The rest of `target` is left
    /// as it was. Submits the work and returns. None, with the last error, for a rect
    /// not in the target, a format a screen cannot store, or a tile laid from
    /// past its picture, from no box or onto none.
    ///
    /// 🚨IT DOES NOT WAIT, as the screen's composite does not
    /// ([`Composite::show`](crate::kernels::composite::Composite::show) has
    /// why): what hands the screen to Flutter waits off the thread that
    /// asked ([`Engine::done_then`], the app's screen texture). ↩️It waited
    /// here till 2026-11-12 — on the thread that builds the app's frames,
    /// whenever a row changed, a scroll passed what the screen held or the
    /// panel grew (the-grid-lay-waits-on-the-ui-thread; the same law as
    /// a-float-in-hand-draws-the-frame-as-it-stands-Q2).
    pub(crate) fn lay(&mut self, engine: &Engine, target: &wgpu::Texture, rect: [u32; 4], laid: &[Laid]) -> Option<()> {
        let [left, top, right, bottom] = rect;
        if left >= right || top >= bottom || right > target.width() || bottom > target.height() {
            return fail(format!(
                "{rect:?} is no rectangle of a {} × {} screen",
                target.width(),
                target.height()
            ));
        }
        let [clear, tile] = self.pipelines(engine, target.format())?;
        let screen = target.create_view(&wgpu::TextureViewDescriptor::default());
        let mut made = vec![(rect, None)];
        for one in laid {
            let map = mapped(one, target)?;
            if let Some(pixels) = covered(one.onto, rect) {
                made.push((pixels, Some((one.picture, map))));
            }
        }
        let groups = |[left, top, right, bottom]: [u32; 4]| ((right - left).div_ceil(GROUP), (bottom - top).div_ceil(GROUP));
        fits(engine, &[], made.iter().map(|(pixels, _)| groups(*pixels)))?;
        let mut held = Vec::with_capacity(made.len());
        for (pixels, from) in &made {
            let [left, top, right, bottom] = *pixels;
            let (width, height, map) = from.map_or((0, 0, [0; ResampleMap::WORDS]), |(picture, map)| {
                (picture.texture.width(), picture.texture.height(), map.words())
            });
            let words: Vec<u32> = [left, top, right - left, bottom - top, width, height].into_iter().chain(map).collect();
            let record = words_buffer(engine, "grid laid", &words, wgpu::BufferUsages::STORAGE);
            let picture = from.map(|(picture, _)| picture.texture.create_view(&wgpu::TextureViewDescriptor::default()));
            held.push((record, picture, groups(*pixels)));
        }
        let encoded: Vec<Encoded> = held
            .iter()
            .map(|(record, picture, groups)| {
                let mut bound = whole(&[(0, record)]);
                if let Some(picture) = picture {
                    bound.push(wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(picture) });
                }
                bound.push(wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&screen) });
                Encoded { pipeline: if picture.is_some() { &tile } else { &clear }, bound, groups: flat(*groups) }
            })
            .collect();
        let mut encoder = engine.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let (clear, tiles) = encoded.split_at(1);
        encode_on(engine, &mut encoder, clear);
        land_storage_writes(&mut encoder, target);
        encode_on(engine, &mut encoder, tiles);
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// R1's map from `target`'s pixels to the part of `laid`'s picture it lays
/// — None, with the last error, where its boxes cannot be laid.
fn mapped(laid: &Laid, target: &wgpu::Texture) -> Option<ResampleMap> {
    let Laid { picture, from, onto } = laid;
    let (width, height) = (f64::from(picture.texture.width()), f64::from(picture.texture.height()));
    let [x0, y0, x1, y1] = *from;
    let inside = 0.0 <= x0 && x0 < x1 && x1 <= width && 0.0 <= y0 && y0 < y1 && y1 <= height;
    if !inside {
        return fail(format!("a tile laid from {from:?} of its {width} × {height} pixels"));
    }
    let [u0, v0, u1, v1] = *onto;
    if !(u0 < u1 && v0 < v1 && onto.iter().all(|edge| edge.is_finite())) {
        return fail(format!("a tile laid onto {onto:?}"));
    }
    let (along, down) = ((x1 - x0) / (u1 - u0), (y1 - y0) / (v1 - v0));
    let inverse = [along, 0.0, x0 - u0 * along, 0.0, down, y0 - v0 * down, 0.0, 0.0, 1.0];
    ResampleMap::new(inverse, 1.0, laid_by(), target.width(), target.height())
        .or_else(|| fail(format!("a tile laid from {from:?} onto {onto:?} lands nothing")))
}

/// The pixels of `rect` whose centres `onto` holds, [left, top, right,
/// bottom) — None where it holds none.
fn covered(onto: [f64; 4], [left, top, right, bottom]: [u32; 4]) -> Option<[u32; 4]> {
    // A pixel p's centre p + ½ is in [a, b) when ⌈a − ½⌉ ≤ p < ⌈b − ½⌉.
    let first = |edge: f64, low: u32, high: u32| (edge - 0.5).ceil().clamp(f64::from(low), f64::from(high)) as u32;
    let [u0, v0, u1, v1] = onto;
    let pixels = [first(u0, left, right), first(v0, top, bottom), first(u1, left, right), first(v1, top, bottom)];
    (pixels[0] < pixels[2] && pixels[1] < pixels[3]).then_some(pixels)
}

/// How a tile is laid: the one texel where a screen pixel's centre lands
/// — at whole pixels R1's copy, which any mode takes there.
///
/// ⚠️Mine (11-08): NOT BLEND. R1 reads nothing past a tile's edges (its
/// host's texel is 0 there, resample.wgsl's contract), so Blend's tent
/// fades a tile toward its edge wherever it lands off whole pixels or is
/// stretched — a line of less ink at every span's edge, where a row's
/// paint (`drawImageRect`, FilterQuality.low) clamps to the edge and joins
/// its tiles. Nearest joins them as they are. What it costs: a tile a span
/// stands on while it is rastered (a zoom's) is stretched by whole texels,
/// not smoothed, and a tile at a fraction of a pixel stands on the nearest
/// pixel, not between two (`standInFor`, timeline_grid_tile_store.dart).
/// ↩️Its host's texel has not been 0 past an edge since 11-09: a hair past
/// one reads the tile's own (lay.wgsl's `resample_texel`). Whether that
/// ends Blend's fade was not tried.
fn laid_by() -> ResampleMode {
    ResampleMode::Nearest
}
