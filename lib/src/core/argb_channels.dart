/// The four channels of a packed `0xAARRGGBB` int — Skia's
/// SkColorGetA/R/G/B, named once.
///
/// Every site that read a colour's bytes spelled the shift-and-mask by
/// hand (the audit's clone scan, 2026-09-06: the stroke painter, the grid
/// op-stream packer, RgbaColor, the onion tint matrix, the dab kernel,
/// the ground mixer, the sampler's paper, the flood fill, the pixel verbs,
/// the hex status bar, the export background). One-expression leaf
/// functions inline under both the JIT and AOT, and none of the callers
/// reads a channel per pixel — each reads once per colour or per dab.
library;

int argbAlpha(int argb) => (argb >> 24) & 0xFF;
int argbRed(int argb) => (argb >> 16) & 0xFF;
int argbGreen(int argb) => (argb >> 8) & 0xFF;
int argbBlue(int argb) => argb & 0xFF;
