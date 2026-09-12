// THE REFERENCE ROW'S FILE BUTTON (유저 2026-09-11, 미디어 배치 라운드 3~5):
// icon only, at the name area's far end right before the fold slot, only on
// a row that points at a file, pressed on the DOWN inside a rail column like
// every rail button, and lit while its popover is open.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

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
        : layer.copyWith(mediaReference: MediaReference(assetPath: file));
  }

  Widget row(
    Layer layer, {
    Future<void> Function(BuildContext, LayerId)? onOpen,
    PressFire fireOn = PressFire.upInside,
    bool isSourceShort = false,
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
        ),
      ),
    ),
  );

  Finder button(String id) =>
      find.byKey(ValueKey<String>('timeline-layer-reference-$id'));

  testWidgets('only a row that points at a FILE has the button — and only '
      'where the host can open its popover', (tester) async {
    Future<void> open(BuildContext _, LayerId _) async {}

    await tester.pumpWidget(
      row(layerNamed('ref', file: 'bg.png'), onOpen: open),
    );
    expect(button('ref'), findsOneWidget);
    expect(
      find.byTooltip('Reference'),
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
      find.byKey(const ValueKey<String>('timeline-layer-name-ref')),
    );
    expect(
      tester.getRect(button('ref')).right,
      closeTo(area.right - layerLaneToggleSlotWidth, 0.01),
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

  testWidgets('it is lit while its popover is open and back at rest when it '
      'closes — selection by colour only', (tester) async {
    final closed = Completer<void>();
    await tester.pumpWidget(
      row(layerNamed('ref', file: 'bg.png'), onOpen: (_, _) => closed.future),
    );
    Color glyph() => IconTheme.of(
      tester.element(
        find.descendant(of: button('ref'), matching: find.byType(Icon)),
      ),
    ).color!;

    final rest = glyph();
    expect(rest, isNot(AppColors.accent), reason: 'the premise');

    await tester.tap(button('ref'));
    await tester.pump();
    expect(glyph(), AppColors.accent);

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
    Color glyph() => IconTheme.of(
      tester.element(
        find.descendant(of: button('ref'), matching: find.byType(Icon)),
      ),
    ).color!;

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
      reason: 'lit is the transient fact; short is the standing one',
    );
    expect(glyph(), isNot(AppColors.accent));

    closed.complete();
    await tester.pumpAndSettle();
  });
}
