//! One way a number on 0..=1 goes onto the 16-bit scale (fx spec 2 ㉯ ②,
//! an-endless-plugin-stalls-the-app). A dab's opacity spelled it, then a
//! lens's threshold; a plugin's colour would have been the third, so all
//! three call `sixteen_bit` (CLAUDE.md, absolute rule 1: a third copy is
//! when they join). A test of behaviour passes copies that agree, so this
//! one reads the source. It reads that spelling only — a copy spelled
//! otherwise is still one.

use super::source_scan::{assert_home_and_ledger, files_where};

/// The multiply by 65535 and its one rounding, without their spaces. In
/// two halves, so a scan of this file would not find it.
const STEP: &str = concat!("*65535.0)", ".round()");

/// Where it is spelled.
const HOME: &str = "kernels/shared/mod.rs";

#[test]
fn the_16_bit_scale_is_spelled_in_shared_alone() {
    let found = files_where("rs", |text| {
        let bare: String = text.chars().filter(|c| !c.is_whitespace()).collect();
        bare.contains(STEP)
    });
    assert_home_and_ledger(found, HOME, &[], &format!("call sixteen_bit ({HOME})"));
}
