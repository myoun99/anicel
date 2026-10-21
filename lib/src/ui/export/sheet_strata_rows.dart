import 'dart:ui' as ui;

import '../../models/layer_blend_mode.dart';
import '../../models/sheet_paint_layer.dart';
import '../text/app_strings.dart';
import 'still_image_encoders.dart' show ExportLayerRow;

/// The strata the timesheet and the cut envelope print — every one but
/// the film's pictures, which only the conte shows
/// ([SheetPaintLayer.picture]).
const List<SheetPaintLayer> paperSheetStrata = [
  SheetPaintLayer.paper,
  SheetPaintLayer.form,
  SheetPaintLayer.content,
  SheetPaintLayer.ink,
];

/// A sheet's [strata] as a Photoshop document's rows, bottom-up (I-117 —
/// 유저 2026-10-21: 「타임시트는 알듯이 층 나눠져있는대로 출력. 컷봉투도
/// 마찬가지. 밑 흰색 용지, 서식, 텍스트들, 잉크 이런식으로」): each drawn
/// alone by [draw], laid whole, and named as the stratum is.
List<ExportLayerRow> sheetStrataRows(
  List<SheetPaintLayer> strata,
  Future<ui.Image> Function(Set<SheetPaintLayer> layers) draw,
) => [
  for (final stratum in strata)
    (
      name: _nameOf(stratum),
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      draw: () => draw({stratum}),
    ),
];

String _nameOf(SheetPaintLayer stratum) {
  final strings = AppText.strings;
  return switch (stratum) {
    SheetPaintLayer.paper => strings.exStratumPaper,
    SheetPaintLayer.form => strings.exStratumForm,
    SheetPaintLayer.content => strings.exStratumContent,
    SheetPaintLayer.picture => strings.exStratumPicture,
    SheetPaintLayer.ink => strings.exStratumInk,
  };
}
