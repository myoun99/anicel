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
//! chunk's first group in the frame. The cut is read once a batch of
//! chunks ([`pace::Batches`]), and a run cut stops at the end of its batch.

pub(crate) mod abi;
#[cfg(test)]
mod abi_tests;
mod pace;
#[cfg(test)]
mod tests;
mod tiles;

use std::borrow::Cow;
use std::time::Instant;

use fx_wgsl::{Bound, CHUNK_WORD, CUT, Cut, FRAME, Frame, INPUT, Kernel, OUTPUT, RENDER, ROWS};

use crate::device::Engine;
use crate::kernels::effects::blur::TileRect;
use crate::kernels::shared::{
    Encoded, chunks, encode, fits, le_bytes, le_words, pipeline_or_why, plane, whole, words_buffer,
};

use pace::Batches;
pub(crate) use pace::{CHUNK_BUDGET, Pace};
pub(crate) use tiles::Tiled;
use tiles::Tiles;

/// The fewest words a host binding holds: the widest element of one, a
/// value's `vec4<i32>`. An empty picture or no values is bound so, its
/// count in the frame 0, so no word of it is read.
const LEAST_WORDS: usize = 4;

/// A plugin the device compiled, and the passes that hand it a chain's
/// tiles and lay what it made back on them ([`Tiles`]).
pub(crate) struct Plugin {
    kernel: Kernel,
    pipeline: wgpu::ComputePipeline,
    tiles: Tiles,
}

/// What a plug-in made over a chain's tiles ([`Plugin::render_tiled`]):
/// straight RGBA8 tiles over `rect`, the chain's rectangle, tile after tile
/// row by row — kept for the app to land in the pool (abi.rs).
pub(crate) struct PluginMade {
    pub(crate) rect: TileRect,
    pub(crate) tiles: wgpu::Buffer,
}

impl Plugin {
    /// Compiles `kernel` on `engine`'s device, or says why the device
    /// would not — the tile passes with it, so no render waits for one.
    pub(crate) fn open(engine: &Engine, kernel: Kernel) -> Result<Self, String> {
        let pipeline = pipeline_or_why(engine, &[kernel.source()], RENDER)?;
        let tiles = Tiles::of(engine);
        tiles.compile(engine);
        Ok(Plugin { kernel, pipeline, tiles })
    }

    /// The plugin's reach for `frame`'s values and moment, run on the CPU
    /// (fx_wgsl's `Kernel::reach`): the chain's plan asks it before a run.
    pub(crate) fn reach(&self, frame: &Frame<'_>) -> Result<u32, Cut> {
        self.kernel.reach(frame)
    }

    /// [`Self::run`] in chunks the device's pace sizes for `frame`'s share
    /// — for a kernel opened uncut, what the chunks are sized for alone:
    /// the tests' run from words, beside the CPU's.
    #[cfg(test)]
    pub(crate) fn render(&self, engine: &Engine, frame: &Frame<'_>, output: &mut [u32]) -> Option<Result<(), Cut>> {
        let most = self.most(engine, frame)?;
        self.run(engine, frame, output, most, Batches::default())
    }

    /// Runs the render over `frame`'s output into `output` — its pixels as
    /// the host started them, so a pixel nothing wrote keeps its word —, as
    /// the CPU's `Kernel::render` does, in chunks of `most` workgroups at
    /// most; none where the device could not (the last error says why). A
    /// run cut leaves `output` as it was. The run from words — what the
    /// pace's probe times ([`pace`]) and the tests hold to the CPU's: the
    /// app's runs are over a chain's tiles ([`Self::render_tiled`]), the
    /// chunks one loop for both ([`Self::chunked`]), in `batches`.
    fn run(
        &self,
        engine: &Engine,
        frame: &Frame<'_>,
        output: &mut [u32],
        most: u64,
        batches: Batches,
    ) -> Option<Result<(), Cut>> {
        let bindings = self.kernel.bindings();
        let words: Vec<Cow<[u32]>> = bindings
            .iter()
            .map(|bound| least(frame.bound(bound.name, output).expect("the prelude binds it")))
            .collect();
        let bytes: Vec<u64> = words.iter().map(|words| 4 * words.len() as u64).collect();
        let groups = self.fitting(engine, frame, &bytes)?;
        let buffers: Vec<_> = bindings
            .iter()
            .zip(&words)
            .map(|(bound, words)| words_buffer(engine, bound.name, words, usage(bound)))
            .collect();
        if let Err(cut) = self.chunked(engine, &bindings, &buffers, groups, most, batches)? {
            return Some(Err(cut));
        }
        if let Some(at) = bindings.iter().position(|bound| bound.name == OUTPUT) {
            output.copy_from_slice(&le_words(&engine.read_buffer(&buffers[at])?)[..output.len()]);
        }
        Some(Ok(()))
    }

