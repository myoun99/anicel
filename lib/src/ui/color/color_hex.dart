/// HEX in one place (R10 R5).
///
/// The window's status bar, the wheel panel's readout and the RGB tab all
/// need the same two directions, and the moment a second copy exists they
/// disagree about case, about the `#`, and about what an unparseable
/// string should do.
library;

/// `0xAARRGGBB` → `#RRGGBB`, uppercase, alpha dropped (this app's colours
/// are opaque; alpha lives on the layer).
String colorHexOf(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// `#RRGGBB` / `RRGGBB` / `#RGB` → `0xFFRRGGBB`, or null when the text is
/// not a colour. Case-insensitive, tolerant of surrounding space and of a
/// missing `#`, because a user typing into a field is not writing CSS.
int? parseColorHex(String text) {
  var body = text.trim();
  if (body.startsWith('#')) {
    body = body.substring(1);
  }
  if (body.length == 3) {
    // #RGB is the shorthand every colour picker takes: each digit doubles.
    body = body.split('').map((digit) => '$digit$digit').join();
  }
  if (body.length != 6) {
    return null;
  }
  final rgb = int.tryParse(body, radix: 16);
  return rgb == null ? null : 0xFF000000 | rgb;
}

/// The three channels of `0xAARRGGBB`, in the order the status bar prints
/// them.
({int r, int g, int b}) colorChannels(int argb) => (
  r: (argb >> 16) & 0xFF,
  g: (argb >> 8) & 0xFF,
  b: argb & 0xFF,
);

/// The channels back into an opaque colour, each clamped to a byte.
int colorFromChannels({required int r, required int g, required int b}) =>
    0xFF000000 |
    (r.clamp(0, 255) << 16) |
    (g.clamp(0, 255) << 8) |
    b.clamp(0, 255);
