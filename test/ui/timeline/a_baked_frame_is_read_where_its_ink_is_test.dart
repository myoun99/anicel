// A bake's frame stays on the engine and crosses where its ink is
// (`inkOfFrame`; card the-attach-row-bake-test-waits-a-gpu-read-a-frame-
// under-load, 2026-11-14).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart' show appGpuExport;
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show layCelPicture;
import 'package:anicel/src/ui/timeline/baked_frame_ink.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart'
    show opensTheEnginesScreens;

/// A patch of premultiplied pixels and where its top-left stands in a
/// frame.
typedef _Patch = ({Uint8List rgba, int width, int height, int x, int y});

void main() {
  opensTheEnginesScreens();

  const canvas = CanvasSize(width: 300, height: 280);
  final wall = canvas.pasteboardAt(PasteboardReach.whole);
  final (wide, high) = (wall.region.width, wall.region.height);

  /// Every alpha under every colour byte, premultiplied as the app does:
  /// a row an alpha — row 0 clear —, a column a colour byte.
  _Patch everyShade(int x, int y) {
    final rgba = Uint8List(256 * 256 * 4);
    for (var alpha = 0; alpha < 256; alpha += 1) {
      for (var byte = 0; byte < 256; byte += 1) {
        final at = (alpha * 256 + byte) * 4;
        rgba[at] = mul255Round(byte, alpha);
        rgba[at + 1] = mul255Round(255 - byte, alpha);
        rgba[at + 2] = mul255Round((byte * 37 + 11) & 255, alpha);
        rgba[at + 3] = alpha;
      }
    }
    return (rgba: rgba, width: 256, height: 256, x: x, y: y);
  }

  /// A [width] × [height] patch of one half-clear colour.
  _Patch halfClear(int width, int height, int x, int y) {
    final rgba = Uint8List(width * height * 4);
    for (var at = 0; at < rgba.length; at += 4) {
      rgba
        ..[at] = 64
        ..[at + 1] = 32
        ..[at + 2] = 16
        ..[at + 3] = 128;
    }
    return (rgba: rgba, width: width, height: height, x: x, y: y);
  }

  /// A frame the size of the wall with [patches] laid on it, for the
  /// caller to free.
  GpuShown frameOf(List<_Patch> patches) {
    final frame = appGpuExport.blank(wide, high);
    for (final patch in patches) {
      final uploaded = appGpuExport.upload(
        patch.rgba,
        patch.width,
        patch.height,
      );
      try {
        appGpuExport.lay(frame, uploaded, x: patch.x, y: patch.y);
      } finally {
        uploaded.free();
      }
    }
    return frame;
  }

  /// [frame] as the cel a bake lays of it (`merge_layer_rows`): read where
  /// its ink is, laid where that stands.
  Future<BitmapSurface> bakeOf(GpuShown frame) async {
    final ink = inkOfFrame(appGpuExport, frame);
    if (ink == null) {
      return BitmapSurface(canvasSize: canvas);
    }
    return layCelPicture(
      picture: ink.pixels,
      canvas: canvas,
      placement: GuideTransform(
        1,
        0,
        0,
        1,
        (wall.left + ink.left).toDouble(),
        (wall.top + ink.top).toDouble(),
      ),
    );
  }

  /// The pixel of [cel] at ([x], [y]) of the wall as the app shows it —
  /// premultiplied ([mul255Round]) — clear where it holds no tile.
  List<int> shownAt(BitmapSurface cel, int x, int y) {
    final side = cel.tileSize;
    final (cx, cy) = (x + wall.left, y + wall.top);
    final coord = TileCoord(x: (cx / side).floor(), y: (cy / side).floor());
    final rgba = cel.tiles[coord]?.pixels;
    if (rgba == null) {
      return const [0, 0, 0, 0];
    }
    final at = ((cy - coord.y * side) * side + (cx - coord.x * side)) * 4;
    final alpha = rgba[at + 3];
    return [
      mul255Round(rgba[at], alpha),
      mul255Round(rgba[at + 1], alpha),
      mul255Round(rgba[at + 2], alpha),
      alpha,
    ];
  }

  /// The pixels of the wall where what [cel] shows ([shownAt]) is not
  /// [frame]'s own, premultiplied as the engine holds it.
  int shownApart(BitmapSurface cel, GpuShown frame) {
    final held = appGpuExport.read(frame).take();
    var apart = 0;
    for (var y = 0; y < high; y += 1) {
      for (var x = 0; x < wide; x += 1) {
        final shown = shownAt(cel, x, y);
        final at = (y * wide + x) * 4;
        for (var channel = 0; channel < 4; channel += 1) {
          if (shown[channel] != held[at + channel]) {
            apart += 1;
            break;
          }
        }
      }
    }
    return apart;
  }

  // 🧭관제 2026-11-14 (the verdict's first condition): 「굽기 결과를 다시
  // 프리멀티플라이하면 프레임과 모든 화소에서 같다 · 알파가 같다」. 🔬What
  // the cel STORES is the engine's straight, one level off Flutter's
  // unpremultiply — the road until then — in 1,877 of 65,280 inked pixels
  // (`ExportFrameRenderer.frameOver`); what it shows is the frame either way.
  final fixtures = <String, List<_Patch> Function()>{
    'every shade against the wall\'s left edge, a half-clear patch in its '
        'far corner': () => [
      everyShade(0, 100),
      halfClear(7, 5, wide - 7, high - 5),
    ],
    'every shade inside the wall, across tile edges': () => [
      everyShade(333, 217),
    ],
    'one half-clear pixel': () => [halfClear(1, 1, 411, 97)],
  };

  for (final MapEntry(key: name, value: patches) in fixtures.entries) {
    testWidgets('🎯$name: the cel baked of a frame shows the frame at every '
        'pixel of the wall — its alpha, and its colours premultiplied as the '
        'app shows a cel', (tester) async {
      final apart = await tester.runAsync(() async {
        final frame = frameOf(patches());
        try {
          return shownApart(await bakeOf(frame), frame);
        } finally {
          frame.free();
        }
      });
      expect(apart, 0);
    });
  }

  // 🧭관제 2026-11-14 (the verdict's second condition): 「같은 것을 두 번
  // 구워도 바이트가 안 움직이는 것을 핀한다 — 굽기를 거듭해도 색이
  // 흘러가지 않아야 한다」.
  testWidgets('🚨a cel baked of a frame, shown and baked again, is the same '
      'cel to the byte — bakes one after another carry no colour off', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final frame = frameOf([everyShade(333, 217)]);
      final BitmapSurface once;
      try {
        once = await bakeOf(frame);
      } finally {
        frame.free();
      }
      // The cel as the engine shows it: each tile's straight bytes
      // premultiplied by the app's one law, where the tile lies.
      final side = once.tileSize;
      final shown = frameOf([
        for (final MapEntry(key: coord, value: tile) in once.tiles.entries)
          (
            rgba: premultipliedRgbaCopy(tile.pixels),
            width: side,
            height: side,
            x: coord.x * side - wall.left,
            y: coord.y * side - wall.top,
          ),
      ]);
      final BitmapSurface twice;
      try {
        twice = await bakeOf(shown);
      } finally {
        shown.free();
      }
      expect(twice.tiles.keys.toSet(), once.tiles.keys.toSet());
      for (final MapEntry(key: coord, value: tile) in once.tiles.entries) {
        expect(twice.tiles[coord]!.pixels, tile.pixels, reason: '$coord');
      }
    });
  });

  // 🧭관제 2026-11-14 (the verdict's first condition): 「통째로 straight 로
  // 읽어 CPU 에서 자른 것과 바이트까지 같다」.
  testWidgets('a frame\'s ink read back is the frame\'s own straight bytes '
      'over its box, and the box is where the ink ends', (tester) async {
    await tester.runAsync(() async {
      final frame = frameOf([everyShade(333, 217)]);
      try {
        final ink = inkOfFrame(appGpuExport, frame)!;
        // Row 0 of the patch is clear: the box starts a row under it.
        expect(
          (ink.left, ink.top, ink.pixels.width, ink.pixels.height),
          (333, 218, 256, 255),
        );
        final whole = appGpuExport.straight(frame, wide, high).take();
        final cut = Uint8List(256 * 255 * 4);
        for (var row = 0; row < 255; row += 1) {
          final from = ((218 + row) * wide + 333) * 4;
          cut.setRange(row * 1024, (row + 1) * 1024, whole, from);
        }
        expect(ink.pixels.rgba, cut);
      } finally {
        frame.free();
      }
    });
  });

  testWidgets('a clear frame has no ink', (tester) async {
    await tester.runAsync(() async {
      final frame = frameOf(const []);
      try {
        expect(inkOfFrame(appGpuExport, frame), isNull);
      } finally {
        frame.free();
      }
    });
  });

  group('the box of a clear mask', () {
    /// A mask of [width] × [height] with every pixel clear but [ink].
    Uint8List maskOf(int width, int height, List<(int, int)> ink) {
      final bits = Uint8List((width * height + 7) >> 3)
        ..fillRange(0, (width * height + 7) >> 3, 0xff);
      for (final (x, y) in ink) {
        final pixel = y * width + x;
        bits[pixel >> 3] &= ~(1 << (pixel & 7));
      }
      return bits;
    }

    test('is none where every pixel is clear', () {
      expect(inkBoxOf(maskOf(13, 7, const []), 13, 7), isNull);
    });

    test('is the one pixel that is not — in a row that starts mid-byte', () {
      for (final (x, y) in [(0, 0), (12, 0), (0, 6), (12, 6), (5, 3)]) {
        expect(
          inkBoxOf(maskOf(13, 7, [(x, y)]), 13, 7),
          DirtyRegion.fromXYWH(x: x, y: y, width: 1, height: 1),
          reason: '($x, $y)',
        );
      }
    });

    test('reaches every pixel that is not clear', () {
      expect(
        inkBoxOf(maskOf(13, 7, [(3, 5), (11, 1), (4, 2)]), 13, 7),
        DirtyRegion(left: 3, top: 1, rightExclusive: 12, bottomExclusive: 6),
      );
    });

    test('takes the filling past the last pixel for no pixel', () {
      // 13 × 7 = 91 pixels: the twelfth byte's last five bits are filling,
      // and a mask that leaves them unset names no ink there.
      final mask = maskOf(13, 7, const [])..[11] = 0x07;
      expect(inkBoxOf(mask, 13, 7), isNull);
    });

    test('a frame full of ink is the whole of it', () {
      expect(
        inkBoxOf(Uint8List(((64 * 40) + 7) >> 3), 64, 40),
        DirtyRegion(left: 0, top: 0, rightExclusive: 64, bottomExclusive: 40),
      );
    });
  });
}
