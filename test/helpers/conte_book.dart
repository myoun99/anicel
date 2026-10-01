import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show Offset, ValueKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/page_stack.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
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

/// The printed form of the first body page on screen — the page
/// [onConteBody] seeds the view on. The view is held to the book's paper
/// (F-201), so the book's other pages can share the screen with it: a
/// test that reads where the page lies finds it by its page, not as the
/// one form there is.
Finder conteBodyForm() => find.descendant(
  of: _conteBodyPage(),
  matching: find.byKey(const ValueKey<String>('conte-form-paint')),
);

/// The first body page on screen.
Finder _conteBodyPage() => find
    .byWidgetPredicate(
      (widget) =>
          widget is ConteBookPage && widget.page.kind == ContePageKind.body,
    )
    .first;

/// Where the first body page on screen has its top-left, on screen — the
/// panel's box moved by the view the page is printed through. That view is
/// held to the book's paper (F-201), so a page [onConteBody] seeded at
/// the origin can stand elsewhere: a narrower book in the middle, a last
/// page shorter than the panel at the paper's end.
Offset conteBodyTopLeft(WidgetTester tester) {
  final page = _conteBodyPage();
  final view = tester.widget<ConteBookPage>(page).viewport;
  return tester.getTopLeft(page) + Offset(view.panX, view.panY);
}

/// A stroke of round [color] dabs, each [size] wide, at [paper] points on
/// [cell]'s band — in its ink surface's own pixels: the body's plane, laid
/// at the ink's scale from the band's corner.
BrushStrokeCommitData conteBandDabs(
  ContePlacedCell cell,
  ConteSheetMetrics metrics,
  List<Offset> paper, {
  required int color,
  double size = 12,
}) {
  final band = cell.rowBandRect(metrics);
  return BrushStrokeCommitData(
    sourceDabs: [
      for (final (index, at) in paper.indexed)
        BrushDab(
          center: CanvasPoint(
            x: (at.dx - band.left) * conteInkScale,
            y: (at.dy - band.top) * conteInkScale,
          ),
          color: color,
          size: size,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: index,
        ),
    ],
  );
}
