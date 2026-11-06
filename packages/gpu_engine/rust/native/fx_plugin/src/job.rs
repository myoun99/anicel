//! What the app hands the host (qa_fx_plugin.h) as the Dart structs that
//! mirror it lay it (`QaFxPictureStruct` · `QaFxRenderJobStruct`,
//! lib/src/native/qa_fx_plugin_host.dart), and the one place its pointers
//! become slices.

/// A picture the app hands a plugin or takes back: premultiplied RGBA8,
/// rows top to bottom, `stride` bytes apart. `left` · `top` place its first
/// pixel on the canvas (anicel_fx_image).
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Picture {
    pub pixels: *const u8,
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub left: i32,
    pub top: i32,
}

/// One render: the row's picture (the reach included), where the result
/// goes (the input's size, `output_stride` bytes a row), the values in the
/// description's order — four doubles each (anicel_fx_value) — and the
/// pictures of the rows its layer parameters name.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct RenderJob {
    pub input: Picture,
    pub output: *mut u8,
    pub output_stride: i32,
    pub value_count: i32,
    pub values: *const f64,
    pub layers: *const Picture,
    pub layer_count: i32,
    pub frame_index: i32,
    pub time: f64,
    pub frame_rate: f64,
    pub scale: f64,
}

/// What a render or a question answers besides a length.
pub const OK: i32 = 0;
/// A size or a pointer the job cannot have.
pub const BAD_JOB: i32 = -1;
/// The plugin answered non-zero.
pub const FAILED: i32 = -2;
/// A .wasm trapped, or a call into it failed.
pub const TRAPPED: i32 = -3;
/// No memory for the frame.
pub const NO_ROOM: i32 = -4;

/// A picture's pixels as a plugin is handed them: `width × 4` bytes a row.
pub(crate) struct Image<'a> {
    rows: &'a [u8],
    stride: usize,
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) left: i32,
    pub(crate) top: i32,
}

impl Image<'_> {
    pub(crate) fn row_bytes(&self) -> usize {
        self.width as usize * 4
    }

    pub(crate) fn packed_bytes(&self) -> usize {
        self.row_bytes() * self.height as usize
    }

    pub(crate) fn row(&self, y: usize) -> &[u8] {
        &self.rows[y * self.stride..][..self.row_bytes()]
    }
}

/// A frame's numbers besides its pictures: what a reach and a render are
/// both handed.
pub(crate) struct Head<'a> {
    /// Four doubles a value.
    pub(crate) values: &'a [f64],
    pub(crate) frame_index: i32,
    pub(crate) time: f64,
    pub(crate) frame_rate: f64,
    pub(crate) scale: f64,
}

/// A render the host can take, its pointers read as slices.
pub(crate) struct Job<'a> {
    pub(crate) input: Image<'a>,
    output: &'a mut [u8],
    output_stride: usize,
    pub(crate) head: Head<'a>,
    pub(crate) layers: Vec<Image<'a>>,
}

impl Job<'_> {
    /// Row `y` of the output, its `width × 4` bytes and not its padding.
    pub(crate) fn output_row(&mut self, y: usize) -> &mut [u8] {
        let row = self.input.row_bytes();
        &mut self.output[y * self.output_stride..][..row]
    }
}

fn is_whole(picture: &Picture) -> bool {
    !picture.pixels.is_null()
        && picture.width > 0
        && picture.height > 0
        && i64::from(picture.stride) >= i64::from(picture.width) * 4
}

/// Whether `job` names pictures and values a render can take — sizes only,
/// nothing read yet.
pub(crate) fn is_whole_job(job: &RenderJob) -> bool {
    is_whole(&job.input)
        && !job.output.is_null()
        && i64::from(job.output_stride) >= i64::from(job.input.width) * 4
        && job.value_count >= 0
        && (job.value_count == 0 || !job.values.is_null())
        && job.layer_count >= 0
        && (job.layer_count == 0 || !job.layers.is_null())
        // SAFETY: a job's layers are `layer_count` pictures (qa_fx_plugin.h).
        && unsafe { layers(job) }.iter().all(is_whole)
}

/// # Safety
/// `job.layers` holds `job.layer_count` pictures when that is above 0.
unsafe fn layers(job: &RenderJob) -> &[Picture] {
    if job.layer_count <= 0 {
        return &[];
    }
    // SAFETY: the caller's contract.
    unsafe { std::slice::from_raw_parts(job.layers, job.layer_count as usize) }
}

/// The bytes a picture's rows span, first pixel to last: `None` where that
/// is more than a slice can be.
fn span(height: i32, stride: i32, width: i32) -> Option<usize> {
    let before_last = usize::try_from(height - 1).ok()?.checked_mul(stride as usize)?;
    let bytes = before_last.checked_add(width as usize * 4)?;
    (bytes <= isize::MAX as usize).then_some(bytes)
}

/// # Safety
/// `picture` is whole, and its pixels hold every row it names.
unsafe fn image(picture: &Picture) -> Option<Image<'_>> {
    let bytes = span(picture.height, picture.stride, picture.width)?;
    Some(Image {
        // SAFETY: the caller's contract.
        rows: unsafe { std::slice::from_raw_parts(picture.pixels, bytes) },
        stride: picture.stride as usize,
        width: picture.width as u32,
        height: picture.height as u32,
        left: picture.left,
        top: picture.top,
    })
}

/// `job`'s pictures and values as slices; `None` where they span more than
/// a slice can.
///
/// # Safety
/// `job` is whole ([`is_whole_job`]), and each of its pointers holds what
/// qa_fx_plugin.h says it holds: every row of each picture, the output's
/// rows `output_stride` apart, and `value_count` values of four doubles.
pub(crate) unsafe fn read(job: &RenderJob) -> Option<Job<'_>> {
    let input = &job.input;
    let output = span(input.height, job.output_stride, input.width)?;
    // SAFETY: the caller's contract, for each.
    unsafe {
        Some(Job {
            input: image(input)?,
            output: std::slice::from_raw_parts_mut(job.output, output),
            output_stride: job.output_stride as usize,
            head: Head {
                values: values(job.values, job.value_count),
                frame_index: job.frame_index,
                time: job.time,
                frame_rate: job.frame_rate,
                scale: job.scale,
            },
            layers: layers(job).iter().map(|layer| image(layer)).collect::<Option<_>>()?,
        })
    }
}

/// `count` values of four doubles at `values`.
///
/// # Safety
/// `count` is not below 0, and `values` holds that many values when it is
/// above 0 — none may come with a null pointer, which no slice may hold.
pub(crate) unsafe fn values<'a>(values: *const f64, count: i32) -> &'a [f64] {
    match count {
        0 => &[],
        // SAFETY: the caller's contract.
        count => unsafe { std::slice::from_raw_parts(values, count as usize * 4) },
    }
}
