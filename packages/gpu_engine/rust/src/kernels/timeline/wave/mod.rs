//! A sound's waveform tile: the |peak| envelope of each of its lanes
//! (`AudioPeaks.lanes`, a channel each) as WaveformPainter draws it — a
//! band mirrored about the middle of the lane's equal share of the strip
//! across, along a strip that runs right or down — in `wave.wgsl`.
//!
//! Its integers (gpu-int-spec-timeline ②, ⚠️Mine where the spec left the
//! lane to say):
//! - A peak is q16: round(min(|s|, 1) · 65535).
//! - A strip pixel e's edge stands at bucket (e·256 + lead_q8) · bps · den /
//!   (frame_q8 · num) — worked out here in u128 ([`edge_of`]), never in the
//!   shader, so a column is the same whichever tile it falls in.
//! - A column shows the most of the line through the peaks over its
//!   stretch; the line runs from the first bucket to the last, and a column
//!   with none of it shows nothing.
//! - A row is covered by how much of it the band overlaps — not the spec's
//!   reach − distance + ½, which draws a line of half a pixel through
//!   silence.

// ↩️Nothing outside the tests called it until the app's bridge round
// (gpu-int-spec-timeline, 관제 13:5x — the app connects after the bridges
// land): its C ABI came with the card
// the-waveform-is-drawn-on-the-cpu-beside-its-kernel (관제 2026-11-14).
// ↩️🔜The lane that lays that bridge puts this pass in the list the app
// compiles ahead (`compileAppKernelsAhead`, app_kernels_ahead.dart): it
// is compiled where a tile of a format is first run
// (`WaveTile::pipeline`), and the thread an app's frames are built on
// compiles no kernel (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦:
// 「선 = UI 스레드가 직접 하는 커널 컴파일 0개」; left out of card
// a-first-mesh-warp-…, 2026-11-14 03:02, the app having no way to it
// yet). It is: the grids' set (`appGpuGridKernels`), which that list
// compiles and a grid's screen warms, has it compiled for the pictures it
// draws ([`WaveTile::for_pictures`]).

pub(crate) mod abi;
#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::Work;
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, aligned, encode_on, fits, flat, pipeline, range, storage_format,
};
use crate::kernels::timeline::LAID_WGSL;
use crate::kernels::timeline::grid::GridPicture;

/// The most lanes a sound may bring.
///
/// ⚠️Mine: more than any file a strip draws (7.1 is eight), and it keeps a
/// row's lane, middle · lanes, inside a u32.
pub(crate) const MOST_LANES: usize = 64;

/// How wide a strip may be across, q8: 65536 pixels, below which a lane's
/// middle · 2·lanes stays inside an i32 and its reach inside the 24 bits
/// `scaled` takes.
///
/// ⚠️Mine, as [`MOST_LANES`] is: refused past it, not drawn narrower.
pub(crate) const MOST_ACROSS_Q8: i32 = 1 << 24;

/// A sound's peaks on the GPU, with the table of their range maxima the
/// pass reads a column's peaks from.
pub(crate) struct WavePeaks {
    words: wgpu::Buffer,
    lanes: u32,
    buckets: u32,
    levels: u32,
}

