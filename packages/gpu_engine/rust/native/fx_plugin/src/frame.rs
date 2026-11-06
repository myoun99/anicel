//! The frame a plugin reads (anicel_fx_plugin.h), laid by ONE WRITER. A
//! render lays one block — the frame, its values, its layers' places and
//! every picture's pixels — and the frame names each part by its distance
//! from itself, so the same bytes are right wherever the block lies: the
//! host's own memory for a native library, the room a module gave in its
//! linear memory for a .wasm (🗣️I-132-Q5).

use crate::job::{Head, Image, Job};

#[cfg(not(target_endian = "little"))]
compile_error!(
    "the frame is laid little-endian: WebAssembly's memory is, and so is every machine the app \
     runs on"
);

/// The spec version this host speaks (ANICEL_FX_SPEC_VERSION).
pub(crate) const SPEC_VERSION: u32 = 1;
/// Spec 1's one format (ANICEL_FX_RGBA8_PREMULTIPLIED).
const RGBA8_PREMULTIPLIED: u32 = 1;

// anicel_fx_frame's size and its fields' places: the numbers the header's
// ANICEL_FX_ASSERT lines hold every plugin's compiler to, and those they
// leave out where the fields' order puts them.
const FRAME: usize = 104;
const SPEC: usize = 0;
const FORMAT: usize = 4;
const INPUT: usize = 8;
const OUTPUT: usize = 32;
const VALUE_COUNT: usize = 56;
const VALUES: usize = 60;
const LAYER_COUNT: usize = 64;
const LAYERS: usize = 68;
const TIME: usize = 72;
const FRAME_RATE: usize = 80;
const SCALE: usize = 88;
const FRAME_INDEX: usize = 96;
/// anicel_fx_image: pixels, width, height, stride, left and top, a word each.
const IMAGE: usize = 24;
/// anicel_fx_value: four doubles.
const VALUE: usize = 32;

fn align16(at: usize) -> usize {
    (at + 15) & !15
}

/// Where each part of a render's block lies from the frame at 0, each on
/// 16 bytes.
pub(crate) struct Plan {
    values: usize,
    layers: usize,
    input: usize,
    output: usize,
    layer_pixels: usize,
    pub(crate) total: usize,
}

impl Plan {
    /// `job`'s; `None` past 4 GB, since every place in the frame is a 32-bit
    /// distance.
    pub(crate) fn of(job: &Job) -> Option<Self> {
        let values = align16(FRAME);
        let layers = align16(values + job.head.values.len() / 4 * VALUE);
        let input = align16(layers + job.layers.len() * IMAGE);
        let output = align16(input + job.input.packed_bytes());
        let layer_pixels = align16(output + job.input.packed_bytes());
        let total = job
            .layers
            .iter()
            .fold(layer_pixels, |at, layer| align16(at + layer.packed_bytes()));
        let plan = Self { values, layers, input, output, layer_pixels, total };
        (total <= u32::MAX as usize).then_some(plan)
    }
}

/// The bytes a reach's frame takes: its head and values, its images empty.
pub(crate) fn reach_size(head: &Head) -> usize {
    align16(FRAME) + head.values.len() / 4 * VALUE
}

/// Lays a reach's frame at the start of `block`.
pub(crate) fn lay_reach(block: &mut [u8], head: &Head) {
    Laying(block).head(head, align16(FRAME), (0, 0));
}

/// Lays `job` at the start of `block` by `plan`, the output's room cleared.
pub(crate) fn lay(block: &mut [u8], plan: &Plan, job: &Job) {
    let mut laying = Laying(block);
    laying.head(&job.head, plan.values, (job.layers.len(), plan.layers));
    laying.image(INPUT, plan.input, &job.input);
    laying.image(OUTPUT, plan.output, &job.input);
    laying.rows(plan.input, &job.input);
    laying.0[plan.output..][..job.input.packed_bytes()].fill(0);
    let mut at = plan.layer_pixels;
    for (index, layer) in job.layers.iter().enumerate() {
        laying.image(plan.layers + index * IMAGE, at, layer);
        laying.rows(at, layer);
        at = align16(at + layer.packed_bytes());
    }
}

/// Copies what the plugin put in `block`'s output into `job`'s.
pub(crate) fn take_output(block: &[u8], plan: &Plan, job: &mut Job) {
    let row = job.input.row_bytes();
    for y in 0..job.input.height as usize {
        job.output_row(y).copy_from_slice(&block[plan.output + y * row..][..row]);
    }
}

/// A block being laid, its places counted from the frame at its start.
struct Laying<'a>(&'a mut [u8]);

impl Laying<'_> {
    fn bytes(&mut self, at: usize, bytes: &[u8]) {
        self.0[at..at + bytes.len()].copy_from_slice(bytes);
    }

    fn word(&mut self, at: usize, word: u32) {
        self.bytes(at, &word.to_le_bytes());
    }

    fn double(&mut self, at: usize, double: f64) {
        self.bytes(at, &double.to_le_bytes());
    }

    /// Everything but the frame's images, which stay 0: its numbers, and the
    /// values laid at `values`.
    fn head(&mut self, head: &Head, values: usize, (layer_count, layers): (usize, usize)) {
        self.0[..FRAME].fill(0);
        self.word(SPEC, SPEC_VERSION);
        self.word(FORMAT, RGBA8_PREMULTIPLIED);
        self.word(VALUE_COUNT, (head.values.len() / 4) as u32);
        self.word(VALUES, values as u32);
        self.word(LAYER_COUNT, layer_count as u32);
        self.word(LAYERS, layers as u32);
        self.double(TIME, head.time);
        self.double(FRAME_RATE, head.frame_rate);
        self.double(SCALE, head.scale);
        self.word(FRAME_INDEX, head.frame_index as u32);
        for (index, &double) in head.values.iter().enumerate() {
            self.double(values + index * 8, double);
        }
    }

    /// `image`'s place in the frame at `at`, its pixels at `pixels`.
    fn image(&mut self, at: usize, pixels: usize, image: &Image) {
        let words = [
            pixels as u32,
            image.width,
            image.height,
            image.width * 4,
            image.left as u32,
            image.top as u32,
        ];
        for (index, word) in words.into_iter().enumerate() {
            self.word(at + index * 4, word);
        }
    }

    /// `image`'s rows at `at`, `width × 4` bytes apart.
    fn rows(&mut self, at: usize, image: &Image) {
        let row = image.row_bytes();
        for y in 0..image.height as usize {
            self.bytes(at + y * row, image.row(y));
        }
    }
}
