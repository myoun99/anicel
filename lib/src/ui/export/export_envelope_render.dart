import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../envelope/cut_envelope_painter.dart';
import '../sheet/sheet_image_cache.dart'
    show SheetImageRun, paintWithSheetImages;
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
/// paper, its form, what is filled in and what is written over it, and the
/// photos laid under the writing ([inkPhotosFor] — I-97). The media images
/// it prints — the logo, a 도장, the photos' files — are the ones it asks
/// [images] for. [layers] draws those strata alone — a Photoshop
/// document's rows ([SheetPaintLayer]); null draws the sheet whole.
///
/// 🪦It could draw a chosen few of the strata, a call a layer — how the
/// export's 「레이어마다 한 장」 shipped. 유저 2026-10-05: 「레이어 항목
/// 버튼? 용지 서식 내용 선화 고르는거 싹 다 필요없어보이니 삭제」.
/// ↩️I-117 (유저 2026-10-21) brought the strata back as the rows of ONE
/// file — 「컷봉투도 마찬가지. 밑 흰색 용지, 서식, 텍스트들, 잉크」 — never
/// as a file each, and with no buttons to pick them.
Future<ui.Image> renderCutEnvelopeImage({
  required CutEnvelopeLayout layout,
  required CutEnvelopeSource source,
  required TextStyle face,
  SheetImageRun? images,
  CutId? inkOwner,
  ui.Image? Function(BrushFrameKey key)? inkImageFor,
  List<CelPhoto> Function(BrushFrameKey key)? inkPhotosFor,
  ({int width, int height})? outputSize,
  Set<SheetPaintLayer>? layers,
}) {
  final width = (outputSize?.width ?? layout.paperWidth.round()).clamp(
    1,
    1 << 16,
  );
  final height = (outputSize?.height ?? layout.paperHeight.round()).clamp(
    1,
    1 << 16,
  );
  void paintEnvelope(ui.Canvas canvas) => CutEnvelopePainter(
    layout: layout,
    source: source,
    face: face,
    imageFor: images?.imageFor,
    inkOwner: inkOwner,
    inkImageFor: inkImageFor,
    inkPhotosFor: inkPhotosFor,
    layers: layers,
  ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) => paintWithSheetImages(canvas, images, paintEnvelope),
  );
}
