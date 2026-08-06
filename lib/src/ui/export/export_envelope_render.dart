import 'dart:ui' as ui;

import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../envelope/cut_envelope_painter.dart';

/// One envelope the export writes: the sheet of one cut (and of every
/// 겸용 sibling it shares a folder with), already laid out on its paper.
class ExportEnvelopeTask {
  const ExportEnvelopeTask({
    required this.owner,
    required this.layout,
    required this.source,
  });

  /// The cut that OWNS the sheet — the representative sibling. Its canvas
  /// sizes the cut-fitted paper and its name the file.
  final Cut owner;

  final CutEnvelopeLayout layout;
  final CutEnvelopeSource source;
}

/// Renders one cut envelope offscreen with the panel's own renderer
/// ([CutEnvelopePainter], fit-to-size path) — what the Envelope tab shows
/// is what exports, the timesheet render's rule.
///
/// [layers] names the strata to draw; null draws all four. A separate call
/// per layer is how the PSD-style layered output ships as PNGs, and each
/// one lines up with the others because they share this one layout.
Future<ui.Image> renderCutEnvelopeImage({
  required CutEnvelopeLayout layout,
  required CutEnvelopeSource source,
  Set<SheetPaintLayer>? layers,
  ui.Image? Function(String assetPath)? imageFor,
  BrushFrameKey Function(String boxId)? inkKeyFor,
  ui.Image? Function(BrushFrameKey key)? inkImageFor,
  ({int width, int height})? outputSize,
}) {
  final width = (outputSize?.width ?? layout.paperWidth.round()).clamp(
    1,
    1 << 16,
  );
  final height = (outputSize?.height ?? layout.paperHeight.round()).clamp(
    1,
    1 << 16,
  );
  final recorder = ui.PictureRecorder();
  CutEnvelopePainter(
    layout: layout,
    source: source,
    layers: layers,
    imageFor: imageFor,
    inkKeyFor: inkKeyFor,
    inkImageFor: inkImageFor,
  ).paint(ui.Canvas(recorder), ui.Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  try {
    return picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
