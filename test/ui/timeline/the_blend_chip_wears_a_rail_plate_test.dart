// A rail row's blend chip is the panels' chip pressed as the rail presses
// (I-57 ①): the rail's plate face around [PanelFlyoutChip], not a tooltip,
// a Material and an InkWell of its own (~43 elements a chip, mounted anew
// whenever a frame panel is shown again — frame-panels-build-in-one-frame,
// 10-24) — and the panels' button is that press too, so the two are one.
//
// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」): the face
// draws a clear chip's edge by fills, its inside the ground it stands on
// with the hover over that ([FaceGround]).
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/widgets/icon_button_box.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/drawn_shapes.dart';
import '../../helpers/named_finders.dart';

const _chipSize = Size(64, 22);

/// [child] in a box of its own, in the app's theme, captured by key.
Widget _boxed(String key, Widget child) => RepaintBoundary(
  key: ValueKey<String>(key),
  child: SizedBox.fromSize(
    size: _chipSize,
    child: ColoredBox(color: AppColors.surface, child: child),
  ),
);

List<PanelFlyoutEntry> _entries() => [
  const PanelFlyoutItem(keyValue: 'blend-probe-entry', label: 'Multiply'),
];

Future<Uint8List> _pixelsOf(WidgetTester tester, String key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey<String>(key)),
  );
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  return pixels;
}

/// The rail's chip as a row wears it, on [ground] where one is given.
Widget _railChip({Color? ground, bool groundSaid = false}) {
  final chip = RailFlyoutTrigger(
    name: 'rail-chip',
    tooltip: 'Blend',
    shape: PanelFlyoutChip.faceOf(),
    entriesBuilder: _entries,
    child: const PanelFlyoutChip(label: 'Normal', expand: true),
  );
  return groundSaid ? FaceGround(ground: ground, child: chip) : chip;
}

/// The hover's colour as the face fills it — its alpha in whole bytes.
Color _hoverOf(ThemeData theme) =>
    theme.hoverColor.withAlpha((theme.hoverColor.a * 255).round());

Future<RenderObject> _pumpChip(
  WidgetTester tester,
  ThemeData theme,
  Widget chip, {
  bool hovered = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Material(child: Center(child: _boxed('rail', chip))),
    ),
  );
  if (hovered) {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey<String>('rail'))),
    );
    await tester.pump();
  }
  return tester.renderObject(find.byType(RailFlyoutTrigger));
}

void main() {
  testWidgets('the panels\' button and the rail\'s chip are one press — the '
      'same pixels at rest and under the mouse', (tester) async {
    const label = 'Normal';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Column(
            children: [
              _boxed(
                'button',
                const PanelFlyoutButton(
                  label: label,
                  expand: true,
                  entriesBuilder: _entries,
                ),
              ),
              _boxed('rail', _railChip()),
            ],
          ),
        ),
      ),
    );

    final rest = await _pixelsOf(tester, 'button');
    expect(await _pixelsOf(tester, 'rail'), rest, reason: 'at rest');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(-50, -50));
    Future<Uint8List> hovered(String key) async {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey<String>(key))));
      await tester.pump();
      final pixels = await _pixelsOf(tester, key);
      await mouse.moveTo(const Offset(-50, -50));
      await tester.pump();
      return pixels;
    }

    final button = await hovered('button');
    expect(button, isNot(rest), reason: 'fixture: the hover shows');
    expect(await hovered('rail'), button, reason: 'under the mouse');
  });

  testWidgets('a clear chip is drawn by fills — its inside the ground it '
      'stands on, the hover over that', (tester) async {
    final theme = buildAppTheme();
    final shape = PanelFlyoutChip.faceOf().borderRadius
        .resolve(TextDirection.ltr)
        .toRSuperellipse(Offset.zero & _chipSize);
    for (final hovered in [false, true]) {
      final plate = await _pumpChip(
        tester,
        theme,
        _railChip(),
        hovered: hovered,
      );
      final inside = hovered
          ? Color.alphaBlend(_hoverOf(theme), AppColors.surface)
          : AppColors.surface;
      expect(
        plate,
        paints
          ..rsuperellipse(rsuperellipse: shape, color: AppColors.hairline)
          ..rsuperellipse(
            rsuperellipse: shape.deflate(1),
            color: inside,
          ),
        reason: hovered ? 'hovered' : 'at rest',
      );
      expect(
        DrawnShapes.of(plate).where(
          (drawn) => drawn.paint.style == PaintingStyle.stroke,
        ),
        isEmpty,
        reason: 'no stroke',
      );
      expect(plate, paintsExactlyCountTimes(#clipPath, 0));
      expect(plate, paintsExactlyCountTimes(#clipRSuperellipse, 0));
    }
  });

  testWidgets('on a ground it is told of, its inside is that ground — and on '
      'one of no one colour its edge is a stroke', (tester) async {
    final theme = buildAppTheme();
    const wash = Color(0xFF334455);
    expect(
      await _pumpChip(
        tester,
        theme,
        _railChip(ground: wash, groundSaid: true),
      ),
      paints
        ..rsuperellipse(color: AppColors.hairline)
        ..rsuperellipse(color: wash),
    );

    final bare = await _pumpChip(
      tester,
      theme,
      _railChip(groundSaid: true),
      hovered: true,
    );
    expect(
      DrawnShapes.of(bare).map((drawn) => drawn.paint.style),
      containsAll([PaintingStyle.fill, PaintingStyle.stroke]),
      reason: 'the hover filled, the edge stroked',
    );
    expect(
      bare,
      isNot(paints..rsuperellipse(color: AppColors.surface)),
      reason: 'no inside of a ground it does not stand on',
    );
  });

  testWidgets('the row\'s blend chip is the rail plate around the panels\' '
      'chip — no InkWell, no Material, no Tooltip of its own', (tester) async {
    LayerBlendMode? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 64,
              child: LayerBlendModeChip(
                name: 'blend-probe',
                optionKeyPrefix: 'blend-probe-option-',
                blendMode: LayerBlendMode.normal,
                onBlendModeSelected: (mode) => picked = mode,
              ),
            ),
          ),
        ),
      ),
    );

    final chip = find.named('blend-probe');
    expect(tester.widget(chip), isA<RailPlateButton>());
    expect(
      tester.widget<RailPlateButton>(chip).shape,
      PanelFlyoutChip.faceOf(),
      reason: 'a clear chip shows its hover',
    );
    final host = find.byType(LayerBlendModeChip);
    for (final heavy in [
      find.byType(InkWell),
      find.byType(Material),
      find.byType(AppTooltip),
    ]) {
      expect(find.descendant(of: host, matching: heavy), findsNothing);
    }

    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('blend-probe-option-multiply')),
    );
    await tester.pumpAndSettle();
    expect(picked, LayerBlendMode.multiply);
  });
}
