import 'dart:ui' as ui;

import '../../models/sheet_paint_layer.dart';
import '../../services/media/still_file_writing.dart' show StillPixels;
import '../../services/straight_rgba_image.dart' show straightRgbaOf;
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
/// alone by [draw], laid whole, and named as the stratum is — in the
/// notation language, as the sheet prints ([AppText.notation]).
List<ExportLayerRow> sheetStrataRows(
  List<SheetPaintLayer> strata,
  Future<ui.Image> Function(Set<SheetPaintLayer> layers) draw,
) => [
  for (final stratum in strata)
    ExportLayerRow(
      name: _nameOf(stratum),
      draw: () async => _pixelsOf(await draw({stratum})),
    ),
];

/// [picture] — one Flutter drew of a sheet, which the raster thread made —
/// as a row's pixels ([ExportLayerRow]), and let go.
Future<StillPixels> _pixelsOf(ui.Image picture) async {
  final (width, height) = (picture.width, picture.height);
  try {
    return (
      pixels: await straightRgbaOf(picture),
      width: width,
      height: height,
      channels: 4,
    );
  } finally {
    picture.dispose();
  }
}

String _nameOf(SheetPaintLayer stratum) => switch (stratum) {
  SheetPaintLayer.paper => AppText.notation.exStratumPaper,
  SheetPaintLayer.form => AppText.notation.exStratumForm,
  SheetPaintLayer.content => AppText.notation.exStratumContent,
  SheetPaintLayer.picture => AppText.notation.exStratumPicture,
  SheetPaintLayer.ink => AppText.notation.exStratumInk,
};
