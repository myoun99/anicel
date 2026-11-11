//! A GPU fx plugin's run on the engine's device (fx spec 2 ㉯,
//! an-endless-plugin-stalls-the-app): the kernel fx_wgsl checked and
//! counted, compiled by the device with its checks on — an index past an
//! array's end is held at its last element, as the CPU's run holds it
//! (wgpu's `Restrict`) — and its workgroup memory zeroed (Q6 ⓒ), then
//! dispatched over the frame's output with the buffers its render reaches,
//! each holding the words fx_wgsl's frame binds there. The CPU's run of the
//! same kernel is the picture this one is held to (tests.rs).
//!
//! 🗣️-Q19 (유저 2026-11-10 16:36): 「화소 하나의 몫으로 고정하고, 그리기를
//! 덩어리로 나눠 넘긴다」 — the output is dispatched a chunk of workgroups
//! at a time, each chunk a submit of its own and as many groups as the
//! device finishes within a budget were each to spend its whole share
//! ([`pace`]), so no plugin keeps the device past it; the counted render
//! sees the ids of one dispatch of the whole (fx_wgsl's count.rs), its
//! chunk's first group in the frame. The cut is read after each chunk, and
//! a run cut stops there.

pub(crate) mod abi;
#[cfg(test)]
mod abi_tests;
mod pace;
#[cfg(test)]
mod tests;

use std::borrow::Cow;

use fx_wgsl::{CHUNK_WORD, CUT, Cut, FRAME, Frame, Kernel, OUTPUT, RENDER};

use crate::device::Engine;
use crate::kernels::shared::{Encoded, encode, fits, le_bytes, le_words, pipeline_or_why, whole, words_buffer};

pub(crate) use pace::Pace;

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

    /// The plugin's reach for `frame`'s values and moment, run on the CPU
    /// (fx_wgsl's `Kernel::reach`): the chain's plan asks it before a run.
    pub(crate) fn reach(&self, frame: &Frame<'_>) -> Result<u32, Cut> {
        self.kernel.reach(frame)
    }

    /// Runs the render over `frame`'s output into `output` — its pixels as
    /// the host started them, so a pixel nothing wrote keeps its word —, as
    /// the CPU's `Kernel::render` does, in chunks the device's pace sizes
    /// for `frame`'s share — for a kernel opened uncut, what the chunks are
    /// sized for alone; none where the device could not (the last error
    /// says why). A run cut leaves `output` as it was.
    pub(crate) fn render(&self, engine: &Engine, frame: &Frame<'_>, output: &mut [u32]) -> Option<Result<(), Cut>> {
        let [across, down, _] = self.kernel.workgroup_size();
        let most = Pace::of(engine)?.chunk(frame.fuel, across * down);
        self.run(engine, frame, output, most)
    }

    /// [`Self::render`] in chunks of `most` workgroups at most.
    fn run(&self, engine: &Engine, frame: &Frame<'_>, output: &mut [u32], most: u64) -> Option<Result<(), Cut>> {
        let bindings = self.kernel.bindings();
        let [across, down, _] = self.kernel.groups(frame);
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
                    let chunked = if bound.name == FRAME { wgpu::BufferUsages::COPY_DST } else { wgpu::BufferUsages::empty() };
                    words_buffer(engine, bound.name, words, kind | back | chunked)
                })
                .collect::<Vec<_>>()
        };
        let bound: Vec<_> = bindings.iter().zip(&buffers).map(|(bound, buffer)| (bound.number, buffer)).collect();
        let buffer = |name: &str| bindings.iter().position(|bound| bound.name == name).map(|at| &buffers[at]);
        let framed = buffer(FRAME).expect("every render reads its frame as it enters");
        let cut = buffer(CUT).expect("every render reads the cut as it enters");
        for (first, size) in chunks([across, down], most) {
            engine.queue.write_buffer(framed, 4 * CHUNK_WORD as u64, &le_bytes(&first));
            let groups = (size[0], size[1], 1);
            encode(engine, &[Encoded { pipeline: &self.pipeline, bound: whole(&bound), groups }]);
            if le_words(&engine.read_buffer(cut)?)[0] != 0 {
                return Some(Err(Cut));
            }
        }
        if let Some(written) = buffer(OUTPUT) {
            output.copy_from_slice(&le_words(&engine.read_buffer(written)?)[..output.len()]);
        }
        Some(Ok(()))
    }
}

/// The chunks a dispatch of `groups` — across, down — is cut into, `most`
/// workgroups each at most: rows of the groups across where `most` holds a
/// row, runs along a row where it does not. Each is its first group and
/// its groups across and down; every group lies in one of them.
fn chunks([across, down]: [u32; 2], most: u64) -> Vec<([u32; 2], [u32; 2])> {
    if across == 0 || down == 0 {
        return Vec::new();
    }
    let wide = u32::try_from(most.clamp(1, u64::from(across))).expect("no more than across");
    let high = u32::try_from((most / u64::from(wide)).clamp(1, u64::from(down))).expect("no more than down");
    (0..down)
        .step_by(high as usize)
        .flat_map(|top| {
            (0..across).step_by(wide as usize).map(move |left| ([left, top], [wide.min(across - left), high.min(down - top)]))
        })
        .collect()
}

/// `words` and zeros after them, [`LEAST_WORDS`] in all.
fn padded(words: &[u32]) -> Vec<u32> {
    let mut padded = words.to_vec();
    padded.resize(LEAST_WORDS, 0);
    padded
}
