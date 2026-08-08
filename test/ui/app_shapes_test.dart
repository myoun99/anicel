import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/superellipse_clip.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

void main() {
  group('AppShapes — the app has one corner', () {
    test('a control keeps the same shape at every size', () {
      // Not "the numbers are these numbers" — the LAW is that the corner is
      // a fixed fraction of the control, so 42, 34 and 32 read as one
      // family. Editing one size's corner without the others is what makes
      // the small button look like a different button.
      const sizes = [
        AppShapes.controlLarge,
        AppShapes.controlMedium,
        AppShapes.controlSmall,
      ];
      for (final size in sizes) {
        expect(
          AppShapes.controlRadius(size) / size,
          closeTo(AppShapes.controlCornerRatio, 1e-9),
          reason: 'control of $size px drifted off the family ratio',
        );
      }
      // And they are genuinely different sizes, so the check above is not
      // passing on a degenerate list.
      expect(sizes.toSet(), hasLength(3));
    });

    test('only the CORNERS bend — the sides stay straight', () {
      // The first drawing of this was wrong: a rectangle drawn ENTIRELY as
      // a superellipse bows its edges, which is absurd on a 1800px panel
      // edge. A long strip is the case that tells the two apart.
      const strip = Rect.fromLTWH(0, 0, 1800, AppShapes.controlLarge);
      final path = AppShapes.control(
        AppShapes.controlLarge,
      ).getOuterPath(strip);

      // Mid-edge, half a pixel inside: on a straight side this is in, on a
      // bowed one the edge has pulled away from the box and it is out.
      expect(path.contains(Offset(strip.center.dx, strip.top + 0.5)), isTrue);
      expect(
        path.contains(Offset(strip.center.dx, strip.bottom - 0.5)),
        isTrue,
      );
      expect(path.contains(Offset(strip.left + 0.5, strip.center.dy)), isTrue);

      // The extreme corner is cut away — that is the whole point of having
      // a corner at all.
      expect(path.contains(strip.topLeft), isFalse);
      expect(
        path.contains(strip.bottomRight - const Offset(0.5, 0.5)),
        isFalse,
      );
    });

    test('a container corner is absolute, not a fraction', () {
      // A panel is not a big button. Were the container family a ratio, the
      // floating timeline at 350px tall would wear a 98px corner.
      expect(
        AppShapes.floatingPanelRadius,
        greaterThan(AppShapes.windowRadius),
      );
      expect(AppShapes.windowRadius, greaterThan(AppShapes.wellRadius));
      expect(
        AppShapes.floatingPanelRadius,
        lessThan(AppShapes.controlRadius(350)),
      );
    });
  });

  group('AppShapes.clipper', () {
    testWidgets('a clipped corner does NOT swallow the pointer', (
      tester,
    ) async {
      // This is the guard the floating timeline stands on. `ClipRSuperellipse`
      // paints the same picture but its `hitTest` asks only
      // `outerRect.contains()`, so each cut-away corner stays a live square
      // that eats strokes aimed at the canvas underneath it.
      final hits = <String>[];
      const size = 200.0;
      const radius = 40.0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  // The "canvas": everything below the floating panel.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => hits.add('below'),
                    ),
                  ),
                  // The "floating panel".
                  Positioned.fill(
                    child: SuperellipseClip(
                      shape: AppShapes.container(radius),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => hits.add('panel'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final panel = tester.getRect(find.byType(SuperellipseClip));

      await tester.tapAt(panel.center);
      expect(hits, ['panel'], reason: 'the body of the panel takes its taps');

      hits.clear();
      // Two pixels in from the extreme corner: outside the superellipse, so
      // the tap belongs to whatever the panel is lying on.
      await tester.tapAt(panel.topLeft + const Offset(2, 2));
      expect(hits, [
        'below',
      ], reason: 'the cut-away corner must fall through to the canvas');

      hits.clear();
      await tester.tapAt(panel.bottomRight - const Offset(2, 2));
      expect(hits, ['below']);
    });
  });
}
