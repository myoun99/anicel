//! One buffer filler (브러시/렌더링 2026-11-11, the lost-device lane).
//! `Engine::filled` in `device.rs` makes a buffer of bytes. wgpu's own
//! helper of that name panics where the device is gone — on its caller's
//! thread, which is the app's, and a panic there ends the process
//! (`Refusals`, in `device.rs`, has the measurement). Its ledger started
//! empty: the eight callers in the kernels and the seven in their tests
//! went to the one filler in the change that made it.

use super::source_scan::{assert_home_and_ledger, files_where};

/// What wgpu's helper is called. Spelled in two halves, so this file is
/// not one.
const CALL: &str = concat!("create_buffer", "_init");

/// The one filler, and the test that holds it to wgpu's bytes.
const FILLER: &str = "device.rs";

#[test]
fn a_buffer_of_bytes_is_filled_by_the_one_filler_or_a_copy_on_the_ledger() {
    let found = files_where("rs", |text| text.contains(CALL));
    assert_home_and_ledger(found, FILLER, &[], "fill these with Engine::filled");
}
