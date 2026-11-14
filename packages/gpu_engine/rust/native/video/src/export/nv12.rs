//! A frame handed as NV12, laid into the buffer an encoder takes: an
//! export's as the GPU engine made it (gpu_engine `kernels/export/nv12`) —
//! the colour law's bytes already, the kernel making what
//! `colour::from_rgba` makes, held to it byte for byte by the kernel's
//! tests — or a trimmed piece's as its movie's decoder made it
//! (`colour::nv12_of`). All that is left here is where they lie: no sum
//! (gpu-export-path ⑶, 2026-11-12).

use super::set_error;
use crate::colour::Planes;

/// An NV12 frame as the engine reads it back: `height` Y rows, then
/// `height / 2` CbCr rows, each `stride` bytes after the last, the first
/// `width` bytes of a row the frame's.
pub struct Nv12<'a> {
    pub bytes: &'a [u8],
    pub stride: usize,
    pub width: usize,
    pub height: usize,
}

impl<'a> Nv12<'a> {
    /// The frame of `width` × `height` over `bytes` with rows `stride`
    /// apart — or none where they cannot hold it: a stride short of the
    /// width, an odd size (an encoder's frame is even), or too few bytes.
    pub fn over(bytes: &'a [u8], stride: usize, width: usize, height: usize) -> Option<Self> {
        let holds = stride >= width && width % 2 == 0 && height % 2 == 0;
        (holds && bytes.len() >= Self::bytes_of(stride, height)).then_some(Self { bytes, stride, width, height })
    }

    /// How many bytes a frame of `height` rows `stride` apart is.
    pub fn bytes_of(stride: usize, height: usize) -> usize {
        stride * height * 3 / 2
    }
}

/// The frame of the open writer's `width` × `height` that a caller handed
/// at `bytes`, rows `stride` apart — or none, and the error says so, where
/// it cannot hold one ([`Nv12::over`]). Every writer that takes NV12 reads
/// what it was handed here.
///
/// # Safety
/// `bytes` holds `Nv12::bytes_of(stride, height)` bytes, for as long as
/// the frame is read.
#[cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]
pub unsafe fn handed<'a>(bytes: *const u8, stride: usize, width: usize, height: usize) -> Option<Nv12<'a>> {
    // SAFETY: the caller's contract.
    let bytes = unsafe { std::slice::from_raw_parts(bytes, Nv12::bytes_of(stride, height)) };
    let frame = Nv12::over(bytes, stride, width, height);
    if frame.is_none() {
        set_error("video export: an NV12 frame of another shape");
    }
    frame
}

/// `frame` laid into `planes`, the frame's own size: its Y rows as they
/// are, and each CbCr pair where the planes lay chroma — side by side
/// (NV12: `chroma_step` 2, `cr` one past `cb`) a row at a time, apart
/// (I420: two planes) a pair at a time.
pub fn lay(frame: &Nv12, planes: &mut Planes) {
    let Nv12 { bytes, stride, width, height } = *frame;
    for y in 0..height {
        planes.y[y * planes.y_stride..][..width].copy_from_slice(&bytes[y * stride..][..width]);
    }
    let chroma = &bytes[stride * height..];
    let side_by_side = planes.chroma_step == 2 && planes.cr == planes.cb + 1;
    for y in 0..height / 2 {
        let row = &chroma[y * stride..][..width];
        let at = y * planes.chroma_stride;
        if side_by_side {
            planes.chroma[planes.cb + at..][..width].copy_from_slice(row);
            continue;
        }
        for (x, pair) in row.chunks_exact(2).enumerate() {
            planes.chroma[planes.cb + at + x * planes.chroma_step] = pair[0];
            planes.chroma[planes.cr + at + x * planes.chroma_step] = pair[1];
        }
    }
}

#[cfg(test)]
#[path = "nv12_tests.rs"]
mod tests;
