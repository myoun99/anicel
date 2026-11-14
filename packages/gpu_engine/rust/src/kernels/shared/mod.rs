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

mod counted;
mod dispatch;
#[cfg(test)]
mod every_free;
#[cfg(test)]
mod one_builder;
#[cfg(test)]
mod one_checkout;
#[cfg(test)]
mod one_device_turn;
#[cfg(test)]
mod one_filler;
#[cfg(test)]
mod one_framing;
#[cfg(test)]
mod one_maths;
#[cfg(test)]
mod one_ndk_table;
#[cfg(test)]
mod one_pass;
#[cfg(test)]
mod one_premultiply;
#[cfg(test)]
mod one_sixteen_bit;
mod paged;
mod pages;
mod resample;
#[cfg(test)]
mod source_scan;
#[cfg(test)]
pub(crate) mod tests;

use std::cell::Cell;
use std::sync::{Arc, OnceLock};

use crate::device::{CompilerTurn, Engine, KernelSource};

pub(crate) use counted::Counted;
pub(crate) use dispatch::{
    Encoded, encode, encode_on, fits, flat, land_storage_writes, le_bytes, le_words, plane, range, room, tiles_a_page, tiles_a_pass,
    whole, words_buffer,
};
pub(crate) use paged::{Given, Run, cut_by, encoded, given};
pub(crate) use pages::{NO_PAGE, Own, Pages, page_table, runs};
pub(crate) use resample::{
    CEILING as RESAMPLE_CEILING, ResampleMap, ResampleMode, ResampleModes, q,
};

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
/// `premultiply8` — a straight word as a surface Flutter shows holds it,
/// and as the export lays it over a ground — and its rounding,
/// `div255_round`, which the cel pixel blend takes too. `one_premultiply.rs`
/// keeps it the one.
pub(crate) const PREMULTIPLY_WGSL: &str = include_str!("premultiply.wgsl");

/// A number on 0..=1 on the 16-bit scale — the scale a channel and an
/// alpha are on (blend.wgsl) — rounded once: a dab's opacity and flow, a
/// lens's threshold, a plugin's colour. `one_sixteen_bit.rs` keeps it the
/// one.
pub(crate) fn sixteen_bit(value: f64) -> u32 {
    (value * 65535.0).round() as u32
}

/// The pipeline of `sources`, one after another, whose entry point is
/// `entry` — its bindings as that entry uses them. The crate's one builder:
/// `one_builder.rs` reads the source for a copy.
pub(crate) fn pipeline(engine: &Engine, sources: &[&str], entry: &str) -> wgpu::ComputePipeline {
    pipeline_with(engine, sources, entry, &[])
}

/// [`pipeline`] with its sources' `override` constants named in
/// `constants` set; the rest keep their defaults.
pub(crate) fn pipeline_with(
    engine: &Engine,
    sources: &[&str],
    entry: &str,
    constants: &[(&str, f64)],
) -> wgpu::ComputePipeline {
    build(engine, sources, entry, constants, true)
}

/// The stack a compile of sources the engine did not write runs on.
/// 🔬D3D12's compiler runs in this process and takes stack with a shader's
/// size: a plugin of 48 thousand IR expressions and 80 loops overflowed
/// 4 MiB and compiled on 8, one of 12 thousand overflowed 1 MiB (Surface
/// Pro 11, release, 2026-11-08) — and Windows gives a process's main
/// thread 1 MiB. Reserved, not committed: only what the compile touches
/// is memory.
const FOREIGN_COMPILE_STACK: usize = 64 << 20;

/// [`pipeline`] of sources the engine did not write — a plugin's —, or why
/// the device would not take them: what its compiler and its pipeline
/// refuse is caught here, where wgpu would raise it on the device, and the
/// compile runs on a thread of its own, whose stack the compiler cannot
/// outgrow ([`FOREIGN_COMPILE_STACK`]) whatever thread asked — in the
/// engine's turn at the compiler, as its own kernels' are
/// (`CompilerTurn`, in `device.rs`).
pub(crate) fn pipeline_or_why(engine: &Engine, sources: &[&str], entry: &str) -> Result<wgpu::ComputePipeline, String> {
    waited_here();
    let (device, source, entry) = (engine.device.clone(), sources.join("\n"), entry.to_owned());
    engine.compiling(move |turn| {
        std::thread::scope(|scope| {
            let compile = std::thread::Builder::new()
                .name("foreign compile".into())
                .stack_size(FOREIGN_COMPILE_STACK)
                .spawn_scoped(scope, move || {
                    let refused = device.push_error_scope(wgpu::ErrorFilter::Validation);
                    let failed = device.push_error_scope(wgpu::ErrorFilter::Internal);
                    let pipeline = compiled(turn, &device, source, &entry, &[], true);
                    let failed = pollster::block_on(failed.pop());
                    let refused = pollster::block_on(refused.pop());
                    match failed.or(refused) {
                        Some(error) => Err(error.to_string()),
                        None => Ok(pipeline),
                    }
                })
                .map_err(|error| format!("no thread to compile on: {error}"))?;
            compile.join().unwrap_or_else(|_| Err("the device's compile panicked".to_string()))
        })
    })
}

