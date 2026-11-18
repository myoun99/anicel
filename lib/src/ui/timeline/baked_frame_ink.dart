import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show GpuExport, GpuShown;

import '../../models/dirty_region.dart';
import '../../services/import/cel_picture.dart' show PixelsPicture;

/// What a frame on the engine holds where its ink is: the box of its pixels
/// that are not clear, straight, and where that box stands in the frame.
typedef FrameInk = ({PixelsPicture pixels, int left, int top});

/// [frame]'s ink ([FrameInk]) read back — null where it holds none.
///
/// A bake draws a cel's picture over the whole pasteboard (a merge's rows,
/// an fx RASTERIZE's riders: what lies past the canvas is theirs too), and
/// most of that is clear. 🔬2026-11-14 (card the-attach-row-bake-test-
/// waits-a-gpu-read-a-frame-under-load): a 20×20 sheet on the default
/// canvas was a frame of 7020×4962 — 139 MB — read back whole for each of
/// its thirteen cels, made a picture on the GPU again and rastered back a
/// block at a time, thirteen blocks a cel for the two that held ink: 41 s
/// a bake under load, 39.6 s of it there.
///
/// So the frame stays on the engine. Which of its pixels are clear comes
/// back a bit apiece ([GpuExport.clear]); the box of the rest is cut out
/// there ([GpuExport.blank], [GpuExport.lay]) and it alone crosses,
/// straight ([GpuExport.straight]) — the bytes a still's writer takes of a
/// frame (`straightOf`).
FrameInk? inkOfFrame(GpuExport export, GpuShown frame) {
  final (width, height) = (frame.width, frame.height);
  final box = inkBoxOf(
    export.clear(frame, width, height, 1).take(),
    width,
    height,
  );
  if (box == null) {
    return null;
  }
  final cut = export.blank(box.width, box.height);
  try {
    export.lay(cut, frame, x: -box.left, y: -box.top);
    return (
      pixels: PixelsPicture(
        export.straight(cut, box.width, box.height).take(),
        width: box.width,
        height: box.height,
      ),
      left: box.left,
      top: box.top,
    );
  } finally {
    cut.free();
  }
}

/// The box of the pixels [clear] does not name, of a picture [width] ×
/// [height] — or null where it names every one. [clear] is a bit a pixel,
/// set where the pixel is clear: pixel i is bit i % 8 of byte i ~/ 8, low
/// bit first, row after row with nothing between ([GpuExport.clear]).
///
/// ⛔Not `inkBoundsOfWords`, the box a picture's own pixels give: those
/// pixels are what this box is found to spare reading — of a frame only a
/// bit a pixel crosses.
DirtyRegion? inkBoxOf(Uint8List clear, int width, int height) {
  final pixels = width * height;
  var (left, top, right, bottom) = (width, height, -1, -1);
  for (var at = 0; at < clear.length; at += 1) {
    final byte = clear[at];
    if (byte == 0xff) {
      continue;
    }
    final first = at * 8;
    final row = first ~/ width;
    final column = first - row * width;
    // A byte whose eight pixels all lie inside the box found so far moves
    // no edge of it: a frame full of ink is walked a byte at a time.
    if (row >= top && row <= bottom && column >= left && column + 7 <= right) {
      continue;
    }
    for (var bit = 0; bit < 8; bit += 1) {
      final pixel = first + bit;
      // Past the picture's last pixel the last byte holds filling.
      if (pixel >= pixels) {
        break;
      }
      if (byte & (1 << bit) != 0) {
        continue;
      }
      final y = pixel ~/ width;
      final x = pixel - y * width;
      left = x < left ? x : left;
      right = x > right ? x : right;
      top = y < top ? y : top;
      bottom = y > bottom ? y : bottom;
    }
  }
  return bottom < 0
      ? null
      : DirtyRegion(
          left: left,
          top: top,
          rightExclusive: right + 1,
          bottomExclusive: bottom + 1,
        );
}
