import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';

Map<String, List<DockSection>> _defaults() => {
  'tool-left': [
    DockSection(tabs: ['tools']),
  ],
  'tool-right': <DockSection>[],
  'left': [
    DockSection(tabs: ['brushes', 'camera'], activeTabId: 'brushes'),
  ],
  'center': [
    DockSection(tabs: ['canvas']),
  ],
};

void main() {
  group('WorkspaceLayoutStore', () {
    test('round-trips a layout payload through the file', () async {
      final directory = await Directory.systemTemp.createTemp('layout_store');
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceLayoutStore(
        filePath: '${directory.path}/workspace_layout.json',
      );

      expect(await store.load(), isNull);

      final model = EditorPanelLayoutModel(docks: _defaults());
      model.moveTabToNewSection(
        tabId: 'camera',
        toDockId: 'left',
        atSectionIndex: 1,
      );
      await store.save({
        'layout': model.toJson(),
        'lockedTabs': ['canvas'],
      });

      final loaded = await store.load();
      expect(loaded, isNotNull);
      final restored = restoreWorkspaceLayout(
        payload: loaded!,
        defaults: _defaults(),
      );
      expect(restored, isNotNull);
      expect(
        [for (final section in restored!.docks['left']!) section.tabs],
        [
          ['brushes'],
          ['camera'],
        ],
      );
      expect(restored.lockedTabIds, {'canvas'});
    });

    test('a corrupt file loads as null', () async {
      final directory = await Directory.systemTemp.createTemp('layout_store');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/workspace_layout.json';
      await File(path).writeAsString('not json at all');

      expect(await WorkspaceLayoutStore(filePath: path).load(), isNull);
    });
  });

  group('restoreWorkspaceLayout', () {
    test('drops unknown tabs and returns missing tabs to their home dock', () {
      final restored = restoreWorkspaceLayout(
        payload: {
          'layout': {
            'docks': {
              'left': [
                {
                  'tabs': ['camera', 'ghost-panel'],
                  'active': 'ghost-panel',
                  'weight': 2,
                },
              ],
              'unknown-dock': [
                {
                  'tabs': ['brushes'],
                },
              ],
            },
            'extents': {'left': 300.0, 'unknown-dock': 99.0},
          },
          'lockedTabs': ['canvas', 'ghost-panel'],
        },
        defaults: _defaults(),
      );

      expect(restored, isNotNull);
      // 'ghost-panel' dropped; 'camera' kept with its saved section.
      expect(restored!.docks['left']!.first.tabs, ['camera']);
      expect(restored.docks['left']!.first.weight, 2);
      // Tabs the save never placed ('tools', 'brushes' via the unknown
      // dock, 'canvas') return to their default docks.
      expect(restored.docks['tool-left']!.single.tabs, ['tools']);
      expect(restored.docks['center']!.single.tabs, ['canvas']);
      expect([
        for (final section in restored.docks['left']!) ...section.tabs,
      ], containsAll(['camera', 'brushes']));
      expect(restored.dockExtents, {'left': 300.0});
      expect(restored.lockedTabIds, {'canvas'});
    });

    test('duplicated tabs keep their first occurrence only', () {
      final restored = restoreWorkspaceLayout(
        payload: {
          'layout': {
            'docks': {
              'left': [
                {
                  'tabs': ['camera'],
                },
              ],
              'center': [
                {
                  'tabs': ['camera', 'canvas'],
                },
              ],
            },
          },
        },
        defaults: _defaults(),
      );

      // The duplicate 'camera' in center is dropped; 'brushes' (never
      // placed by the save) returns to its default dock as a new section.
      expect(
        [for (final section in restored!.docks['left']!) section.tabs],
        [
          ['camera'],
          ['brushes'],
        ],
      );
      expect(restored.docks['center']!.single.tabs, ['canvas']);
    });

    test('a payload without a layout is rejected', () {
      expect(
        restoreWorkspaceLayout(payload: {'version': 1}, defaults: _defaults()),
        isNull,
      );
    });
  });
}
