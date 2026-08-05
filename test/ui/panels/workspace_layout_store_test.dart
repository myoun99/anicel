import 'dart:io';

import 'package:flutter/material.dart';
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
      // 'ghost-panel' dropped; 'camera' kept with its saved section, and
      // 'brushes' (lost to the unknown dock) JOINS that section — its
      // default-section sibling survived, so no split appears.
      expect(restored!.docks['left']!.single.tabs, ['camera', 'brushes']);
      expect(restored.docks['left']!.single.weight, 2);
      // Tabs the save never placed ('tools', 'canvas') return to their
      // default docks.
      expect(restored.docks['tool-left']!.single.tabs, ['tools']);
      expect(restored.docks['center']!.single.tabs, ['canvas']);
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
      // placed by the save) joins the section holding its sibling.
      expect(
        [for (final section in restored!.docks['left']!) section.tabs],
        [
          ['camera', 'brushes'],
        ],
      );
      expect(restored.docks['center']!.single.tabs, ['canvas']);
    });

    test('an update-added panel joins the saved sibling section instead of '
        'splitting the dock', () {
      // The save predates 'camera' (an app update added it): its default
      // section sibling 'brushes' was saved alone, with a resized weight
      // and itself active.
      final restored = restoreWorkspaceLayout(
        payload: {
          'layout': {
            'docks': {
              'left': [
                {
                  'tabs': ['brushes'],
                  'active': 'brushes',
                  'weight': 3,
                },
              ],
              'center': [
                {
                  'tabs': ['canvas'],
                },
              ],
              'tool-left': [
                {
                  'tabs': ['tools'],
                },
              ],
            },
          },
        },
        defaults: _defaults(),
      );

      // ONE section: the new tab slipped into the strip (fresh-install
      // shape), keeping the saved active tab and weight — not a second
      // section halving the dock with an empty panel.
      final left = restored!.docks['left']!;
      expect(left, hasLength(1));
      expect(left.single.tabs, ['brushes', 'camera']);
      expect(left.single.activeTabId, 'brushes');
      expect(left.single.weight, 3);
    });

    test('a payload without a layout is rejected', () {
      expect(
        restoreWorkspaceLayout(payload: {'version': 1}, defaults: _defaults()),
        isNull,
      );
    });
  });

  group('rail extents', () {
    test('a rail the user never dragged is simply absent', () {
      // Absent, not "saved at today's natural width": otherwise a later
      // column change would be pinned to yesterday's geometry.
      expect(restoreRailExtents({'version': 1}), isEmpty);
      expect(restoreRailExtents({'railExtents': <String, Object?>{}}), isEmpty);
    });

    test('saved rail windows come back per panel', () {
      expect(
        restoreRailExtents({
          'railExtents': {'timeline': 300, 'xsheet': 180.5},
        }),
        {'timeline': 300.0, 'xsheet': 180.5},
      );
    });

    test('junk is dropped rather than crashing the editor', () {
      expect(
        restoreRailExtents({
          'railExtents': {
            'timeline': 'wide',
            'xsheet': -4,
            'storyboard': 0,
            'nan': double.nan,
            'infinite': double.infinity,
            'ok': 240,
          },
        }),
        {'ok': 240.0},
      );
      expect(restoreRailExtents({'railExtents': 'nonsense'}), isEmpty);
    });
  });

  group('restored splitter numbers all go through one door', () {
    // The rail extents were filtered from the start and the dock extents
    // were not, which is a difference nobody chose. What made it matter:
    // `jsonDecode` rejects NaN and Infinity, so those never come out of the
    // file — but `-100` decodes fine, and a negative width reaching
    // `SizedBox` throws instead of clamping. See the widget test below.
    test('a dock extent must be a usable positive size, like a rail is', () {
      final restored = restoreWorkspaceLayout(
        payload: {
          'layout': {
            'docks': {
              'left': [
                {'tabs': ['brushes']},
              ],
            },
            'extents': {
              'left': -100,
              'center': 0,
              'tool-left': 'wide',
              'unknown-dock': 260,
            },
          },
        },
        defaults: _defaults(),
      );

      expect(restored, isNotNull);
      expect(
        restored!.dockExtents,
        isEmpty,
        reason: 'every one of those is either unusable or not a dock',
      );
    });

    test('a good extent still comes back', () {
      final restored = restoreWorkspaceLayout(
        payload: {
          'layout': {
            'docks': {
              'left': [
                {'tabs': ['brushes']},
              ],
            },
            'extents': {'left': 300.0},
          },
        },
        defaults: _defaults(),
      );

      expect(restored!.dockExtents, {'left': 300.0});
    });

    test('an unusable section weight falls back to 1 instead of dividing '
        'the dock by it', () {
      for (final weight in [-3, 0, 'heavy', double.nan, double.infinity]) {
        final restored = restoreWorkspaceLayout(
          payload: {
            'layout': {
              'docks': {
                'left': [
                  {
                    'tabs': ['brushes'],
                    'weight': weight,
                  },
                ],
              },
            },
          },
          defaults: _defaults(),
        );
        final section = restored!.docks['left']!.single;
        expect(section.weight, 1, reason: 'weight $weight');
        expect(section.weight, isPositive);
      }
    });
  });

  testWidgets('WHY: a negative extent is not clamped on the way to the '
      'screen — it throws', (tester) async {
    // The consequence the filter exists for, measured rather than assumed.
    // Zero and absurdly large values are survivable (a collapsed dock, and
    // the side docks scale to fit); a negative one takes the workspace down.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: -100, child: SizedBox.expand()),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.takeException(),
      isA<FlutterError>(),
      reason: 'this is what a hand-edited layout file used to reach',
    );
  });
}
