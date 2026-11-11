import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';

/// The app converts a frame as the screen shows it through the package's
/// Dart (gpu-export-path ①): each conversion takes the numbers Dart hands
/// it where it names them, and a readout's rows land where they are asked.
/// That each call is its pass is the crate's to pin
/// (rust/src/kernels/export/abi/tests.rs) — here, what Dart hands it.
void main() {
  late GpuPool pool;
  late GpuComposite composite;
  late GpuExport export;
  const red = 0xFF0000FF;
  // A pixel at (1, 4) half there, and (2, 0) and (0, 3) not at all: bits
  // 13, 2 and 9 of the picture's 15, across its first two bytes.
  const half = 0x800000FF;
  const unpainted = [(2, 0), (0, 3)];

  setUpAll(() {
    composite = GpuComposite(appGpuEngine);
    export = GpuExport(appGpuEngine);
  });
  tearDownAll(() {
    export.free();
    composite.free();
  });
  setUp(() => pool = GpuPool(appGpuEngine, 1 << 30));
  tearDown(() => pool.free());

  /// A surface showing a picture of [width] × [height] 1:1, as the canvas
  /// shows a frame — its pixel (x, y) [colour], straight RGBA8,
  /// A<<24|B<<16|G<<8|R, or nothing where that is null.
  GpuSurface surfaceOf(
    int width,
    int height,
    int? Function(int, int) colour,
  ) {
    final plan = GpuPlan();
    addTearDown(plan.free);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = colour(x, y);
        if (pixel != null) {
          plan.solid(pixel, x, y, x + 1, y + 1);
        }
      }
    }
    final whole = (0, 0, width, height);
    final screen = GpuScreen(composite, whole);
    addTearDown(screen.free);
    screen.compose(pool, plan, whole);
    final surface = ScreenTexture.surfaceOf(appGpuEngine, width, height);
    addTearDown(surface.free);
    screen.show(
      surface,
      inverse: const [1, 0, 0, 0, 1, 0],
      scale: 1,
      sampling: GpuSampling.nearest,
      rect: whole,
    );
    return surface;
  }

  /// [surfaceOf]'s picture, as the export's conversions read it.
  GpuShown frameOf(int width, int height, int? Function(int, int) colour) {
    final frame = export.shown(
      surfaceOf(width, height, colour),
      width,
      height,
    );
    addTearDown(frame.free);
    return frame;
  }

  /// 3 × 5 of colours no two pixels share — red 10 + 40x, green 10 + 40y,
  /// blue 200 — but for [half] and [unpainted].
  GpuShown mixed() => frameOf(3, 5, (x, y) {
    if ((x, y) == (1, 4)) {
      return half;
    }
    if (unpainted.contains((x, y))) {
      return null;
    }
    return 0xFF000000 | 200 << 16 | (10 + 40 * y) << 8 | (10 + 40 * x);
  });

  /// All of [readout]'s bytes, mapped and copied out as one row; it is
  /// freed.
  Uint8List readAll(GpuReadout readout) => using((arena) {
    addTearDown(readout.free);
    final bytes = readout.bytes;
    final dst = arena<Uint8>(bytes);
    readout
      ..map()
      ..rows(
        dst,
        offset: 0,
        stride: bytes,
        rowBytes: bytes,
        rows: 1,
        dstStride: bytes,
      );
    return Uint8List.fromList(dst.asTypedList(bytes));
  });

  // Red's numbers by the law (nv12.wgsl): Y 82, Cb 90, Cr 240; past the
  // picture, white's: Y 235, no colour. Each number its own, so two put in
  // each other's place is a frame the picture does not fit.
  test('nv12 takes the picture, the frame and its rows where it names '
      'them', () {
    final frame = frameOf(3, 5, (_, _) => red);
    final bytes = readAll(
      export.nv12(frame, 3, 5, frameWidth: 4, frameHeight: 6, stride: 8),
    );

    expect(bytes.length, 8 * 6 * 3 ~/ 2);
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 8; x++) {
        final inside = x < 3 && y < 5;
        expect(bytes[y * 8 + x], inside ? 82 : 235, reason: 'Y ($x, $y)');
      }
    }
    for (var y = 0; y < 6; y += 2) {
      for (var x = 0; x < 8; x += 2) {
        final at = 6 * 8 + y ~/ 2 * 8 + x;
        final colour = x < 3 && y < 5 ? [90, 240] : [128, 128];
        expect(bytes.sublist(at, at + 2), colour, reason: 'CbCr ($x, $y)');
      }
    }
  });

  test('over the ground, red is its low byte and no rows have bytes '
      'between', () {
    final bytes = readAll(export.overGround(mixed(), 3, 5, 0xC86432));

    expect(bytes.length, 3 * 5 * 3);
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 3; x++) {
        final at = (y * 3 + x) * 3;
        final colour = bytes.sublist(at, at + 3);
        final own = [10 + 40 * x, 10 + 40 * y, 200];
        if (unpainted.contains((x, y))) {
          expect(colour, [0x32, 0x64, 0xC8], reason: '($x, $y)');
        } else if ((x, y) != (1, 4)) {
          expect(colour, own, reason: '($x, $y)');
        }
      }
    }
    final shade = bytes[(4 * 3 + 1) * 3];
    expect(shade, inExclusiveRange(0x32, 255), reason: 'no cut: its shade');
  });

  // 128 is not under a cut of 128, and is under one of 129.
  test('a cut lays a pixel whole or clear, never its shade', () {
    const at = (4 * 3 + 1) * 3;
    final whole = readAll(
      export.overGround(mixed(), 3, 5, 0xC86432, cut: 128),
    );
    final clear = readAll(
      export.overGround(mixed(), 3, 5, 0xC86432, cut: 129),
    );

    expect(whole.sublist(at, at + 3), [255, 0, 0]);
    expect(clear.sublist(at, at + 3), [0x32, 0x64, 0xC8]);
  });

  test('clear bits run low bit first, row after row with nothing '
      'between', () {
    final frame = mixed();

    expect(readAll(export.clear(frame, 3, 5, 129)), [
      1 << 2,
      1 << 1 | 1 << 5,
      0,
      0,
    ]);
    expect(readAll(export.clear(frame, 3, 5, 128)), [1 << 2, 1 << 1, 0, 0]);
  });

  test('a picture is opaque only where every pixel is', () {
    expect(export.opaque(frameOf(3, 5, (_, _) => red), 3, 5), isTrue);
    expect(export.opaque(mixed(), 3, 5), isFalse);
  });

  // Red's first row is least under Sub — its first pixel, then nothing —
  // and every row below it under Up, all nothing (png.wgsl).
  test("a PNG's rows are a filter's byte, the row and a word's filling", () {
    final frame = frameOf(3, 5, (_, _) => red);
    final rgba = readAll(export.pngRgba(frame, 3, 5));
    final rgb = export.overGround(frame, 3, 5, 0);
    addTearDown(rgb.free);
    final threes = readAll(export.pngRgb(rgb, 3, 5));

    expect(GpuExport.pngRowBytes(3, 4), 16);
    expect(rgba.length, 5 * 16);
    expect(rgba.sublist(0, 16), [1, 255, 0, 0, 255, ...List.filled(11, 0)]);
    expect(rgba.sublist(16), [
      for (var row = 1; row < 5; row++) ...[2, ...List.filled(15, 0)],
    ]);
    expect(GpuExport.pngRowBytes(3, 3), 12);
    expect(threes.length, 5 * 12);
    expect(threes.sublist(0, 12), [1, 255, 0, 0, ...List.filled(8, 0)]);
    expect(threes.sublist(12), [
      for (var row = 1; row < 5; row++) ...[2, ...List.filled(11, 0)],
    ]);
  });

  // Two pixels of each of three rows from the second row's second pixel,
  // into rows of 7: each of the five numbers its own.
  test('rows are copied from where they are asked to where they go', () {
    final frame = mixed();
    final whole = readAll(export.overGround(frame, 3, 5, 0xC86432));
    final readout = export.overGround(frame, 3, 5, 0xC86432);
    addTearDown(readout.free);

    final copied = using((arena) {
      final dst = arena<Uint8>(20)..asTypedList(20).fillRange(0, 20, 0xEE);
      readout
        ..map()
        ..rows(dst, offset: 12, stride: 9, rowBytes: 6, rows: 3, dstStride: 7);
      return Uint8List.fromList(dst.asTypedList(20));
    });

    for (var row = 0; row < 3; row++) {
      final from = 12 + row * 9;
      expect(
        copied.sublist(row * 7, row * 7 + 6),
        whole.sublist(from, from + 6),
        reason: 'row $row',
      );
    }
    expect([copied[6], copied[13]], [0xEE, 0xEE], reason: 'between rows');
  });

  test('a readout copies no rows before it is mapped or past its bytes', () {
    final readout = export.overGround(mixed(), 3, 5, 0);
    addTearDown(readout.free);
    using((arena) {
      final dst = arena<Uint8>(45);
      void rows(int offset) => readout.rows(
        dst,
        offset: offset,
        stride: 9,
        rowBytes: 9,
        rows: 5,
        dstStride: 9,
      );

      expect(
        () => rows(0),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'a readout is mapped before its rows are read',
          ),
        ),
      );
      readout.map();
      rows(0);
      expect(
        () => rows(1),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '5 rows of 9 from 1, 9 apart, reach past the 45 bytes read out',
          ),
        ),
      );
    });
  });

  test('a picture its surface does not hold is no frame', () {
    final surface = surfaceOf(3, 5, (_, _) => red);

    expect(
      () => export.shown(surface, 3, 6),
      throwsA(
        isA<GpuRefused>().having(
          (error) => error.message,
          'message',
          'a 3x6 picture is not in a 3x5 surface',
        ),
      ),
    );
  });

  test('a frame a conversion refuses throws why', () {
    expect(
      () => export.nv12(
        frameOf(3, 5, (_, _) => red),
        3,
        5,
        frameWidth: 3,
        frameHeight: 6,
        stride: 8,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          "an encoder's frame is even and not empty, not 3x6",
        ),
      ),
    );
  });

  // A frame's last picture made on the engine (gpu-export-path ①⑵): what
  // Dart hands the lay pass lands where it names it. Its law is the
  // crate's to pin (rust/src/kernels/export/lay_tests.rs).
  group('a frame laid', () {
    const white = 0xFFFFFFFF;

    GpuShown blank(int width, int height) {
      final frame = export.blank(width, height, ground: white);
      addTearDown(frame.free);
      return frame;
    }

    /// [frame]'s pixels over black, three bytes each.
    List<List<int>> pixelsOf(GpuShown frame, int width, int height) {
      final rgb = readAll(export.overGround(frame, width, height, 0));
      return [
        for (var at = 0; at < rgb.length; at += 3) rgb.sublist(at, at + 3),
      ];
    }

    test('a picture lands where Dart stands it, on the ground', () {
      final frame = blank(4, 3);
      final picture = export.upload(
        Uint8List.fromList([for (var i = 0; i < 2; i++) ...[255, 0, 0, 255]]),
        2,
        1,
      );
      addTearDown(picture.free);

      export.lay(frame, picture, x: 1, y: 2);

      expect(pixelsOf(frame, 4, 3), [
        for (var at = 0; at < 12; at++)
          if (at == 9 || at == 10) [255, 0, 0] else [255, 255, 255],
      ]);
    });

    // Red over white at half: green and blue 127 (lay_tests.rs).
    test('a strength and a cover are handed where Dart names them', () {
      final covered = blank(3, 1);
      final cover = export.cover(Uint8List.fromList([0, 128, 255]), 3, 1);
      addTearDown(cover.free);
      final halved = blank(3, 1);

      export
        ..layColour(covered, red, cover: cover)
        ..layColour(halved, red, opacity: 128);

      expect(pixelsOf(covered, 3, 1), [
        [255, 255, 255],
        [255, 127, 127],
        [255, 0, 0],
      ]);
      expect(pixelsOf(halved, 3, 1), List.filled(3, [255, 127, 127]));
    });

    test('a cover of another size is refused, and says why', () {
      final cover = export.cover(Uint8List.fromList([255, 255, 255]), 3, 1);
      addTearDown(cover.free);

      expect(
        () => export.layColour(blank(3, 2), red, cover: cover),
        throwsA(
          isA<GpuRefused>().having(
            (error) => error.message,
            'message',
            "a 3x1 cover is not a 3x2 frame's",
          ),
        ),
      );
    });

    test('a picture of too few bytes is refused, and says why', () {
      expect(
        () => export.upload(Uint8List(15), 2, 2),
        throwsA(
          isA<GpuRefused>().having(
            (error) => error.message,
            'message',
            'a 2x2 picture is 16 bytes, not 15',
          ),
        ),
      );
    });
  });
}
