import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

import '../../helpers/app_icon_button_probe.dart';

/// A LANE WHOSE VALUE IS A LINKED PAIR WEARS ITS CHAIN beside the value —
/// a layer's Scale, After Effects' own mark (`transform-fx-scale-x-y`).
///
/// 🗣️`transform-fx-scale-x-y-Q1` (유저 2026-10-07): 「Scale 행에 사슬 버튼 —
/// 변형 도구의 「배율 연동」과 한 스위치」.
///
/// This half is the ROW: what it wears, when it acts, and what the chain
/// costs the cells beside it. Whose switch it flips is the rail's to say
/// (`a_scale_lane_takes_its_rows_form_test`, and `property_lanes_test` for
/// the app).
void main() {
  final layer = Layer(id: const LayerId('sc'), name: 'S', frames: const []);

  PropertyLaneRow lane({required bool linkable, bool navigator = true}) =>
      PropertyLaneRow(
        laneId: 'scale',
        label: 'Scale',
        keyedFrames: const {},
        valueLabel: (_) => '150, 80%',
        linkable: linkable,
        showsKeyNavigator: navigator,
      );

  /// A chain over [on], counting its presses.
  ({PropertyLaneValueLink link, List<bool> presses}) chainOver(
    ValueNotifier<bool> on,
  ) {
    final presses = <bool>[];
    return (
      link: (
        changes: on,
        isOn: () => on.value,
        toggle: () {
          on.value = !on.value;
          presses.add(on.value);
        },
        tooltip: 'Link scale',
      ),
      presses: presses,
    );
  }

  Future<void> pumpRow(
    WidgetTester tester, {
    required PropertyLaneRow lane,
    required PropertyLaneValueLink? link,
    Axis axis = Axis.horizontal,
    Size size = const Size(600, 40),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane,
              metrics: TimelineGridMetrics.defaults,
              axis: axis,
              keyPrefix: axis == Axis.horizontal ? 'timeline' : 'xsheet',
              width: size.width,
              height: size.height,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, _) {},
                valueLink: link,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder keyed(String name, {String prefix = 'timeline'}) =>
      find.byKey(ValueKey<String>('$prefix-lane-$name-sc-scale'));

  group('along the rail', () {
    testWidgets('the chain is there on and off — what a press changes is its '
        'colour', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);
      final chain = chainOver(on);
      await pumpRow(tester, lane: lane(linkable: true), link: chain.link);

      expect(keyed('value-link'), findsOneWidget);
      expect(tester.appIconButton(keyed('value-link')).isSelected, isTrue);
      expect(tester.appIconButton(keyed('value-link')).tooltip, 'Link scale');

      await tester.tap(keyed('value-link'));
      await tester.pump();

      expect(chain.presses, [false]);
      expect(keyed('value-link'), findsOneWidget, reason: 'still on the row');
      expect(tester.appIconButton(keyed('value-link')).isSelected, isFalse);
    });

    testWidgets('it acts on the press, as every button on a rail row does', (
      tester,
    ) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);
      final chain = chainOver(on);
      await pumpRow(tester, lane: lane(linkable: true), link: chain.link);

      final gesture = await tester.startGesture(
        tester.getCenter(keyed('value-link')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(chain.presses, [false], reason: 'on the DOWN');

      await gesture.up();
      await tester.pump();
      expect(chain.presses, [false], reason: 'and once');
    });

    testWidgets('flipped from elsewhere, the chain follows — the switch is '
        'not the row\'s own', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);
      await pumpRow(
        tester,
        lane: lane(linkable: true),
        link: chainOver(on).link,
      );

      on.value = false;
      await tester.pump();
      expect(tester.appIconButton(keyed('value-link')).isSelected, isFalse);

      on.value = true;
      await tester.pump();
      expect(tester.appIconButton(keyed('value-link')).isSelected, isTrue);
    });

    testWidgets('⛔a lane that is not a linked pair wears none, and neither '
        'does a rail handed no chain', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);

      await pumpRow(
        tester,
        lane: lane(linkable: false),
        link: chainOver(on).link,
      );
      expect(keyed('value-link'), findsNothing);

      await pumpRow(tester, lane: lane(linkable: true), link: null);
      expect(keyed('value-link'), findsNothing);
    });

    testWidgets('the chain takes its room from the NAME: the value stays in '
        'the column every lane has it in', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);

      await pumpRow(tester, lane: lane(linkable: false), link: null);
      final bare = tester.getRect(keyed('value'));

      await pumpRow(
        tester,
        lane: lane(linkable: true),
        link: chainOver(on).link,
      );
      final chained = tester.getRect(keyed('value'));
      final chain = tester.getRect(keyed('value-link'));

      expect(chained, bare);
      expect(chain.right, lessThanOrEqualTo(chained.left));
      expect(tester.takeException(), isNull);
    });
  });

  group('down the sheet', () {
    final column = TimelineGridMetrics.defaults.layerRowHeight;

    Future<({bool navigator, bool value, bool chain})> shownAt(
      WidgetTester tester,
      double height,
      ValueNotifier<bool> on, {
      bool navigator = true,
    }) async {
      await pumpRow(
        tester,
        lane: lane(linkable: true, navigator: navigator),
        link: chainOver(on).link,
        axis: Axis.vertical,
        size: Size(column, height),
      );
      expect(tester.takeException(), isNull, reason: 'at $height');
      return (
        navigator: keyed('key-toggle', prefix: 'xsheet').evaluate().isNotEmpty,
        value: keyed('value', prefix: 'xsheet').evaluate().isNotEmpty,
        chain: keyed('value-link', prefix: 'xsheet').evaluate().isNotEmpty,
      );
    }

    testWidgets('with room for everything, the chain stands between the name '
        'and the value it links', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);

      final shown = await shownAt(tester, 260, on);

      expect(shown, (navigator: true, value: true, chain: true));
      final chain = tester.getRect(keyed('value-link', prefix: 'xsheet'));
      final value = tester.getRect(keyed('value', prefix: 'xsheet'));
      final navigator = tester.getRect(keyed('key-toggle', prefix: 'xsheet'));
      expect(chain.bottom, lessThanOrEqualTo(value.top));
      expect(navigator.bottom, lessThanOrEqualTo(chain.top));
    });

    testWidgets('the chain is paid LAST — never without its value, never at '
        'the navigator\'s cost — and once it is there it stays as the column '
        'grows', (tester) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);

      var seenChain = false;
      var seenValueAlone = false;
      var seenNavigatorWithoutChain = false;
      for (var height = 80.0; height <= 260; height += 2) {
        final shown = await shownAt(tester, height, on);
        if (shown.chain) {
          expect(shown.value, isTrue, reason: 'at $height');
          expect(shown.navigator, isTrue, reason: 'at $height');
        }
        if (seenChain) {
          expect(shown.chain, isTrue, reason: 'gone again at $height');
        }
        seenChain = seenChain || shown.chain;
        seenValueAlone =
            seenValueAlone || (shown.value && !shown.navigator && !shown.chain);
        seenNavigatorWithoutChain =
            seenNavigatorWithoutChain || (shown.navigator && !shown.chain);
      }

      expect(seenChain, isTrue, reason: 'LIVENESS — the walk reached it');
      expect(seenValueAlone, isTrue, reason: 'the value is paid first');
      expect(
        seenNavigatorWithoutChain,
        isTrue,
        reason: 'then the navigator, and the chain after both',
      );
    });

    testWidgets('on a lane with no navigator the chain still waits for its '
        'value: a link with nothing beside it to link says nothing', (
      tester,
    ) async {
      final on = ValueNotifier(true);
      addTearDown(on.dispose);

      var seenChain = false;
      var seenNeither = false;
      for (var height = 60.0; height <= 200; height += 2) {
        final shown = await shownAt(tester, height, on, navigator: false);
        expect(shown.navigator, isFalse, reason: 'at $height');
        if (shown.chain) {
          expect(shown.value, isTrue, reason: 'at $height');
        }
        if (seenChain) {
          expect(shown.chain, isTrue, reason: 'gone again at $height');
        }
        seenChain = seenChain || shown.chain;
        seenNeither = seenNeither || (!shown.value && !shown.chain);
      }

      expect(seenChain, isTrue, reason: 'LIVENESS — the walk reached it');
      expect(seenNeither, isTrue, reason: 'LIVENESS — and began below it');
    });
  });
}
