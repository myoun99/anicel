import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/face_ink_well.dart';
import 'package:anicel/src/ui/widgets/icon_button_box.dart';

import '../../helpers/drawn_shapes.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」): a well's
/// hover and focus are its face's inside — the ground it stands on, its own
/// fill over that, the highlight over both — and its edge two fills.
void main() {
  const size = Size(40, 24);
  const key = ValueKey<String>('well');
  final theme = buildAppTheme();
  final edge = AppShapes.container(
    AppShapes.wellRadius,
    side: BorderSide(color: AppColors.hairline),
  );
  final outer = edge.borderRadius
      .resolve(TextDirection.ltr)
      .toRSuperellipse(Offset.zero & size);
  Color whole(Color ink) => ink.withAlpha((ink.a * 255).round());
  final hover = whole(theme.hoverColor);
  final focus = whole(theme.focusColor);

  Future<RenderObject> pumpWell(
    WidgetTester tester, {
    RoundedSuperellipseBorder? shape,
    Color? fill,
    bool live = true,
    bool groundSaid = false,
    Color? ground,
  }) async {
    Widget well = FaceInkWell(
      key: key,
      edge: shape ?? edge,
      fill: fill,
      onTap: live ? () {} : null,
      child: SizedBox.fromSize(size: size),
    );
    if (groundSaid) {
      well = FaceGround(ground: ground, child: well);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: Align(alignment: Alignment.topLeft, child: well),
        ),
      ),
    );
    return tester.renderObject(find.byKey(key));
  }

  Future<void> hoverIt(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byKey(key)));
    // ⛔One frame: the face shows the hover at once, as an icon button's
    // does — an InkWell's ink faded in over 50 ms.
    await tester.pump();
  }

  PaintPattern twoFills(Color inside) => paints
    ..rsuperellipse(rsuperellipse: outer, color: AppColors.hairline)
    ..rsuperellipse(rsuperellipse: outer.deflate(1), color: inside);

  testWidgets('at rest, its inside is the ground it stands on, and its edge '
      'two fills', (tester) async {
    expect(await pumpWell(tester), twoFills(AppColors.surface));
  });

  testWidgets('under the mouse, the hover fills its inside over the ground — '
      'on the first frame', (tester) async {
    final well = await pumpWell(tester);
    await hoverIt(tester);
    expect(well, twoFills(Color.alphaBlend(hover, AppColors.surface)));
  });

  testWidgets('a chosen cell\'s fill lies over the ground, the hover over '
      'the fill', (tester) async {
    final fill = theme.colorScheme.surfaceContainerHigh;
    final well = await pumpWell(tester, fill: fill);
    expect(well, twoFills(fill), reason: 'at rest');
    await hoverIt(tester);
    expect(
      well,
      twoFills(Color.alphaBlend(hover, fill)),
      reason: 'hovered',
    );
  });

  testWidgets('a dead well shows no hover', (tester) async {
    final well = await pumpWell(tester, live: false);
    await hoverIt(tester);
    expect(well, twoFills(AppColors.surface));
  });

  testWidgets('the keyboard\'s focus fills its inside; a pointer\'s does not',
      (tester) async {
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final well = await pumpWell(tester);
    Focus.of(
      tester.element(
        find.descendant(of: find.byKey(key), matching: find.byType(SizedBox)),
      ),
    ).requestFocus();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    expect(
      well,
      twoFills(Color.alphaBlend(focus, AppColors.surface)),
      reason: 'the keyboard',
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    expect(well, twoFills(AppColors.surface), reason: 'a pointer');
  });

  testWidgets('on a ground it is told of, its inside is that ground', (
    tester,
  ) async {
    const wash = Color(0xFF334455);
    expect(
      await pumpWell(tester, groundSaid: true, ground: wash),
      twoFills(wash),
    );
  });

  testWidgets('on no one colour its edge is a stroke, and the hover fills '
      'the shape alone', (tester) async {
    final well = await pumpWell(tester, groundSaid: true);
    await hoverIt(tester);
    expect(
      DrawnShapes.of(well).map((drawn) => drawn.paint.style),
      containsAll([PaintingStyle.fill, PaintingStyle.stroke]),
    );
    expect(well, isNot(paints..rsuperellipse(color: AppColors.surface)));
    expect(well, paints..rsuperellipse(color: hover));
  });

  testWidgets('a clear well paints nothing at rest, and its hover fills its '
      'shape', (tester) async {
    final clear = AppShapes.container(AppShapes.wellRadius);
    final well = await pumpWell(tester, shape: clear);
    expect(well, paintsExactlyCountTimes(#drawRSuperellipse, 0));
    await hoverIt(tester);
    expect(well, paints..rsuperellipse(rsuperellipse: outer, color: hover));
  });

  testWidgets('the well lays no ink of its own', (tester) async {
    await pumpWell(tester);
    await hoverIt(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.renderObject(find.byType(Material)),
      isNot(paints..path(color: hover)),
    );
    expect(
      tester.renderObject(find.byType(Material)),
      isNot(paints..rect(color: hover)),
    );
  });
}
