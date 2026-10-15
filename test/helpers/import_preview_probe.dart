import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/viewport_pages_painter.dart';

/// The import window's preview, read as it is DRAWN — the page its panel
/// paints and what stands under it (`DocumentPreviewPanel`, F-282 ④).
/// ↩️It was a 16:9 well, its checker a widget of its own
/// (`import-preview-checker`).
extension ImportPreviewProbe on WidgetTester {
  /// The page as its painter holds it, or null while nothing is on show.
  ViewportPagesPainter? get importPreviewPage {
    final page = find.byKey(const ValueKey<String>('import-preview-page'));
    return page.evaluate().isEmpty
        ? null
        : widget<CustomPaint>(page).painter as ViewportPagesPainter?;
  }

  /// The picture that is up, or null while none is.
  ui.Image? get importPreviewImage =>
      importPreviewPage?.pages.firstOrNull?.image;

  /// Whether the page stands on the app's one transparency checker.
  bool get importPreviewCheckered =>
      importPreviewPage?.ground == ViewportPageGround.checker;
}
