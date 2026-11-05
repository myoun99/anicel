//! The export's conversions before the readback (gpu-export-path ①, 저장):
//! a frame the composite left in its output tiles, turned on the GPU into
//! the bytes its writer takes, so fewer cross to the CPU — the readback
//! was the largest single cost (960×540: 27 ms against the encoder's 5.5).
//!
//! - `nv12` — a movie's frame for its encoder (①a).
//! - `over_ground` — a still's frame over its format's background, for the
//!   writers that keep no alpha (①b).
//!
//! Each kernel reads the frame through `frame.wgsl`, after the shared
//! `tile.wgsl`.

// ⏳Nothing outside the tests calls it until the app's bridge round
// (gpu-export-path, 관제 16:26 — the app connects after the bridges).
#![cfg_attr(not(test), allow(dead_code))]

mod nv12;
mod over_ground;
#[cfg(test)]
mod tests;

pub(crate) use nv12::{Nv12, Nv12Shape};
pub(crate) use over_ground::{OverGround, OverGroundShape};

/// The frame read: `frame_word`.
const FRAME_WGSL: &str = include_str!("frame.wgsl");
