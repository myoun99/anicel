//! The vendored crates' maths is `libm`'s (유저 native-to-rust-Q14,
//! 2026-11-07): a sound decodes alike on every device, and Rust's float
//! methods — `sin` · `cos` · `powf` and the rest — call the device's own
//! maths library, which rounds its last place differently from OS to OS.
//! The audio pins (native/audio/src/tests/pins.rs) see a call left to the
//! device only on a device that rounds it otherwise, in CI; this reads the
//! vendored source for one, on any machine. `sqrt` is IEEE's, rounded
//! exactly everywhere, and `powi` multiplies, the same Rust on every target
//! — neither is the device's.

use super::source_scan::files_under;

/// The float methods that call the device's maths library.
const DEVICE_MATHS: [&str; 22] = [
    ".sin()", ".cos()", ".tan()", ".sin_cos()", ".asin()", ".acos()", ".atan()", ".atan2(",
    ".sinh()", ".cosh()", ".tanh()", ".exp()", ".exp2()", ".exp_m1()", ".ln()", ".ln_1p()",
    ".log(", ".log2()", ".log10()", ".powf(", ".cbrt()", ".hypot(",
];

/// Whether `text` calls one, as a method or as `f32::`/`f64::` does.
fn calls_device_maths(text: &str) -> bool {
    DEVICE_MATHS.iter().any(|call| {
        let name = call.trim_start_matches('.').trim_end_matches(['(', ')']);
        text.contains(call)
            || text.contains(&format!("f32::{name}("))
            || text.contains(&format!("f64::{name}("))
    })
}

#[test]
fn no_vendored_crate_leaves_its_maths_to_the_device() {
    assert!(calls_device_maths("(theta * k as f64).cos()"), "LIVENESS — a method call");
    assert!(calls_device_maths("f64::powf(2.0, x)"), "LIVENESS — a path call");
    assert!(!calls_device_maths("libm::cos(theta * k as f64)"), "libm's is not the device's");
    let reached = files_under("vendor", "rs", |text| text.contains("libm::"));
    assert!(
        reached.contains("symphonia-codec-aac/src/aac/window.rs"),
        "LIVENESS — the scan reads the vendored crates: {reached:?}"
    );
    let left = files_under("vendor", "rs", calls_device_maths);
    assert!(left.is_empty(), "call `libm` there, as the workspace's [patch] says: {left:?}");
}
