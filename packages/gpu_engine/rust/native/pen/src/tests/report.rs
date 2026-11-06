//! A report's flag word and pose, and what `qpr_poll` hands over of them,
//! on answers worked out here: the C keeps both inside its observer, where
//! only a digitizer's report reaches them.

use crate::report::{flags, pose, snapshot};

/// What a snapshot of seven floats reads.
fn seven(flags: i32, sequence: i32, pose: i64) -> [f32; 7] {
    let mut out = [f32::NAN; 7];
    snapshot(flags, sequence, pose, &mut out);
    out
}

#[test]
fn each_button_the_hid_tables_name_is_its_own_flag() {
    assert_eq!(flags(&[0x42]), 0x01, "Tip Switch");
    assert_eq!(flags(&[0x44]), 0x02, "Barrel Switch");
    assert_eq!(flags(&[0x45]), 0x04, "Eraser");
    assert_eq!(flags(&[0x3C]), 0x08, "Invert");
    assert_eq!(flags(&[0x5A]), 0x10, "Secondary Barrel Switch");
    assert_eq!(flags(&[0x42, 0x3D, 0x45, 0x30]), 0x05, "other usages are no button");
    assert_eq!(flags(&[]), 0, "nothing pressed");
}

#[test]
fn a_lean_is_read_in_hundredths_and_whole() {
    let read = seven(0x01, 7, pose(Some((45.0, -30.25)), None));
    assert_eq!(read, [1.0, 7.0, 45.0, -30.25, 1.0, 0.0, 0.0]);
    // Halves away from zero.
    let read = seven(0, 0, pose(Some((12.346, -12.346)), None));
    assert_eq!(&read[2..5], &[12.35, -12.35, 1.0]);
    // A pen's reach is ±90°: past it is clamped, not wrapped.
    let read = seven(0, 0, pose(Some((100.0, -100.0)), None));
    assert_eq!(&read[2..5], &[90.0, -90.0, 1.0]);
}

#[test]
fn a_report_without_both_tilts_carries_no_lean() {
    let read = seven(0, 0, pose(None, None));
    assert_eq!(&read[2..], &[0.0; 5]);
}

#[test]
fn a_twist_is_read_once_round() {
    assert_eq!(&seven(0, 0, pose(None, Some(270.0)))[5..], &[270.0, 1.0]);
    assert_eq!(&seven(0, 0, pose(None, Some(-90.0)))[5..], &[270.0, 1.0], "back round");
    assert_eq!(&seven(0, 0, pose(None, Some(360.0)))[5..], &[0.0, 1.0], "a full turn");
    assert_eq!(&seven(0, 0, pose(None, Some(719.996)))[5..], &[0.0, 1.0], "rounded, twice");
    assert_eq!(&seven(0, 0, pose(None, Some(359.994)))[5..], &[359.99, 1.0]);
    // A twist leaves the lean as it is, and the lean the twist.
    let read = seven(0, 0, pose(Some((-1.5, 2.25)), Some(33.5)));
    assert_eq!(&read[2..], &[-1.5, 2.25, 1.0, 33.5, 1.0]);
}

#[test]
fn the_counter_is_whole_in_a_float() {
    assert_eq!(seven(0, 0x0123_4567, 0)[1], 0x23_4567 as f32);
    assert_eq!(seven(0, -1, 0)[1], 0xFF_FFFF as f32, "wrapped");
}

#[test]
fn a_snapshot_writes_what_its_abi_reads() {
    let posed = pose(Some((10.0, 20.0)), Some(30.0));
    for (length, written) in [(2, 2), (3, 2), (4, 2), (5, 5), (6, 5), (7, 7)] {
        let mut out = [f32::NAN; 7];
        snapshot(3, 4, posed, &mut out[..length]);
        let wrote = out.iter().take_while(|value| !value.is_nan()).count();
        assert_eq!(wrote, written, "a snapshot of {length}");
        assert!(out[written..].iter().all(|value| value.is_nan()), "a snapshot of {length}");
    }
}
