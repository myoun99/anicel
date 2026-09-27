import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_reorder_grid.dart'
    show brushPresetRowHeightFor;
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// 🚨★★★**F-198 — 브러시 칸은 브러시 그룹 탭과 같은 법으로 눌리고 끌린다.**
///
/// > 「브러시 클릭가능하고 드래그 가능하게 하란거 그렇게 어렵나? 이번엔
/// > 드래그로 위치이동이 안되는더? 그냥 브라시 그룹 동작하듯이 하라고.
/// > **펜다운하면 선택되고** 그런거 싹 다 통일하면 해결이잖아」
/// > (유저 2026-09-27)
///
/// 🔬What broke the drag: the cell resolved its drag only once the pointer
/// LEFT it (F-138-Q1), and the brush list under it takes a mouse at one
/// pixel and a pen at its slop — both long before a 48px cell is left
/// behind — so a brush dragged along its own list scrolled the list. And a
/// scrolled list aimed the drop against its viewport, as many rows short as
/// it was scrolled.
///
/// ★Now: the press picks on the DOWN (a pen, a mouse) as a group tab's
/// does; the first move claims the pointer, so nothing under a brush
/// scrolls; leaving the cell starts the drag, so a tremor stays a press.
/// And I-49 rides the same drag: 「브러시를 다른 그룹으로 옮길수있게. 그룹에
/// 하나밖에 없는 브러시일때든 뭐든 옮기기 허용. 그룹안에 브러시 없으면
/// 없는대로 두도록」.
void main() {
  const ink = BrushGroupId('ink');
  const paint = BrushGroupId('paint');
  const chalk = BrushGroupId('chalk');

  BrushPreset brush(int n, {BrushGroupId? group}) => BrushPreset(
    id: BrushPresetId('b$n'),
    name: 'Brush $n',
    groupId: group,
    settings: BrushSettings(size: 10.0 + n),
  );

  // Every view on (the default): the height one cell is allotted.
  final rowHeight = brushPresetRowHeightFor(
    showName: true,
    showStrokePreview: true,
  );

  Finder cell(String id) =>
      find.byKey(ValueKey<String>('brush-preset-entry-$id'));
  Finder tab(String id) => find.byKey(ValueKey<String>('brush-preset-tab-$id'));

  ScrollableState listScroll(WidgetTester tester) => tester.state(
    find
        .descendant(
          of: find.byKey(const ValueKey<String>('brush-preset-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );

  List<String> order(_HostState host, {BrushGroupId? group}) => [
    for (final preset in host.presets)
      if (preset.groupId == group) preset.id.value,
  ];

  Future<_HostState> pumpHost(
    WidgetTester tester, {
    required List<BrushPreset> presets,
    List<BrushGroup> groups = const <BrushGroup>[],
    BrushPresetId? selected,
  }) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, presets: presets, groups: groups, selected: selected),
    );
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// Walks the pointer by [by] in 2px steps — a real hand, not a teleport:
  /// every rival in the arena gets to see each step.
  Future<void> walk(
    WidgetTester tester,
    TestGesture gesture,
    Offset by,
  ) async {
    final steps = (by.distance / 2).ceil();
    for (var i = 0; i < steps; i += 1) {
      await gesture.moveBy(by / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 8));
    }
  }

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    // A finger picks on the release instead — a group tab's rule too
    // (`InstantTapRegion`: a press that becomes a scroll must not pick).
    final picksOnDown = kind != PointerDeviceKind.touch;
    group('${kind.name}:', () {
      testWidgets('a brush is picked when a group tab is — '
          '${picksOnDown ? 'on the DOWN' : 'on the release'}', (tester) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: paint, name: 'Paint'),
          ],
          presets: [
            brush(0, group: ink),
            brush(1, group: ink),
            brush(2, group: paint),
          ],
          selected: const BrushPresetId('b0'),
        );

        final press = await tester.startGesture(
          tester.getCenter(cell('b1')),
          kind: kind,
        );
        await tester.pump();
        expect(
          host.applied,
          picksOnDown ? ['b1'] : isEmpty,
          reason: '유저: 「펜다운하면 선택되고」 — before the pen lifts',
        );
        await press.up();
        await tester.pumpAndSettle();
        expect(host.applied, ['b1'], reason: 'once, not again on the lift');

        // The group tab beside it, by the same hand: it answers at the same
        // moment — the law the cell was brought to.
        final tabPress = await tester.startGesture(
          tester.getCenter(tab('paint')),
          kind: kind,
        );
        await tester.pump();
        expect(
          cell('b2'),
          picksOnDown ? findsOneWidget : findsNothing,
          reason: 'the tab switched at the same moment',
        );
        await tabPress.up();
        await tester.pumpAndSettle();
        expect(cell('b2'), findsOneWidget);
      });

      testWidgets('a brush dragged along its own list moves — the list under '
          'it does not scroll', (tester) async {
        final host = await pumpHost(
          tester,
          presets: [for (var n = 0; n < 16; n += 1) brush(n)],
        );
        final scroll = listScroll(tester);
        expect(
          scroll.position.maxScrollExtent,
          greaterThan(200),
          reason: '⛔premise: the list overflows, so its scroller is in the '
              'arena — a list that cannot scroll would prove nothing',
        );
        scroll.position.jumpTo(100);
        await tester.pumpAndSettle();

        final pitch =
            tester.getCenter(cell('b5')).dy - tester.getCenter(cell('b4')).dy;
        expect(pitch, greaterThan(0), reason: '⛔premise: one column');

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b4')),
          kind: kind,
        );
        await tester.pump();
        await walk(tester, gesture, Offset(0, pitch * 2));
        expect(
          scroll.position.pixels,
          100,
          reason: '🚨유저 08-29: 「터치 좌표가 버튼인데 거기서 움직였다고 '
              '스크롤이 발생하는게 심각한 버그야」 — a press on a brush is the '
              "brush's",
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          order(host).take(8),
          ['b0', 'b1', 'b2', 'b3', 'b5', 'b6', 'b4', 'b7'],
          reason: '유저: 「이번엔 드래그로 위치이동이 안되는더?」 — two cells '
              'down, in a list scrolled by 100: aimed at the rows, not at '
              'the viewport',
        );
        expect(scroll.position.pixels, 100);
      });

      testWidgets('a tremor on a brush is a press: picked, not lifted, and '
          'nothing scrolls', (tester) async {
        final host = await pumpHost(
          tester,
          presets: [for (var n = 0; n < 16; n += 1) brush(n)],
        );
        final scroll = listScroll(tester);
        scroll.position.jumpTo(40);
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b3')),
          kind: kind,
        );
        for (final shake in const [
          Offset(0, 2),
          Offset(1, -3),
          Offset(-2, 2),
          Offset(1, -1),
        ]) {
          await gesture.moveBy(shake);
          await tester.pump(const Duration(milliseconds: 8));
        }
        expect(scroll.position.pixels, 40, reason: 'nothing under it moved');
        await gesture.up();
        await tester.pumpAndSettle();

        expect(host.applied, ['b3']);
        expect(host.reorders, 0, reason: 'F-138: a tremor stays a press');
        expect(scroll.position.pixels, 40);
      });

      testWidgets('a group tab: a tremor is a press, and leaving it drags it '
          '— the brush cell\'s rule', (tester) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: paint, name: 'Paint'),
            BrushGroup(id: chalk, name: 'Chalk'),
          ],
          presets: [
            brush(0, group: ink),
            brush(1, group: paint),
            brush(2, group: chalk),
          ],
          selected: const BrushPresetId('b0'),
        );

        // The rail takes its tooltips down the moment a tab lifts
        // (`_railDragging`), so a tooltip still standing on ANOTHER tab says
        // nothing has lifted.
        Finder inkTooltip() =>
            find.ancestor(of: tab('ink'), matching: find.byType(AppTooltip));
        expect(inkTooltip(), findsOneWidget, reason: '⛔premise: at rest');

        final shaky = await tester.startGesture(
          tester.getCenter(tab('paint')),
          kind: kind,
        );
        for (final shake in const [Offset(0, 2), Offset(1, -3), Offset(0, 2)]) {
          await shaky.moveBy(shake);
          await tester.pump(const Duration(milliseconds: 8));
          expect(
            inkTooltip(),
            findsOneWidget,
            reason: 'F-138: 「펜을 떨리면서 클릭해도 제대로 클릭되고」 — a '
                'tremor on a tab must not lift it',
          );
        }
        await shaky.up();
        await tester.pumpAndSettle();
        expect(host.groupOrder, ['ink', 'paint', 'chalk']);
        expect(cell('b1'), findsOneWidget, reason: 'and it still switched');

        final pitch =
            tester.getCenter(tab('chalk')).dy - tester.getCenter(tab('paint')).dy;
        final drag = await tester.startGesture(
          tester.getCenter(tab('ink')),
          kind: kind,
        );
        await tester.pump();
        // Past the last tab's middle, so the drop is unambiguously the end.
        await walk(tester, drag, Offset(0, pitch * 2.5));
        await drag.up();
        await tester.pumpAndSettle();
        expect(host.groupOrder, ['paint', 'chalk', 'ink']);
      });

      testWidgets('I-49: a group\'s ONLY brush moves into another group, and '
          'the group it leaves stays', (tester) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: paint, name: 'Paint'),
          ],
          presets: [
            brush(0, group: ink),
            brush(1, group: paint),
            brush(2, group: paint),
          ],
          selected: const BrushPresetId('b0'),
        );
        expect(cell('b0'), findsOneWidget, reason: '⛔premise: Ink is open');

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b0')),
          kind: kind,
        );
        await tester.pump();
        // Out of the cell, then over the Paint tab until it springs open.
        await walk(tester, gesture, const Offset(0, 40));
        await gesture.moveTo(tester.getCenter(tab('paint')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(cell('b2'), findsOneWidget, reason: '⛔premise: Paint sprang open');

        // Held over Paint's SECOND slot — aimed by the rows' own geometry,
        // not by where an animating cell happens to be drawn.
        final list = tester.getRect(
          find.byKey(const ValueKey<String>('brush-preset-list')),
        );
        await gesture.moveTo(Offset(list.center.dx, list.top + rowHeight * 1.5));
        await tester.pump(const Duration(milliseconds: 20));
        await walk(tester, gesture, const Offset(0, 2));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(cell('b2')).top,
          closeTo(list.top + rowHeight * 2, 0.5),
          reason: 'the gap it would fill opens under it: Paint\'s second '
              'brush steps down a row',
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          order(host, group: paint),
          ['b1', 'b0', 'b2'],
          reason: '유저: 「그룹에 하나밖에 없는 브러시일때든 뭐든 옮기기 허용」',
        );
        expect(order(host, group: ink), isEmpty);
        expect(
          host.groupOrder,
          ['ink', 'paint'],
          reason: '유저: 「그룹안에 브러시 없으면 없는대로 두도록」',
        );
      });

      testWidgets('I-49: a brush can be dropped into a group with no brushes '
          'at all', (tester) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: chalk, name: 'Chalk'),
          ],
          presets: [brush(0, group: ink), brush(1, group: ink)],
          selected: const BrushPresetId('b0'),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b1')),
          kind: kind,
        );
        await tester.pump();
        await walk(tester, gesture, const Offset(0, 40));
        await gesture.moveTo(tester.getCenter(tab('chalk')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(cell('b0'), findsNothing, reason: '⛔premise: Chalk sprang open');

        // Anywhere in the empty list — the viewport takes the drop.
        final list = tester.getRect(
          find.byKey(const ValueKey<String>('brush-preset-list')),
        );
        await gesture.moveTo(list.center);
        await tester.pump(const Duration(milliseconds: 20));
        await walk(tester, gesture, const Offset(0, 2));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(order(host, group: chalk), ['b1']);
        expect(order(host, group: ink), ['b0']);
      });

      testWidgets('I-49: past another group\'s last brush is the end of it', (
        tester,
      ) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: paint, name: 'Paint'),
          ],
          presets: [
            brush(0, group: ink),
            brush(1, group: paint),
            brush(2, group: paint),
          ],
          selected: const BrushPresetId('b0'),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b0')),
          kind: kind,
        );
        await tester.pump();
        await walk(tester, gesture, const Offset(0, 40));
        await gesture.moveTo(tester.getCenter(tab('paint')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        final list = tester.getRect(
          find.byKey(const ValueKey<String>('brush-preset-list')),
        );
        await gesture.moveTo(Offset(list.center.dx, list.top + rowHeight * 3.5));
        await tester.pump(const Duration(milliseconds: 20));
        await walk(tester, gesture, const Offset(0, 2));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(order(host, group: paint), ['b1', 'b2', 'b0']);
      });

      testWidgets('a brush carried to another group and back still leaves '
          'its gap', (tester) async {
        final host = await pumpHost(
          tester,
          groups: const [
            BrushGroup(id: ink, name: 'Ink'),
            BrushGroup(id: paint, name: 'Paint'),
          ],
          presets: [
            brush(0, group: ink),
            brush(1, group: ink),
            brush(2, group: paint),
          ],
          selected: const BrushPresetId('b0'),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b0')),
          kind: kind,
        );
        await tester.pump();
        await walk(tester, gesture, const Offset(0, 40));
        for (final group in const ['paint', 'ink']) {
          await gesture.moveTo(tester.getCenter(tab(group)));
          await tester.pump(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
        }
        expect(cell('b1'), findsOneWidget, reason: '⛔premise: Ink is back');
        expect(
          find.byKey(const ValueKey<String>('brush-preset-chip-b0')),
          findsOneWidget,
          reason: 'only the brush in the hand — the list keeps the gap it '
              'left, not a second copy',
        );

        // Let go over the rail: nothing moves.
        await gesture.up();
        await tester.pumpAndSettle();
        expect(order(host, group: ink), ['b0', 'b1']);
      });

      testWidgets('a brush held at the list\'s edge scrolls the list, as a tab '
          'held at the rail\'s does', (tester) async {
        final host = await pumpHost(
          tester,
          presets: [for (var n = 0; n < 16; n += 1) brush(n)],
        );
        final scroll = listScroll(tester);
        final list = tester.getRect(
          find.byKey(const ValueKey<String>('brush-preset-list')),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(cell('b0')),
          kind: kind,
        );
        await tester.pump();
        await walk(tester, gesture, const Offset(0, 40));
        // Held still with the brush hanging past the bottom edge.
        await gesture.moveTo(Offset(list.center.dx, list.bottom - 4));
        for (var i = 0; i < 30; i += 1) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          scroll.position.pixels,
          greaterThan(rowHeight * 2),
          reason: 'the list keeps following the brush while it is held there',
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          order(host).indexOf('b0'),
          greaterThan(6),
          reason: 'and it lands where the list took it',
        );
      });
    });
  }
}

/// The workspace in miniature: applies what the panel asks, and counts it.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.presets,
    required this.groups,
    this.selected,
  });

  final List<BrushPreset> presets;
  final List<BrushGroup> groups;
  final BrushPresetId? selected;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<BrushPreset> presets = widget.presets;
  late List<BrushGroup> groups = widget.groups;
  late BrushPresetId? selected = widget.selected;
  final List<String> applied = <String>[];
  int reorders = 0;

  List<String> get groupOrder => [for (final group in groups) group.id.value];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The app's own: a mouse drags a list too (유저 2026-08-29), which is
      // exactly the rival that took the brush's drag.
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 260,
            height: 360,
            child: BrushPresetPanel(
              presets: presets,
              groups: groups,
              selectedPresetId: selected,
              onPresetApplied: (preset) {
                applied.add(preset.id.value);
                setState(() => selected = preset.id);
              },
              onPresetsReordered: (next) {
                reorders += 1;
                setState(() => presets = next);
              },
              onGroupsReordered: (next) => setState(() => groups = next),
            ),
          ),
        ),
      ),
    );
  }
}
