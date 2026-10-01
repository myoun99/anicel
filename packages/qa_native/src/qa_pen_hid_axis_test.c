// The HID axis law, run (desktop-pen-tilt).
//
// The reader it serves only runs where a pen does — a Windows digitizer —
// so without this file the arithmetic that turns a report's bits into a
// lean would reach a device before anything had executed it. The law has
// no platform in it, so this runs on every host.

#include "qa_pen_hid_axis.h"

#include <math.h>
#include <stdio.h>

static int g_failures;

static void expect_degrees(const char *what, const qa_hid_axis *axis,
                           uint32_t raw, double want) {
  double got = -12345.0;
  if (!qa_hid_axis_degrees(axis, raw, &got)) {
    printf("FAIL %s: said no angle, want %g\n", what, want);
    g_failures += 1;
    return;
  }
  if (fabs(got - want) > 1e-9) {
    printf("FAIL %s: got %.12g, want %.12g\n", what, got, want);
    g_failures += 1;
  }
}

static void expect_no_angle(const char *what, const qa_hid_axis *axis,
                            uint32_t raw) {
  double got = -12345.0;
  if (qa_hid_axis_degrees(axis, raw, &got)) {
    printf("FAIL %s: read %.12g, want no angle\n", what, got);
    g_failures += 1;
  }
}

int main(void) {
  // Microsoft's own shape for a pen's tilt: hundredths of a degree, signed
  // sixteen bits, logical and physical alike.
  const qa_hid_axis hundredths = {16, -9000, 9000, -9000, 9000, 0x14, 0x0E};
  expect_degrees("hundredths: +45", &hundredths, 4500, 45.0);
  expect_degrees("hundredths: -45 arrives as its bits", &hundredths,
                 (uint32_t)(0x10000 - 4500), -45.0);
  expect_degrees("hundredths: upright", &hundredths, 0, 0.0);

  // The exponent written as a whole byte (0xFE) is the same -2.
  const qa_hid_axis byte_exp = {16, -9000, 9000, -9000, 9000, 0x14, 0xFE};
  expect_degrees("a byte-wide exponent", &byte_exp, 4500, 45.0);

  // A logical range finer than the physical one: the reach is ±60°.
  const qa_hid_axis reach = {8, -127, 127, -60, 60, 0x14, 0};
  expect_degrees("reach: the top of the range", &reach, 127, 60.0);
  expect_degrees("reach: the bottom, sign-extended", &reach, 0x81, -60.0);
  expect_degrees("reach: the middle is upright", &reach, 0, 0.0);
  expect_degrees("reach: in between is in proportion", &reach, 0x40,
                 -60.0 + (64.0 + 127.0) * 120.0 / 254.0);

  // No physical range declared: the logical one counts in degrees.
  const qa_hid_axis bare = {8, -60, 60, 0, 0, 0x14, 0};
  expect_degrees("no physical range", &bare, 30, 30.0);

  // An unsigned field is not sign-extended, however high its top bit.
  const qa_hid_axis unsigned_field = {8, 0, 255, 0, 0, 0x14, 0};
  expect_degrees("an unsigned field", &unsigned_field, 200, 200.0);

  // A signed field as wide as the word: its bits are the number already.
  const qa_hid_axis wide = {32, -9000, 9000, -9000, 9000, 0x14, 0x0E};
  expect_degrees("a 32-bit signed field", &wide, (uint32_t)-4500, -45.0);

  // A positive exponent multiplies: tens of degrees.
  const qa_hid_axis tens = {8, -9, 9, 0, 0, 0x14, 0x01};
  expect_degrees("an exponent of +1", &tens, 4, 40.0);

  // Radians (SI Rotation) come out in degrees.
  const qa_hid_axis radians = {16, -157, 157, -157, 157, 0x12, 0x0E};
  expect_degrees("radians", &radians, 157, 1.57 * 180.0 / 3.14159265358979323846);

  // What does not declare an angle says none.
  const qa_hid_axis no_unit = {16, -9000, 9000, -9000, 9000, 0, 0x0E};
  expect_no_angle("no unit declares a number, not an angle", &no_unit, 4500);
  const qa_hid_axis linear = {16, -9000, 9000, -9000, 9000, 0x11, 0x0E};
  expect_no_angle("a length is not an angle", &linear, 4500);
  const qa_hid_axis squared = {16, -9000, 9000, -9000, 9000, 0x24, 0x0E};
  expect_no_angle("degrees squared is not an angle", &squared, 4500);
  const qa_hid_axis empty = {16, 0, 0, 0, 0, 0x14, 0};
  expect_no_angle("an empty logical range", &empty, 0);

  if (g_failures == 0) {
    printf("qa_pen_hid_axis: all passed\n");
  }
  return g_failures == 0 ? 0 : 1;
}
