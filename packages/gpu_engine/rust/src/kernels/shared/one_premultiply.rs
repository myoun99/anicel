//! One 8-bit premultiply (저장 2026-11-06, gpu-export-path ①e). The
//! export's over-the-ground pass spelled SkMulDiv255Round a second time,
//! under a name of its own beside `premultiply8`, so both compiled; it now
//! calls this one. A test of behaviour passes two copies that agree, so
//! this one reads the source: the rounding's last step, spaces aside, is
//! in `premultiply.wgsl` alone. It reads that spelling only — a copy
//! spelled otherwise is still one (CLAUDE.md, absolute rule 1).

use super::source_scan::{assert_home_and_ledger, files_where};

/// `(t + (t >> 8)) >> 8` without its spaces, the tail any spelling of it
/// ends in. In two halves, so a scan of this file would not find it.
const STEP: &str = concat!(">>8u))", ">>8u");

/// Where it is spelled.
const HOME: &str = "kernels/shared/premultiply.wgsl";

#[test]
fn the_8_bit_premultiply_is_spelled_in_premultiply_wgsl_alone() {
    let found = files_where("wgsl", |text| {
        let bare: String = text.chars().filter(|c| !c.is_whitespace()).collect();
        bare.contains(STEP)
    });
    assert_home_and_ledger(found, HOME, &[], &format!("premultiply with premultiply8 ({HOME})"));
}
