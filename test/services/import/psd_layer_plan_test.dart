import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportIdMint;
import 'package:anicel/src/services/import/psd_layer_plan.dart';
import 'package:anicel/src/services/photoshop/psd_pixels.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';

/// The EXPAND plan: what a Photoshop stack becomes before a single pixel is
/// touched. Every rule here is a decision the user made in the round — the
/// one folder, the adjustment that gets named rather than applied, the
/// group whose members must not be orphaned — so each is pinned.
void main() {
  var layerCounter = 0;
  var frameCounter = 0;
  ImportIdMint mint() {
    layerCounter = 0;
    frameCounter = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('L${layerCounter += 1}'),
      nextFrameId: (layer) => FrameId('F${frameCounter += 1}'),
      nextCutId: () => const CutId('C1'),
    );
  }

  PsdLayer raster(
    String name, {
    int left = 0,
    int top = 0,
    int right = 4,
    int bottom = 4,
    int opacity = 255,
    bool visible = true,
    bool clipping = false,
    String blend = 'norm',
    String? adjustment,
    bool pixels = true,
  }) => PsdLayer(
    name: name,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    opacity: opacity,
    visible: visible,
    clipping: clipping,
    blendKey: blend,
    role: PsdLayerRole.raster,
    pixels: pixels ? Uint8List((right - left) * (bottom - top) * 4) : null,
    adjustmentKey: adjustment,
  );

  PsdLayer bracket(PsdLayerRole role, {String name = 'G', String blend = 'pass'}) =>
      PsdLayer(
        name: name,
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
        opacity: 255,
        visible: true,
        clipping: false,
        blendKey: blend,
        role: role,
        pixels: null,
        adjustmentKey: null,
      );

  PsdDocument document(
    List<PsdLayer> layers, {
    int width = 4,
    int height = 4,
    List<String> warnings = const [],
  }) => PsdDocument(
    width: width,
    height: height,
    depth: 8,
    colorMode: PsdColorMode.rgb,
    isPsb: false,
    composite: null,
    layers: layers,
    warnings: warnings,
  );

  PsdExpandPlan plan(
    PsdDocument doc, {
    MediaFitMode fit = MediaFitMode.none,
    CanvasSize canvas = const CanvasSize(width: 4, height: 4),
    int duration = 12,
  }) => planPsdExpansion(
    document: doc,
    displayName: 'BG_a12.psd',
    cutId: const CutId('C1'),
    duration: duration,
    canvas: canvas,
    fit: fit,
    mint: mint(),
  );

  group('the shape of the stack', () {
    test('everything lands inside ONE folder named after the file', () {
      final result = plan(document([raster('a'), raster('b')]));
      expect(result.layers, hasLength(3));
      final root = result.layers.last;
      expect(root.kind, LayerKind.folder);
      expect(root.name, 'BG_a12.psd');
      expect(root.folderId, isNull);
      for (final layer in result.layers.take(2)) {
        expect(layer.kind, LayerKind.image);
        expect(layer.folderId, root.id);
      }
    });

    test('the order stays bottom-first, so the folder row sits above its '
        'members', () {
      final result = plan(document([raster('bottom'), raster('top')]));
      expect(
        result.layers.map((layer) => layer.name).toList(),
        ['bottom', 'top', 'BG_a12.psd'],
      );
    });

    test('a group becomes a folder holding exactly its members', () {
      final result = plan(
        document([
          raster('under'),
          bracket(PsdLayerRole.groupClose),
          raster('inside'),
          bracket(PsdLayerRole.groupOpen, name: 'BOOK'),
          raster('over'),
        ]),
      );
      expect(
        result.layers.map((layer) => layer.name).toList(),
        ['under', 'inside', 'BOOK', 'over', 'BG_a12.psd'],
      );
      final root = result.layers.last;
      final book = result.layers[2];
      expect(book.kind, LayerKind.folder);
      expect(result.layers[1].folderId, book.id, reason: 'inside the group');
      expect(book.folderId, root.id);
      expect(result.layers[0].folderId, root.id);
      expect(result.layers[3].folderId, root.id);
    });

    test('groups nest', () {
      final result = plan(
        document([
          bracket(PsdLayerRole.groupClose),
          bracket(PsdLayerRole.groupClose),
          raster('deep'),
          bracket(PsdLayerRole.groupOpen, name: 'inner'),
          bracket(PsdLayerRole.groupOpen, name: 'outer'),
        ]),
      );
      final byName = {for (final layer in result.layers) layer.name: layer};
      expect(byName['deep']!.folderId, byName['inner']!.id);
      expect(byName['inner']!.folderId, byName['outer']!.id);
      expect(byName['outer']!.folderId, byName['BG_a12.psd']!.id);
    });

    test('a group the file never closed still gets its folder', () {
      final result = plan(
        document([bracket(PsdLayerRole.groupClose), raster('orphan')]),
      );
      final orphan = result.layers.firstWhere((l) => l.name == 'orphan');
      final holder = result.layers.firstWhere((l) => l.id == orphan.folderId);
      expect(holder.kind, LayerKind.folder);
      expect(result.layers.map((l) => l.id), contains(holder.id));
    });
  });

  group('what each layer carries over', () {
    test('the eye, the opacity and the blend', () {
      final result = plan(
        document([
          raster('hidden', visible: false, opacity: 128, blend: 'mul '),
        ]),
      );
      final layer = result.layers.first;
      expect(layer.isVisible, isFalse);
      expect(layer.opacity, closeTo(128 / 255, 0.001));
      expect(layer.blendMode, LayerBlendMode.multiply);
    });

    test('a pass-through group is not a translation — we have that mode', () {
      final result = plan(
        document([
          bracket(PsdLayerRole.groupClose),
          raster('a'),
          bracket(PsdLayerRole.groupOpen, name: 'G', blend: 'pass'),
        ]),
      );
      final folder = result.layers.firstWhere((l) => l.name == 'G');
      expect(folder.blendMode, LayerBlendMode.passThrough);
    });

    test('a blend we do not have becomes normal AND says so', () {
      final result = plan(document([raster('burnt', blend: 'lbrn')]));
      expect(result.layers.first.blendMode, LayerBlendMode.normal);
      expect(
        result.warnings.any((w) => w.contains('burnt') && w.contains('lbrn')),
        isTrue,
      );
    });

    test('the cel is held across the whole cut', () {
      final result = plan(document([raster('a')]), duration: 24);
      final layer = result.layers.first;
      expect(layer.frames, hasLength(1));
      expect(layer.frames.single.duration, 24);
      expect(layer.timeline[0]!.length, 24);
    });
  });

  group('what is left behind', () {
    test('an adjustment layer is dropped and named', () {
      final result = plan(
        document([raster('art'), raster('Curves 1', adjustment: 'curv')]),
      );
      expect(
        result.layers.map((layer) => layer.name).toList(),
        ['art', 'BG_a12.psd'],
      );
      expect(
        result.warnings.any((w) => w.contains('Curves 1')),
        isTrue,
      );
    });

    test('a clipping mask is kept as a layer but flagged', () {
      final result = plan(document([raster('colour', clipping: true)]));
      expect(result.layers.first.name, 'colour');
      expect(
        result.warnings.any((w) => w.contains('clipping')),
        isTrue,
      );
    });

    test('the reader warnings ride along', () {
      final result = plan(
        document([raster('a')], warnings: ['16-bit document stepped down.']),
      );
      expect(result.warnings, contains('16-bit document stepped down.'));
    });

    test('an empty layer keeps its row and asks for no pixels', () {
      final result = plan(document([raster('empty', pixels: false)]));
      expect(result.layers.first.name, 'empty');
      expect(result.placements, isEmpty);
    });
  });

  group('placement', () {
    test('every layer sits at its document offset, scaled by the same fit',
        () {
      final result = plan(
        document(
          [raster('a', left: 10, top: 20, right: 30, bottom: 60)],
          width: 100,
          height: 100,
        ),
        canvas: const CanvasSize(width: 400, height: 200),
        fit: MediaFitMode.contain,
      );
      // Contain into 400x200 fits the square document to 200x200, centred.
      final rect = result.placements.single.rect;
      expect(rect.left, closeTo(100 + 10 * 2, 0.001));
      expect(rect.top, closeTo(0 + 20 * 2, 0.001));
      expect(rect.width, closeTo(20 * 2, 0.001));
      expect(rect.height, closeTo(40 * 2, 0.001));
    });

    test('1:1 centres the document and keeps every layer beside its '
        'neighbours', () {
      final result = plan(
        document(
          [
            raster('a', left: 0, top: 0, right: 10, bottom: 10),
            raster('b', left: 10, top: 0, right: 20, bottom: 10),
          ],
          width: 20,
          height: 10,
        ),
        canvas: const CanvasSize(width: 100, height: 100),
        fit: MediaFitMode.none,
      );
      final first = result.placements[0].rect;
      final second = result.placements[1].rect;
      expect(first.width, 10);
      expect(second.left - first.left, 10);
      expect(first.top, second.top);
    });

    test('a placement points at the layer and cel it belongs to', () {
      final result = plan(document([raster('a')]));
      final placement = result.placements.single;
      expect(placement.layerId, result.layers.first.id);
      expect(placement.frameId, result.layers.first.frames.single.id);
      expect(placement.sourceIndex, 0);
    });
  });
}
