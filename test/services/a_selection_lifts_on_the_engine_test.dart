// The first lift compiles the kernels and the pool's: tens of seconds on a
// machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuMask;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_cel_pixels.dart';
import 'package:anicel/src/native/engine_selection_masks.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/selection_lift.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/selection_clip.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/services/cel_pixel_region.dart';

import '../helpers/surface_rgba_in_place.dart';
import '../helpers/selection_reads_spied.dart';

/// A SELECTION'S LIFT ON THE ENGINE (flip lane ⓒ): on the app's grid what a
/// selection takes off a cel is the kernel's (lift.wgsl), under the mask the
/// selection made there, held byte for byte to the Dart gather, over boxes
/// that straddle tile edges and whole pixels or a feather's — and its erase
/// is laid from that same mask, taking what the erase's picture takes, with
/// the selection read on the CPU nowhere (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`, L1b-2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final ledger = EngineTileLedger.instance;

  tearDown(() => debugSelectionLiftInDart = false);

  BitmapTile tileOf(int seed) {
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      final o = i * 4;
      if ((i + seed) % 5 == 0) {
        continue;
      }
      bytes
        ..[o] = (i * 31 + seed) % 256
        ..[o + 1] = (i * 17) % 256
        ..[o + 2] = (i * 13 + 5) % 256
        ..[o + 3] = (i * 7 + seed) % 256;
    }
    return BitmapTile(size: side, pixels: bytes);
  }

  BitmapSurface artwork() => BitmapSurface(
    canvasSize: canvas,
    tileSize: side,
    tiles: {
      TileCoord(x: 0, y: 0): tileOf(0),
      TileCoord(x: 1, y: 0): tileOf(3),
      TileCoord(x: 0, y: 1): tileOf(7),
      TileCoord(x: -1, y: -1): tileOf(11),
    },
  );

  Uint8List maskOf(int width, int height) => Uint8List.fromList([
    for (var i = 0; i < width * height; i += 1)
      switch (i % 5) {
        0 => 0,
        1 => 255,
        _ => (i * 37) % 256,
      },
  ]);

  CanvasSelectionRegion rect(int left, int top, int right, int bottom) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: left.toDouble(),
          top: top.toDouble(),
          right: right.toDouble(),
          bottom: bottom.toDouble(),
        ),
      );

  final outlines = <String, CanvasSelectionRegion>{
    'inside a tile': rect(5, 9, 45, 39),
    'across a tile edge': rect(100, 20, 160, 40),
    'across four tiles, one of them none': rect(100, 100, 160, 160),
    'off the top-left': rect(-30, -20, 20, 20),
    'of a tile alone': rect(128, 0, 256, 128),
    'an ellipse across a tile edge': CanvasSelectionRegion.shape(
      CanvasSelectionShape.ellipse(
        left: 90.5,
        top: 10.25,
        right: 170.75,
        bottom: 70.5,
      ),
    ),
    'a lasso folded in on itself over tile edges': CanvasSelectionRegion.shape(
      CanvasSelectionShape([
        for (final (x, y) in [(-100, -90), (220, 30), (100, 70), (70, 230)])
          CanvasPoint(x: x.toDouble(), y: y.toDouble()),
      ]),
    ),
  };
  const softnesses = [
    SelectionMaskOptions.none,
    SelectionMaskOptions(featherPx: 4),
    SelectionMaskOptions(growPx: 2, antiAlias: true),
  ];

  String labelOf(String name, SelectionMaskOptions options) =>
      '$name, grow ${options.growPx} feather ${options.featherPx} '
      'aa ${options.antiAlias}';

  for (final MapEntry(key: name, value: region) in outlines.entries) {
    for (final options in softnesses) {
      test('${labelOf(name, options)}: as the gather in Dart', () {
        final surface = artwork();
        SelectionPixels? lifted() => liftSelectionPixels(
          region: region,
          surface: surface,
          options: options,
        );
        debugSelectionLiftInDart = true;
        final inDart = lifted();
        debugSelectionLiftInDart = false;
        final reads = ledger.debugTileReads;
        final onEngine = lifted();
        expect(inDart, isNotNull, reason: '⛔premise: it takes something');
        expect(onEngine!.box, inDart!.box);
        expect(onEngine.rgba, inDart.rgba);
        expect(ledger.debugTileReads, reads, reason: 'no tile read back');
      });
    }
  }

  /// [region] lifted off [surface] at [options], its erase landed there —
  /// on the engine, or as the picture of the erase's own bytes.
  BitmapSurface erasedBy(
    BitmapSurface surface,
    CanvasSelectionRegion region,
    SelectionMaskOptions options, {
    required bool asPicture,
  }) {
    final lifted = liftSelectionPixels(
      region: region,
      surface: surface,
      options: options,
    )!;
    final erase = selectionEraseDab(lifted, id: 'erase');
    final stamp = erase.stamp!;
    final laid = asPicture
        ? erase.copyWith(
            stamp: BrushStampImage(
              id: 'erase-picture',
              width: stamp.width,
              height: stamp.height,
              rgba: stamp.rgba,
            ),
          )
        : erase;
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([laid]),
    ).surface;
  }

  for (final MapEntry(key: name, value: region) in outlines.entries) {
    for (final options in softnesses) {
      test('${labelOf(name, options)}: the erase takes on the engine what '
          'its picture takes', () {
        final surface = artwork();
        final handedUp = EngineStampPictures.debugHandedUp;
        final onEngine = erasedBy(surface, region, options, asPicture: false);
        expect(
          EngineStampPictures.debugHandedUp,
          handedUp,
          reason: 'the erase is laid from the mask, no picture handed up',
        );
        final asPicture = erasedBy(surface, region, options, asPicture: true);
        var erased = 0;
        for (var y = -40; y < 260; y += 1) {
          for (var x = -40; x < 260; x += 1) {
            final got = surfaceRgbaInPlace(onEngine, x, y);
            final want = surfaceRgbaInPlace(asPicture, x, y);
            if (got != want) {
              fail(
                '$x,$y: the erase left ${got?.toRadixString(16)} where its '
                'picture leaves ${want?.toRadixString(16)}',
              );
            }
            if (got != surfaceRgbaInPlace(surface, x, y)) {
              erased += 1;
            }
          }
        }
        expect(erased, isNonZero, reason: '⛔premise: it erases something');
      });
    }
  }

  test('a lift on the engine reads the selection nowhere but there', () {
    for (final options in softnesses) {
      final asked = <int>[];
      final region = SelectionReadsSpied(rect(100, 20, 160, 40), asked);
      final surface = artwork();
      final lifted = liftSelectionPixels(
        region: region,
        surface: surface,
        options: options,
      )!;
      materializeBrushDabSequenceOnBitmapSurface(
        surface: surface,
        sequence: BrushDabSequence([selectionEraseDab(lifted, id: 'erase')]),
      );
      expect(asked, isEmpty, reason: labelOf('the region', options));
    }
  });

  test('an erase laid in a selection is cut by its mask, as its picture is',
      () {
    final surface = artwork();
    final lifted = liftSelectionPixels(
      region: rect(100, 20, 160, 40),
      surface: surface,
      options: SelectionMaskOptions.none,
    )!;
    final erase = selectionEraseDab(lifted, id: 'erase');
    final stamp = erase.stamp!;
    final within = SelectionClip.of(
      rect(130, 0, 200, 60),
      wall: surface.pasteboard,
      options: const SelectionMaskOptions(featherPx: 4),
    );
    BitmapSurface laid(BrushDab dab) =>
        materializeBrushDabSequenceOnBitmapSurface(
          surface: surface,
          sequence: BrushDabSequence([dab]),
          selection: within,
        ).surface;
    final onEngine = laid(erase);
    final asPicture = laid(
      erase.copyWith(
        stamp: BrushStampImage(
          id: 'erase-picture',
          width: stamp.width,
          height: stamp.height,
          rgba: stamp.rgba,
        ),
      ),
    );
    for (var y = 0; y < 60; y += 1) {
      for (var x = 90; x < 200; x += 1) {
        expect(
          surfaceRgbaInPlace(onEngine, x, y),
          surfaceRgbaInPlace(asPicture, x, y),
          reason: '$x,$y',
        );
      }
    }
    expect(
      surfaceRgbaInPlace(onEngine, 111, 30),
      surfaceRgbaInPlace(surface, 111, 30),
      reason: '⛔premise: the selection keeps what lies left of it',
    );
    expect(
      surfaceRgbaInPlace(onEngine, 151, 30),
      isNot(surfaceRgbaInPlace(surface, 151, 30)),
      reason: '⛔premise: it erases inside the selection',
    );
  });

  test('a lift refuses a box its room is not the size of', () {
    final plane = GpuMask(
      appGpuComposite,
      maskOf(4, 4),
      x: 0,
      y: 0,
      width: 4,
      height: 4,
    );
    addTearDown(plane.free);
    final tile = tileOf(0);

    expect(
      () => ledger.held(
        (hold) => EngineCelPixels.pass.lift(
          ledger.pool,
          0,
          0,
          1,
          1,
          hold.slotsOf(Object(), [tile]),
          mask: plane,
          whole: false,
          into: Uint8List(4 * 4 * 4 - 1),
        ),
      ),
      throwsStateError,
    );
  });

  test('a selection over no tile lifts nothing, and asks the engine nothing',
      () {
    final surface = artwork();
    final made = EngineSelectionMasks.debugMade;
    expect(
      liftSelectionPixels(
        region: rect(300, 300, 310, 310),
        surface: surface,
        options: SelectionMaskOptions.none,
      ),
      isNull,
    );
    final lifted = gatherMaskedSurfacePixels(
      surface: surface,
      clip: SelectionClip.of(
        rect(300, 300, 310, 310),
        wall: surface.pasteboard,
        options: SelectionMaskOptions.none,
      ),
      takeWholePixels: true,
    );
    expect(lifted.liftedAnything, isFalse);
    expect(lifted.rgba, everyElement(0));
    expect(EngineSelectionMasks.debugMade, made, reason: 'no mask made');
  });

  test('a selection over nothing painted lifts nothing', () {
    // tileOf(0) leaves every fifth pixel clear, its first among them.
    final surface = artwork();
    final lifted = gatherMaskedSurfacePixels(
      surface: surface,
      clip: SelectionClip.of(
        rect(0, 0, 1, 1),
        wall: surface.pasteboard,
        options: SelectionMaskOptions.none,
      ),
      takeWholePixels: true,
    );
    expect(lifted.liftedAnything, isFalse);
    expect(lifted.rgba, everyElement(0));
  });

  test('the gather in Dart is the one those compare against: it reads the '
      'engine\'s tiles back', () {
    final surface = artwork();
    final verbed = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.colour,
      walk: celPixelWalkFor(surface: surface),
      value: Uint8List.fromList([1, 2, 3]),
    ).surface;
    debugSelectionLiftInDart = true;
    final reads = ledger.debugTileReads;
    liftSelectionPixels(
      region: rect(1, 0, 3, 2),
      surface: verbed,
      options: SelectionMaskOptions.none,
    );
    expect(ledger.debugTileReads, greaterThan(reads));
  });

  test('a lift off what a verb left reads none of it back', () {
    final surface = artwork();
    final verbed = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.colour,
      walk: celPixelWalkFor(surface: surface),
      value: Uint8List.fromList([1, 2, 3]),
    ).surface;
    final reads = ledger.debugTileReads;
    final lifted = liftSelectionPixels(
      region: rect(1, 0, 3, 2),
      surface: verbed,
      options: SelectionMaskOptions.none,
    )!;
    expect(ledger.debugTileReads, reads);
    expect(lifted.rgba.sublist(0, 3), [1, 2, 3]);
  });
}
