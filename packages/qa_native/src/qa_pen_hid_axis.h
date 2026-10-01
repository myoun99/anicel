// THE HID AXIS LAW (desktop-pen-tilt) — what a digitizer's value means, in
// the unit its report descriptor names.
//
// A HID value arrives as bare bits. What they mean is DECLARED beside them:
// the logical range they count over, the physical range that counts in,
// the unit, and a power of ten. Windows requires a pen's X Tilt (0x3D) and
// Y Tilt (0x3E) in degrees (unit 0x14), with a physical range that is the
// pen's own reach; a descriptor may still count in hundredths through its
// exponent, or over a logical range finer than the physical one. So nothing
// here assumes a range — each is read off the declaration.
//
// Pure C with no platform in it: qa_penraw_win.c reads with it, and
// qa_pen_hid_axis_test.c runs it on every host.

#ifndef QA_PEN_HID_AXIS_H
#define QA_PEN_HID_AXIS_H

#include <stdint.h>

// One value's declaration, as Windows' HIDP_VALUE_CAPS carries it.
typedef struct {
  uint32_t bit_size;
  int32_t logical_min;
  int32_t logical_max;
  int32_t physical_min;
  int32_t physical_max;
  // HID Unit: nibble 0 the system, nibble 1 the length's exponent.
  uint32_t units;
  // HID Unit Exponent: a four-bit two's-complement code (0xE is -2).
  uint32_t units_exp;
} qa_hid_axis;

// The angle [raw] declares on [axis], in degrees, into *[degrees]. 0 when
// the axis says no angle: an empty logical range, or a unit that is not
// one — including none at all, which declares a number, not an angle.
static int qa_hid_axis_degrees(const qa_hid_axis *axis, uint32_t raw,
                               double *degrees) {
  if (axis->logical_max <= axis->logical_min) {
    return 0;
  }
  const uint32_t system = axis->units & 0xF;
  const uint32_t length = (axis->units >> 4) & 0xF;
  const int is_degrees = system == 4 && length == 1;  // English Rotation
  const int is_radians = system == 2 && length == 1;  // SI Rotation
  if (!is_degrees && !is_radians) {
    return 0;
  }
  // A field with a negative minimum is signed: its top bit is the sign.
  int64_t logical = (int64_t)raw;
  if (axis->logical_min < 0 && axis->bit_size > 0 && axis->bit_size < 32 &&
      (raw & ((uint32_t)1 << (axis->bit_size - 1))) != 0) {
    logical -= (int64_t)1 << axis->bit_size;
  } else if (axis->logical_min < 0 && axis->bit_size == 32) {
    logical = (int32_t)raw;
  }
  // HID: a physical range of 0..0 is the logical range again.
  double value = (double)logical;
  if (axis->physical_min != 0 || axis->physical_max != 0) {
    value = axis->physical_min +
            (double)(logical - axis->logical_min) *
                (double)((int64_t)axis->physical_max - axis->physical_min) /
                (double)((int64_t)axis->logical_max - axis->logical_min);
  }
  int exponent = (int)(axis->units_exp & 0xF);
  if (exponent >= 8) {
    exponent -= 16;
  }
  for (; exponent > 0; exponent -= 1) {
    value *= 10.0;
  }
  for (; exponent < 0; exponent += 1) {
    value /= 10.0;
  }
  *degrees = is_radians ? value * (180.0 / 3.14159265358979323846) : value;
  return 1;
}

#endif  // QA_PEN_HID_AXIS_H