    /// [`Self::render`] over pictures that stay on the device: `input`'s
    /// tiles and each of `rows`' — a layer's, by slot — read at `frame`'s
    /// input place (its `in_origin` and `in_size`; its `input` and `rows`
    /// words are not read), the output started clear, and what the render
    /// made at its output place laid on tiles over `input`'s rectangle,
    /// clear past it and wherever its alpha is 0 — what a chain lays of a
    /// plug-in's step (`Op::Put`). A place of `frame`'s lies `at` from its
    /// place on the tiles' grid: the plug-in is told the paper's pixels,
    /// the tiles lie on the canvas's. Submits the work; the caller waits
    /// for what it reads of the tiles.
    pub(crate) fn render_tiled(
        &self,
        engine: &Engine,
        frame: &Frame<'_>,
        at: [i32; 2],
        input: Tiled,
        rows: &[Tiled],
    ) -> Option<Result<wgpu::Buffer, Cut>> {
        let most = self.most(engine, frame)?;
        let place = |[left, top]: [i32; 2], [width, height]: [i32; 2]| {
            ([left + at[0], top + at[1], width, height], width.max(0) as u64 * height.max(0) as u64)
        };
        let (read, area) = place(frame.in_origin, frame.in_size);
        let (drawn, drawn_area) = place(frame.out_origin, frame.out_size);
        let bindings = self.kernel.bindings();
        // The words a binding is laid from, or none for a picture the
        // device holds.
        let words = |bound: &Bound| match bound.name {
            FRAME => Some(Cow::Owned(frame.words_of_layers(rows.len()))),
            INPUT | ROWS | OUTPUT => None,
            name => Some(least(frame.bound(name, &[]).expect("the prelude binds it"))),
        };
        let pictured = |words: u64| 4 * words.max(LEAST_WORDS as u64);
        let bytes: Vec<u64> = bindings
            .iter()
            .map(|bound| match (bound.name, words(bound)) {
                (_, Some(words)) => 4 * words.len() as u64,
                (ROWS, None) => pictured(area * rows.len() as u64),
                (OUTPUT, None) => pictured(drawn_area),
                (_, None) => pictured(area),
            })
            .collect();
        let groups = self.fitting(engine, frame, &bytes)?;
        // A new buffer is zeros: the output as the render starts it.
        let buffers: Vec<_> = bindings
            .iter()
            .zip(&bytes)
            .map(|(bound, &bytes)| match words(bound) {
                Some(words) => words_buffer(engine, bound.name, &words, usage(bound)),
                None => plane(engine, bound.name, bytes),
            })
            .collect();
        let buffer = |name: &str| bindings.iter().position(|bound| bound.name == name).map(|at| &buffers[at]);
        if let Some(planes) = buffer(INPUT) {
            self.tiles.rows_of(engine, input, read, planes, 0);
        }
        if let Some(planes) = buffer(ROWS) {
            for (slot, &row) in rows.iter().enumerate() {
                self.tiles.rows_of(engine, row, read, planes, (area * slot as u64) as u32);
            }
        }
        let batches = Batches::default();
        if let Err(cut) = self.chunked(engine, &bindings, &buffers, groups, most, batches)? {
            return Some(Err(cut));
        }
        let made = match buffer(OUTPUT) {
            Some(made) => made,
            // A render that writes no pixel made a clear picture.
            None => &plane(engine, OUTPUT, pictured(drawn_area)),
        };
        self.tiles.tiles_of(engine, made, 0, drawn, input.rect).map(Ok)
    }

