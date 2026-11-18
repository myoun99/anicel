//! The sample plugin (invert.rs) with no render, which a host must refuse:
//! its other exports by hand, the spec crate's glue under them.

// The checkout this example is built from (lib.rs says why).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod invert;

use anicel_fx::{Frame, glue};
use invert::Invert;

#[unsafe(no_mangle)]
pub extern "C" fn anicel_fx_spec() -> u32 {
    anicel_fx::SPEC_VERSION
}

/// # Safety
/// `out` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anicel_fx_describe(out: *mut u8, capacity: u32) -> u32 {
    // SAFETY: the caller's contract.
    unsafe { glue::describe::<Invert>(out, capacity) }
}

/// # Safety
/// `frame` is a frame the host laid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anicel_fx_reach(frame: *const Frame) -> u32 {
    // SAFETY: the caller's contract.
    unsafe { glue::reach::<Invert>(frame) }
}