/// [`pipeline`], its workgroup memory left as the device hands it — for a
/// shader that writes each word of it before any thread reads that word.
///
/// 🔬wgpu zeroes it at the top of every workgroup otherwise, and that was
/// the Gaussian's whole cost at a small reach: its 16 KiB window zeroed
/// took Blurriness 2 from 0.36 to 0.55 ms on the RTX 4080, past what the
/// shared window saved (gaussian-shared-rows, 2026-11-08). ⚠️A word read
/// before it is written would hold what the last workgroup left there.
pub(crate) fn pipeline_unzeroed(
    engine: &Engine,
    sources: &[&str],
    entry: &str,
) -> wgpu::ComputePipeline {
    build(engine, sources, entry, &[], false)
}

/// The engine's own pipeline of these: [`Kernel::pipeline`]'s.
fn build(
    engine: &Engine,
    sources: &[&str],
    entry: &str,
    constants: &[(&str, f64)],
    zeroed: bool,
) -> wgpu::ComputePipeline {
    Kernel::kept(engine, sources, entry, constants, zeroed).pipeline(engine).clone()
}

/// One of the engine's own kernels, compiled or still to be: the one it
/// has of these sources, entry and constants (`Kernels`, in `device.rs`).
/// Held so by what runs without it meanwhile and takes it up once it is
/// there ([`Kernel::compiled`]): the blur brush's strips, a dab going a
/// pass a dispatch till they are (`dab/blur.rs`).
pub(crate) struct Kernel {
    of: KernelSource,
    kept: Arc<OnceLock<wgpu::ComputePipeline>>,
}

impl Kernel {
    /// [`pipeline`]'s kernel, compiled only where the engine has it.
    pub(crate) fn of(engine: &Engine, sources: &[&str], entry: &str) -> Self {
        Self::kept(engine, sources, entry, &[], true)
    }

    fn kept(
        engine: &Engine,
        sources: &[&str],
        entry: &str,
        constants: &[(&str, f64)],
        zeroed: bool,
    ) -> Self {
        let of = KernelSource {
            source: sources.join("\n"),
            entry: entry.to_owned(),
            constants: constants
                .iter()
                .map(|&(name, value)| (name.to_owned(), value.to_bits()))
                .collect(),
            zeroed,
        };
        let kept = engine.kernels.slot(&of);
        Self { of, kept }
    }

    /// Its pipeline where the engine has it: whoever compiled it, through
    /// this one or another of the same sources.
    pub(crate) fn compiled(&self) -> Option<&wgpu::ComputePipeline> {
        self.kept.get()
    }

    /// Its pipeline, compiled on the engine's thread (`EngineThread`, in
    /// `device.rs`, says why) while the caller waits where the engine has
    /// none — and where another caller's compile of it is under way, waited
    /// for behind that one. A kernel the engine has is no thread's wait.
    pub(crate) fn pipeline(&self, engine: &Engine) -> &wgpu::ComputePipeline {
        if let Some(made) = self.kept.get() {
            return made;
        }
        let (device, of, kept) = (engine.device.clone(), self.of.clone(), Arc::clone(&self.kept));
        waited_here();
        let made = engine.compiling(move |turn| {
            let made = kept.get_or_init(|| {
                let constants: Vec<_> = of
                    .constants
                    .iter()
                    .map(|(name, bits)| (name.as_str(), f64::from_bits(*bits)))
                    .collect();
                compiled(turn, &device, of.source, &of.entry, &constants, of.zeroed)
            });
            made.clone()
        });
        self.kept.get_or_init(|| made)
    }
}

thread_local! {
    /// The kernels this thread has waited on a compile of
    /// ([`gpu_engine_kernels_built_here`]).
    static BUILT_HERE: Cell<u64> = const { Cell::new(0) };
}

/// One more kernel whose compile the calling thread waits on.
fn waited_here() {
    BUILT_HERE.with(|built| built.set(built.get() + 1));
}

/// How many kernels the calling thread has waited on a compile of since it
/// began — what the thread an app's frames are built on is not to do: a
/// compile is seconds on a slow device and the app stands still under it
/// (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦: 「UI 스레드가 직접
/// 하는 커널 컴파일 0개」; 🔬Surface Pro 11, S5 opening: eleven of them,
/// 15.2–15.5 s in all). The app's pin reads it there.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_kernels_built_here() -> u64 {
    BUILT_HERE.with(Cell::get)
}

/// The module and the pipeline of `source`, on the thread that asks — which
/// has the compiler to itself, by the turn it shows.
fn compiled(
    _turn: &CompilerTurn,
    device: &wgpu::Device,
    source: String,
    entry: &str,
    constants: &[(&str, f64)],
    zeroed: bool,
) -> wgpu::ComputePipeline {
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some(entry),
        source: wgpu::ShaderSource::Wgsl(source.into()),
    });
    device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(entry),
        layout: None,
        module: &module,
        entry_point: Some(entry),
        compilation_options: wgpu::PipelineCompilationOptions {
            constants,
            zero_initialize_workgroup_memory: zeroed,
            ..Default::default()
        },
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
