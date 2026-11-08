//! A GPU fx plugin's run on the engine's device (fx spec 2 ㉯,
//! an-endless-plugin-stalls-the-app): the kernel fx_wgsl checked and
//! counted, compiled by the device with its checks on — an index past an
//! array's end is held at its last element, as the CPU's run holds it
//! (wgpu's `Restrict`) — and its workgroup memory zeroed (Q6 ⓒ), then
//! dispatched over the frame's output with the buffers its render reaches,
//! each holding the words fx_wgsl's frame binds there. The CPU's run of the
//! same kernel is the picture this one is held to (tests.rs).

// ⏳Reached only by tests until the app's seam asks it (㉯ ②: the
// `FxPluginRunner` on `appGpuEngine`, 관제 an-endless-plugin-stalls-the-app
// 17:00).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use std::borrow::Cow;

use fx_wgsl::{CUT, Cut, Frame, Kernel, OUTPUT, RENDER};

use crate::device::Engine;
use crate::kernels::shared::{Encoded, encode, fits, le_words, pipeline_or_why, whole, words_buffer};

/// The fewest words a host binding holds: the widest element of one, a
/// value's `vec4<i32>`. An empty picture or no values is bound so, its
/// count in the frame 0, so no word of it is read.
const LEAST_WORDS: usize = 4;

/// A plugin the device compiled.
pub(crate) struct Plugin {
    kernel: Kernel,
    pipeline: wgpu::ComputePipeline,
}

impl Plugin {
    /// Compiles `kernel` on `engine`'s device, or says why the device
    /// would not.
    pub(crate) fn open(engine: &Engine, kernel: Kernel) -> Result<Self, String> {
        let pipeline = pipeline_or_why(engine, &[kernel.source()], RENDER)?;
        Ok(Plugin { kernel, pipeline })
    }

    /// Runs the render over `frame`'s output into `output` — its pixels as
    /// the host started them, so a pixel nothing wrote keeps its word —, as
    /// the CPU's `Kernel::render` does; none where the device could not
    /// (the last error says why).
    pub(crate) fn render(&self, engine: &Engine, frame: &Frame<'_>, output: &mut [u32]) -> Option<Result<(), Cut>> {
        let bindings = self.kernel.bindings();
        let [across, down, deep] = self.kernel.groups(frame);
        let buffers = {
            let words: Vec<Cow<[u32]>> = bindings
                .iter()
                .map(|bound| {
                    let words = frame.bound(bound.name, output).expect("the prelude binds it");
                    if words.len() < LEAST_WORDS { Cow::Owned(padded(&words)) } else { words }
                })
                .collect();
            let bytes: Vec<u64> = words.iter().map(|words| 4 * words.len() as u64).collect();
            fits(engine, &bytes, std::iter::once((across, down)))?;
            bindings
                .iter()
                .zip(&words)
                .map(|(bound, words)| {
                    let kind = if bound.uniform { wgpu::BufferUsages::UNIFORM } else { wgpu::BufferUsages::STORAGE };
                    let back = if bound.written { wgpu::BufferUsages::COPY_SRC } else { wgpu::BufferUsages::empty() };
                    words_buffer(engine, bound.name, words, kind | back)
                })
                .collect::<Vec<_>>()
        };
        let bound: Vec<_> = bindings.iter().zip(&buffers).map(|(bound, buffer)| (bound.number, buffer)).collect();
        encode(engine, &[Encoded { pipeline: &self.pipeline, bound: whole(&bound), groups: (across, down, deep) }]);
        let mut cut = false;
        for (bound, buffer) in bindings.iter().zip(&buffers) {
            match bound.name {
                OUTPUT => output.copy_from_slice(&le_words(&engine.read_buffer(buffer)?)[..output.len()]),
                CUT => cut = le_words(&engine.read_buffer(buffer)?)[0] != 0,
                _ => {}
            }
        }
        Some(if cut { Err(Cut) } else { Ok(()) })
    }
}

/// `words` and zeros after them, [`LEAST_WORDS`] in all.
fn padded(words: &[u32]) -> Vec<u32> {
    let mut padded = words.to_vec();
    padded.resize(LEAST_WORDS, 0);
    padded
}
