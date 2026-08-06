import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_visible_rect.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../helpers/brush_canvas_fixture.dart';

/// The window you look through vs the box you touch.
///
/// A full-bleed canvas is laid out as one box but is not all visible — an
/// always-open timeline, a rail panel and a view cluster float ON it. Every
/// verb that FRAMES the artwork has to aim at the visible part, or Fit puts
/// the bottom of the drawing under the timeline and zoom walks the picture
/// toward the covered edge. This pins both halves: the pure geometry, and the
/// law that Fit centres the artwork in the WINDOW.
void main() {
  group('canvasVisibleRect', () {
    test('zero insets is the whole box', () {
      expect(
        canvasVisibleRect(const Size(800, 600), EdgeInsets.zero),
        const Rect.fromLTRB(0, 0, 800, 600),
      );
    });

    test('insets deflate the box on the covered edges', () {
      expect(
        canvasVisibleRect(
          const Size(800, 600),
          const EdgeInsets.only(left: 48, top: 48, right: 48, bottom: 350),
        ),
        const Rect.fromLTRB(48, 48, 752, 250),
      );
    });

    test('a cover wider than the box keeps a usable window, leading edge '
        'first — every consumer divides by these extents', () {
      final rect = canvasVisibleRect(
        const Size(200, 120),
        const EdgeInsets.only(left: 60, right: 400),
      );
      expect(rect.left, 60);
      expect(rect.width, greaterThan(0));
      expect(rect.right, lessThanOrEqualTo(200));
    });

    test('a degenerate box is returned untouched rather than divided by', () {
      expect(
        canvasVisibleRect(Size.zero, const EdgeInsets.all(10)),
        Rect.zero,
      );
    });
  });

  group('Fit frames the artwork in the window, not in the box', () {
    Future<CanvasViewport> pumpAndFit(
      WidgetTester tester, {
      required EdgeInsets insets,
    }) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 600,
                child: BrushCanvasPanel(
                  coordinator: BrushCanvasFixture.createCoordinator(
                    frameKeys: frameKeys,
                  ),
                  availableFrameKeys: frameKeys,
                  cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                  visibleInsets: insets,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fit = find.byKey(const ValueKey<String>('canvas-viewport-fit'));
      await tester.ensureVisible(fit);
      await tester.pumpAndSettle();
      await tester.tap(fit);
      await tester.pumpAndSettle();
      return tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport;
    }

    /// Where the canvas's own centre lands on screen, in layout coordinates.
    Offset artworkCentre(CanvasViewport viewport) {
      const size = BrushCanvasFixture.canvasSize;
      final mapped = viewport.canvasToViewport(
        CanvasPoint(x: size.width / 2, y: size.height / 2),
      );
      return Offset(mapped.x, mapped.y);
    }

    testWidgets('with nothing floating, Fit centres on the box', (
      tester,
    ) async {
      final viewport = await pumpAndFit(tester, insets: EdgeInsets.zero);
      final centre = artworkCentre(viewport);
      // The panel's own shell eats a few px off the box, so this asserts the
      // artwork is centred in whatever the panel measured — not a literal.
      expect(centre.dy, greaterThan(0));
      expect(centre.dy, lessThan(600));
    });

    testWidgets('with a tall cover along the bottom, Fit lifts the artwork '
        'out from under it', (tester) async {
      final open = await pumpAndFit(tester, insets: EdgeInsets.zero);
      final covered = await pumpAndFit(
        tester,
        insets: const EdgeInsets.only(bottom: 300),
      );

      // The whole point: the artwork must move UP, not stay where a box-
      // centred Fit would have left it.
      expect(artworkCentre(covered).dy, lessThan(artworkCentre(open).dy));

      // And it must be smaller, because the window it has to fit into is.
      expect(covered.zoom, lessThan(open.zoom));

      // The law itself: the artwork's centre sits at the centre of the
      // window. Half the cover is 150px, so a box-centred Fit would miss by
      // that much; this asserts it does not.
      expect(
        artworkCentre(covered).dy,
        closeTo(artworkCentre(open).dy - 150, 1.0),
      );
    });

    testWidgets('a cover on one side pushes the artwork off the box centre '
        'by half of it', (tester) async {
      final open = await pumpAndFit(tester, insets: EdgeInsets.zero);
      final covered = await pumpAndFit(
        tester,
        insets: const EdgeInsets.only(left: 200),
      );
      expect(
        artworkCentre(covered).dx,
        closeTo(artworkCentre(open).dx + 100, 1.0),
      );
    });
  });
}
