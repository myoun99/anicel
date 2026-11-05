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

// ⏳Nothing outside the tests calls it until the app's bridge round
// (gpu-int-spec-timeline, 관제 13:5x — the app connects after the bridges
// land).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use std::time::Instant;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::shared::ISQRT_WGSL;
use crate::kernels::timeline::LAID_WGSL;

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
        let most = engine.device.limits().max_storage_buffer_binding_size as usize;
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
        let words = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("wave peaks"),
                contents: &words,
                usage: wgpu::BufferUsages::STORAGE,
            });
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
    /// The tile's bytes before the band, as an RGBA word.
    pub background: u32,
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

/// The WGSL name of a format the pass can store to.
fn storage_format(format: wgpu::TextureFormat) -> Option<&'static str> {
    match format {
        wgpu::TextureFormat::Bgra8Unorm => Some("bgra8unorm"),
        wgpu::TextureFormat::Rgba8Unorm => Some("rgba8unorm"),
        _ => None,
    }
}

/// A waveform tile's pass, one pipeline per texture format it has been run
/// on.
pub(crate) struct WaveTile {
    params: wgpu::Buffer,
    pipelines: Vec<(wgpu::TextureFormat, wgpu::ComputePipeline)>,
}

impl WaveTile {
    pub(crate) fn new(engine: &Engine) -> Self {
        let params = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("wave params"),
            size: 48,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        Self {
            params,
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
            return fail(format!("the wave pass cannot store to {format:?}"));
        };
        let body = include_str!("wave.wgsl").replace("__FORMAT__", token);
        let source = [ISQRT_WGSL, BLEND_WGSL, LAID_WGSL, &body].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("wave"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("wave"),
                layout: None,
                module: &module,
                entry_point: Some("wave"),
                compilation_options: Default::default(),
                cache: None,
            });
        self.pipelines.push((format, pipeline.clone()));
        Some(pipeline)
    }

    /// Draws `peaks` into `tile` as `view` shows them, and waits for the
    /// GPU. Returns the wall time from submit to completion, in
    /// nanoseconds; None, with the last error, for a view it refuses.
    pub(crate) fn run(
        &mut self,
        engine: &Engine,
        tile: &wgpu::Texture,
        peaks: &WavePeaks,
        view: &WaveView,
    ) -> Option<u64> {
        if let Some(fault) = fault_in(view) {
            return fail(fault);
        }
        let pipeline = self.pipeline(engine, tile.format())?;
        // A lane's reach stops a pixel inside half its share; the gain is
        // drawn into it and held to 1 — the band cannot outgrow its lane
        // (WaveformPainter's `gain`).
        let reach_q8 = (view.across_q8 as u64 / (2 * peaks.lanes as u64)).saturating_sub(256);
        let gain = (view.gain_q16 as u64).min(65536);
        let scale_q8 = ((reach_q8 * gain + 32768) >> 16) as u32;
        let params: Vec<u8> = [
            tile.width(),
            tile.height(),
            view.vertical as u32,
            peaks.lanes,
            peaks.buckets,
            peaks.levels,
            view.across_q8 as u32,
            scale_q8,
            view.rgba,
            view.background,
            0,
            0,
        ]
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect();
        engine.queue.write_buffer(&self.params, 0, &params);
        let along = if view.vertical { tile.height() } else { tile.width() };
        let edges: Vec<u8> = (0..=along as i64)
            .flat_map(|x| edge_of(view, peaks.buckets, view.along0 as i64 + x))
            .flat_map(|word| word.to_le_bytes())
            .collect();
        let edges = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("wave edges"),
                contents: &edges,
                usage: wgpu::BufferUsages::STORAGE,
            });
        let tile_view = tile.create_view(&wgpu::TextureViewDescriptor::default());
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("wave"),
            layout: &pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: self.params.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: peaks.words.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: edges.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&tile_view),
                },
            ],
        });
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups(tile.width().div_ceil(8), tile.height().div_ceil(8), 1);
        }
        let start = Instant::now();
        engine.queue.submit([encoder.finish()]);
        engine.wait()?;
        Some(start.elapsed().as_nanos() as u64)
    }
}
