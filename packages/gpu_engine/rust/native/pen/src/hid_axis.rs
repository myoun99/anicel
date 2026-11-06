//! THE HID AXIS LAW (desktop-pen-tilt) — what a digitizer's value means, in
//! the unit its report descriptor names.
//!
//! A HID value arrives as bare bits. What they mean is DECLARED beside them:
//! the logical range they count over, the physical range that counts in,
//! the unit, and a power of ten. Windows requires a pen's X Tilt (0x3D) and
//! Y Tilt (0x3E) in degrees (unit 0x14), with a physical range that is the
//! pen's own reach; a descriptor may still count in hundredths through its
//! exponent, or over a logical range finer than the physical one. So nothing
//! here assumes a range — each is read off the declaration.
//!
//! No platform in it: the Raw Input observer reads with it, and its cases
//! run on every host.

/// One value's declaration, as Windows' HIDP_VALUE_CAPS carries it.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Axis {
    pub(crate) bit_size: u32,
    pub(crate) logical_min: i32,
    pub(crate) logical_max: i32,
    pub(crate) physical_min: i32,
    pub(crate) physical_max: i32,
    /// HID Unit: nibble 0 the system, nibble 1 the length's exponent.
    pub(crate) units: u32,
    /// HID Unit Exponent: a four-bit two's-complement code (0xE is -2).
    pub(crate) units_exp: u32,
}

impl Axis {
    /// The angle `raw` declares, in degrees. None when the axis says no
    /// angle: an empty logical range, or a unit that is not one — including
    /// none at all, which declares a number, not an angle.
    pub(crate) fn degrees(&self, raw: u32) -> Option<f64> {
        if self.logical_max <= self.logical_min {
            return None;
        }
        let system = self.units & 0xF;
        let length = (self.units >> 4) & 0xF;
        let is_degrees = system == 4 && length == 1; // English Rotation
        let is_radians = system == 2 && length == 1; // SI Rotation
        if !is_degrees && !is_radians {
            return None;
        }
        // A field with a negative minimum is signed: its top bit is the sign.
        let mut logical = i64::from(raw);
        if self.logical_min < 0
            && self.bit_size > 0
            && self.bit_size < 32
            && raw & (1 << (self.bit_size - 1)) != 0
        {
            logical -= 1 << self.bit_size;
        } else if self.logical_min < 0 && self.bit_size == 32 {
            logical = i64::from(raw as i32);
        }
        // HID: a physical range of 0..0 is the logical range again.
        let mut value = logical as f64;
        if self.physical_min != 0 || self.physical_max != 0 {
            value = f64::from(self.physical_min)
                + (logical - i64::from(self.logical_min)) as f64
                    * (i64::from(self.physical_max) - i64::from(self.physical_min)) as f64
                    / (i64::from(self.logical_max) - i64::from(self.logical_min)) as f64;
        }
        let mut exponent = (self.units_exp & 0xF) as i32;
        if exponent >= 8 {
            exponent -= 16;
        }
        // A power of ten at a time, as the C stepped: the same steps round
        // the same.
        for _ in 0..exponent {
            value *= 10.0;
        }
        for _ in exponent..0 {
            value /= 10.0;
        }
        Some(if is_radians { value * (180.0 / std::f64::consts::PI) } else { value })
    }
}
