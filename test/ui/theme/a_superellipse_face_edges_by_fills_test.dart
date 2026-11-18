import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q9 (유저 2026-11-08, 2): a filled
/// corner's edge is drawn by FILLS — the side's colour over the shape, the
/// inside over the shape the side's width in — so an image of it and the
/// screen agree (🔬the Surface, 11-08 04:40: a stroke 49/255, two fills
/// 3~5). Where two fills cannot draw it — a translucent inside — the face
/// is drawn as `ShapeDecoration` draws it.
void main() {
  const size = Size(60, 24);
  const inside = Color(0xFF3A3D42);
  const edge = Color(0xFFE6E8EB);
  final outer = AppShapes.container(
    4,
  ).borderRadius.resolve(TextDirection.ltr).toRSuperellipse(Offset.zero & size);

  Future<RenderBox> faceOf(
    WidgetTester tester,
    Color color, {
    BorderSide side = const BorderSide(color: edge, width: 1.5),
  }) async {
    await tester.pumpWidget(
      Center(
        child: SizedBox.fromSize(
          size: size,
          child: DecoratedBox(
            decoration: SuperellipseFace(
              color: color,
              edge: AppShapes.container(4, side: side),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderBox>(find.byType(DecoratedBox));
  }

  bool onlyFills(Symbol method, List<dynamic> arguments) =>
      method != #drawRSuperellipse ||
      (arguments[1] as Paint).style == PaintingStyle.fill;

  testWidgets('over an opaque inside: the side\'s colour over the shape, '
      'then the inside over the shape its width in — fills, no stroke', (
    tester,
  ) async {
    final face = await faceOf(tester, inside);
    expect(
      face,
      paints
        ..rsuperellipse(rsuperellipse: outer, color: edge)
        ..rsuperellipse(
          rsuperellipse: outer.deflate(1.5),
          color: inside,
        ),
    );
    expect(face, paints..everything(onlyFills));
    expect(face, paintsExactlyCountTimes(#drawRSuperellipse, 2));
  });

  testWidgets('it is drawn where its box is laid', (tester) async {
    const at = Offset(7, 3);
    await tester.pumpWidget(
      Center(
        child: Padding(
          padding: EdgeInsets.only(left: at.dx, top: at.dy),
          child: SizedBox.fromSize(
            size: size,
            child: DecoratedBox(
              decoration: SuperellipseFace(
                color: inside,
                edge: AppShapes.container(
                  4,
                  side: const BorderSide(color: edge, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final laid = AppShapes.container(
      4,
    ).borderRadius.resolve(TextDirection.ltr).toRSuperellipse(at & size);
    expect(
      tester.renderObject(find.byType(Padding)),
      paints
        ..rsuperellipse(rsuperellipse: laid, color: edge)
        ..rsuperellipse(rsuperellipse: laid.deflate(1.5), color: inside),
    );
  });

  testWidgets('a translucent side lies over the inside, as its stroke did', (
    tester,
  ) async {
    final face = await faceOf(
      tester,
      inside,
      side: BorderSide(color: edge.withValues(alpha: 0.5)),
    );
    expect(
      face,
      paints
        ..rsuperellipse(rsuperellipse: outer, color: inside)
        ..rsuperellipse(
          rsuperellipse: outer,
          color: edge.withValues(alpha: 0.5),
        )
        ..rsuperellipse(
          rsuperellipse: outer.deflate(1),
          color: inside,
        ),
    );
    expect(face, paints..everything(onlyFills));
  });

  testWidgets('over a translucent inside it is drawn as ShapeDecoration '
      'draws it — the side a stroke', (tester) async {
    final face = await faceOf(tester, inside.withValues(alpha: 0.4));
    expect(
      face,
      paints
        ..rsuperellipse(color: inside.withValues(alpha: 0.4))
        ..rsuperellipse(strokeWidth: 1.5, color: edge),
    );
    expect(
      face,
      isNot(paints..everything(onlyFills)),
      reason: 'two fills would let the side show through the inside',
    );
  });

  // Two fills lay the side inside the edge, its whole width: a side laid
  // across the edge or past it, or a hairline — a pixel whatever its width
  // — is no such side.
  for (final (what, side) in [
    (
      'across the edge',
      const BorderSide(
        color: edge,
        width: 1.5,
        strokeAlign: BorderSide.strokeAlignCenter,
      ),
    ),
    (
      'past the edge',
      const BorderSide(
        color: edge,
        width: 1.5,
        strokeAlign: BorderSide.strokeAlignOutside,
      ),
    ),
    ('a hairline', const BorderSide(color: edge, width: 0)),
  ]) {
    testWidgets('a side $what is drawn as ShapeDecoration draws it — a '
        'stroke', (tester) async {
      final face = await faceOf(tester, inside, side: side);
      expect(
        face,
        paints
          ..rsuperellipse(color: inside)
          ..rsuperellipse(color: edge),
      );
      expect(face, isNot(paints..everything(onlyFills)));
    });
  }

  for (final side in [
    BorderSide.none,
    const BorderSide(color: edge, width: 1.5, style: BorderStyle.none),
  ]) {
    testWidgets('with no side it is the plain fill — $side', (tester) async {
      final face = await faceOf(tester, inside, side: side);
      expect(face, paintsExactlyCountTimes(#drawRSuperellipse, 1));
      expect(face, paints..rsuperellipse(color: inside));
    });
  }
}
