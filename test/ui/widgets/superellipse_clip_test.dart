import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/superellipse_clip.dart';

/// What this clip has to keep is not how it looks — it is that a pointer
/// in a corner the shape CUT AWAY misses whatever is behind it.
///
/// That is the documented reason `AppShapes` bans the stock
/// `ClipRSuperellipse` widget, whose `hitTest` asks only
/// `outerRect.contains`: a floating panel drawn with it swallows strokes
/// in a square of empty canvas at each corner. Swapping `ClipPath` for
/// the engine's superellipse op is only allowed because this asks
/// `RSuperellipse.contains` instead, and these tests are what says so.
///
/// [SuperellipseHit] is the same shape to a pointer, clipping nothing —
/// what a still region holds is not clipped (Q10).
void main() {
  const radius = 24.0;
  const size = Size(200, 200);

  for (final (name, stand) in [
    (
      'SuperellipseClip',
      (Widget child) =>
          SuperellipseClip(shape: AppShapes.container(radius), child: child),
    ),
    (
      'SuperellipseHit',
      (Widget child) =>
          SuperellipseHit(shape: AppShapes.container(radius), child: child),
    ),
  ]) {
    Future<bool> tapLands(WidgetTester tester, Offset at) async {
      var landed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: stand(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => landed = true,
                  child: const ColoredBox(color: Color(0xFF224466)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(at);
      await tester.pump();
      return landed;
    }

    group(name, () {
      testWidgets('the middle is hittable', (tester) async {
        expect(await tapLands(tester, const Offset(100, 100)), isTrue);
      });

      testWidgets('a cut corner is NOT hittable', (tester) async {
        // The extreme corner of the bounding box. A 24px superellipse
        // corner is well inside it, so this point is outside the
        // silhouette — and the stock ClipRSuperellipse widget would have
        // swallowed the tap here, which is exactly the bug this app banned
        // it for.
        expect(
          await tapLands(tester, const Offset(1, 1)),
          isFalse,
          reason: 'the corner it visibly cut away must not eat pointers',
        );
        expect(await tapLands(tester, const Offset(199, 1)), isFalse);
        expect(await tapLands(tester, const Offset(1, 199)), isFalse);
        expect(await tapLands(tester, const Offset(199, 199)), isFalse);
      });

      testWidgets('a point just inside the silhouette still hits', (
        tester,
      ) async {
        // Along the flat of an edge, clear of the corner run.
        expect(await tapLands(tester, const Offset(100, 2)), isTrue);
        expect(await tapLands(tester, const Offset(2, 100)), isTrue);
      });
    });
  }

  testWidgets('a SuperellipseHit clips nothing — what it holds paints as it '
      'lies', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: SuperellipseHit(
              shape: AppShapes.container(radius),
              child: const ColoredBox(color: Color(0xFF224466)),
            ),
          ),
        ),
      ),
    );
    final hit = tester.renderObject(find.byType(SuperellipseHit));
    expect(hit, paintsExactlyCountTimes(#clipRSuperellipse, 0));
    expect(hit, paintsExactlyCountTimes(#clipPath, 0));
    expect(hit, paints..rect(rect: Offset.zero & size));
    expect(
      tester.layers.whereType<ClipRSuperellipseLayer>(),
      isEmpty,
      reason: 'nor as a layer',
    );
  });

  testWidgets('it paints, and survives a resize and a radius change', (
    tester,
  ) async {
    Widget at(double extent, double r) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: extent,
          height: extent,
          child: SuperellipseClip(
            shape: AppShapes.container(r),
            child: const ColoredBox(color: Color(0xFF224466)),
          ),
        ),
      ),
    );

    await tester.pumpWidget(at(200, 24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(at(320, 24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(at(320, 8));
    final render = tester.renderObject<RenderSuperellipseClip>(
      find.byType(SuperellipseClip),
    );
    expect(render.borderRadius, BorderRadius.circular(8));
  });
}
