//! The engine's maths is `libm`'s (유저 native-to-rust-Q14, 2026-11-07):
//! a sound decodes alike on every device, and Rust's float methods — `sin`
//! · `cos` · `powf` and the rest — call the device's own maths library,
//! which rounds its last place differently from OS to OS. The audio pins
//! (native/audio/src/tests/pins.rs) see a call left to the device only on a
//! device that rounds it otherwise, in CI; this reads the source for one,
//! on any machine. `sqrt` is IEEE's, rounded exactly everywhere, and `powi`
//! multiplies, the same Rust on every target — neither is the device's.
//!
//! ↩️It read the vendored crates alone till 2026-11-17, when a glyph's
//! outline was found measured by the device's `hypot` in the engine's own
//! source (board `linux-libm-hands-the-engine-other-last-bits`): it reads
//! the crate, its workspace's crates and the vendored ones. A test's own
//! maths is left out — what it works out to check within a tolerance never
//! ships — ⚠️but one that hands the device's to a pinned fingerprint goes
//! red on the device that rounds otherwise, in CI, as the app's did.

use std::collections::BTreeSet;

use super::source_scan::files_under;

/// The float methods that call the device's maths library.
const DEVICE_MATHS: [&str; 22] = [
    ".sin()", ".cos()", ".tan()", ".sin_cos()", ".asin()", ".acos()", ".atan()", ".atan2(",
    ".sinh()", ".cosh()", ".tanh()", ".exp()", ".exp2()", ".exp_m1()", ".ln()", ".ln_1p()",
    ".log(", ".log2()", ".log10()", ".powf(", ".cbrt()", ".hypot(",
];

/// The shipped files the device's maths is left to, each with why its bits
/// part no two devices.
const LEFT_TO_THE_DEVICE: [(&str, &str); 1] = [(
    "native/video/src/decode/apple.rs",
    "a movie's turn read off its matrix and rounded to whole degrees — on Apple's decoder alone",
)];

/// Whether `text` calls one, as a method or as `f32::`/`f64::` does.
fn calls_device_maths(text: &str) -> bool {
    DEVICE_MATHS.iter().any(|call| {
        let name = call.trim_start_matches('.').trim_end_matches(['(', ')']);
        text.contains(call)
            || text.contains(&format!("f32::{name}("))
            || text.contains(&format!("f64::{name}("))
    })
}

/// Whether the file at `path` is a test's — `tests.rs`, `…_tests.rs`, or
/// under a `tests` folder — or this scan's own, whose list names each call.
fn is_left_out(path: &str) -> bool {
    path.ends_with("tests.rs") || path.contains("/tests/") || path == "src/kernels/shared/one_maths.rs"
}

#[test]
fn no_engine_source_leaves_its_maths_to_the_device() {
    assert!(calls_device_maths("(theta * k as f64).cos()"), "LIVENESS — a method call");
    assert!(calls_device_maths("f64::powf(2.0, x)"), "LIVENESS — a path call");
    assert!(!calls_device_maths("libm::cos(theta * k as f64)"), "libm's is not the device's");
    assert!(is_left_out("native/audio/src/tests/pins.rs") && is_left_out("src/kernels/composite/screen_tests.rs"));
    assert!(!is_left_out("src/kernels/letters/glyphs.rs"));
    let reached = files_under(".", "rs", |_| true);
    for file in [
        "vendor/symphonia-codec-aac/src/aac/window.rs",
        "src/kernels/letters/glyphs.rs",
        "native/audio_mix/src/resample.rs",
    ] {
        assert!(reached.contains(file), "LIVENESS — the scan reads {file}");
    }
    let left: BTreeSet<String> =
        files_under(".", "rs", calls_device_maths).into_iter().filter(|path| !is_left_out(path)).collect();
    let ledgered: BTreeSet<String> = LEFT_TO_THE_DEVICE.iter().map(|(path, _)| (*path).to_owned()).collect();
    assert_eq!(
        left, ledgered,
        "call `libm` there — the same Rust on every OS, as the workspace's [patch] says for the vendored \
         crates; where the device's IS meant, the file goes in LEFT_TO_THE_DEVICE, with why"
    );
    for (path, why) in LEFT_TO_THE_DEVICE {
        assert!(why.len() > 20, "{path} says why the device's is meant");
    }
}
