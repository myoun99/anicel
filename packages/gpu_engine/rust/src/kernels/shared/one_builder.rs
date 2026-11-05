//! One pipeline builder (관제 2026-11-05, gpu-engine-skeleton; 저장 found
//! the copies). `pipeline` beside this file joins a kernel's sources and
//! makes its module and its pipeline; a file of its own that calls
//! wgpu's `create_compute_pipeline` is a copy of that, however different
//! the text. Its ledger started with seven copies and was empty by 11-06.

use super::source_scan::{assert_home_and_ledger, files_where};

/// What a builder calls. Spelled in two halves, so this file is not one.
const CALL: &str = concat!("create_compute", "_pipeline(");

/// The one builder.
const BUILDER: &str = "kernels/shared/mod.rs";

#[test]
fn a_compute_pipeline_is_built_by_the_one_builder_or_a_copy_on_the_ledger() {
    let found = files_where("rs", |text| text.contains(CALL));
    assert_home_and_ledger(found, BUILDER, &[], "build these with kernels::shared::pipeline");
}
