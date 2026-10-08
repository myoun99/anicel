import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../envelope/cut_envelope_painter.dart';
import 'offscreen_raster.dart';

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
/// ([CutEnvelopePainter], fit-to-size path) — what the envelope panel shows
/// is what exports, the timesheet render's rule — the sheet WHOLE: its
/// paper, its form, what is filled in and what is written over it.
///
/// 🪦It could draw a chosen few of the strata, a call a layer — how the
/// export's 「레이어마다 한 장」 shipped. 유저 2026-10-05: 「레이어 항목
/// 버튼? 용지 서식 내용 선화 고르는거 싹 다 필요없어보이니 삭제」.
Future<ui.Image> renderCutEnvelopeImage({
  required CutEnvelopeLayout layout,
  required CutEnvelopeSource source,
  required TextStyle face,
  ui.Image? Function(String assetPath)? imageFor,
  CutId? inkOwner,
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
  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) => CutEnvelopePainter(
      layout: layout,
      source: source,
      face: face,
      imageFor: imageFor,
      inkOwner: inkOwner,
      inkImageFor: inkImageFor,
    ).paint(canvas, ui.Size(width.toDouble(), height.toDouble())),
  );
}
