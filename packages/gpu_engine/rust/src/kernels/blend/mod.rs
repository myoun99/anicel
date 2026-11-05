//! The blend family (gpu-canonical-store ⑥): one integer formula for what a
//! dab piles, a stamp lands and a stroke or a row composites — every mode
//! of the C engine's stroke table, normal and the eraser. `blend.wgsl` has
//! the arithmetic and why each bound holds.
//!
//! It runs inside the kernels that blend: each prepends [`BLEND_WGSL`] to
//! its own source, so there is one copy of the formula on the GPU and none
//! on the CPU (`kernels/mod.rs`).

#[cfg(test)]
mod tests;

/// The blend family's functions, for a kernel that blends to prepend.
// No kernel prepends it yet: the stroke, stamp and row composites that will
// are the next rounds of gpu-canonical-store's order.
#[allow(dead_code)]
pub(crate) const BLEND_WGSL: &str = include_str!("blend.wgsl");
