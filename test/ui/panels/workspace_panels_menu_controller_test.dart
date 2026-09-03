// THE PANELS-MENU BRIDGE: EMPTY AND INERT BEFORE THE WORKSPACE ATTACHES,
// A MIRROR OF THE WORKSPACE WHILE IT IS ATTACHED, AND INERT AGAIN AFTER
// DETACH — WITH THE RELAY UNHOOKED.
//
// No test named this file (audit 2026-09-03) although the AppBar's Panels
// menu, the floor switch, the tool-rail side and the region side all go
// through it. These pins drive the bridge without a workspace.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/panels/workspace_panels_menu.dart';

void main() {
  test('before attach the bridge is empty and every verb is a no-op', () {
    final controller = WorkspacePanelsMenuController();
    addTearDown(controller.dispose);
    expect(controller.isAttached, isFalse);
    expect(controller.entries, isEmpty);
    expect(controller.canResetLayout, isFalse);
    expect(controller.canMoveToolRail, isFalse);
    expect(controller.toolRailOnRight, isFalse);
    expect(controller.canMoveRegion, isFalse);
    expect(controller.regionOnTop, isFalse);
    expect(controller.floorTabId, isNull);
    expect(controller.floorTabs, isEmpty);
    controller
      ..toggle('timeline')
      ..resetLayout()
      ..setToolRailOnRight(true)
      ..setRegionOnTop(true)
      ..selectFloorTab('canvas');
  });

  test(
    'attached, the bridge mirrors the workspace and forwards its verbs',
    () async {
      final controller = WorkspacePanelsMenuController();
      addTearDown(controller.dispose);
      final relay = ChangeNotifier();
      addTearDown(relay.dispose);
      final toggled = <String>[];
      final railMoves = <bool>[];
      final regionMoves = <bool>[];
      final floorPicks = <String>[];
      var resets = 0;
      var notifies = 0;
      controller.addListener(() => notifies += 1);

      controller.attach(
        entriesProvider: () => const [
          (tabId: 'timeline', label: 'Timeline', visible: true),
          (tabId: 'storyboard', label: 'Storyboard', visible: false),
        ],
        toggler: toggled.add,
        relay: relay,
        layoutReset: () => resets += 1,
        toolRailOnRight: () => true,
        toolRailMover: railMoves.add,
        floorTabId: () => 'canvas',
        floorTabs: () => const [
          (tabId: 'canvas', label: 'Canvas', icon: IconDataProbe.icon),
        ],
        floorTabSelector: floorPicks.add,
        regionOnTop: () => true,
        regionMover: regionMoves.add,
      );

      expect(controller.isAttached, isTrue);
      expect(controller.entries.map((e) => e.tabId), [
        'timeline',
        'storyboard',
      ]);
      expect(controller.canResetLayout, isTrue);
      expect(controller.toolRailOnRight, isTrue);
      expect(controller.regionOnTop, isTrue);
      expect(controller.floorTabId, 'canvas');
      expect(controller.floorTabs.single.label, 'Canvas');

      controller
        ..toggle('storyboard')
        ..resetLayout()
        ..setToolRailOnRight(false)
        ..setRegionOnTop(false)
        ..selectFloorTab('viewer');
      expect(toggled, ['storyboard']);
      expect(resets, 1);
      expect(railMoves, [false]);
      expect(regionMoves, [false]);
      expect(floorPicks, ['viewer']);

      // The initial refresh is deferred past the frame, and the relay drives
      // every later one.
      expect(notifies, 0, reason: 'attach does not notify synchronously');
      await Future<void>.delayed(Duration.zero);
      expect(notifies, 1);
      relay.notifyListeners();
      expect(notifies, 2);
    },
  );

  test('detach empties the bridge and unhooks the relay', () async {
    final controller = WorkspacePanelsMenuController();
    addTearDown(controller.dispose);
    final relay = ChangeNotifier();
    addTearDown(relay.dispose);
    var notifies = 0;
    controller.addListener(() => notifies += 1);
    controller.attach(
      entriesProvider: () => const [
        (tabId: 'timeline', label: 'Timeline', visible: true),
      ],
      toggler: (_) {},
      relay: relay,
      layoutReset: () {},
    );
    await Future<void>.delayed(Duration.zero);
    final afterAttach = notifies;

    controller.detach();
    expect(controller.isAttached, isFalse);
    expect(controller.entries, isEmpty);
    expect(controller.canResetLayout, isFalse);
    relay.notifyListeners();
    expect(notifies, afterAttach, reason: 'the relay no longer reaches it');
  });
}

/// A stand-in icon: the floor tab record wants an [IconData], and the test
/// has no icon font to care about.
abstract final class IconDataProbe {
  static const IconData icon = IconData(0xe000);
}
