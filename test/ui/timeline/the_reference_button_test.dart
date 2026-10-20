// THE REFERENCE ROW'S FILE BUTTON (유저 2026-09-11, 미디어 배치 라운드 3~5):
// icon only, at the name area's far end right before the fold slot, only on
// a row that points at a file, pressed on the DOWN inside a rail column like
// every rail button.
//
// 🚨F-409 (유저 2026-10-19): 「카메라랑 참조레이어의 참조버튼. 얘네만 다른
// 버튼 사용하는거 눈에띄는게 얘네만 누르면 버튼 실루엣이 강조색됨. 같은버튼
// 공용화된거 쓰도록」. ↩️It wore the box's edge and lit while its popover was
// open (the 09-11 mockup).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/reference_to.dart';
import '../../helpers/named_finders.dart';

void main() {
  Layer layerNamed(String id, {String? file}) {
    final layer = Layer(
      id: LayerId(id),
      name: id,
      frames: const [],
      timeline: const {},
    );
    return file == null
        ? layer
        : layer.copyWith(mediaReference: referenceTo(file));
  }

  Widget row(
    Layer layer, {
    Future<void> Function(BuildContext, LayerId)? onOpen,
    PressFire fireOn = PressFire.upInside,
    bool isSourceShort = false,
    List<String> linkPartners = const [],
  }) => MaterialApp(
    home: Material(
      child: PressFireScope(
        fireOn: fireOn,
        child: TimelineLayerControlsRow(
          layer: layer,
          active: false,
          metrics: TimelineGridMetrics.defaults,
          onSelectLayer: (_) {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          onOpenLayerReference: onOpen,
          isReferenceSourceShort: isSourceShort,
          linkPartners: linkPartners,
        ),
      ),
    ),
  );

  Finder button(String id) =>
      find.named('timeline-layer-reference-$id');

  testWidgets('only a row that points at a FILE has the button — and only '
      'where the host can open its popover', (tester) async {
    Future<void> open(BuildContext _, LayerId _) async {}

    await tester.pumpWidget(
      row(layerNamed('ref', file: 'bg.png'), onOpen: open),
    );
    expect(button('ref'), findsOneWidget);
    expect(
      find.railTooltip('Reference'),
      findsOneWidget,
      reason: 'icon only — its name is the tooltip, the LAYER\'s word',
    );

    await tester.pumpWidget(row(layerNamed('plain'), onOpen: open));
    expect(
      button('plain'),
      findsNothing,
      reason:
          'no slot at all on a row that is not a reference (유저: 「참조인 '
          '레이어만 자리 만들어서 버튼두도록」)',
    );

    await tester.pumpWidget(row(layerNamed('ref', file: 'bg.png')));
    expect(button('ref'), findsNothing, reason: 'no host, no button');
  });

  testWidgets('it stands at the name area\'s far end, right before the fold '
      'slot (「폴더 접기 펼치기 … 그거 왼쪽」)', (tester) async {
    await tester.pumpWidget(
      row(layerNamed('ref', file: 'bg.png'), onOpen: (_, _) async {}),
    );
    final area = tester.getRect(
      find.named('timeline-layer-name-ref'),
    );
    expect(
      tester.getRect(button('ref')).right,
      closeTo(area.right - layerLaneToggleSlotWidth, 0.01),
    );
  });

  testWidgets('a linked row\'s badge stands there too, not after the '
      'letters — and beside the button on a row that is both (I-89 Q1: '
      '「참조/링크가 동시에 될수있는거 말되니까 … 중복되도록」)', (tester) async {
    Rect area(String id) => tester.getRect(
      find.named('timeline-layer-name-$id'),
    );
    Rect badge(String id) => tester.getRect(
      find.named('timeline-layer-link-badge-$id'),
    );

    await tester.pumpWidget(row(layerNamed('a'), linkPartners: const ['b']));
    expect(
      badge('a').right,
      closeTo(area('a').right - layerLaneToggleSlotWidth, 0.01),
    );

    await tester.pumpWidget(
      row(
        layerNamed('ref', file: 'bg.png'),
        onOpen: (_, _) async {},
        linkPartners: const ['b'],
      ),
    );
    expect(
      tester.getRect(button('ref')).right,
      closeTo(area('ref').right - layerLaneToggleSlotWidth, 0.01),
      reason: 'the reference keeps its place by the fold slot',
    );
    expect(
      badge('ref').right,
      closeTo(tester.getRect(button('ref')).left, 0.01),
    );
  });

  testWidgets('a rail column presses it on the DOWN, once, and it hands over '
      'its OWN context — the popover lands on the button', (tester) async {
    final opened = <LayerId>[];
    Rect? anchor;
    await tester.pumpWidget(
      row(
        layerNamed('ref', file: 'bg.png'),
        fireOn: PressFire.down,
        onOpen: (context, layerId) async {
          final box = context.findRenderObject()! as RenderBox;
          anchor = box.localToGlobal(Offset.zero) & box.size;
          opened.add(layerId);
        },
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(button('ref')),
    );
    await tester.pump();
    expect(opened, [const LayerId('ref')], reason: 'before the release');
    await gesture.up();
    await tester.pump();
    expect(opened, hasLength(1), reason: 'and not again on the release');
    expect(anchor, rectMoreOrLessEquals(tester.getRect(button('ref'))));
  });

  testWidgets('it is the rail\'s shared button: the box a name\'s buttons '
      'stand in, and at rest while its popover is open', (
    tester,
  ) async {
    final closed = Completer<void>();
    await tester.pumpWidget(
      row(layerNamed('ref', file: 'bg.png'), onOpen: (_, _) => closed.future),
    );
    Color glyph() => tester.glyphInkOf(button('ref'))!;
    expect(tester.getSize(button('ref')), const Size(22, 26));

    final rest = glyph();
    await tester.tap(button('ref'));
    await tester.pump();
    expect(glyph(), rest, reason: 'nothing lit while the popover is open');
    expect(glyph(), isNot(AppColors.accent));

    closed.complete();
    await tester.pumpAndSettle();
    expect(glyph(), rest);
  });

  testWidgets('a row asking its file for more film than it holds wears '
      'DANGER — and keeps it while its own popover is open, because the red '
      'is what the popover is there to explain (유저 2026-09-12)', (
    tester,
  ) async {
    final closed = Completer<void>();
    Color glyph() => tester.glyphInkOf(button('ref'))!;

    await tester.pumpWidget(
      row(layerNamed('ref', file: 'take.mov'), onOpen: (_, _) => closed.future),
    );
    expect(glyph(), isNot(AppColors.danger), reason: 'the premise');

    await tester.pumpWidget(
      row(
        layerNamed('ref', file: 'take.mov'),
        onOpen: (_, _) => closed.future,
        isSourceShort: true,
      ),
    );
    expect(glyph(), AppColors.danger);

    await tester.tap(button('ref'));
    await tester.pump();
    expect(
      glyph(),
      AppColors.danger,
      reason: 'short is the standing fact, the popover open or not',
    );
    expect(glyph(), isNot(AppColors.accent));

    closed.complete();
    await tester.pumpAndSettle();
  });
}
