//! What more than one area's kernels compute, one WGSL file per function
//! family, in one place (gpu-canonical-store, 관제 14:51): the same integer
//! formula written in two areas' folders is a copy however different the
//! text (CLAUDE.md, absolute rule 1). Before writing one, look here.
//!
//! A kernel prepends the files it uses, each once, in the order their
//! heads ask — a function prepended twice does not compile, so a second
//! copy has nowhere to hide. Each is pinned through its users' tests, or
//! here in `tests.rs` while a user reaches only part of it.

// ⏳R1's caller, the executor's rows (kernels/composite), is reached only
// by tests until the app's bridge round, and the canvas's transforms come
// after (gpu-canonical-store 14:51).
#![cfg_attr(not(test), allow(dead_code, unused_imports))]

#[cfg(test)]
mod one_builder;
mod pages;
mod resample;
#[cfg(test)]
pub(crate) mod tests;

use crate::device::Engine;

pub(crate) use pages::{Pages, page_table};
pub(crate) use resample::{ResampleMap, ResampleMode, q};

/// `isqrt_round` — the blend family's soft light, the timeline's coverage.
pub(crate) const ISQRT_WGSL: &str = include_str!("isqrt.wgsl");
/// Signed 64- and 128-bit integers on u32 words.
pub(crate) const WIDE_WGSL: &str = include_str!("wide.wgsl");
/// R1, the integer resample — after [`WIDE_WGSL`]; its host defines
/// `resample_texel`.
pub(crate) const RESAMPLE_WGSL: &str = include_str!("resample.wgsl");
/// `tile_texel` and the tile's size — where a pixel sits in a tile: the
/// export kernels' frame (`kernels/export/frame.wgsl`) and the composite's
/// rows and output tiles.
pub(crate) const TILE_WGSL: &str = include_str!("tile.wgsl");
/// `premultiply8` — a straight word as a surface Flutter shows holds it.
pub(crate) const PREMULTIPLY_WGSL: &str = include_str!("premultiply.wgsl");

/// The pipeline of `sources`, one after another, whose entry point is
/// `entry` — its bindings as that entry uses them. The crate's one builder:
/// `one_builder.rs` holds the copies left, on a ledger.
pub(crate) fn pipeline(engine: &Engine, sources: &[&str], entry: &str) -> wgpu::ComputePipeline {
    let source = sources.join("\n");
    let module = engine
        .device
        .create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(entry),
            source: wgpu::ShaderSource::Wgsl(source.into()),
        });
    engine
        .device
        .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some(entry),
            layout: None,
            module: &module,
            entry_point: Some(entry),
            compilation_options: Default::default(),
            cache: None,
        })
}

/// The WGSL name of a surface's format, as a pass storing to it declares
/// it: BGRA8 or RGBA8 unorm, what `platform::Surface` makes, and no other.
pub(crate) fn storage_format(format: wgpu::TextureFormat) -> Option<&'static str> {
    match format {
        wgpu::TextureFormat::Bgra8Unorm => Some("bgra8unorm"),
        wgpu::TextureFormat::Rgba8Unorm => Some("rgba8unorm"),
        _ => None,
    }
}
