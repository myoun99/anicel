//! A selection's hard mask read back as its runs (runs.wgsl): where each
//! row's selected pixels start and end — what the app's CPU readers of a
//! selection ask (`CanvasSelectionRegion.pixelRunsFor`: its ants, the area
//! a shape fills, a cut from the viewer's picture). ↩️The app folded each
//! row's crossings itself in f64 (`_pixelRuns`), the engine's mask in Q.8
//! beside it: the ants could stand a pixel off what a lift moved.
//! ⛔RUNS, NOT BYTES: a selection's inverse covers the whole pasteboard
//! wall, ~35 MB at a byte a pixel (`pixel_run_contours.dart`, I-23) — the
//! runs are as many as its outline has rows.

#[cfg(test)]
#[path = "runs_tests.rs"]
mod tests;

use super::MaskBox;
use super::region::Folded;
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{Encoded, encode_on, fits, le_words, pipeline, plane, whole, words_buffer};

/// runs.wgsl's rows a workgroup, for the passes a thread a row.
const ROWS: u32 = 64;

/// The runs' passes, compiled once.
pub(crate) struct MaskRuns {
    count: wgpu::ComputePipeline,
    offsets: wgpu::ComputePipeline,
    put: wgpu::ComputePipeline,
}

/// A selection's runs over its box: row r's are `ends[offsets[r] ..
/// offsets[r + 1]]`, a start and an end in turn, columns from the box's
/// left — what the app reads (`gpu_engine_selection_runs`).
pub struct SelectionRuns {
    pub(crate) offsets: Vec<u32>,
    pub(crate) ends: Vec<u32>,
}

impl MaskRuns {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [include_str!("runs.wgsl")];
        let compile = |entry| pipeline(engine, &source, entry);
        Self {
            count: compile("runs_count"),
            offsets: compile("runs_offsets"),
            put: compile("runs_put"),
        }
    }

    /// `folded`'s runs over `size`, read back. Waits for the GPU once: the
    /// offsets and the room for the ends come back in one copy, the room
    /// read whole however few of it the runs fill. ↩️The offsets were read
    /// first and then as many ends as they said, a wait each (L2e).
    pub(crate) fn read(&self, engine: &Engine, folded: &Folded, size: MaskBox) -> Option<SelectionRuns> {
        let rows = size.height;
        // A binding holds a word at least: a box no edge crosses still has
        // room for one.
        let room = folded.crossings.max(1);
        let Ok(room_words) = u32::try_from(room) else {
            return fail(format!("{room} crossings exceed what a pass counts"));
        };
        let offset_bytes = (u64::from(rows) + 1) * 4;
        let a_row = (rows.div_ceil(ROWS), 1, 1);
        fits(engine, &[offset_bytes, room * 4], [(a_row.0, 1)].into_iter())?;
        let offsets = plane(engine, "runs offsets", offset_bytes);
        let ends = plane(engine, "runs", room * 4);
        let words = [rows, folded.stride, room_words, 0];
        let words = &words_buffer(engine, "runs", &words, wgpu::BufferUsages::UNIFORM);
        let counted = whole(&[(0, words), (1, &folded.plane), (2, &offsets)]);
        let laid = whole(&[(0, words), (2, &offsets)]);
        let put = whole(&[(0, words), (1, &folded.plane), (2, &offsets), (3, &ends)]);
        let readback = engine.readback(offset_bytes + room * 4);
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encode_on(
            engine,
            &mut encoder,
            &[
                Encoded { pipeline: &self.count, bound: counted, groups: a_row },
                Encoded { pipeline: &self.offsets, bound: laid, groups: (1, 1, 1) },
                Encoded { pipeline: &self.put, bound: put, groups: a_row },
            ],
        );
        encoder.copy_buffer_to_buffer(&offsets, 0, &readback, 0, offset_bytes);
        encoder.copy_buffer_to_buffer(&ends, 0, &readback, offset_bytes, room * 4);
        engine.queue.submit([encoder.finish()]);
        let mut read = vec![0; (offset_bytes + room * 4) as usize];
        engine.mapped_into(&readback, &mut read)?;
        let mut offsets = le_words(&read);
        let total = offsets[rows as usize];
        if total > room_words {
            return fail(format!("{total} runs' ends past the room of {room}"));
        }
        let mut ends = offsets.split_off(rows as usize + 1);
        ends.truncate(total as usize);
        Some(SelectionRuns { offsets, ends })
    }
}