impl WavePeaks {
    /// `lanes`' peaks (q16), uploaded with level k of each lane's table —
    /// the most of the 2^k buckets from each bucket — up to the largest 2^k
    /// a lane holds. None, with the last error, for no lane, an empty one,
    /// lanes of different lengths, more than [`MOST_LANES`], or a table
    /// past what the device binds.
    pub(crate) fn new(engine: &Engine, lanes: &[&[u16]]) -> Option<Self> {
        let Some(buckets) = lanes.first().map(|lane| lane.len()) else {
            return fail("a sound with no lane has no waveform".to_owned());
        };
        if buckets == 0 || lanes.iter().any(|lane| lane.len() != buckets) {
            return fail("a sound's lanes must hold the same buckets, and some".to_owned());
        }
        if lanes.len() > MOST_LANES {
            return fail(format!("{} lanes is more than {MOST_LANES}", lanes.len()));
        }
        let levels = buckets.ilog2() as usize + 1;
        let bytes = (lanes.len() * levels * buckets).div_ceil(2) * 4;
        let most = engine.device().limits().max_storage_buffer_binding_size as usize;
        if bytes > most {
            return fail(format!("a table of {bytes} bytes is past the {most} bound"));
        }
        let mut table: Vec<u16> = Vec::with_capacity(lanes.len() * levels * buckets);
        for lane in lanes {
            let start = table.len();
            table.extend_from_slice(lane);
            for level in 1..levels {
                let below = start + (level - 1) * buckets;
                let half = 1 << (level - 1);
                for i in 0..buckets {
                    // Past the last whole block a level holds no query.
                    let next = table[below + (i + half).min(buckets - 1)];
                    table.push(table[below + i].max(next));
                }
            }
        }
        let words: Vec<u8> = table
            .chunks(2)
            .map(|pair| pair[0] as u32 | (*pair.get(1).unwrap_or(&0) as u32) << 16)
            .flat_map(|word| word.to_le_bytes())
            .collect();
        let words = engine.filled("wave peaks", &words, wgpu::BufferUsages::STORAGE);
        Some(Self {
            words,
            lanes: lanes.len() as u32,
            buckets: buckets as u32,
            levels: levels as u32,
        })
    }
}

/// Where a strip shows its sound, and how: what WaveformPainter takes, in
/// the integers the bridge hands over.
#[derive(Clone, Copy, Debug)]
pub(crate) struct WaveView {
    /// The strip pixel the tile's first column (or row, running down) is.
    pub along0: i32,
    /// How many pixels long the strip is: a column before its first or past
    /// its last shows what the tile holds — a tile of a row's frames ends
    /// where it ends, and a sound's strip where its block does.
    pub length: i32,
    pub vertical: bool,
    /// Pixels a frame, q8.
    pub frame_q8: i32,
    /// Frames a second: numerator, denominator.
    pub fps: (u32, u32),
    pub buckets_per_second: u32,
    /// Frames into the file before the strip's start — the clip's trim.
    pub leading_frames: i32,
    /// The strip's extent across, q8.
    pub across_q8: i32,
    /// The clip's gain, q16 (65536 is 1).
    pub gain_q16: i32,
    /// The band's straight colour, r | g<<8 | b<<16 | a<<24.
    pub rgba: u32,
}

/// Why `view` cannot be drawn, if it cannot.
fn fault_in(view: &WaveView) -> Option<String> {
    if view.frame_q8 <= 0 || view.fps.0 == 0 || view.fps.1 == 0 {
        return Some(format!("{view:?} has no pace"));
    }
    if view.buckets_per_second == 0 {
        return Some("a sound with no buckets a second has no place".to_owned());
    }
    if !(1..MOST_ACROSS_Q8).contains(&view.across_q8) {
        return Some(format!("a strip {} across (q8) is out of reach", view.across_q8));
    }
    if view.gain_q16 < 0 {
        return Some(format!("a gain of {} is below none", view.gain_q16));
    }
    if view.length < 0 {
        return Some(format!("a strip {} long is shorter than none", view.length));
    }
    None
}

/// Where strip pixel `e`'s edge stands in a lane of `buckets`: the bucket,
/// and how far on toward the next, q16 (rounded down) — held to the first
/// and the last bucket.
fn edge_of(view: &WaveView, buckets: u32, e: i64) -> [u32; 2] {
    let lead_q8 = view.leading_frames as i64 * view.frame_q8 as i64;
    let numer = (e * 256 + lead_q8) as i128
        * view.buckets_per_second as i128
        * view.fps.1 as i128;
    let denom = view.frame_q8 as i128 * view.fps.0 as i128;
    if numer <= 0 {
        return [0, 0];
    }
    let bucket = numer / denom;
    if bucket >= (buckets - 1) as i128 {
        return [buckets - 1, 0];
    }
    [bucket as u32, (((numer % denom) << 16) / denom) as u32]
}

