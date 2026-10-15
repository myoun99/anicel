import 'dart:ui' as ui;

import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';

/// A sheet's media images as a test hands them to an export render: each
/// path's picture from [images] — a clone per read, as the run owns and
/// lets go of what it reads — whatever width is asked, which [asks] (when
/// given) keeps, in the order asked.
SheetImageRun sheetImageRunOf(
  Map<String, ui.Image> images, {
  List<({String path, int? width})>? asks,
}) => SheetImageRun((path, width) async {
  asks?.add((path: path, width: width));
  return images[path]?.clone();
});
