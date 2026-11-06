//! What the Raw Input observer keeps of a pen's report, and what
//! `qpr_poll` hands over of it. No platform in it.

/// The HID digitizer usage page, and the usages on it read here.
pub(crate) const PAGE_DIGITIZER: u16 = 0x0D;
pub(crate) const USAGE_DIGITIZER: u16 = 0x01;
pub(crate) const USAGE_PEN: u16 = 0x02;
pub(crate) const USAGE_X_TILT: u16 = 0x3D;
pub(crate) const USAGE_Y_TILT: u16 = 0x3E;
pub(crate) const USAGE_TWIST: u16 = 0x41;
const USAGE_INVERT: u16 = 0x3C;
const USAGE_TIP_SWITCH: u16 = 0x42;
const USAGE_BARREL_SWITCH: u16 = 0x44;
const USAGE_ERASER: u16 = 0x45;
const USAGE_SECONDARY_BARREL: u16 = 0x5A;

/// The flag word handed to Dart.
const FLAG_TIP: i32 = 0x01;
const FLAG_BARREL: i32 = 0x02;
const FLAG_ERASER: i32 = 0x04;
const FLAG_INVERT: i32 = 0x08;
const FLAG_SECONDARY_BARREL: i32 = 0x10;

/// The flag word of a report whose buttons on the digitizer page are
/// `usages`.
pub(crate) fn flags(usages: &[u16]) -> i32 {
    usages.iter().fold(0, |flags, usage| {
        flags
            | match *usage {
                USAGE_TIP_SWITCH => FLAG_TIP,
                USAGE_BARREL_SWITCH => FLAG_BARREL,
                USAGE_ERASER => FLAG_ERASER,
                USAGE_INVERT => FLAG_INVERT,
                USAGE_SECONDARY_BARREL => FLAG_SECONDARY_BARREL,
                _ => 0,
            }
    })
}

/// A report's pose as ONE word, so a reader never pairs one report's X with
/// another's Y, or its twist with another's lean: bit 32 set when the
/// report carried both tilts, then X and Y in hundredths of a degree as two
/// signed 16-bit halves (a pen's reach is ±90°, well inside them); bit 33
/// set when it carried a twist, and the twist in hundredths of a degree,
/// 0..35999, in the top sixteen bits.
pub(crate) fn pose(tilt: Option<(f64, f64)>, twist: Option<f64>) -> i64 {
    let tilt = tilt.map_or(0, |(x, y)| 1 << 32 | centi(x) << 16 | centi(y));
    let twist = twist.map_or(0, |twist| {
        // Once round, whatever range the axis declares it over.
        let mut centi = rounded(twist * 100.0) % 36000;
        if centi < 0 {
            centi += 36000;
        }
        1 << 33 | i64::from(centi as u16) << 48
    });
    tilt | twist
}

/// `degrees` as a signed 16-bit count of hundredths.
fn centi(degrees: f64) -> i64 {
    let degrees = degrees.clamp(-90.0, 90.0);
    i64::from(rounded(degrees * 100.0) as i16 as u16)
}

/// `value` to the nearest whole number, halves away from zero.
fn rounded(value: f64) -> i32 {
    (value + if value < 0.0 { -0.5 } else { 0.5 }) as i32
}

/// What `qpr_poll` writes of the newest report into `out`, which is as long
/// as the caller's ABI reads: the flag word and the report counter; with
/// five, its lean — X Tilt and Y Tilt in degrees, then 1 when the report
/// carried both and 0 when it carried none; with seven, its twist — in
/// degrees 0..360, clockwise as HID declares it, then 1 when it carried one.
pub(crate) fn snapshot(flags: i32, sequence: i32, pose: i64, out: &mut [f32]) {
    out[0] = flags as f32;
    // Masked to 24 bits because the transport is float: past 2^24 adjacent
    // integers stop being representable and the counter would silently
    // stall, which reads as "no new report" — the exact opposite of what it
    // is for. Wrapping is harmless; only CHANGE is ever tested.
    out[1] = (sequence & 0xFF_FFFF) as f32;
    if out.len() >= 5 {
        out[2] = f32::from((pose >> 16) as u16 as i16) / 100.0;
        out[3] = f32::from(pose as u16 as i16) / 100.0;
        out[4] = if (pose >> 32) & 1 != 0 { 1.0 } else { 0.0 };
    }
    if out.len() >= 7 {
        out[5] = f32::from((pose >> 48) as u16) / 100.0;
        out[6] = if (pose >> 33) & 1 != 0 { 1.0 } else { 0.0 };
    }
}
