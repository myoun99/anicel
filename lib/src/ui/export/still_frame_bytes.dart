import 'dart:io' show ZLibEncoder;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart'
    show GpuExport, GpuReadout, GpuShown, gpuColourOf;

import '../../native/app_gpu_engine.dart' show appGpuExport;
import '../../services/media/png_writing.dart';
import 'png_srgb.dart';

/// What a still file's writer takes of a frame on the engine — turned
/// there into the bytes it writes and read back once (gpu-export-path ①):
/// the frame's colour straight where the file keeps alpha ([straightOf]),
/// laid over a ground where it does not ([rgbOverGroundOf]), and a PNG's
/// rows under their filters ([rgbaPngOf], [rgbPngOf]).
///
/// [frame] stays its maker's: nothing here frees it.
///
/// ↩️Each writer read a picture back from Flutter and turned it on the CPU
/// — its colour unpremultiplied by Flutter (`rawStraightRgba`), laid over
/// the ground and filtered row by row by the app's own copies of the laws
/// the engine's passes keep (`over_ground.wgsl`, `png.wgsl`).
Uint8List straightOf(GpuShown frame) =>
    appGpuExport.straight(frame, frame.width, frame.height).take();

/// [frame] laid over [groundArgb] — a `Color`'s, A<<24|R<<16|G<<8|B, its
/// alpha unread — three bytes a pixel, red first, row after row with
/// nothing between.
Uint8List rgbOverGroundOf(GpuShown frame, int groundArgb) =>
    _overGround(frame, groundArgb).take();

/// [frame] as a PNG of four channels — its colour straight, its rows under
/// the filters the engine picks — with the sRGB stamp every PNG this app
/// hands out carries ([tagPngAsSrgb]).
///
/// Deflated in an isolate of its own: a run of frames would stall the
/// window's cancel.
Future<Uint8List> rgbaPngOf(GpuShown frame) async {
  final (width, height) = (frame.width, frame.height);
  final rows = _filteredRows(
    appGpuExport.pngRgba(frame, width, height),
    width,
    height,
    4,
  );
  return tagPngAsSrgb(
    await Isolate.run(
      () => encodeStillPng(
        width: width,
        height: height,
        colourType: pngRgba,
        imageData: _deflated(rows),
      ),
    ),
  );
}

/// [frame] over [groundArgb] as a PNG of three channels — colour type 2,
/// no alpha at all — with the sRGB stamp ([tagPngAsSrgb]): its rows
/// deflated twice — under the filters the engine picks, and unfiltered —
/// and the smaller kept.
///
/// 🗣️F-335 (유저 10-10): 「알파채널 아예없는걸 원하거든? RGBA가 아닌 RGB는
/// 그게 효율적이잖아」 → 「그렇게하자」.
///
/// ⚠️BOTH, because the guess loses to no filter at all on a picture of flat
/// colours and wins on gradients (measured 10-11 against the engine's RGBA
/// PNG of the same picture: a cel 2436×1678 — engine 812,659 B · filtered
/// 732,890 B · unfiltered 588,376 B; a page of lines and boxes the same
/// size — 2,814,565 B · 2,456,257 B · 1,858,095 B; a picture of gradients
/// 1920×1080 — engine 1,180,600 B, this 1,083,146 B). Kept to one, a cel or
/// a gradient each pays for the other's.
Future<Uint8List> rgbPngOf(GpuShown frame, int groundArgb) async {
  final (width, height) = (frame.width, frame.height);
  final rgb = _overGround(frame, groundArgb);
  final Uint8List filtered;
  final Uint8List pixels;
  try {
    filtered = _filteredRows(
      appGpuExport.pngRgb(rgb, width, height),
      width,
      height,
      3,
    );
    pixels = rgb.copy();
  } finally {
    rgb.free();
  }
  return tagPngAsSrgb(
    await Isolate.run(() {
      final underFilters = _deflated(filtered);
      final asTheyAre = _deflated(_unfiltered(pixels, width * 3));
      return encodeStillPng(
        width: width,
        height: height,
        colourType: pngRgb,
        imageData: underFilters.length <= asTheyAre.length
            ? underFilters
            : asTheyAre,
      );
    }),
  );
}

/// [frame] over [groundArgb] ([rgbOverGroundOf]), on the GPU: the ground
/// is the engine's colour of it, red its low byte.
GpuReadout _overGround(GpuShown frame, int groundArgb) =>
    appGpuExport.overGround(
      frame,
      frame.width,
      frame.height,
      gpuColourOf(groundArgb) & 0xFFFFFF,
    );

/// The rows [filtered] put, each its filter's byte and [pixelBytes] a
/// pixel of [width], one after another — without the filling that starts
/// each on a word ([GpuExport.pngRowBytes]) — and [filtered] freed.
Uint8List _filteredRows(
  GpuReadout filtered,
  int width,
  int height,
  int pixelBytes,
) {
  try {
    return filtered.copyRows(
      stride: GpuExport.pngRowBytes(width, pixelBytes),
      rowBytes: 1 + width * pixelBytes,
      rows: height,
    );
  } finally {
    filtered.free();
  }
}

/// [pixels]' rows of [rowBytes], each under filter 0 — none.
Uint8List _unfiltered(Uint8List pixels, int rowBytes) {
  final height = pixels.length ~/ rowBytes;
  final rows = Uint8List(height * (rowBytes + 1));
  for (var y = 0; y < height; y += 1) {
    rows.setRange(
      y * (rowBytes + 1) + 1,
      (y + 1) * (rowBytes + 1),
      pixels,
      y * rowBytes,
    );
  }
  return rows;
}

/// [rows] deflated: the body of a PNG's IDAT.
Uint8List _deflated(Uint8List rows) => switch (ZLibEncoder().convert(rows)) {
  final Uint8List bytes => bytes,
  final bytes => Uint8List.fromList(bytes),
};
