// An expanded Photoshop layer is cut where its document is read (card
// a-raster-import-goes-gpu-cpu-gpu-cpu): the isolate that paints takes its
// tiles, and lays on the engine only those a fit resamples — the cels the
// engine lays of the same layers. ↩️The document's pixels came to the
// isolate that paints, and each layer was cut there.
import 'dart:typed_data';

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/psd_expand_import.dart';
import 'package:anicel/src/services/import/psd_layer_plan.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/engine_pixels.dart';
import '../../helpers/psd_fixture.dart';

void main() {
  const document = CanvasSize(width: 150, height: 90);

  /// An opaque layer over [left]..[right] × [top]..[bottom], each pixel its
  /// own colour — a cut from the wrong rows or a slip of the place shows.
  PsdTestLayer layer(String name, int left, int top, int right, int bottom) {
    final width = right - left;
    final height = bottom - top;
    return PsdTestLayer(
      name: name,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      planes: [
        for (final step in [5, 9, 3])
          Uint8List.fromList([
            for (var y = 0; y < height; y += 1)
              for (var x = 0; x < width; x += 1)
                (x * step + y * (step + 2)) % 256,
          ]),
      ],
    );
  }

  final bytes = buildPsd(
    width: document.width,
    height: document.height,
    layers: [
      layer('inside', 20, 10, 120, 70),
      // Past the document's left and bottom: only its part inside is laid.
      layer('past the side', -30, 5, 90, 110),
    ],
  );

  ImportIdMint mint() {
    var minted = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('L${minted += 1}'),
      nextFrameId: (_) => FrameId('F${minted += 1}'),
      nextCutId: () => const CutId('C1'),
    );
  }

  Future<PsdExpansion> expanded(
    CanvasSize canvas,
    MediaFitMode fit, {
    bool newCut = false,
  }) async => (await readPsdExpansion(
    bytes: bytes,
    displayName: 'stack.psd',
    cutId: const CutId('c'),
    duration: 12,
    canvas: canvas,
    fit: fit,
    mint: mint(),
    newCut: newCut,
  ))!;

  /// The cel the engine lays of [source]'s part inside the document where
  /// [placement] puts it on [canvas] — the layer uploaded and held by it.
  Future<BitmapSurface> engineLaid(
    PsdLayer source,
    PsdLayerPlacement placement,
    CanvasSize canvas,
  ) async {
    final crop = placement.crop;
    final rgba = Uint8List(crop.width * crop.height * 4);
    for (var y = 0; y < crop.height; y += 1) {
      final from = ((crop.top + y) * source.width + crop.left) * 4;
      rgba.setRange(
        y * crop.width * 4,
        (y + 1) * crop.width * 4,
        source.pixels!,
        from,
      );
    }
    final picture = EnginePicture(
      await uploadRawRgba(
        premultipliedRgbaCopy(rgba),
        width: crop.width,
        height: crop.height,
      ),
    );
    try {
      return await layCelPicture(
        picture: picture,
        canvas: canvas,
        placement: rectPlacement(
          placement.rect,
          width: crop.width,
          height: crop.height,
        ),
      );
    } finally {
      picture.dispose();
    }
  }

  /// [ours] against the cels the engine lays of the document's layers where
  /// the plan of an expansion onto [canvas] by [fit] places them.
  Future<void> expectEngineLaid(
    PsdExpansion ours,
    CanvasSize canvas,
    MediaFitMode fit,
  ) async {
    final read = readPsdDocument(bytes);
    final plan = planPsdExpansion(
      document: read,
      displayName: 'stack.psd',
      cutId: const CutId('c'),
      duration: 12,
      canvas: canvas,
      fit: fit,
      mint: mint(),
      newCut: false,
    );
    expect(ours.cels, hasLength(plan.placements.length));
    expect(plan.placements, hasLength(2));
    for (final (index, placement) in plan.placements.indexed) {
      final theirs = await engineLaid(
        read.layers[placement.sourceIndex],
        placement,
        canvas,
      );
      expect(theirs.tiles, isNotEmpty);
      expectSameCel(ours.cels[index].surface, theirs);
    }
  }

  testWidgets('🎯laid 1:1 on a cut of its own, each layer is the cel the '
      'engine copies of it — and the engine runs nothing', (tester) async {
    await tester.runAsync(() async {
      final runs = debugLayRuns;
      final ours = await expanded(
        const CanvasSize(width: 1, height: 1),
        MediaFitMode.none,
        newCut: true,
      );
      expect(debugLayRuns, runs);
      expect(ours.canvas, document);
      await expectEngineLaid(ours, document, MediaFitMode.none);
    });
  });

  testWidgets('stood 1:1 on a larger cut, half a pixel off its centre, each '
      'layer is the cel the engine copies of it', (tester) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 211, height: 133);
      final runs = debugLayRuns;
      final ours = await expanded(canvas, MediaFitMode.none);
      expect(debugLayRuns, runs);
      await expectEngineLaid(ours, canvas, MediaFitMode.none);
    });
  });

  testWidgets('🎯fitted onto another cut, each layer is the cel the engine '
      'lays of it', (tester) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 64, height: 48);
      for (final fit in [MediaFitMode.contain, MediaFitMode.stretch]) {
        final ours = await expanded(canvas, fit);
        await expectEngineLaid(ours, canvas, fit);
      }
    });
  });
}