    /// The most workgroups a chunk of a render over `frame` takes.
    fn most(&self, engine: &Engine, frame: &Frame<'_>) -> Option<u64> {
        let [across, down, _] = self.kernel.workgroup_size();
        Some(Pace::of(engine)?.chunk(frame.fuel, across * down))
    }

    /// The workgroups across and down a render over `frame` is dispatched
    /// over, where its bindings of `bytes` fit the device.
    fn fitting(&self, engine: &Engine, frame: &Frame<'_>, bytes: &[u64]) -> Option<[u32; 2]> {
        let [across, down, _] = self.kernel.groups(frame);
        fits(engine, bytes, std::iter::once((across, down)))?;
        Some([across, down])
    }

    /// Dispatches the render over `groups` with `bindings`' `buffers`, in
    /// chunks of `most` workgroups at most, each a submit of its own, the
    /// cut read once a batch of them (`batches`): a run cut stops at the
    /// end of its batch — a chunk after the cut enters with no share (the
    /// prelude's `anicel_host_enter`) and ends at its first charge. One
    /// loop whichever pictures the run is handed.
    ///
    /// ↩️The cut was read after every chunk till 11-17: a plug-in that
    /// spends next to nothing waited for the device as many times as its
    /// picture had chunks — 🔬main PC, the measuring scene with the
    /// fixture's invert on a row others wear, the band filled: 176 renders
    /// waited p50 33 times each (p90 48), 11.9 ms each on the engine's
    /// thread, where the band with the plug-in off waited 41 times in all
    /// (a-plugin-step-is-keyed-by-a-moment-it-may-not-read, 11-17).
    fn chunked(
        &self,
        engine: &Engine,
        bindings: &[Bound],
        buffers: &[wgpu::Buffer],
        groups: [u32; 2],
        most: u64,
        mut batches: Batches,
    ) -> Option<Result<(), Cut>> {
        let bound: Vec<_> = bindings.iter().zip(buffers).map(|(bound, buffer)| (bound.number, buffer)).collect();
        let buffer = |name: &str| bindings.iter().position(|bound| bound.name == name).map(|at| &buffers[at]);
        let framed = buffer(FRAME).expect("every render reads its frame as it enters");
        let cut = buffer(CUT).expect("every render reads the cut as it enters");
        let mut left = chunks(groups, most).into_iter().peekable();
        while left.peek().is_some() {
            let began = Instant::now();
            // A write is laid at the next submit, ahead of its work.
            for (first, size) in left.by_ref().take(batches.size()) {
                engine.queue.write_buffer(framed, 4 * CHUNK_WORD as u64, &le_bytes(&first));
                let groups = (size[0], size[1], 1);
                let chunk = Encoded { pipeline: &self.pipeline, bound: whole(&bound), groups };
                encode(engine, &[chunk]);
            }
            if le_words(&engine.read_buffer(cut)?)[0] != 0 {
                return Some(Err(Cut));
            }
            batches.took(began.elapsed());
        }
        Some(Ok(()))
    }
}

/// How the buffer of `bound` is made: a uniform or storage buffer, read
/// back where the run writes it, written a chunk at a time where it is the
/// frame.
fn usage(bound: &Bound) -> wgpu::BufferUsages {
    let kind = if bound.uniform { wgpu::BufferUsages::UNIFORM } else { wgpu::BufferUsages::STORAGE };
    let back = if bound.written { wgpu::BufferUsages::COPY_SRC } else { wgpu::BufferUsages::empty() };
    let chunked = if bound.name == FRAME { wgpu::BufferUsages::COPY_DST } else { wgpu::BufferUsages::empty() };
    kind | back | chunked
}

/// `words`, with zeros after them where they are fewer than
/// [`LEAST_WORDS`].
fn least(words: Cow<[u32]>) -> Cow<[u32]> {
    if words.len() >= LEAST_WORDS {
        return words;
    }
    let mut padded = words.into_owned();
    padded.resize(LEAST_WORDS, 0);
    Cow::Owned(padded)
}
