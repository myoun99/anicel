import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';

import 'drawn_shapes.dart';

/// What the band of the grip [gripKey] names paints, where the screen has
/// it: nothing while the band is clear, its ink over the rows it covers
/// while it shows — whether its own box paints it or the sheet over it
/// does (`LiveSheet`).
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2): a band
/// is its owner's shape cut to the band's rows, not a box clipped to the
/// owner's corner — so it is read as the shape it covers.
List<DrawnShape> gripBandDrawn(WidgetTester tester, Key gripKey) {
  final band = find
      .descendant(
        of: find
            .ancestor(
              of: find.byKey(gripKey),
              matching: find.byWidgetPredicate(
                (widget) => widget is LiftingGripBand,
              ),
            )
            .first,
        matching: find.byElementPredicate(
          (element) => element.renderObject is RenderGripBand,
        ),
      )
      .first;
  final box = tester.renderObject<RenderGripBand>(band);
  final origin = box.localToGlobal(Offset.zero);
  return [
    for (final shape in DrawnShapes.by(box.debugPaintBand))
      (outline: shape.outline.shift(origin), paint: shape.paint),
  ];
}
