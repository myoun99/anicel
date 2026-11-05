//! The timeline's kernels (gpu-int-spec-timeline): a frame grid's tile
//! (`grid`), drawn from integers the app has already worked out, the same
//! on every device.

pub(crate) mod grid;

/// How it lays a colour (`laid.wgsl`), after the blend library.
pub(crate) const LAID_WGSL: &str = include_str!("laid.wgsl");
