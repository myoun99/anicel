import 'dart:typed_data';

import '../models/bitmap_tile.dart';

/// THE RGBA stamp blitter — the one every 1:1 stamp landing runs.
///
/// A stamp's straight-alpha pixels land source-over (or destination-out
/// when erasing) onto straight-alpha destination bytes. That happens in
/// two places: the pen-up commit blends the stamp into each tile's
/// scratch buffer (`_blendStampDab`), and the live overlay pre-blends the
/// finished stroke buffer against the cel's committed bytes
/// (`preBlendStrokeOverlayPixels`) so the tile on screen IS the tile
/// pen-up will land.
///
/// Those two used to be one loop and a hand-written mirror of it, with
/// the mirror's own comments telling the next reader that the fast paths,
/// the double expressions and their ORDER had to match so the doubles
/// round to the same bytes. Here the math is written once, so "live ==
/// commit" is a fact about the code rather than a promise a parity test
/// re-checks.
///
/// Everything one stamp needs that does not change between spans is
/// resolved once, here — the same shape `BrushDabPlan` uses for the
/// geometric kernel.
class BrushStampBlitter {
  const BrushStampBlitter({
    required this.rgba,
    required this.dabOpacity,
    required this.erase,
  });

  /// The stamp's straight-alpha RGBA pixels.
  final Uint8List rgba;
  final double dabOpacity;
  final bool erase;

  /// Blends [count] stamp pixels from [sourceOffset] into [buffer] at
  /// [offset], IN PLACE, and answers whether any byte changed — the
  /// commit turns that into one dirty-tile mark per span instead of one
  /// per pixel.
  ///
  /// Shared at SPAN granularity, exactly like `blendDabTilesDart`: one
  /// call per (row, tile) run of pixels, nothing per pixel became
  /// indirect, and the three fields are read into locals up front, so
  /// this costs nothing per pixel even in a debug build, where nothing
  /// inlines.
  ///
  /// The C kernel is a THIRD transcription and stays one: it is a
  /// different language, gated behind the ABI version, and pinned
  /// byte-exact by its own parity suite. It already has this exact shape
  /// — `qa_stamp_blend_row(tile_row, stamp_row, count, opacity, erase)`
  /// returning whether the row changed — which is where the signature
  /// here comes from.
  bool blendSpanInPlace(
    Uint8List buffer,
    int offset,
    int sourceOffset,
    int count,
  ) {
    // Locals, not field reads: the loop below is per pixel.
    final rgba = this.rgba;
    final dabOpacity = this.dabOpacity;
    final erase = this.erase;
    var changed = false;
    for (
      var i = 0;
      i < count;
      i += 1, offset += BitmapTile.bytesPerPixel, sourceOffset += 4
    ) {
      final stampA = rgba[sourceOffset + 3];
      if (stampA == 0) {
        continue;
      }

      // Opaque full-coverage fast paths (R16-④ measured: full-canvas
      // fill/lift stamps spent ~0.5s in the per-pixel double math) —
      // a fully covering stamp pixel at opacity 1 is a byte copy
      // (srcOver) or a byte zero (erase).
      if (stampA == 255 && dabOpacity == 1.0) {
        if (erase) {
          if (buffer[offset] != 0 ||
              buffer[offset + 1] != 0 ||
              buffer[offset + 2] != 0 ||
              buffer[offset + 3] != 0) {
            buffer[offset] = 0;
            buffer[offset + 1] = 0;
            buffer[offset + 2] = 0;
            buffer[offset + 3] = 0;
            changed = true;
          }
        } else {
          if (buffer[offset] != rgba[sourceOffset] ||
              buffer[offset + 1] != rgba[sourceOffset + 1] ||
              buffer[offset + 2] != rgba[sourceOffset + 2] ||
              buffer[offset + 3] != 255) {
            buffer[offset] = rgba[sourceOffset];
            buffer[offset + 1] = rgba[sourceOffset + 1];
            buffer[offset + 2] = rgba[sourceOffset + 2];
            buffer[offset + 3] = 255;
            changed = true;
          }
        }
        continue;
      }
      final sourceAlpha = (stampA / 255.0) * dabOpacity;
      final destR = buffer[offset];
      final destG = buffer[offset + 1];
      final destB = buffer[offset + 2];
      final destA = buffer[offset + 3];
      final destinationAlpha = destA / 255.0;

      int outRByte;
      int outGByte;
      int outBByte;
      int outAByte;
      if (erase) {
        // Stamp-ERASE (R15-④): destination-out from the stamp's EXACT
        // alpha — no tip-mask resampling, so a lift's cut edge is
        // byte-hard (the bilinear tip-mask erase left a half-alpha ring
        // at the selection silhouette: the fringe + origin remnant).
        final outAlpha = destinationAlpha * (1.0 - sourceAlpha);
        if (outAlpha == 0.0) {
          outRByte = 0;
          outGByte = 0;
          outBByte = 0;
          outAByte = 0;
        } else {
          outRByte = destR;
          outGByte = destG;
          outBByte = destB;
          outAByte = (outAlpha * 255.0).round().clamp(0, 255);
        }
        if (outRByte != destR ||
            outGByte != destG ||
            outBByte != destB ||
            outAByte != destA) {
          buffer[offset] = outRByte;
          buffer[offset + 1] = outGByte;
          buffer[offset + 2] = outBByte;
          buffer[offset + 3] = outAByte;
          changed = true;
        }
        continue;
      }

      final outAlpha = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
      if (outAlpha == 0.0) {
        outRByte = 0;
        outGByte = 0;
        outBByte = 0;
        outAByte = 0;
      } else {
        final inverseSourceAlpha = 1.0 - sourceAlpha;
        outRByte =
            ((rgba[sourceOffset] * sourceAlpha +
                        destR * destinationAlpha * inverseSourceAlpha) /
                    outAlpha)
                .round()
                .clamp(0, 255);
        outGByte =
            ((rgba[sourceOffset + 1] * sourceAlpha +
                        destG * destinationAlpha * inverseSourceAlpha) /
                    outAlpha)
                .round()
                .clamp(0, 255);
        outBByte =
            ((rgba[sourceOffset + 2] * sourceAlpha +
                        destB * destinationAlpha * inverseSourceAlpha) /
                    outAlpha)
                .round()
                .clamp(0, 255);
        outAByte = (outAlpha * 255.0).round().clamp(0, 255);
      }

      if (outRByte != destR ||
          outGByte != destG ||
          outBByte != destB ||
          outAByte != destA) {
        buffer[offset] = outRByte;
        buffer[offset + 1] = outGByte;
        buffer[offset + 2] = outBByte;
        buffer[offset + 3] = outAByte;
        changed = true;
      }
    }
    return changed;
  }
}
