//! One way to encode a kernel's dispatches (관제 2026-11-06,
//! gpu-engine-skeleton; 브러시/렌더링 found the copies, 11-06 00:33).
//! `encode_on` in `dispatch.rs` makes each dispatch's bind group, opens one
//! compute pass and dispatches in order; a file of its own that opens
//! wgpu's compute pass is a copy of that, however different the text.

use super::source_scan::{assert_home_and_ledger, files_where};

/// What an encoder calls. In two halves, so this file is not one.
const CALL: &str = concat!("begin_compute", "_pass(");

/// The one encoder.
const HOME: &str = "kernels/shared/dispatch.rs";

/// The copies still standing, and whose they are.
const LEDGER: &[(&str, &str)] = &[
    ("kernels/blend/tests.rs", "브러시/렌더링"),
    ("kernels/shared/tests.rs", "브러시/렌더링"),
    ("kernels/effects/tests.rs", "캔버스 베이스 패널"),
    ("kernels/timeline/grid/mod.rs", "타임라인/콘티"),
    ("kernels/timeline/wave/mod.rs", "타임라인/콘티"),
];

#[test]
fn a_compute_pass_is_opened_by_encode_on_or_a_copy_on_the_ledger() {
    let found = files_where("rs", |text| text.contains(CALL));
    assert_home_and_ledger(found, HOME, LEDGER, "encode these with kernels::shared::encode_on");
}
