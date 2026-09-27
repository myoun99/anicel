import 'dart:math' as math;
import 'dart:ui';

import 'package:anicel/src/core/page_stack.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// [view] moved so the conte book's first body page stands at the panel's
/// content origin — where the panel's one page stood before the book's
/// pages lay one under another (F-201). A test that maps a page's own
/// coordinates to the screen one for one seeds its view with this.
CanvasViewport onConteBody(
  EditorSessionManager session,
  CanvasViewport view,
) {
  final pages = layoutConteBook(
    buildConteSheetSource(session.repository.requireProject()),
    metrics: ConteSheetMetrics(cameraAspect: session.camera.cameraFrameAspect),
  );
  final stack = PageStack([
    for (final page in pages)
      Size(page.metrics.pageWidth, page.metrics.pageHeight),
  ]);
  final body = math.max(
    0,
    pages.indexWhere((page) => page.kind == ContePageKind.body),
  );
  final at = stack.pageRect(body).topLeft;
  return view.translated(dx: -at.dx * view.zoom, dy: -at.dy * view.zoom);
}
