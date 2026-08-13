import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/straight_rgba_image.dart';
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
  });

  /// Bottom-first, folder rows above their members.
  final List<Layer> layers;
  final List<PsdExpandedCel> cels;
  final List<String> warnings;
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
}) async {
  // Off the UI isolate: a layout PSD is routinely a hundred megabytes, and
  // its layer section is the expensive half.
  final document = await Isolate.run(() => readPsdDocument(bytes));
  if (document.layers.isEmpty) {
    return null;
  }
  final plan = planPsdExpansion(
    document: document,
    displayName: displayName,
    cutId: cutId,
    duration: duration,
    canvas: canvas,
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
    final image = await _imageFrom(
      pixels,
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
            canvas: canvas,
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
  );
}

Future<ui.Image> _imageFrom(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  final completer = Completer<ui.Image>();
  decodeStraightRgbaImage(
    rgba: rgba,
    width: width,
    height: height,
    onDecoded: completer.complete,
  );
  return completer.future;
}
