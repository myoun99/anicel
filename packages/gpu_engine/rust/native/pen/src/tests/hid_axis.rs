//! The HID axis law on the cases of the C's own test
//! (qa_pen_hid_axis_test.c), which runs on every host, as these do.

use crate::hid_axis::Axis;

fn axis(
    bit_size: u32,
    logical: (i32, i32),
    physical: (i32, i32),
    units: u32,
    units_exp: u32,
) -> Axis {
    Axis {
        bit_size,
        logical_min: logical.0,
        logical_max: logical.1,
        physical_min: physical.0,
        physical_max: physical.1,
        units,
        units_exp,
    }
}

fn expect_degrees(what: &str, axis: &Axis, raw: u32, want: f64) {
    let got = axis.degrees(raw).unwrap_or_else(|| panic!("{what}: said no angle, want {want}"));
    assert!((got - want).abs() <= 1e-9, "{what}: got {got}, want {want}");
}

fn expect_no_angle(what: &str, axis: &Axis, raw: u32) {
    let got = axis.degrees(raw);
    assert_eq!(got, None, "{what}: read {got:?}, want no angle");
}

#[test]
fn microsofts_own_shape_for_a_pens_tilt() {
    // Hundredths of a degree, signed sixteen bits, logical and physical alike.
    let hundredths = axis(16, (-9000, 9000), (-9000, 9000), 0x14, 0x0E);
    expect_degrees("hundredths: +45", &hundredths, 4500, 45.0);
    expect_degrees("hundredths: -45 arrives as its bits", &hundredths, 0x10000 - 4500, -45.0);
    expect_degrees("hundredths: upright", &hundredths, 0, 0.0);
    // The exponent written as a whole byte (0xFE) is the same -2.
    let byte_exp = axis(16, (-9000, 9000), (-9000, 9000), 0x14, 0xFE);
    expect_degrees("a byte-wide exponent", &byte_exp, 4500, 45.0);
}

#[test]
fn a_logical_range_finer_than_the_physical_one() {
    // The reach is ±60°.
    let reach = axis(8, (-127, 127), (-60, 60), 0x14, 0);
    expect_degrees("reach: the top of the range", &reach, 127, 60.0);
    expect_degrees("reach: the bottom, sign-extended", &reach, 0x81, -60.0);
    expect_degrees("reach: the middle is upright", &reach, 0, 0.0);
    expect_degrees(
        "reach: in between is in proportion",
        &reach,
        0x40,
        -60.0 + (64.0 + 127.0) * 120.0 / 254.0,
    );
}

#[test]
fn the_fields_and_units_a_descriptor_may_declare() {
    // No physical range declared: the logical one counts in degrees.
    expect_degrees("no physical range", &axis(8, (-60, 60), (0, 0), 0x14, 0), 30, 30.0);
    // An unsigned field is not sign-extended, however high its top bit.
    expect_degrees("an unsigned field", &axis(8, (0, 255), (0, 0), 0x14, 0), 200, 200.0);
    // A signed field as wide as the word: its bits are the number already.
    let wide = axis(32, (-9000, 9000), (-9000, 9000), 0x14, 0x0E);
    expect_degrees("a 32-bit signed field", &wide, -4500i32 as u32, -45.0);
    // A positive exponent multiplies: tens of degrees.
    expect_degrees("an exponent of +1", &axis(8, (-9, 9), (0, 0), 0x14, 0x01), 4, 40.0);
    // Radians (SI Rotation) come out in degrees.
    let radians = axis(16, (-157, 157), (-157, 157), 0x12, 0x0E);
    expect_degrees("radians", &radians, 157, 1.57 * 180.0 / std::f64::consts::PI);
}

#[test]
fn what_does_not_declare_an_angle_says_none() {
    let no_unit = axis(16, (-9000, 9000), (-9000, 9000), 0, 0x0E);
    expect_no_angle("no unit declares a number, not an angle", &no_unit, 4500);
    let linear = axis(16, (-9000, 9000), (-9000, 9000), 0x11, 0x0E);
    expect_no_angle("a length is not an angle", &linear, 4500);
    let squared = axis(16, (-9000, 9000), (-9000, 9000), 0x24, 0x0E);
    expect_no_angle("degrees squared is not an angle", &squared, 4500);
    expect_no_angle("an empty logical range", &axis(16, (0, 0), (0, 0), 0x14, 0), 0);
}