/// A sound a batch lays over a tile: `peaks` over what `tile` holds as
/// `view` shows them.
pub(crate) struct Waved<'a> {
    pub(crate) tile: &'a wgpu::Texture,
    pub(crate) peaks: &'a WavePeaks,
    pub(crate) view: WaveView,
}

/// A waveform tile's pass, one pipeline per texture format it has been run
/// on.
pub(crate) struct WaveTile {
    /// The plane a batch's words and edges lie on, a part a sound.
    work: Work,
    /// What a tile holds is read from as the band is laid over it, one a
    /// format, as big as the largest tile it has held: the batch copies
    /// each tile into it before the tile's pass — a storage texture is not
    /// read where it is written. ↩️A texture was made for each sound drawn.
    unders: Vec<wgpu::Texture>,
    pipelines: Vec<(wgpu::TextureFormat, wgpu::ComputePipeline)>,
}

impl WaveTile {
    pub(crate) fn new(_engine: &Engine) -> Self {
        Self {
            work: Work::default(),
            unders: Vec::new(),
            pipelines: Vec::new(),
        }
    }

    /// The pass with its pipeline for a frame grid's picture compiled where
    /// the caller is — what a strip's waveform is drawn into and its screen
    /// lays ([`GridPicture`]) — so the first sound drawn compiles nothing,
    /// as the grid's tile pass is made (`GridTile::for_pictures`).
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
            return fail(format!("the wave pass cannot store to {format:?}"));
        };
        let body = include_str!("wave.wgsl").replace("__FORMAT__", token);
        let pipeline = pipeline(
            engine,
            &[ISQRT_WGSL, BLEND_WGSL, LAID_WGSL, &body],
            "wave",
        );
        self.pipelines.push((format, pipeline.clone()));
        Some(pipeline)
    }

    /// The under of `format` at least `width` × `height`: the one kept, or
    /// one made in its place.
    fn under(&mut self, engine: &Engine, format: wgpu::TextureFormat, (width, height): (u32, u32)) -> wgpu::Texture {
        let kept = self.unders.iter().position(|under| under.format() == format);
        if let Some(index) = kept {
            let under = &self.unders[index];
            if under.width() >= width && under.height() >= height {
                return under.clone();
            }
            self.unders.swap_remove(index);
        }
        let under = engine.device().create_texture(&wgpu::TextureDescriptor {
            label: Some("wave under"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        self.unders.push(under.clone());
        under
    }

    /// The bytes it keeps between its batches: the plane, and the unders.
    pub(crate) fn kept_bytes(&self) -> u64 {
        let unders: u64 = self
            .unders
            .iter()
            .map(|under| u64::from(under.width()) * u64::from(under.height()) * 4)
            .sum();
        unders + self.work.bytes()
    }

    /// What it keeps between its batches, let go: the next makes its own.
    pub(crate) fn let_go_kept(&mut self) {
        self.unders.clear();
        self.work.let_go();
    }

    /// Encodes each of `waved` on `encoder`, in order: the tile copied to
    /// its under, then a pass laying the band over it — each sound's words
    /// and edges a part of the one plane the batch's passes share
    /// ([`Work`], [`range`]); the caller submits, and what reads a tile
    /// after comes after it on the same queue. None, with the last error,
    /// for a view it refuses or a batch past what the device binds: nothing
    /// is encoded then. Every tile is copied from, as every grid picture
    /// may be. ↩️Each sound was drawn and submitted alone
    /// (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q2, 유저
    /// 2026-11-15 「(라)」). ↩️It waited for the GPU and gave back the wall
    /// time, which nothing read.
    pub(crate) fn encode(
        &mut self,
        engine: &Engine,
        encoder: &mut wgpu::CommandEncoder,
        waved: &[Waved],
    ) -> Option<()> {
        for (index, wave) in waved.iter().enumerate() {
            if let Some(fault) = fault_in(&wave.view) {
                return fail(format!("sound {index}: {fault}"));
            }
        }
        if waved.is_empty() {
            return Some(());
        }
        let align = engine.device().limits().min_storage_buffer_offset_alignment as usize;
        let mut bytes = Vec::new();
        let mut parts = Vec::with_capacity(waved.len());
        for &Waved { tile, peaks, ref view } in waved {
            // A lane's reach stops a pixel inside half its share; the gain
            // is drawn into it and held to 1 — the band cannot outgrow its
            // lane (WaveformPainter's `gain`).
            let reach_q8 = (view.across_q8 as u64 / (2 * peaks.lanes as u64)).saturating_sub(256);
            let gain = (view.gain_q16 as u64).min(65536);
            let scale_q8 = ((reach_q8 * gain + 32768) >> 16) as u32;
            let words_at = aligned(&mut bytes, align);
            for value in [
                tile.width(),
                tile.height(),
                view.vertical as u32,
                peaks.lanes,
                peaks.buckets,
                peaks.levels,
                view.across_q8 as u32,
                scale_q8,
                view.rgba,
                0,
                0,
                0,
            ] {
                bytes.extend(value.to_le_bytes());
            }
            let edges_at = aligned(&mut bytes, align);
            let along = if view.vertical { tile.height() } else { tile.width() };
            // A column past either end of the strip has its two edges at
            // the same place, and shows nothing of the band.
            for x in 0..=along as i64 {
                let e = (view.along0 as i64 + x).clamp(0, view.length as i64);
                for word in edge_of(view, peaks.buckets, e) {
                    bytes.extend(word.to_le_bytes());
                }
            }
            parts.push((words_at..edges_at, edges_at..bytes.len() as u64));
        }
        let groups: Vec<(u32, u32)> = waved
            .iter()
            .map(|wave| (wave.tile.width().div_ceil(8), wave.tile.height().div_ceil(8)))
            .collect();
        fits(engine, &[bytes.len() as u64], groups.iter().copied())?;
        let mut pipelines = Vec::with_capacity(waved.len());
        let mut unders = Vec::with_capacity(waved.len());
        for wave in waved {
            let format = wave.tile.format();
            pipelines.push(self.pipeline(engine, format)?);
            let widest = waved.iter().filter(|other| other.tile.format() == format);
            let size = widest.fold((1, 1), |(width, height), other| {
                (width.max(other.tile.width()), height.max(other.tile.height()))
            });
            unders.push(self.under(engine, format, size));
        }
        let plane = self.work.of(engine, bytes.len() as u64);
        engine.queue.write_buffer(&plane, 0, &bytes);
        for ((((wave, (words, edges)), pipeline), under), groups) in
            waved.iter().zip(parts).zip(&pipelines).zip(&unders).zip(groups)
        {
            encoder.copy_texture_to_texture(
                wave.tile.as_image_copy(),
                under.as_image_copy(),
                wave.tile.size(),
            );
            let tile_view = wave.tile.create_view(&wgpu::TextureViewDescriptor::default());
            let under_view = under.create_view(&wgpu::TextureViewDescriptor::default());
            encode_on(
                engine,
                encoder,
                &[Encoded {
                    pipeline,
                    bound: vec![
                        wgpu::BindGroupEntry {
                            binding: 0,
                            resource: range(&plane, words),
                        },
                        wgpu::BindGroupEntry {
                            binding: 1,
                            resource: wave.peaks.words.as_entire_binding(),
                        },
                        wgpu::BindGroupEntry {
                            binding: 2,
                            resource: range(&plane, edges),
                        },
                        wgpu::BindGroupEntry {
                            binding: 3,
                            resource: wgpu::BindingResource::TextureView(&tile_view),
                        },
                        wgpu::BindGroupEntry {
                            binding: 4,
                            resource: wgpu::BindingResource::TextureView(&under_view),
                        },
                    ],
                    groups: flat(groups),
                }],
            );
        }
        Some(())
    }

    /// `peaks` laid over what `tile` holds as `view` shows them, alone — a
    /// batch of one, submitted.
    #[cfg(test)]
    pub(crate) fn run(&mut self, engine: &Engine, tile: &wgpu::Texture, peaks: &WavePeaks, view: &WaveView) -> Option<()> {
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        self.encode(engine, &mut encoder, &[Waved { tile, peaks, view: *view }])?;
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
