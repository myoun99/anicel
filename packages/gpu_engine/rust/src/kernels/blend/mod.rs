//! The blend family (gpu-canonical-store ⑥): one integer formula for what a
//! dab piles, a stamp lands and a stroke or a row composites — every mode
//! of the C engine's stroke table, normal and the eraser. `blend.wgsl` has
//! the arithmetic and why each bound holds.
//!
//! It runs inside the kernels that blend: each prepends [`BLEND_WGSL`] to
//! its own source, after the shared files it needs, so there is one copy
//! of the formula on the GPU and none on the CPU (`kernels/mod.rs`).

#[cfg(test)]
mod tests;

/// The blend family's functions, for a kernel that blends to prepend after
/// [`ISQRT_WGSL`](crate::kernels::shared::ISQRT_WGSL).
pub(crate) const BLEND_WGSL: &str = include_str!("blend.wgsl");
