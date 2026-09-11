import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../straight_rgba_image.dart';
import '../../models/bitmap_surface.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../photoshop/psd_reader.dart';
import 'media_import_planner.dart' show ImportIdMint;
import 'psd_layer_plan.dart';
import 'raster_cel_import.dart';

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
  final List<String> warnings;

  /// The canvas the stack was laid out on — the document's own size when
  /// the stack makes a NEW cut ([readPsdExpansion]'s `canvasFromDocument`).
  final CanvasSize canvas;
}

/// Expands [bytes] into layers and cel surfaces, or null when the document
/// has no layer stack to expand (a flattened PSD — which the MERGE reading
/// handles perfectly well).
Future<PsdExpansion?> readPsdExpansion({
  required Uint8List bytes,
  required String displayName,
  required CutId cutId,
  required int duration,
  required CanvasSize canvas,
  required MediaFitMode fit,
  required ImportIdMint mint,
  bool canvasFromDocument = false,
}) async {
  // Off the UI isolate: a layout PSD is routinely a hundred megabytes, and
  // its layer section is the expensive half.
  final document = await Isolate.run(() => readPsdDocument(bytes));
  if (document.layers.isEmpty) {
    return null;
  }
  // A NEW cut is made at the document's own size, which is only known once
  // the header has been read — here.
  final laidOn = canvasFromDocument
      ? CanvasSize(width: document.width, height: document.height)
      : canvas;
  final plan = planPsdExpansion(
    document: document,
    displayName: displayName,
    cutId: cutId,
    duration: duration,
    canvas: laidOn,
    fit: fit,
    mint: mint,
  );

  final cels = <PsdExpandedCel>[];
  for (final placement in plan.placements) {
    final source = document.layers[placement.sourceIndex];
    final pixels = source.pixels;
    if (pixels == null) {
      continue;
    }
    final image = await decodeStraightRgbaImage(
      rgba: pixels,
      width: source.width,
      height: source.height,
    );
    try {
      cels.add(
        PsdExpandedCel(
          layerId: placement.layerId,
          frameId: placement.frameId,
          // The rect comes from the plan, which already carried the
          // document's fit — fitting each layer on its own would scatter a
          // stack that lines up in Photoshop.
          surface: await rasterizeImageToSurface(
            image: image,
            canvas: laidOn,
            fit: fit,
            placement: placement.rect,
          ),
        ),
      );
    } finally {
      // One layer's picture at a time: eighty full-canvas layers held at
      // once is how expanding a background runs a tablet out of memory.
      image.dispose();
    }
  }

  return PsdExpansion(
    layers: plan.layers,
    cels: cels,
    warnings: plan.warnings,
    canvas: laidOn,
  );
}
