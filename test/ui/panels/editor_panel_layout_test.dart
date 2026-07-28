import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';

EditorPanelLayoutModel _model() => EditorPanelLayoutModel(
  docks: {
    'left': [
      DockSection(tabs: ['tools', 'brushes', 'camera'], activeTabId: 'brushes'),
    ],
    'bottom': [
      DockSection(tabs: ['timeline', 'storyboard']),
    ],
    'right': <DockSection>[],
  },
);

List<List<String>> _tabsOf(EditorPanelLayoutModel model, String dockId) => [
  for (final section in model.sectionsIn(dockId)) section.tabs,
];

void main() {
  group('EditorPanelLayoutModel', () {
    test('exposes docks, sections and active tabs', () {
      final model = _model();
      expect(_tabsOf(model, 'left'), [
        ['tools', 'brushes', 'camera'],
      ]);
      expect(model.sectionsIn('left').single.activeTabId, 'brushes');
      expect(model.sectionsIn('bottom').single.activeTabId, 'timeline');
      expect(model.sectionsIn('right'), isEmpty);
      expect(model.locateTab('camera'), (
        dockId: 'left',
        sectionIndex: 0,
        tabIndex: 2,
      ));
      expect(model.locateTab('unknown'), isNull);
    });

    test('selectTab switches the active tab and notifies', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.selectTab('left', 0, 'camera');

      expect(model.sectionsIn('left').single.activeTabId, 'camera');
      expect(notified, 1);
    });

    test('selectTab ignores unknown tabs and re-selection', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.selectTab('left', 0, 'storyboard');
      model.selectTab('left', 0, 'brushes');
      model.selectTab('left', 5, 'camera');

      expect(notified, 0);
    });

    test('same-section move reorders with insertion-index semantics', () {
      final model = _model();

      model.moveTabToSection(
        tabId: 'tools',
        toDockId: 'left',
        toSectionIndex: 0,
        insertIndex: 2,
      );

      expect(_tabsOf(model, 'left'), [
        ['brushes', 'tools', 'camera'],
      ]);
    });

    test('same-section move onto its own slot is a silent no-op', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.moveTabToSection(
        tabId: 'brushes',
        toDockId: 'left',
        toSectionIndex: 0,
        insertIndex: 1,
      );
      model.moveTabToSection(
        tabId: 'brushes',
        toDockId: 'left',
        toSectionIndex: 0,
        insertIndex: 2,
      );

      expect(notified, 0);
    });

    test('cross-dock move joins the target section and activates', () {
      final model = _model();

      model.moveTabToSection(
        tabId: 'camera',
        toDockId: 'bottom',
        toSectionIndex: 0,
        insertIndex: 1,
      );

      expect(_tabsOf(model, 'left'), [
        ['tools', 'brushes'],
      ]);
      expect(_tabsOf(model, 'bottom'), [
        ['timeline', 'camera', 'storyboard'],
      ]);
      expect(model.sectionsIn('bottom').single.activeTabId, 'camera');
    });

    test('moving the active tab out falls back to a neighbour', () {
      final model = _model();

      model.moveTabToSection(
        tabId: 'brushes',
        toDockId: 'bottom',
        toSectionIndex: 0,
        insertIndex: 0,
      );

      expect(model.sectionsIn('left').single.activeTabId, 'camera');
    });

    test('moveTabToNewSection stacks a panel below a panel', () {
      final model = _model();

      model.moveTabToNewSection(
        tabId: 'camera',
        toDockId: 'left',
        atSectionIndex: 1,
      );

      expect(_tabsOf(model, 'left'), [
        ['tools', 'brushes'],
        ['camera'],
      ]);
      expect(model.sectionsIn('left')[1].activeTabId, 'camera');
    });

    test('a new section can open an empty dock', () {
      final model = _model();

      model.moveTabToNewSection(
        tabId: 'camera',
        toDockId: 'right',
        atSectionIndex: 0,
      );

      expect(_tabsOf(model, 'right'), [
        ['camera'],
      ]);
      expect(_tabsOf(model, 'left'), [
        ['tools', 'brushes'],
      ]);
    });

    test('emptied sections are removed and can empty the dock', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': [
            DockSection(tabs: ['camera']),
          ],
          'bottom': [
            DockSection(tabs: ['timeline']),
          ],
        },
      );

      model.moveTabToSection(
        tabId: 'camera',
        toDockId: 'bottom',
        toSectionIndex: 0,
        insertIndex: 0,
      );

      expect(model.sectionsIn('left'), isEmpty);
      expect(_tabsOf(model, 'bottom'), [
        ['camera', 'timeline'],
      ]);
    });

    test('same-dock section removal shifts the target section index', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': [
            DockSection(tabs: ['a']),
            DockSection(tabs: ['b']),
            DockSection(tabs: ['c', 'd']),
          ],
        },
      );

      // Moving lone 'a' into the LAST section: removing a's section shifts
      // that section from index 2 to 1.
      model.moveTabToSection(
        tabId: 'a',
        toDockId: 'left',
        toSectionIndex: 2,
        insertIndex: 0,
      );

      expect(_tabsOf(model, 'left'), [
        ['b'],
        ['a', 'c', 'd'],
      ]);
    });

    test('lifting a lone-section tab beside itself is a no-op', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': [
            DockSection(tabs: ['a']),
            DockSection(tabs: ['b']),
          ],
        },
      );
      var notified = 0;
      model.addListener(() => notified += 1);

      model.moveTabToNewSection(
        tabId: 'a',
        toDockId: 'left',
        atSectionIndex: 0,
      );
      model.moveTabToNewSection(
        tabId: 'a',
        toDockId: 'left',
        atSectionIndex: 1,
      );

      expect(_tabsOf(model, 'left'), [
        ['a'],
        ['b'],
      ]);
      expect(notified, 0);
    });

    test('moveTabToNewSection below its own section reorders sections', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': [
            DockSection(tabs: ['a']),
            DockSection(tabs: ['b']),
          ],
        },
      );

      model.moveTabToNewSection(
        tabId: 'a',
        toDockId: 'left',
        atSectionIndex: 2,
      );

      expect(_tabsOf(model, 'left'), [
        ['b'],
        ['a'],
      ]);
    });

    test('unknown tabs or docks cannot move', () {
      final model = _model();
      expect(model.canMoveTab(tabId: 'nope', toDockId: 'left'), isFalse);
      expect(model.canMoveTab(tabId: 'tools', toDockId: 'nope'), isFalse);
      expect(model.canMoveTab(tabId: 'tools', toDockId: 'right'), isTrue);
    });

    test('resizeSections shifts weight between neighbours with a floor', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': [
            DockSection(tabs: ['a']),
            DockSection(tabs: ['b']),
          ],
        },
      );

      // +100px of 400px total moves 0.5 weight down to the upper section.
      model.resizeSections('left', 0, delta: 100, totalExtent: 400);
      expect(model.sectionsIn('left')[0].weight, closeTo(1.5, 1e-9));
      expect(model.sectionsIn('left')[1].weight, closeTo(0.5, 1e-9));

      // The lower section can never squash below the minimum weight.
      model.resizeSections('left', 0, delta: 10000, totalExtent: 400);
      expect(model.sectionsIn('left')[1].weight, closeTo(0.2, 1e-9));
    });

    test('dock extents clamp and notify', () {
      final model = _model();
      expect(model.dockExtent('left', fallback: 260), 260);

      model.resizeDock('left', 40, fallback: 260);
      expect(model.dockExtent('left', fallback: 260), 300);

      model.resizeDock('left', -1000, fallback: 260);
      expect(model.dockExtent('left', fallback: 260), 160);
    });

    test('toJson/restore round-trips the layout', () {
      final model = _model();
      model.moveTabToNewSection(
        tabId: 'camera',
        toDockId: 'left',
        atSectionIndex: 1,
      );
      model.resizeDock('bottom', 50, fallback: 350);
      final json = model.toJson();

      final other = _model();
      final docksJson = (json['docks'] as Map).cast<String, Object?>();
      other.restore(
        docks: {
          for (final entry in docksJson.entries)
            entry.key: [
              for (final section in entry.value as List)
                DockSection(
                  tabs: ((section as Map)['tabs'] as List).cast<String>(),
                  activeTabId: section['active'] as String,
                  weight: (section['weight'] as num).toDouble(),
                ),
            ],
        },
        dockExtents: (json['extents'] as Map).cast<String, double>(),
      );

      expect(_tabsOf(other, 'left'), [
        ['tools', 'brushes'],
        ['camera'],
      ]);
      expect(other.dockExtent('bottom', fallback: 350), 400);
    });
  });
}
