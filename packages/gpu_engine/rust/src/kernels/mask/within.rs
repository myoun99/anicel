//! A mask cut by another (within.wgsl): whole where both hold any of the
//! pixel, nothing elsewhere — a fill's range as its mark shows it under a
//! selection (the app's `FillRange.coveredWithin`). ↩️The app cut it on
//! the CPU, reading the selection's bytes over the range's box at every
//! region a held fill's press reached (`SelectionClip.maskFor`), and
//! handed the cut up to be marked under.

#[cfg(test)]
#[path = "within_tests.rs"]
mod tests;

use super::{BYTE_WGSL, Mask};
use crate::device::Engine;
use crate::kernels::shared::{Encoded, encode, fits, flat, pipeline, plane, whole, words_buffer};

/// The cut's pass, compiled once.
pub(crate) struct MaskWithin {
    pass: wgpu::ComputePipeline,
}

impl MaskWithin {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [BYTE_WGSL, include_str!("within.wgsl")];
        Self { pass: pipeline(engine, &source, "mask_within") }
    }

    /// `mask` cut by `by`: a new plane over `mask`'s box, whole where both
    /// hold any of the pixel and 0 elsewhere — `by` read where it lies on
    /// the canvas, nothing past its box. Submits the work; the caller
    /// waits.
    pub(crate) fn cut(&self, engine: &Engine, mask: &Mask, by: &Mask) -> Option<wgpu::Buffer> {
        let size = mask.size;
        size.held_by(mask.plane)?;
        by.checked()?;
        fits(engine, &[size.bytes(), by.size.bytes()], std::iter::once(size.groups(4)))?;
        let put = plane(engine, "mask within", size.bytes());
        let (dx, dy) = (mask.at.0 - by.at.0, mask.at.1 - by.at.1);
        let words = [
            size.width,
            size.height,
            size.stride(),
            dx.cast_unsigned(),
            dy.cast_unsigned(),
            by.size.width,
            by.size.height,
            by.size.stride(),
        ];
        let words = &words_buffer(engine, "mask within", &words, wgpu::BufferUsages::UNIFORM);
        let bound = [(0, words), (1, mask.plane), (2, &put), (3, by.plane)];
        let groups = flat(size.groups(4));
        encode(engine, &[Encoded { pipeline: &self.pass, bound: whole(&bound), groups }]);
        Some(put)
    }
}
