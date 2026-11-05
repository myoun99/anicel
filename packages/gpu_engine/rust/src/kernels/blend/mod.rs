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

/// Mode ids as blend.wgsl names them (`BLEND_*`, the C engine's stroke
/// table) — the ones Rust names, some of them in tests alone.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) mod mode {
    pub(crate) const BEHIND: u32 = 0;
    pub(crate) const MULTIPLY: u32 = 3;
    pub(crate) const SCREEN: u32 = 6;
    pub(crate) const OVERLAY: u32 = 8;
    pub(crate) const DIFFERENCE: u32 = 11;
    pub(crate) const LINEAR_BURN: u32 = 13;
    pub(crate) const SUBTRACT: u32 = 14;
    pub(crate) const DARKER_COLOR: u32 = 20;
    pub(crate) const LUMINOSITY: u32 = 25;
    pub(crate) const GLOW_ADD: u32 = 27;
    pub(crate) const NORMAL: u32 = 28;
}
