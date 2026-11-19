import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/import/tvpp_raster_decoder.dart';

/// [slot]'s picture whole — its rows ([TvppPicturesInOrder.read]) laid into
/// one straight RGBA buffer, clear where no row was handed on — for a check
/// against a whole picture. Null for a hold slot.
Uint8List? tvppSlotRgba({
  required Uint8List recordBytes,
  required TvppSlot slot,
  required int width,
  required int height,
}) {
  if (slot.kind == TvppSlotKind.hold) {
    return null;
  }
  final rgba = Uint8List(width * height * 4);
  final stride = width * 4;
  TvppPicturesInOrder().read(
    recordBytes: recordBytes,
    slot: slot,
    size: CanvasSize(width: width, height: height),
    row: (y, row) => rgba.setRange(y * stride, (y + 1) * stride, row),
  );
  return rgba;
}
