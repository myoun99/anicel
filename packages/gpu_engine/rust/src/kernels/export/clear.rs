//! Which pixels of a GIF are its clear colour (gpu-export-path ①c) —
//! `clear.wgsl` has the law.

use super::{Frame, Picture, Pipelines, Shown, out_plane, submit};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{
    Encoded, encode, fits, flat, room, rows_a_binding, whole, words_bound, words_buffer,
};

impl Picture {
    /// The bytes of its clear bits: whole words of 32 pixels each, the
    /// last filled out with 0.
    pub(crate) fn clear_bytes(&self) -> u64 {
        self.pixels().div_ceil(32) * 4
    }
}

/// The clear pass.
pub(crate) struct Clear {
    pub(super) pipelines: Pipelines,
}

impl Clear {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("clear.wgsl")], "clear_pass"),
        }
    }

    /// Marks the pixels of the picture in `frame` whose alpha is under
    /// `cut`, and submits the work; the caller waits. Returns the buffer of
    /// the bits ([`Picture::clear_bytes`] of them).
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: Frame,
        picture: Picture,
        cut: u8,
    ) -> Option<wgpu::Buffer> {
        self.run_by(engine, frame, (picture, cut), room(engine))
    }

    /// [`Self::run`], each pass binding no more than `room` bytes of a
    /// frame shown — a test's fewer than the device's, to see one read a
    /// band of rows at a time.
    ///
    /// 🚨A PASS BINDS THE ROWS ITS BITS' PIXELS LIE ON, NOT THE FRAME WHOLE
    /// (board conversions-bind-a-frame-past-the-device-limit, 2026-11-17): a
    /// bake reads a frame of the whole wall for where its ink is
    /// (`inkOfFrame`, baked_frame_ink.dart) — 139,332,960 bytes on the CI,
    /// refused past lavapipe's 128 MiB once the frame itself could be made.
    /// The bits are a 32nd of the frame and bound whole. A run's tiles are
    /// read as they were, whole.
    pub(super) fn run_by(
        &self,
        engine: &Engine,
        frame: Frame,
        (picture, cut): (Picture, u8),
        room: u64,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let row_words = picture.width.div_ceil(32);
        let params = |(first_row, base): (u32, u64)| {
            [
                frame.stride(picture),
                picture.width,
                picture.height,
                row_words,
                u32::from(cut),
                // Inside u32: a word of a frame the shader indexes.
                base as u32,
                first_row,
                0,
            ]
        };
        let groups = (row_words.div_ceil(64), picture.height);
        let out = out_plane(engine, "clear out", picture.clear_bytes(), groups)?;
        let pipeline = self.pipelines.of(engine, frame);
        let Frame::Shown(shown) = frame else {
            submit(engine, pipeline, &params((0, 0)), frame.buffer(), &out, groups)?;
            return Some(out);
        };
        let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);
        let bands = Bands::of(shown, picture, (room, step))?;
        let mut words = Vec::new();
        let mut bound = Vec::new();
        for band in &bands.0 {
            let (given, base) = words_bound(&shown.rows, band.words.clone(), step);
            words.push(words_buffer(
                engine,
                "clear params",
                &params((band.rows.start, base)),
                wgpu::BufferUsages::UNIFORM,
            ));
            bound.push(given);
        }
        let band_groups =
            |band: &Band| (row_words.div_ceil(64), band.rows.end - band.rows.start);
        fits(engine, &[], bands.0.iter().map(band_groups))?;
        let passes: Vec<Encoded> = words
            .iter()
            .zip(bound)
            .zip(&bands.0)
            .map(|((words, given), band)| {
                let mut entries = whole(&[(0, words), (2, &out)]);
                entries.push(wgpu::BindGroupEntry { binding: 1, resource: given });
                Encoded { pipeline, bound: entries, groups: flat(band_groups(band)) }
            })
            .collect();
        encode(engine, &passes);
        Some(out)
    }
}

/// A pass's part of the clear bits: its rows of words, as the dispatch
/// counts them, and the words of the frame their pixels lie on.
struct Band {
    rows: std::ops::Range<u32>,
    words: std::ops::Range<u64>,
}

/// The parts a frame shown is read in.
struct Bands(Vec<Band>);

impl Bands {
    /// `shown`'s picture in parts whose pixels' rows one binding of `room`
    /// bytes, begun on a multiple of `step`, holds wherever they start. A
    /// row of words is 32 pixels to the word, run on across the picture's
    /// rows; a part's pixels touch a row more than they fill. None, with
    /// why, where a row of words lies on more rows than a binding holds.
    fn of(shown: &Shown, picture: Picture, (room, step): (u64, u64)) -> Option<Self> {
        let (width, stride) = (u64::from(picture.width), u64::from(shown.stride));
        let row_pixels = u64::from(picture.width.div_ceil(32)) * 32;
        let rows = rows_a_binding(room, step, stride * 4)?;
        let per_band = rows.saturating_sub(1).saturating_mul(width) / row_pixels;
        if per_band == 0 {
            return fail(format!("a row of {row_pixels} clear bits exceeds a binding of {room}"));
        }
        let per_band = u32::try_from(per_band).unwrap_or(u32::MAX);
        let pixels = picture.pixels();
        // The word of the frame pixel `at` (row after row) lies in.
        let word = |at: u64| at / width * stride + at % width;
        let bands = (0..picture.height)
            .step_by(per_band as usize)
            .map(|first| first..first.saturating_add(per_band).min(picture.height))
            .take_while(|rows| u64::from(rows.start) * row_pixels < pixels)
            .map(|rows| {
                let first = u64::from(rows.start) * row_pixels;
                let last = (u64::from(rows.end) * row_pixels).min(pixels) - 1;
                Band { rows, words: word(first)..word(last) + 1 }
            })
            .collect();
        Some(Self(bands))
    }
}
