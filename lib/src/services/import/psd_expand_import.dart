import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../persistence/brush_drawing_binary_codec.dart' show AnicelLaidCel;
import '../photoshop/psd_reader.dart';
import 'media_import_planner.dart' show ImportIdMint;
import 'psd_layer_plan.dart';
import 'raster_cel_import.dart';
import 'tile_cutter.dart' show TileCutter, giveBackCut, laidCelOf, tileCutOf;
import '../../models/import/import_warning.dart';

/// The pixel half of EXPAND: read the document, plan the stack, and turn
/// each layer's own pixels into a cel surface at the place the plan says.
///
/// Kept out of the session for the usual reason — the session is the file
/// every round in this repo touches, and this is a hundred lines that only
/// one verb needs.

/// One expanded layer's cel, ready to donate.
class PsdExpandedCel {
  const PsdExpandedCel({
    required this.layerId,
    required this.frameId,
    required this.surface,
  });

  final LayerId layerId;
  final FrameId frameId;
  final BitmapSurface surface;
}

class PsdExpansion {
  const PsdExpansion({
    required this.layers,
    required this.cels,
    required this.warnings,
    required this.canvas,
  });

  /// Bottom-first, folder rows above their members.
  final List<Layer> layers;
  final List<PsdExpandedCel> cels;
  final List<ImportWarning> warnings;

  /// The canvas the stack was laid out on — the document's own size when
  /// the stack makes a NEW cut ([readPsdExpansion]'s `newCut`).
  final CanvasSize canvas;
}

/// Expands [bytes] into layers and cel surfaces, or null when the document
/// has no layer stack to expand (a flattened PSD — which the MERGE reading
/// handles perfectly well).
///
/// [newCut]: the stack makes a cut of its own — laid out at the document's
/// own size, and standing in it unwrapped ([planPsdExpansion]).
///
/// Each layer's pixels are cut where the document is read ([_readAndCut]):
/// the isolate that paints takes their tiles, and lays on the engine only
/// those a fit resamples ([layCut]). ↩️(2026-11-14, card
/// a-raster-import-goes-gpu-cpu-gpu-cpu) the document's pixels came here
/// and each layer was cut here — 10 layers of 2400×1600 held it 185 ms
/// laid 1:1, 411 ms fitted (Surface, test engine).
Future<PsdExpansion?> readPsdExpansion({
  required Uint8List bytes,
  required String displayName,
  required CutId cutId,
  required int duration,
  required CanvasSize canvas,
  required MediaFitMode fit,
  required ImportIdMint mint,
  required bool newCut,
}) async {
  // Off the UI isolate: a layout PSD is routinely a hundred megabytes, and
  // its layer section is the expensive half.
  final read = await Isolate.run(
    () => _readAndCut(bytes, canvas: canvas, fit: fit, newCut: newCut),
  );
  if (read == null) {
    return null;
  }
  final (:document, :laidOn, :cuts) = read;
  try {
    final plan = planPsdExpansion(
      document: document,
      displayName: displayName,
      cutId: cutId,
      duration: duration,
      canvas: laidOn,
      fit: fit,
      mint: mint,
      newCut: newCut,
    );
    final cels = <PsdExpandedCel>[];
    for (final placement in plan.placements) {
      final cut = cuts.remove(placement.sourceIndex);
      cels.add(
        PsdExpandedCel(
          layerId: placement.layerId,
          frameId: placement.frameId,
          surface: cut == null
              ? nothingLaid(laidOn)
              : await layCut(cut.lay, cut.cel),
        ),
      );
    }
    return PsdExpansion(
      layers: plan.layers,
      cels: cels,
      warnings: plan.warnings,
      canvas: laidOn,
    );
  } finally {
    // A cut no cel took: nothing adopts its blocks, so they go back here.
    for (final cut in cuts.values) {
      giveBackCut(cut.cel.tiles);
    }
  }
}

/// What the isolate that read a Photoshop document hands back: the
/// document, the canvas its stack is laid on, and each layer an expansion
/// lays cut there by its lay — by the layer's index.
typedef _ReadAndCut = ({
  PsdDocument document,
  CanvasSize laidOn,
  Map<int, ({CelLay lay, AnicelLaidCel cel})> cuts,
});

/// [bytes] read as a Photoshop document and each layer an expansion lays
/// ([psdLayersLaid]) cut where it was read — or null when it has no layers.
_ReadAndCut? _readAndCut(
  Uint8List bytes, {
  required CanvasSize canvas,
  required MediaFitMode fit,
  required bool newCut,
}) {
  final document = readPsdDocument(bytes);
  if (document.layers.isEmpty) {
    return null;
  }
  // A NEW cut is made at the document's own size, which is only known once
  // the header has been read — here.
  final laidOn = newCut
      ? CanvasSize(width: document.width, height: document.height)
      : canvas;
  final laid = psdLayersLaid(document: document, canvas: laidOn, fit: fit);
  final cuts = <int, ({CelLay lay, AnicelLaidCel cel})>{};
  try {
    for (final MapEntry(key: index, value: at) in laid.entries) {
      final source = document.layers[index];
      final crop = at.crop;
      final lay = celLayOf(
        picture: CanvasSize(width: crop.width, height: crop.height),
        canvas: laidOn,
        // The rect already carries the document's fit — fitting each layer
        // on its own would scatter a stack that lines up in Photoshop.
        placement: rectPlacement(
          at.rect,
          width: crop.width,
          height: crop.height,
        ),
      );
      if (lay == null) {
        continue;
      }
      // Its rows packed one at a time straight into the tiles they land in
      // — the layer is never held whole, only its planes and the row under
      // way, as a PNG's rows go in as they are inflated (`cutFileInWorker`).
      // ↩️Each layer was packed whole as the document was read and cropped
      // to a copy of its own here till 2026-11-16 (card
      // psd-planes-pack-on-the-engine): 27–29 % of laying an 8K document of
      // four layers out, nearly all of it the fresh RGBA's first touch.
      final picture = source.picture!;
      final tiles = TileCutter.cutting(
        tileCutOf(lay.cut),
        crop.width,
        (row) => picture.rows(crop, row: row),
      );
      cuts[index] = (lay: lay, cel: laidCelOf(lay.cut.layout, tiles));
    }
  } on Object {
    for (final cut in cuts.values) {
      giveBackCut(cut.cel.tiles);
    }
    rethrow;
  }
  return (document: document, laidOn: laidOn, cuts: cuts);
}
