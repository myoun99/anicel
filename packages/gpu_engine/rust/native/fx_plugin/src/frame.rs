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

#[cfg(test)]
mod tests {
    use super::{Plan, lay, lay_reach, take_output};
    use crate::job::{Picture, RenderJob, read};

    fn word(block: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(block[at..at + 4].try_into().expect("four bytes"))
    }

    fn double(block: &[u8], at: usize) -> f64 {
        f64::from_le_bytes(block[at..at + 8].try_into().expect("eight bytes"))
    }

    /// The six words of the image whose place in the frame is `at`.
    fn image(block: &[u8], at: usize) -> [u32; 6] {
        std::array::from_fn(|index| word(block, at + index * 4))
    }

    fn picture(pixels: &[u8], (width, height, stride): (i32, i32, i32), at: (i32, i32)) -> Picture {
        Picture { pixels: pixels.as_ptr(), width, height, stride, left: at.0, top: at.1 }
    }

    /// A render and then a reach laid in one room of stale bytes, read back
    /// by the header's own numbers (anicel_fx_plugin.h: the frame 104 bytes,
    /// input at 8, output at 32, value_count at 56, layer_count at 64, time
    /// at 72, frame_index at 96; an image 24 bytes, a value 32): every part
    /// where the frame says, each on 16 bytes and none on another, the
    /// pictures packed, the output cleared — and the reach's images empty,
    /// nothing of the render left in its frame.
    #[test]
    fn a_frame_is_laid_where_the_spec_says_and_keeps_nothing_of_the_last() {
        let input: Vec<u8> = (0..32).collect();
        let first: Vec<u8> = (100..112).collect();
        let second: Vec<u8> = (200..212).collect();
        let layers = [picture(&first, (2, 1, 12), (5, -6)), picture(&second, (1, 2, 8), (-7, 8))];
        let values = [1.5, 2.5, 3.5, 4.5, -1.0, 0.25, 0.0, 9.0];
        let mut out = vec![0xEE; 2 * 16];
        let job = RenderJob {
            input: picture(&input, (3, 2, 16), (-4, 7)),
            output: out.as_mut_ptr(),
            output_stride: 16,
            value_count: 2,
            values: values.as_ptr(),
            layers: layers.as_ptr(),
            layer_count: 2,
            frame_index: 9,
            time: 0.375,
            frame_rate: 24.0,
            scale: 0.5,
        };
        // SAFETY: every pointer holds what it says.
        let mut job = unsafe { read(&job) }.expect("a job");
        let plan = Plan::of(&job).expect("a plan");
        let mut block = vec![0x5A; plan.total];
        lay(&mut block, &plan, &job);

        assert_eq!([word(&block, 0), word(&block, 4)], [1, 1], "spec 1, RGBA8 premultiplied");
        assert_eq!([word(&block, 56), word(&block, 64)], [2, 2], "two values, two layers");
        let at_72 = [72, 80, 88].map(|at| double(&block, at));
        assert_eq!(at_72, [0.375, 24.0, 0.5], "time, frame rate, scale");
        assert_eq!([word(&block, 96), word(&block, 100)], [9, 0], "the index; reserved");
        let (values_at, layers_at) = (word(&block, 60) as usize, word(&block, 68) as usize);
        let laid: Vec<f64> = (0..8).map(|index| double(&block, values_at + index * 8)).collect();
        assert_eq!(laid, values);

        let [input_at, w, h, stride, left, top] = image(&block, 8);
        assert_eq!([w, h, stride, left, top], [3, 2, 12, -4i32 as u32, 7], "the input");
        let input_at = input_at as usize;
        assert_eq!(block[input_at..input_at + 12], input[..12]);
        assert_eq!(block[input_at + 12..input_at + 24], input[16..28]);
        let [output_at, w, h, stride, left, top] = image(&block, 32);
        assert_eq!([w, h, stride, left, top], [3, 2, 12, -4i32 as u32, 7], "the output");
        let output_at = output_at as usize;
        assert!(block[output_at..output_at + 24].iter().all(|&byte| byte == 0), "cleared");

        let [first_at, w, h, stride, left, top] = image(&block, layers_at);
        assert_eq!([w, h, stride, left, top], [2, 1, 8, 5, -6i32 as u32], "the first layer");
        let [second_at, w, h, stride, left, top] = image(&block, layers_at + 24);
        assert_eq!([w, h, stride, left, top], [1, 2, 4, -7i32 as u32, 8], "the second layer");
        let (first_at, second_at) = (first_at as usize, second_at as usize);
        assert_eq!(block[first_at..first_at + 8], first[..8]);
        assert_eq!(block[second_at..second_at + 8], [200, 201, 202, 203, 208, 209, 210, 211]);

        let mut parts = [
            (values_at, 64),
            (layers_at, 48),
            (input_at, 24),
            (output_at, 24),
            (first_at, 8),
            (second_at, 8),
        ];
        parts.sort();
        assert!(parts[0].0 >= 104, "after the frame");
        assert!(parts.iter().all(|&(at, _)| at % 16 == 0), "on 16 bytes: {parts:?}");
        assert!(parts.windows(2).all(|two| two[0].0 + two[0].1 <= two[1].0), "{parts:?}");
        let (last, bytes) = parts[5];
        assert!(last + bytes <= plan.total, "inside the plan");

        let answer: Vec<u8> = (0..24).map(|byte| byte + 50).collect();
        block[output_at..output_at + 24].copy_from_slice(&answer);
        take_output(&block, &plan, &mut job);
        drop(job);
        assert_eq!(out[..12], answer[..12]);
        assert_eq!(out[16..28], answer[12..]);
        assert!(out[12..16].iter().chain(&out[28..]).all(|&byte| byte == 0xEE), "padding");

        let head = crate::job::Head {
            values: &values[..4],
            frame_index: -2,
            time: 1.25,
            frame_rate: 12.0,
            scale: 2.0,
        };
        lay_reach(&mut block, &head);
        assert_eq!([word(&block, 0), word(&block, 4), word(&block, 56)], [1, 1, 1]);
        assert_eq!([word(&block, 64), word(&block, 68)], [0, 0], "no layers");
        assert!(block[8..56].iter().all(|&byte| byte == 0), "the images empty");
        assert_eq!([72, 80, 88].map(|at| double(&block, at)), [1.25, 12.0, 2.0]);
        assert_eq!([word(&block, 96), word(&block, 100)], [-2i32 as u32, 0]);
        let values_at = word(&block, 60) as usize;
        assert!(values_at >= 104 && values_at % 16 == 0, "after the frame, on 16 bytes");
        let laid: Vec<f64> = (0..4).map(|index| double(&block, values_at + index * 8)).collect();
        assert_eq!(laid, values[..4]);
    }
}
