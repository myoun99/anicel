import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';

/// 🚨★★★DROPPING A GROUP TAB MUST NOT TURN THE RAIL RED.
///
/// 유저 2026-09-01 (F-60), with the exact recipe: 「3번째 브러시 그룹을
/// 드래그해서 4번째랑 자리바꾸기, 즉 3번째를 마지막자리로 옮기고 나서
/// **커밋될때? 끝날때** 빨간화면떴어」.
///
/// The first exception in the cascade names the mechanism outright:
///
///   A _RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout.
///   _RenderTheater._addDeferredChild ← _OverlayEntryLocation._activate
///     ← _OverlayPortalElement.activate ← Element._activateRecursively
///   The relevant error-causing widget was:
///     ReorderableListView-[<'brush-preset-tab-rail'>]
///
/// ⇒ On the DROP, `ReorderableListView` brings the item back from the
/// inactive list by global key (`_activateRecursively`). A `Tooltip` is an
/// `OverlayPortal`, so reviving one adds a deferred child to the theater —
/// and that happens inside the panel's `LayoutBuilder` layout callback, where
/// mutating is illegal. Everything after it (the ink `referenceBox.attached`
/// asserts on `brush-preset-import-button`, the semantics
/// `traversalParentIdentifier` failure, buttons vanishing on hover all over
/// the app) is the wreckage of that one frame.
///
/// ⛔The panel ALREADY had the guard and it fired one frame too early:
/// `onReorderEnd` cleared `_railDragging` synchronously, so the rebuild that
/// revives the item was the same rebuild that put its tooltip back. The flag
/// has to outlive the drop by a frame.
void main() {
  BrushPreset preset(String id, String name) => BrushPreset(
    id: BrushPresetId(id),
    name: name,
    settings: BrushSettings(size: 12),
  );

  BrushGroup group(String id) =>
      BrushGroup(id: BrushGroupId(id), name: id.toUpperCase());

  testWidgets('🚨★★★drag the 3rd tab to last and drop it', (tester) async {
    var groups = [group('a'), group('b'), group('c'), group('d')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            // ⚠️TWO nested LayoutBuilders, because that is the shape the
            // crash needs: 유저's first exception names an OUTER
            // `_RenderLayoutBuilder` (1264x681) being mutated by an INNER one
            // (250x198). The panel carries the inner one; the app shell
            // carries the outer. With only the panel'"'"'s own, the revival
            // lands outside anyone'"'"'s performLayout and nothing asserts.
            builder: (context, setState) => LayoutBuilder(
              builder: (context, _) => SizedBox(
              width: 260,
              height: 420,
              child: BrushPresetPanel(
                groups: groups,
                presets: [preset('p', 'Calligraphy')],
                onPresetsReordered: (_) {},
                onGroupsReordered: (next) => setState(() => groups = next),
              ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final third = find.byKey(
      const ValueKey<String>('brush-preset-tab-entry-c'),
    );
    final fourth = find.byKey(
      const ValueKey<String>('brush-preset-tab-entry-d'),
    );
    expect(third, findsOneWidget, reason: '⛔premise: the 3rd tab is drawn');
    expect(fourth, findsOneWidget, reason: '⛔premise: the 4th tab is drawn');

    final from = tester.getCenter(third);
    final step = tester.getCenter(fourth).dy - from.dy;
    expect(
      step,
      greaterThan(0),
      reason: '⛔premise: the rail runs downwards, so 「to last」 is a drag '
          'DOWN — a zero step would drop it where it started and measure '
          'nothing',
    );

    // ⚠️`ReorderableDragStartListener` is IMMEDIATE, not delayed — the drag
    // starts on movement, and waiting for a long press only let the gesture
    // expire. 🧪The premise assertion below caught exactly that: the first
    // version waited and the list came back unchanged.
    final drag = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    // Small steps, because the recogniser needs movement to claim the arena
    // and the list needs to cross the next item'"'"'s midpoint to swap.
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(Offset(0, step / 3));
      await tester.pump(const Duration(milliseconds: 20));
    }

    await drag.up();
    // The drop, the settle animation, and every frame after it — the
    // exception fires on the frame that revives the item.
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '🚨the drop must not mutate the LayoutBuilder — that one frame '
          'is what takes the whole app down',
    );
    expect(
      groups.map((g) => g.id.value).toList(),
      ['a', 'b', 'd', 'c'],
      reason: '⛔premise: the reorder actually COMMITTED. A test where the '
          'drag fell short would pass while measuring nothing at all',
    );
  });
}
