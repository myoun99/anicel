import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/face_ink_well.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/drawn_shapes.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」): a strip is
/// one face, its edge two fills; a pill's hover and choice are its share of
/// the strip's inside — the inside cut by the pill's box — and nothing is
/// clipped to the strip's corners. An even strip's opaque frame hid its
/// pills' hover (an-even-pill-strip-hides-its-hover); the share lies on it.
void main() {
  final theme = buildAppTheme();
  final hover = theme.hoverColor.withAlpha(
    (theme.hoverColor.a * 255).round(),
  );

  List<PillItem> items({int? chosen}) => [
    for (final (index, word) in ['Aa', 'Bb', 'Cc'].indexed)
      PillItem(
        keyValue: 'pill-$index',
        label: word,
        selected: index == chosen,
        onTap: () {},
      ),
  ];

  Future<RenderObject> pumpStrip(WidgetTester tester, Widget strip) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 180, child: strip),
          ),
        ),
      ),
    );
    return tester.renderObject(find.byType(SharedFace));
  }

  Future<void> hoverPill(WidgetTester tester, int index) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(ValueKey<String>('pill-$index'))),
    );
    await tester.pump();
  }

  /// [index]'s box where the strip paints it.
  Rect pillIn(WidgetTester tester, int index) => tester
      .getRect(find.byKey(ValueKey<String>('pill-$index')))
      .shift(-tester.getTopLeft(find.byType(SharedFace)));

  /// The strip's inside where it paints it: its shape, the hairline in.
  RSuperellipse insideOf(WidgetTester tester) => AppShapes.container(
    AppShapes.wellRadius,
  ).borderRadius
      .resolve(TextDirection.ltr)
      .toRSuperellipse(Offset.zero & tester.getSize(find.byType(SharedFace)))
      .deflate(1);

  testWidgets('a strip is one face, its edge two fills, and clips nothing', (
    tester,
  ) async {
    final strip = await pumpStrip(tester, PillStrip(items: items()));
    expect(
      strip,
      paints
        ..rsuperellipse(color: theme.dividerColor)
        ..rsuperellipse(
          rsuperellipse: insideOf(tester),
          color: AppColors.surface,
        ),
    );
    expect(strip, paintsExactlyCountTimes(#clipRSuperellipse, 0));
    expect(strip, paintsExactlyCountTimes(#clipPath, 0));
  });

  /// Inside [index]'s box, and inside each of its neighbours'.
  Offset centreOf(WidgetTester tester, int index) =>
      pillIn(tester, index).center;
  List<Offset> besides(WidgetTester tester, int index) => [
    for (var other = 0; other < 3; other += 1)
      if (other != index) centreOf(tester, other),
  ];

  testWidgets('a pill in the middle fills its own box with the hover', (
    tester,
  ) async {
    final strip = await pumpStrip(tester, PillStrip(items: items()));
    await hoverPill(tester, 1);
    expect(
      strip,
      paintsShape(
        color: hover,
        includes: [centreOf(tester, 1)],
        excludes: besides(tester, 1),
      ),
    );
  });

  testWidgets('the first pill fills the strip\'s inside where it lies — the '
      'strip\'s corner drawn by its formula, cut by the pill\'s box', (
    tester,
  ) async {
    final strip = await pumpStrip(tester, PillStrip(items: items()));
    await hoverPill(tester, 0);
    expect(
      strip,
      paints
        ..clipRect(rect: pillIn(tester, 0))
        ..rsuperellipse(rsuperellipse: insideOf(tester), color: hover),
    );
  });

  testWidgets('a chosen pill\'s wash is its share, and the hover lies over '
      'it', (tester) async {
    final wash = theme.colorScheme.primary.withValues(alpha: 0.14);
    final strip = await pumpStrip(tester, PillStrip(items: items(chosen: 1)));
    expect(
      strip,
      paintsShape(
        color: wash,
        includes: [centreOf(tester, 1)],
        excludes: besides(tester, 1),
      ),
      reason: 'at rest',
    );
    await hoverPill(tester, 1);
    expect(
      strip,
      paintsShape(
        color: Color.alphaBlend(hover, wash),
        includes: [centreOf(tester, 1)],
        excludes: besides(tester, 1),
      ),
      reason: 'hovered',
    );
  });

  testWidgets('an even strip\'s hover lies on its frame, where the frame hid '
      'it', (tester) async {
    final strip = await pumpStrip(tester, PillStrip.even(items: items()));
    await hoverPill(tester, 1);
    final drawn = DrawnShapes.of(strip);
    final frame = drawn.indexWhere(
      (shape) =>
          shape.paint.color.toARGB32() == AppColors.surface.toARGB32(),
    );
    final share = drawn.indexWhere(
      (shape) => shape.paint.color.toARGB32() == hover.toARGB32(),
    );
    expect(frame, isNonNegative, reason: 'the frame is filled');
    expect(share, greaterThan(frame), reason: 'the hover lies on it');
    expect(
      strip,
      paintsShape(
        color: hover,
        includes: [centreOf(tester, 1)],
        excludes: besides(tester, 1),
      ),
    );
  });
}
