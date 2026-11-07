import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q11 (유저 2026-11-08): an outline
/// with nothing painted behind it, on one opaque ground, is filled with
/// that ground — 「안쪽을 그 테두리가 놓인 바탕색으로 칠해 『채우기 둘』로
/// 그린다」 — so its edge is drawn by fills and an image of it and the
/// screen agree. The command pill and an outlined icon button stand on
/// [AppColors.surface] wherever they are (census 11-08).
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  bool onlyFills(Symbol method, List<dynamic> arguments) =>
      method != #drawRSuperellipse ||
      (arguments[1] as Paint).style == PaintingStyle.fill;

  RenderBox faceOf(WidgetTester tester) => tester.renderObject(
    find.iconButtonFace(find.byKey(const ValueKey<String>('button'))),
  );

  Color? layerOf(RenderBox face) => switch (face) {
    RenderIconButtonPressFace(:final debugLayerInk) ||
    RenderRailGlyphFace(:final debugLayerInk) => debugLayerInk,
    final other => throw StateError('$other is no icon button face'),
  };

  // The rail's glyph face draws a plain Icon; anything else is the app's
  // face around a widget — both wear the one layer.
  for (final (face, icon) in [
    ('the glyph face', const Icon(Icons.add) as Widget),
    ('the widget face', const Text('A')),
  ]) {
    testWidgets('an outlined icon button is its ground inside its edge, '
        'drawn by fills — $face', (tester) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'button',
          tooltip: 'button',
          icon: icon,
          outlined: true,
          onPressed: () {},
        ),
      );
      final button = faceOf(tester);
      expect(
        button,
        paints
          ..rsuperellipse(color: AppColors.hairlineStrong)
          ..rsuperellipse(color: AppColors.surface),
      );
      expect(button, paints..everything(onlyFills));
    });

    testWidgets('its hover lies over the ground, inside the edge — $face', (
      tester,
    ) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'button',
          tooltip: 'button',
          icon: icon,
          outlined: true,
          onPressed: () {},
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('button'))),
      );
      await tester.pump();
      final button = faceOf(tester);
      final hover = layerOf(button);
      expect(hover, isNotNull, reason: '⛔전제: the mouse is over it');
      expect(
        button,
        paints
          ..rsuperellipse(color: AppColors.hairlineStrong)
          ..rsuperellipse(color: Color.alphaBlend(hover!, AppColors.surface)),
      );
      expect(button, paints..everything(onlyFills));
    });
  }

  testWidgets('a button with no outline paints nothing at rest', (
    tester,
  ) async {
    await pump(
      tester,
      AppIconButton(
        keyValue: 'button',
        tooltip: 'button',
        icon: const Icon(Icons.add),
        onPressed: () {},
      ),
    );
    expect(faceOf(tester), paintsExactlyCountTimes(#drawRSuperellipse, 0));
  });

  testWidgets('the command pill is its ground inside its edge, drawn by '
      'fills', (tester) async {
    await pump(
      tester,
      const CommandPill(children: [SizedBox(width: 40)]),
    );
    final pill = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(CommandPill),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final outer = AppShapes.control(pill.size.height).borderRadius
        .resolve(TextDirection.ltr)
        .toRSuperellipse(Offset.zero & pill.size);
    expect(
      pill,
      paints
        ..rsuperellipse(rsuperellipse: outer, color: AppColors.hairline)
        ..rsuperellipse(
          rsuperellipse: outer.deflate(1),
          color: AppColors.surface,
        ),
    );
    expect(pill, paints..everything(onlyFills));
  });
}
